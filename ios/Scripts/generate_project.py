#!/usr/bin/env python3
"""Generate the checked-in Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1]
objects={}
def uid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def add(key,isa,**fields):
    id=uid(key); objects[id]={'isa':isa,**fields}; return id

def ref(path,kind): return add('file:'+path,'PBXFileReference',lastKnownFileType=kind,path=path,sourceTree='<group>')
shared=[str(p.relative_to(ROOT)) for p in sorted((ROOT/'Shared').glob('*.swift'))]
app=[str(p.relative_to(ROOT)) for p in sorted((ROOT/'App').glob('*.swift'))]+shared
keyboard=[str(p.relative_to(ROOT)) for p in sorted((ROOT/'Keyboard').glob('*.swift'))]+shared
refs={p:ref(p,'sourcecode.swift') for p in set(app+keyboard+['Tests/KeyboardIntegrationTests.swift'])}
refs['App/Assets.xcassets']=ref('App/Assets.xcassets','folder.assetcatalog')
refs['Resources/Licenses']=ref('Resources/Licenses','folder')
refs['Resources/PrivacyInfo.xcprivacy']=ref('Resources/PrivacyInfo.xcprivacy','text.xml')
refs['Resources/Localizable.xcstrings']=ref('Resources/Localizable.xcstrings','text.json.xcstrings')
refs['Resources/lexicon.sqlite']=ref('Resources/lexicon.sqlite','file')
refs['Resources/Native']=ref('Resources/Native','folder')
for path in ['App/Info.plist','Keyboard/Info.plist','Config/FusionIME.entitlements','Config/Shared.xcconfig']:
    refs[path]=ref(path,'text.xcconfig' if path.endswith('xcconfig') else 'text.plist.xml')
package=add('package','XCLocalSwiftPackageReference',relativePath='FusionCore')
appProduct=add('product-app','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='FusionIME.app',sourceTree='BUILT_PRODUCTS_DIR')
extProduct=add('product-keyboard','PBXFileReference',explicitFileType='wrapper.app-extension',includeInIndex=0,path='FusionKeyboard.appex',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products','PBXGroup',children=[appProduct,extProduct],name='Products',sourceTree='<group>')
main=add('main','PBXGroup',children=[refs[p] for p in sorted(refs)]+[products],sourceTree='<group>')
projectID=uid('project');appID=uid('app');extID=uid('keyboard')

def configs(key,settings,base=True):
    ids=[]
    for name in ['Debug','Release']:
        config={**settings}
        config['SWIFT_OPTIMIZATION_LEVEL']='-Onone' if name=='Debug' else '-O'
        config['DEBUG_INFORMATION_FORMAT']='dwarf' if name=='Debug' else 'dwarf-with-dsym'
        if name=='Debug': config['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        fields={'buildSettings':config,'name':name}
        if base: fields['baseConfigurationReference']=refs['Config/Shared.xcconfig']
        ids.append(add(key+name,'XCBuildConfiguration',**fields))
    return add(key+'configs','XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

projectConfig=configs('project',{'SDKROOT':'iphoneos','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ENABLE_STRICT_OBJC_MSGSEND':'YES','CLANG_WARN_DOCUMENTATION_COMMENTS':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','SWIFT_EMIT_LOC_STRINGS':'NO'})
for key,name,files,product,kind in [('app','FusionIME',app,appProduct,'com.apple.product-type.application'),('keyboard','FusionKeyboard',keyboard,extProduct,'com.apple.product-type.app-extension')]:
    sources=add(key+'sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[add(key+p,'PBXBuildFile',fileRef=refs[p]) for p in files],runOnlyForDeploymentPostprocessing=0)
    dependency=add(key+'core','XCSwiftPackageProductDependency',package=package,productName='FusionCore')
    frameworks=add(key+'frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[add(key+'core-build','PBXBuildFile',productRef=dependency)],runOnlyForDeploymentPostprocessing=0)
    resources=['Resources/PrivacyInfo.xcprivacy','Resources/Localizable.xcstrings']+(['App/Assets.xcassets','Resources/Licenses'] if key=='app' else ['Resources/lexicon.sqlite','Resources/Native'])
    resourcePhase=add(key+'resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[add(key+'resource'+p,'PBXBuildFile',fileRef=refs[p]) for p in resources],runOnlyForDeploymentPostprocessing=0)
    phases=[sources,frameworks,resourcePhase];dependencies=[]
    if key=='app':
        embedded=add('embed-build','PBXBuildFile',fileRef=extProduct,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
        phases.append(add('embed','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embedded],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0))
        proxy=add('proxy','PBXContainerItemProxy',containerPortal=projectID,proxyType=1,remoteGlobalIDString=extID,remoteInfo='FusionKeyboard')
        dependencies=[add('dependency','PBXTargetDependency',target=extID,targetProxy=proxy)]
    settings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'$(FUSION_BUNDLE_ID)'+('.keyboard' if key=='keyboard' else ''),'INFOPLIST_FILE':('App' if key=='app' else 'Keyboard')+'/Info.plist','CODE_SIGN_ENTITLEMENTS':'Config/FusionIME.entitlements','GENERATE_INFOPLIST_FILE':'NO','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']+(['@executable_path/../../Frameworks'] if key=='keyboard' else [])}
    if key=='app': settings['ASSETCATALOG_COMPILER_APPICON_NAME']='AppIcon'
    else: settings.update({'APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES'})
    add(key,'PBXNativeTarget',buildConfigurationList=configs(key,settings),buildPhases=phases,buildRules=[],dependencies=dependencies,name=name,packageProductDependencies=[dependency],productName=name,productReference=product,productType=kind)
add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600','TargetAttributes':{appID:{'CreatedOnToolsVersion':'16.0','SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':1}}},extID:{'CreatedOnToolsVersion':'16.0','SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':1}}}}},buildConfigurationList=projectConfig,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','ko','ja','zh-Hans','zh-Hant','vi','Base'],mainGroup=main,packageReferences=[package],productRefGroup=products,projectDirPath='',projectRoot='',targets=[appID,extID])
testProduct=add('product-tests','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,path='FusionKeyboardTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
objects[products]['children'].append(testProduct)
testCore=add('test-core','XCSwiftPackageProductDependency',package=package,productName='FusionCore')
testSources=add('test-sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[add('test'+p,'PBXBuildFile',fileRef=refs[p]) for p in ['Tests/KeyboardIntegrationTests.swift']+keyboard],runOnlyForDeploymentPostprocessing=0)
testFrameworks=add('test-frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[add('test-core-build','PBXBuildFile',productRef=testCore)],runOnlyForDeploymentPostprocessing=0)
testResources=add('test-resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
testProxy=add('test-proxy','PBXContainerItemProxy',containerPortal=projectID,proxyType=1,remoteGlobalIDString=appID,remoteInfo='FusionIME')
testDependency=add('test-dependency','PBXTargetDependency',target=appID,targetProxy=testProxy)
testID=add('tests','PBXNativeTarget',name='FusionKeyboardTests',productName='FusionKeyboardTests',productReference=testProduct,productType='com.apple.product-type.bundle.unit-test',buildConfigurationList=configs('tests',{'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'$(FUSION_BUNDLE_ID).tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/FusionIME.app/FusionIME','BUNDLE_LOADER':'$(TEST_HOST)','CODE_SIGNING_ALLOWED':'NO','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks']}),buildPhases=[testSources,testFrameworks,testResources],buildRules=[],dependencies=[testDependency],packageProductDependencies=[testCore])
objects[projectID]['targets'].append(testID)

def emit(value,level=0):
    if isinstance(value,dict): return '{\n'+''.join('\t'*(level+1)+json.dumps(k)+ ' = '+emit(v,level+1)+';\n' for k,v in value.items())+'\t'*level+'}'
    if isinstance(value,list): return '('+', '.join(emit(v,level) for v in value)+')'
    if isinstance(value,int): return str(value)
    return value if value in objects else json.dumps(value,ensure_ascii=False)
project=ROOT/'FusionIME.xcodeproj';project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+emit({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':projectID})+'\n')
scheme=project/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
(scheme/'FusionIME.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appID}" BuildableName="FusionIME.app" BlueprintName="FusionIME" ReferencedContainer="container:FusionIME.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{testID}" BuildableName="FusionKeyboardTests.xctest" BlueprintName="FusionKeyboardTests" ReferencedContainer="container:FusionIME.xcodeproj"/></TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appID}" BuildableName="FusionIME.app" BlueprintName="FusionIME" ReferencedContainer="container:FusionIME.xcodeproj"/></BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appID}" BuildableName="FusionIME.app" BlueprintName="FusionIME" ReferencedContainer="container:FusionIME.xcodeproj"/></BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated',project)
