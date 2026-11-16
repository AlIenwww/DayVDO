#!/usr/bin/env python3
"""Build and verify an isolated DayVDO app with the active Xcode SDK.

No installed app or production data is touched. Requires Xcode 27 or later.
"""
import argparse
import datetime
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP_ICON = ROOT / 'Design' / 'AppIcon' / 'DayVDO.icon'
LANGUAGES = ('zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'es', 'fr', 'de')


def run(*args, capture=False):
    return subprocess.run([str(a) for a in args], cwd=ROOT, check=True,
                          text=True, stdout=subprocess.PIPE if capture else None).stdout


def verify_binary(binary, sdk, minimum):
    report = run('xcrun', 'vtool', '-show-build', binary, capture=True)
    for key, expected in [('sdk', sdk), ('minos', minimum)]:
        values = re.findall(r'^\s*' + key + r'\s+(\S+)', report, re.MULTILINE)
        if not values or any(tuple(map(int, v.split('.'))) != tuple(map(int, expected.split('.'))) for v in values):
            raise RuntimeError(f'{binary}: expected {key} {expected}, got {values}')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configuration', choices=('debug', 'release'), default='debug')
    parser.add_argument('--test', action='store_true', help='Run the complete Swift test suite before packaging')
    parser.add_argument('--test-data', type=Path, help='Debug only: explicit isolated UI fixture file')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'dist' / 'macOS27')
    args = parser.parse_args()
    if args.test_data and args.configuration != 'debug':
        parser.error('--test-data requires a Debug build')
    sdk_path = run('xcrun', '--sdk', 'macosx', '--show-sdk-path', capture=True).strip()
    sdk = run('xcrun', '--sdk', 'macosx', '--show-sdk-version', capture=True).strip()
    if int(sdk.split('.')[0]) < 27:
        raise RuntimeError('Select Xcode 27 or later with xcode-select before building.')
    package = json.loads(run('xcrun', 'swift', 'package', 'dump-package', capture=True))
    minimum = next(p['version'] for p in package['platforms'] if p['platformName'] == 'macos')
    scratch = ROOT / '.build' / f'macos-sdk{sdk}'
    # Swift Build in Xcode 27 can record the deployment target as the SDK version.
    # Pass the *actual* SDK and deployment target to the linker, then verify Mach-O.
    common = ['--sdk', sdk_path, '--scratch-path', str(scratch), '-c', args.configuration,
              '-Xlinker', '-platform_version', '-Xlinker', 'macos',
              '-Xlinker', minimum, '-Xlinker', sdk]
    run('xcrun', 'swift', 'build', *common)
    if args.test:
        run('xcrun', 'swift', 'test', *common)
    products = Path(run('xcrun', 'swift', 'build', *common, '--show-bin-path', capture=True).strip())
    executable = products / 'DayVDO'
    build_report = verify_binary(executable, sdk, minimum)
    resource_bundle = products / 'DayVDO_DayVDO.bundle'
    resource_root = resource_bundle / 'Contents' / 'Resources'
    if not resource_root.is_dir():
        resource_root = resource_bundle
    for language in LANGUAGES:
        run('plutil', '-lint', resource_root / f'{language}.lproj' / 'Localizable.strings')

    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    app_name = f'DayVDO macOS27 {args.configuration.title()}'
    bundle_id = f'com.wuyuchen.DayVDO.CompatibilityTest.{args.configuration}'
    app = output / f'{app_name}.app'
    # Never overwrite an arbitrary existing application or silently replace a running one.
    if app.exists():
        raise RuntimeError(f'Output exists: {app}. Choose a new --output-dir.')
    with tempfile.TemporaryDirectory(prefix='dayvdo-package-', dir=output) as temporary:
        stage = Path(temporary) / app.name
        contents = stage / 'Contents'
        resources = contents / 'Resources'
        (contents / 'MacOS').mkdir(parents=True)
        resources.mkdir()
        shutil.copy2(executable, contents / 'MacOS' / 'DayVDO')
        shutil.copytree(resource_bundle, resources / resource_bundle.name)
        icon_info = Path(temporary) / 'AppIconInfo.plist'
        run('xcrun', 'actool', APP_ICON, '--compile', resources, '--platform', 'macosx',
            '--minimum-deployment-target', minimum, '--app-icon', APP_ICON.stem,
            '--output-partial-info-plist', icon_info, '--output-format', 'human-readable-text')
        with icon_info.open('rb') as f:
            icon_metadata = plistlib.load(f)
        if (icon_metadata.get('CFBundleIconName') != APP_ICON.stem
                or icon_metadata.get('CFBundleIconFile') != APP_ICON.stem
                or not (resources / 'Assets.car').is_file()
                or not (resources / f'{APP_ICON.stem}.icns').is_file()):
            raise RuntimeError(f'Xcode did not produce the expected app icon from {APP_ICON}.')
        info = {
            **icon_metadata,
            'CFBundleIdentifier': bundle_id, 'CFBundleName': app_name,
            'CFBundleDisplayName': app_name, 'CFBundleExecutable': 'DayVDO',
            'CFBundlePackageType': 'APPL', 'CFBundleInfoDictionaryVersion': '6.0',
            'CFBundleShortVersionString': '0.9.1',
            'CFBundleVersion': datetime.datetime.now().strftime('%Y%m%d%H%M%S'),
            'CFBundleDevelopmentRegion': 'zh-Hans', 'CFBundleLocalizations': list(LANGUAGES),
            'NSPrincipalClass': 'NSApplication',
            'NSHighResolutionCapable': True, 'LSMinimumSystemVersion': minimum,
            'DTSDKName': f'macosx{sdk}', 'DayVDOIsolatedTesting': True,
        }
        if args.test_data:
            info['DayVDOIsolatedTesting'] = False
            info['DayVDOTestingDataPath'] = str(args.test_data.resolve())
        with (contents / 'Info.plist').open('wb') as f:
            plistlib.dump(info, f)
        run('plutil', '-lint', contents / 'Info.plist')
        verify_binary(contents / 'MacOS' / 'DayVDO', sdk, minimum)
        run('codesign', '--force', '--deep', '--sign', '-', stage)
        run('codesign', '--verify', '--deep', '--strict', stage)
        stage.rename(app)
    report = {'app': str(app), 'configuration': args.configuration, 'sdk': sdk,
              'minimumOS': minimum, 'isolatedDataDirectory': str(args.test_data.resolve()) if args.test_data else f'Application Support/{bundle_id}',
              'testSuiteRan': args.test, 'signing': 'ad-hoc; not notarized',
              'machO': build_report, 'xcode': run('xcodebuild', '-version', capture=True).strip()}
    (output / f'{app_name}-build.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f'Verified isolated application: {app}')


if __name__ == '__main__':
    main()
