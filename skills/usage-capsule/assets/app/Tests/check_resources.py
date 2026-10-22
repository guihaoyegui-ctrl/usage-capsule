import json
import plistlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
packs = {}
for code in ('en', 'zh-Hans', 'ja', 'ko'):
    with (root / 'Resources' / f'{code}.lproj' / 'Localizable.strings').open('rb') as stream:
        packs[code] = plistlib.load(stream)

used = set()
for path in (root / 'Sources').glob('*.swift'):
    for match in re.finditer(r'L10n\.(?:text|format)\(("(?:[^"\\]|\\.)*")', path.read_text()):
        used.add(json.loads(match.group(1)))

for code, entries in packs.items():
    assert set(entries) == set(packs['en']), f'{code}: resource keys differ'
    assert used <= set(entries), f'{code}: missing {used-set(entries)}'
    for key, value in entries.items():
        assert isinstance(value, str) and value.strip(), (code, key, 'empty translation')
        assert value.count('%@') == key.count('%@'), (code, key, 'lost format argument')
    print(f'PASS: {code} has {len(entries)} complete translations with intact format arguments')
