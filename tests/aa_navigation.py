from pathlib import Path
import subprocess
import repo_tmp as tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='aa-navigation-') as work:
    sources = [root/'probe/src/kr/gen5w/probe/Item.java', *sorted((root/'app/src/kr/gen5w/hud').glob('*.java')), *sorted((root/'app/test').glob('AaNavigation*Test.java'))]
    subprocess.run(['javac', '-encoding', 'UTF-8', '-nowarn', '--release', '8', '-d', work, *map(str, sources)], check=True)
    for name in ['AaNavigationParserTest', 'AaNavigationStateTest']:
        subprocess.run(['java', '-cp', work, name], check=True)
