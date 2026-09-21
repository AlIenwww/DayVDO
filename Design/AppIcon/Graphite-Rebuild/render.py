"""Render the editable icon with Apple's generation-27 renderer."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent
TOOL = Path('/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool')

if not TOOL.is_file():
    raise SystemExit('Icon Composer bundled with Xcode was not found.')

for size in (1024, 256, 64):
    suffix = '' if size == 1024 else f'-{size}'
    output = ROOT / f'DayVDO-Graphite-27{suffix}.png'
    subprocess.run([
        str(TOOL), str(ROOT / 'DayVDO-Graphite-Clean.icon'),
        '--export-image', '--output-file', str(output),
        '--platform', 'macOS', '--rendition', 'Default',
        '--width', str(size), '--height', str(size), '--scale', '1',
        '--design-generation', '27',
    ], check=True)
    print(output)
