#!/usr/bin/env python3
"""Record, or --verify, Apple framework and bundled native dictionary hashes."""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
paths=sorted(p for folder in ['FusionCore/Native','Resources/Native'] for p in (ROOT/folder).rglob('*') if p.is_file() and p.name!='.DS_Store')
actual={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
manifest=ROOT/'Native/artifacts.json'
if '--verify' in sys.argv:
    assert actual==json.loads(manifest.read_text()),'Native artifacts changed; rebuild and record manifest'
    print(f'Verified {len(actual)} native artifacts.')
else:
    manifest.write_text(json.dumps(actual,indent=2)+'\n')
    print(f'Recorded {len(actual)} native artifacts.')
