#!/usr/bin/env python3
"""Build both iOS targets' catalog, preferring the original Android translations."""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / 'android/app/src/main/res'
LOCALES = {'en':'values', 'ko':'values-ko', 'ja':'values-ja',
           'zh-Hans':'values-zh-rCN', 'zh-Hant':'values-zh-rTW', 'vi':'values-vi'}
DIRECTORY = ROOT / 'Resources/Localization'
mapping = json.loads((DIRECTORY / 'android-map.json').read_text())
supplemental = json.loads((DIRECTORY / 'supplemental.json').read_text())
original = {}
for locale, directory in LOCALES.items():
    original[locale] = {
        node.attrib['name']: ''.join(node.itertext()).replace("\\'", "'").replace('\\"', '"').replace('\\?', '?')
        for node in ET.parse(SOURCE / directory / 'strings.xml').getroot()
        if node.tag == 'string'
    }

strings = {}
missing = []
reused = 0
for key in sorted(mapping.keys() | supplemental.keys()):
    android_id = mapping.get(key)
    translations = {}
    for locale in LOCALES:
        # An existing upstream translation always wins over a supplement.
        value = original[locale].get(android_id)
        if value is not None:
            reused += 1
        else:
            value = supplemental.get(key, {}).get(locale, key if locale == 'ko' else None)
        if value is None:
            missing.append((key, locale))
            continue
        assert sorted(re.findall(r'%(?:\d+\$)?(?:lld|d|@)', key)) == sorted(re.findall(r'%(?:\d+\$)?(?:lld|d|@)', value)), (key, locale)
        translations[locale] = {'stringUnit': {'state':'translated', 'value':value}}
    strings[key] = {
        'comment': ('Android: ' + android_id) if android_id else 'iOS UI',
        'extractionState':'manual', 'localizations':translations,
    }
if missing:
    print('\n'.join(f'{locale}\t{key}' for key, locale in missing))
    sys.exit(1)
catalog = {'sourceLanguage':'en', 'strings':strings, 'version':'1.0'}
output = json.dumps(catalog, ensure_ascii=False, indent=2) + '\n'
path = ROOT / 'Resources/Localizable.xcstrings'
if '--check' in sys.argv:
    assert json.loads(path.read_text()) == catalog, 'Regenerate Localizable.xcstrings'
else:
    path.write_text(output)
print(f'{len(strings)} UI keys, {len(LOCALES)} languages, {reused} original translations reused.')
