/* Portable audio recipe: ELF loader identity and bounded region fingerprints.
 * Only ABI facts, hashes and independently authored replacements are compiled. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <io.h>
#define fsync _commit
#else
#define O_BINARY 0
#endif
#include "../portable/sha256.h"

struct audio_span {
    uint32_t offset, length;
    const char *before, *after;
    const unsigned char *replacement;
};
struct audio_profile {
    const char *name;
    uint32_t flags, phoff, phnum;
    const char *ph_sha;
    const struct audio_span *spans;
    uint32_t count;
};
#include <region_recipe.h>

static uint32_t u16(const unsigned char *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8);
}
static uint32_t u32(const unsigned char *p) {
    return u16(p) | (u16(p + 2) << 16);
}
static int bounded(size_t size, uint32_t offset, uint32_t length) {
    return offset <= size && length <= size - offset;
}
static int matches(const unsigned char *data, size_t length, const char *expected) {
    char digest[65];
    size_t i;
    if (!expected) return 0;
    for (i = 0; i < 64; i++) if (!expected[i]) return 0;
    if (expected[64]) return 0;
    sha256(data, length, digest);
    return !strcmp(digest, expected);
}
static int validate(const unsigned char *data, size_t size,
                    const struct audio_profile *p, int after) {
    uint32_t i, j, loads = 0;
    size_t table_size;
    if (size < 52 || data[0] != 127 || data[1] != 'E' ||
        data[2] != 'L' || data[3] != 'F' || data[4] != 1 ||
        data[5] != 1 || data[6] != 1 || u16(data + 16) != 3 ||
        u16(data + 18) != 40 || u32(data + 20) != 1 ||
        u32(data + 36) != p->flags || u16(data + 40) != 52 ||
        u32(data + 28) != p->phoff || u16(data + 42) != 32 ||
        u16(data + 44) != p->phnum || !p->phnum || p->phnum > 65535 ||
        p->phoff < 52 || !p->count || !p->spans) return 0;
    table_size = (size_t)p->phnum * 32;
    if (p->phoff > size || table_size > size - p->phoff ||
        !matches(data + p->phoff, table_size, p->ph_sha)) return 0;
    for (i = 0; i < p->phnum; i++) {
        const unsigned char *ph = data + p->phoff + (size_t)i * 32;
        uint32_t offset = u32(ph + 4), address = u32(ph + 8);
        uint32_t filesz = u32(ph + 16), memsz = u32(ph + 20);
        uint32_t align = u32(ph + 28);
        if (!bounded(size, offset, filesz)) return 0;
        if (u32(ph) != 1) continue;
        loads++;
        if (filesz > memsz || memsz > UINT32_MAX - address ||
            (align > 1 && ((align & (align - 1)) ||
                           (offset & (align - 1)) !=
                           (address & (align - 1))))) return 0;
    }
    if (!loads) return 0;
    for (i = 0; i < p->count; i++) {
        const struct audio_span *s = p->spans + i;
        int mapped = 0;
        if (!s->length || !bounded(size, s->offset, s->length) ||
            !s->before || !s->after ||
            (!s->replacement && strcmp(s->before, s->after))) return 0;
        for (j = 0; j < p->phnum; j++) {
            const unsigned char *ph = data + p->phoff + (size_t)j * 32;
            uint32_t offset = u32(ph + 4), filesz = u32(ph + 16);
            if (u32(ph) == 1 && s->offset >= offset &&
                s->offset - offset <= filesz &&
                s->length <= filesz - (s->offset - offset)) mapped = 1;
        }
        if (!mapped || !matches(data + s->offset, s->length,
                                 after ? s->after : s->before)) return 0;
        for (j = 0; j < i; j++) {
            const struct audio_span *other = p->spans + j;
            if (s->offset < (uint64_t)other->offset + other->length &&
                other->offset < (uint64_t)s->offset + s->length) return 0;
        }
    }
    return 1;
}

int main(int argc, char **argv) {
    const struct audio_profile *profile = NULL;
    const char *role;
    unsigned char *data;
    size_t size, i;
    long length;
    int in, fd, rc = 1, apply, after, verify;
    if (argc < 3) return 2;
    apply = !strcmp(argv[1], "apply");
    after = !strcmp(argv[1], "patched");
    verify = !strcmp(argv[1], "verify");
    if ((!apply && !after && !verify && strcmp(argv[1], "original")) ||
        argc != ((apply || verify) ? 4 : 3)) return 2;
    role = verify ? argv[3] : "audio";
    if (verify && strcmp(role, "core") && strcmp(role, "utils") &&
        strcmp(role, "opus")) return 2;
    for (i = 0; i < sizeof(profiles) / sizeof(profiles[0]); i++)
        if (!strcmp(role, profiles[i].name)) { profile = profiles + i; break; }
    if (!profile) return 1;
    in = open(argv[2], O_RDONLY | O_BINARY);
    if (in < 0) return 1;
    length = (long)lseek(in, 0, SEEK_END);
    if (length < 0 || length > 32 * 1024 * 1024 || lseek(in, 0, SEEK_SET) != 0) {
        close(in); return 1;
    }
    size = (size_t)length;
    data = malloc(size ? size : 1);
    if (!data) { close(in); return 1; }
    for (i = 0; i < size;) {
        int n = (int)read(in, data + i, (unsigned)(size - i));
        if (n <= 0) break;
        i += (size_t)n;
    }
    close(in);
    if (i != size || !validate(data, size, profile, after)) { free(data); return 1; }
    if (!apply) { free(data); return 0; }
    for (i = 0; i < profile->count; i++) {
        const struct audio_span *s = profile->spans + i;
        if (s->replacement) memcpy(data + s->offset, s->replacement, s->length);
    }
    if (!validate(data, size, profile, 1)) { free(data); return 1; }
    fd = open(argv[3], O_WRONLY | O_CREAT | O_EXCL | O_BINARY, 0600);
    if (fd < 0) { free(data); return 1; }
    for (i = 0; i < size;) {
        int n = (int)write(fd, data + i, (unsigned)(size - i));
        if (n <= 0) break;
        i += (size_t)n;
    }
    if (i == size && !fsync(fd)) rc = 0;
    if (close(fd)) rc = 1;
    if (rc) unlink(argv[3]);
    free(data);
    return rc;
}
