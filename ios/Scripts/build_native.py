#!/usr/bin/env python3
"""Build generated XCFrameworks. Requires Xcode, Bazelisk and Rust >=1.88.

Override FUSION_BAZELISK and FUSION_CARGO for isolated toolchain installations.
Rust targets: aarch64-apple-darwin, aarch64-apple-ios, aarch64-apple-ios-sim.
"""
from pathlib import Path
import argparse,os,shutil,subprocess
parser=argparse.ArgumentParser()
parser.add_argument('--mozc-only',action='store_true',help='Rebuild Mozc while keeping existing Chewing artifacts')
options=parser.parse_args()
ROOT=Path(__file__).resolve().parents[1]
NATIVE=ROOT/'Native'
environment={**os.environ,'DEVELOPER_DIR':os.environ.get('DEVELOPER_DIR','/Applications/Xcode.app/Contents/Developer'),'USE_BAZEL_VERSION':'9.0.1','CARGO_PROFILE_RELEASE_DEBUG':'false'}
cache=Path(os.environ.get('FUSION_NATIVE_CACHE','/tmp/fusion-native-build'))
environment['CARGO_TARGET_DIR']=str(cache/'cargo')
bazel=os.environ.get('FUSION_BAZELISK','bazelisk')
cargo=os.environ.get('FUSION_CARGO','cargo')
def run(command,cwd=ROOT): subprocess.run([str(c) for c in command],cwd=cwd,env=environment,check=True)
run(['python3',ROOT/'Scripts/prepare_native.py'])
mozc=NATIVE/'Sources/mozc/src'
base=[bazel,'--output_user_root='+str(cache/'bazel'),'build','--config=release_build','--jobs=4']
for platform,cpu in [('macos-arm64',None),('ios-arm64','arm64'),('ios-arm64-simulator','sim_arm64')]:
    args=['//ios:FusionMozcMac','--macos_minimum_os=13.0'] if cpu is None else ['//ios:FusionMozcIOS','--noenable_platform_specific_config','--config=compiler_gcc_like','--define','TARGET=ios','--copt=-DMOZC_BUILD','--host_copt=-DMOZC_BUILD','--ios_multi_cpus='+cpu]
    run(base+args,mozc)
    output=NATIVE/'Artifacts'/platform;output.mkdir(parents=True,exist_ok=True)
    archive=output/'libFusionMozc.a'
    if archive.exists():archive.unlink()
    shutil.copyfile(mozc/'bazel-bin/ios'/('libFusionMozcMac.a' if cpu is None else 'FusionMozcIOS_lipo.a'),archive)
targets={'macos-arm64':'aarch64-apple-darwin','ios-arm64':'aarch64-apple-ios','ios-arm64-simulator':'aarch64-apple-ios-sim'}
for platform,target in targets.items():
    if options.mozc_only: continue
    run([cargo,'build','--locked','--release','-p','chewing_capi','--target',target],NATIVE/'Sources/libchewing-0.12.0')
    shutil.copyfile(cache/'cargo'/target/'release/libchewing_capi.a',NATIVE/'Artifacts'/platform/'libChewing.a')
for module,library in [('CMozc','libFusionMozc.a'),('CChewing','libChewing.a')]:
    if options.mozc_only and module=='CChewing': continue
    output=ROOT/'FusionCore/Native'/(module+'.xcframework')
    output.parent.mkdir(parents=True,exist_ok=True)
    temporary=output.with_name(module+'.building.xcframework')
    if temporary.exists(): shutil.rmtree(temporary)
    args=['xcodebuild','-create-xcframework']
    for platform in targets: args+=['-library',NATIVE/'Artifacts'/platform/library,'-headers',NATIVE/'Headers'/module]
    run(args+['-output',temporary])
    if output.exists(): shutil.rmtree(output)
    temporary.rename(output)
run(['python3',ROOT/'Scripts/native_manifest.py'])
