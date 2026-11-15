#!/usr/bin/env python3
"""Prepare the ignored iOS build outputs from this repository's source inputs."""
from pathlib import Path
import os
import platform
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT.parent / 'android'
CORE_RESOURCES = ROOT / 'FusionCore/Sources/FusionCore/Resources'
PLATFORMS = ('macos-arm64', 'ios-arm64', 'ios-arm64-simulator')
LANGUAGES = ('de', 'en', 'es', 'fr', 'it', 'ko', 'pt_br')


def run_script(name):
    subprocess.run([sys.executable, str(ROOT / 'Scripts' / name)], check=True)


def frameworks_ready():
    for module, header in [('CMozc', 'FusionMozc.h'), ('CChewing', 'chewing.h')]:
        framework = ROOT / 'FusionCore/Native' / (module + '.xcframework')
        try:
            info = plistlib.loads((framework / 'Info.plist').read_bytes())
            libraries = {item['LibraryIdentifier']: item for item in info['AvailableLibraries']}
        except (OSError, ValueError, KeyError, TypeError):
            return False
        for architecture in PLATFORMS:
            item = libraries.get(architecture, {})
            library = framework / architecture / item.get('LibraryPath', '')
            headers = framework / architecture / item.get('HeadersPath', '') / module
            if not library.is_file():
                return False
            if not (headers / 'module.modulemap').is_file() or not (headers / header).is_file():
                return False
    return True


def require_native_tools():
    bazel = os.environ.get('FUSION_BAZELISK', 'bazelisk')
    cargo = os.environ.get('FUSION_CARGO', 'cargo')
    for command in (bazel, cargo):
        if shutil.which(command) is None:
            raise SystemExit(f'Missing build tool: {command}. See ./build.sh --help.')
    version = subprocess.check_output([cargo, '--version'], text=True)
    match = re.search(r'cargo (\d+)\.(\d+)\.(\d+)', version)
    if not match or tuple(map(int, match.groups())) < (1, 88, 0):
        raise SystemExit('Rust/Cargo 1.88 or newer is required. See ./build.sh --help.')


def main():
    if sys.version_info < (3, 10):
        raise SystemExit('Python 3.10 or newer is required.')
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('This build currently requires an Apple Silicon Mac.')
    os.environ.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    subprocess.run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'],
                   stdout=subprocess.DEVNULL, check=True)
    if not (ANDROID / 'app/src/main/res/raw').is_dir():
        raise SystemExit('Missing android/ sources. Keep android/ and ios/ together.')

    needs_native = not frameworks_ready()
    if needs_native:
        require_native_tools()

    generated_resources = [ROOT / 'Resources/lexicon.sqlite', ROOT / 'Resources/manifest.json']
    generated_resources += [CORE_RESOURCES / 'Korean' / (name + '.bin')
                            for name in ('hanja_index', 'hanja_content', 'hanja_bigram')]
    generated_resources += [CORE_RESOURCES / 'Vietnamese' / (name + '.bin')
                            for name in ('nom_qwerty', 'nom_quoc_ngu', 'quoc_ngu_qwerty')]
    generated_resources += [CORE_RESOURCES / name for name in
                            ('tables.json', 'latin-keymaps.json', 'layout-extras.json',
                             'kana-modifiers.json', 'jyutping-syllables.json')]
    if not all(path.is_file() for path in generated_resources):
        print('Generating dictionaries and keyboard tables…', flush=True)
        run_script('fetch_mozc.py')
        run_script('build_resources.py')

    native_resources = ROOT / 'Resources/Native'
    native_resources.mkdir(parents=True, exist_ok=True)
    raw = ANDROID / 'app/src/main/res/raw'
    assets = ANDROID / 'app/src/main/assets'
    sources = [raw / ('main_' + language + '.dict') for language in LANGUAGES]
    sources += [raw / name for name in ('dict_pinyin_hans.dat', 'dict_pinyin_hant.dat')]
    sources += [assets / name for name in ('mozc.data', 'swkb.dat', 'symbols.dat', 'tsi.dat', 'word.dat')]
    copied = False
    for source in sources:
        target = native_resources / source.name
        if not target.is_file() or source.read_bytes() != target.read_bytes():
            shutil.copyfile(source, target)
            copied = True

    if needs_native:
        print('Building Mozc and Chewing for macOS, iPhone and Simulator…', flush=True)
        run_script('build_native.py')
    elif copied or not (ROOT / 'Native/artifacts.json').is_file():
        run_script('native_manifest.py')

    subprocess.run([sys.executable, str(ROOT / 'Scripts/native_manifest.py'), '--verify'], check=True)
    run_script('verify_project.py')
    print('iOS build resources are ready.', flush=True)


if __name__ == '__main__':
    main()
