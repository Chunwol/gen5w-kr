"""Build a portable audio helper from reviewed ELF regions, never OEM bytes.

The private reference is checked when producing a recipe. On the car only the
ELF ABI/mappings and consumed regions are checked; file-wide digests are not
compatibility gates. The existing legacy audio builder is unchanged.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def profile(data, patches=()):
    if len(data) < 52 or data[:7] != b'\x7fELF\x01\x01\x01':
        raise ValueError('ELF32 little-endian required')
    fields = struct.unpack_from('<HHIIIIIHHHHHH', data, 16)
    kind, machine, version, _, phoff, shoff, flags, ehsize, phsize, phnum, shsize, shnum, strings = fields
    if (kind, machine, version, ehsize, phsize, shsize) != (3, 40, 1, 52, 32, 40):
        raise ValueError('reviewed ARM shared ELF required')
    if not phnum or phnum > 128 or phoff + phnum * phsize > len(data):
        raise ValueError('program headers unavailable')
    if not shnum or shnum > 4096 or strings >= shnum or shoff + shnum * shsize > len(data):
        raise ValueError('reference section headers unavailable')
    sections = [struct.unpack_from('<10I', data, shoff + i * shsize) for i in range(shnum)]
    names = sections[strings]
    if names[4] + names[5] > len(data):
        raise ValueError('section names out of bounds')
    table = data[names[4]:names[4] + names[5]]
    patches = list(patches)
    used = set()
    spans = []
    for section in sections:
        name_index, section_type, attributes, _, offset, length, _, _, _, _ = section
        if section_type == 8 or not attributes & 2 or not length:
            continue
        if offset + length > len(data) or name_index >= len(table):
            raise ValueError('allocated section out of bounds')
        name = table[name_index:].split(b'\0', 1)[0]
        if patches and name == b'.text':
            for index, patch in enumerate(patches):
                start, count = patch['offset'], patch['length']
                if start < offset or count <= 0 or start + count > offset + length:
                    raise ValueError('patch outside executable text')
                replacement = patch['replacement']
                before = digest(data[start:start + count])
                if len(replacement) != count or before != patch['original_span_sha256']:
                    raise ValueError('unreviewed patch bytes')
                spans.append(dict(offset=start, length=count, before=before,
                                  after=digest(replacement), replacement=replacement))
                used.add(index)
        else:
            value = digest(data[offset:offset + length])
            spans.append(dict(offset=offset, length=length, before=value, after=value, replacement=None))
    if len(used) != len(patches) or not spans:
        raise ValueError('patch text or allocated regions missing')
    spans.sort(key=lambda item: item['offset'])
    for previous, current in zip(spans, spans[1:]):
        if previous['offset'] + previous['length'] > current['offset']:
            raise ValueError('overlapping regions')
    return dict(flags=flags, phoff=phoff, phnum=phnum,
                ph_sha=digest(data[phoff:phoff + phnum * phsize]), spans=spans)


def header_for_profiles(profiles):
    if set(profiles) != {'audio', 'core', 'utils', 'opus'}:
        raise ValueError('exact audio/dependency roles required')
    lines = ['/* Only hashes, ABI facts and independently authored replacements. */']
    for role, item in profiles.items():
        for index, span in enumerate(item['spans']):
            if span['replacement'] is not None:
                lines.append('static const unsigned char %s_bytes_%d[] = {%s};' %
                             (role, index, ','.join(map(str, span['replacement']))))
        lines.append('static const struct audio_span %s_spans[] = {' % role)
        for index, span in enumerate(item['spans']):
            replacement = '%s_bytes_%d' % (role, index) if span['replacement'] is not None else 'NULL'
            lines.append('{%d,%d,"%s","%s",%s},' %
                         (span['offset'], span['length'], span['before'], span['after'], replacement))
        lines.append('};')
    lines.append('static const struct audio_profile profiles[] = {')
    for role, item in profiles.items():
        lines.append('{"%s",%d,%d,%d,"%s",%s_spans,%d},' %
                     (role, item['flags'], item['phoff'], item['phnum'], item['ph_sha'], role, len(item['spans'])))
    return '\n'.join(lines + ['};', ''])


def build(reference_lib, output, ndk=None, host_only=False):
    from importlib.util import spec_from_file_location, module_from_spec
    spec = spec_from_file_location('legacy_audio_build', ROOT / 'tools/audio/build.py')
    legacy = module_from_spec(spec)
    spec.loader.exec_module(legacy)
    recipe = json.loads((ROOT / 'tools/audio/recipe.json').read_text(encoding='utf-8'))
    expected = {'audio': recipe['original_sha256'], **recipe['dependencies']}
    filenames = {'audio': 'libCarPlayAudio.so', 'core': 'libCarPlayCore.so',
                 'utils': 'libCarPlayUtils.so', 'opus': 'libopus.so'}
    references = {}
    for role, name in filenames.items():
        path = reference_lib / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('regular private reference required')
        data = path.read_bytes()
        if digest(data) != expected[role]:
            raise ValueError('build reference is not the reviewed V039 baseline: ' + role)
        references[role] = data
    if output.exists() or output.is_symlink():
        raise FileExistsError(output)
    output.mkdir(parents=True)
    try:
        compiler = None
        if not host_only:
            host = 'windows-x86_64' if os.name == 'nt' else 'linux-x86_64'
            compiler = Path(ndk) / 'toolchains/llvm/prebuilt' / host / 'bin' / ('clang.exe' if os.name == 'nt' else 'clang')
            subprocess.run([str(compiler), '--target=armv7a-linux-androideabi19', '-nostdlib',
                            '-Wl,-T,tools/audio/layout.ld', '-Wl,-e,input_formats', '-Wl,--build-id=none',
                            '-Wl,-no-pie', 'tools/audio/formats.S', '-o', str(output / 'formats.elf')],
                           cwd=ROOT, check=True)
            authored_elf = (output / 'formats.elf').read_bytes()
        else:
            # The authored selector was already assembled; verify every byte
            # against the reviewed recipe before reusing it for a host-only run.
            authored_elf = (ROOT / '.build/audio/formats.elf').read_bytes()
        patches = []
        for patch in recipe['patches']:
            replacement = legacy.section(authored_elf, patch['section'])
            if len(replacement) != patch['length'] or digest(replacement) != patch['replacement_sha256']:
                raise ValueError('authored replacement differs from reviewed assembly')
            patches.append({**patch, 'replacement': replacement})
        profiles = {'audio': profile(references['audio'], patches)}
        profiles.update({role: profile(references[role]) for role in ('core', 'utils', 'opus')})
        (output / 'region_recipe.h').write_text(header_for_profiles(profiles), encoding='ascii', newline='\n')
        summary = {role: {**item, 'spans': [{key: value for key, value in span.items() if key != 'replacement'}
                                          for span in item['spans']]} for role, item in profiles.items()}
        (output / 'regions.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='ascii')
        common = ['-std=c99', '-O2', '-Wall', '-Wextra', '-Werror', '-I', str(output), 'tools/audio/region_patch.c']
        subprocess.run([shutil.which('gcc') or 'cc', *common, '-o', str(output / ('audio-region-host.exe' if os.name == 'nt' else 'audio-region-host'))], cwd=ROOT, check=True)
        if not host_only:
            subprocess.run([str(compiler), '--target=armv7a-linux-androideabi19', *common,
                            '-fno-builtin', '-fno-stack-protector', '-fno-unwind-tables',
                            '-fno-asynchronous-unwind-tables', '-fno-pie', '-nostdlib', '-static',
                            '-Wl,-e,_start', '-Wl,--build-id=none', 'tools/audio/runtime.c',
                            'tools/audio/syscalls.S', '-o', str(output / 'audio-region-patch')], cwd=ROOT, check=True)
    except BaseException:
        # Failed builds are retained for diagnosis and cannot be mistaken for
        # a completed candidate because the consumer requires the ELF helper.
        (output / 'BUILD-FAILED').write_text('incomplete\n', encoding='ascii')
        raise
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-lib', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--ndk', type=Path, default=os.environ.get('ANDROID_NDK_HOME') or str(Path.home() / 'AppData/Local/Android/Sdk/ndk/27.2.12479018'))
    parser.add_argument('--host-only', action='store_true')
    args = parser.parse_args()
    print('Built regional audio helper:', build(args.reference_lib, args.output, args.ndk, args.host_only))
