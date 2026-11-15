#!/usr/bin/env python3
"""Run the real XCTest suite with the Xcode SDK and native Apple libraries."""
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
env={**os.environ}
env.setdefault('DEVELOPER_DIR','/Applications/Xcode.app/Contents/Developer')
cache=Path(tempfile.gettempdir())/'FusionIME-CoreTests'
env['CLANG_MODULE_CACHE_PATH']=str(cache/'clang')
env['SWIFT_MODULECACHE_PATH']=str(cache/'swift')
subprocess.run(['xcrun','swift','test','--disable-sandbox','--package-path',str(root/'FusionCore'),'--scratch-path',str(cache/'build'),'--cache-path',str(cache/'packages')],env=env,check=True)
