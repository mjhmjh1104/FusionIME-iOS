#!/usr/bin/env python3
"""Fetch a pinned, redistributable Mozc lexicon. Never used at app runtime."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'Vendor' / 'Mozc'
MANIFEST = ROOT / 'Scripts' / 'mozc-source.json'

def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    if MANIFEST.exists():
        manifest = json.loads(MANIFEST.read_text())
    else:
        commit = json.loads(Path('/tmp/fusion-mozc-commit.json').read_text())['sha']
        manifest = {'repository': 'https://github.com/google/mozc', 'commit': commit, 'files': {}}
    paths = [f'src/data/dictionary_oss/dictionary{i:02}.txt' for i in range(10)]
    paths += ['LICENSE', 'src/data/dictionary_oss/README.txt', 'src/data/dictionary_oss/id.def']
    paths += ['src/data/preedit/flick-hiragana.tsv']
    def fetch(path):
        target = CACHE / path
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            url = f"https://raw.githubusercontent.com/google/mozc/{manifest['commit']}/{path}"
            with urllib.request.urlopen(url, timeout=90) as response:
                target.write_bytes(response.read())
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        expected = manifest['files'].get(path)
        if expected and digest != expected:
            raise ValueError(f'Checksum mismatch: {path}')
        print(f'{path}: {target.stat().st_size:,} bytes', flush=True)
        return path, digest
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        manifest['files'] = dict(pool.map(fetch, paths))
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')

if __name__ == '__main__':
    main()
