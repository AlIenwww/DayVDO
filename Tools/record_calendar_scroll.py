#!/usr/bin/env python3
"""Record manual scrolling in a running isolated comparison app; never opens production data."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path, help='Running isolated .app bundle')
    parser.add_argument('--seconds', type=int, default=30)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--ready', action='store_true', help='Skip the interactive preparation prompt')
    args = parser.parse_args()
    if not 10 <= args.seconds <= 60:
        parser.error('--seconds must be between 10 and 60')
    app = args.app.resolve()
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if not info.get('CFBundleIdentifier', '').startswith('com.wuyuchen.DayVDO.CompatibilityTest.'):
        parser.error('Only a DayVDO isolated test bundle may be recorded')
    data = info.get('DayVDOTestingDataPath')
    if not data or not Path(data).is_file():
        parser.error('The bundle must name an existing, explicit test fixture')
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    processes = subprocess.check_output(['ps', '-ax', '-o', 'pid=', '-o', 'comm='], text=True)
    pids = []
    for line in processes.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) == 2 and Path(fields[1]).resolve() == executable:
            pids.append(fields[0])
    if len(pids) != 1:
        parser.error('先打开这个测试包；必须恰好有一个对应进程正在运行。')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    name = f"{info['CFBundleExecutable']}-{stamp}"
    trace = output / f'{name}.trace'
    log = output / f'{name}.log'
    print(f"测试应用：{info['CFBundleExecutable']}（PID {pids[0]}）", flush=True)
    print('进入 日历 → 月，清除筛选，点击 今天；两个应用保持相同窗口大小。', flush=True)
    print('先上下滚动两次预热，再点击 今天。准备好后回到此终端按回车。', flush=True)
    if not args.ready:
        input()
    print('五秒内切回测试应用，把指针放在日历中部。', flush=True)
    for remaining in range(5, 0, -1):
        print(remaining, flush=True)
        time.sleep(1)
    print(f'开始：持续 {args.seconds} 秒，约每秒换一次方向，上下移动约一至两周。', flush=True)
    print('让密集任务区域反复经过标题下方；不要切页、改窗口大小或编辑任务。', flush=True)
    command = ['xcrun', 'xctrace', 'record', '--template', 'Time Profiler', '--attach', pids[0],
               '--time-limit', f'{args.seconds}s', '--output', str(trace)]
    metadata = {
        'app': str(app), 'pid': int(pids[0]), 'durationSeconds': args.seconds,
        'nativeMonthPrototype': info.get('DayVDONativeMonthPrototype', False),
        'executableSHA256': hashlib.sha256(executable.read_bytes()).hexdigest(),
        'fixtureSHA256': hashlib.sha256(Path(data).read_bytes()).hexdigest(),
        'startTime': datetime.datetime.now().isoformat(), 'command': command,
        'note': 'Manual gestures; CPU samples do not establish frame rate or energy savings.',
    }
    with log.open('w') as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    metadata['exitCode'] = result.returncode
    metadata['endTime'] = datetime.datetime.now().isoformat()
    (output / f'{name}.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    if result.returncode:
        print(log.read_text())
        raise SystemExit(result.returncode)
    print(f'录制结束：{trace}\n可以停止滚动。告诉 Codex 已完成及体感即可，无需上传文件。', flush=True)


if __name__ == '__main__':
    main()
