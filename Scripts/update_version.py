#!/usr/bin/env python3
"""Interactively update DayVDO's source and packaging version together."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", re.ASCII)
TARGETS = (
    ("Scripts/build_app.py", re.compile(r"('CFBundleShortVersionString': ')([^'\n]+)(')")),
    ("Sources/DayVDO/Views/SettingsView.swift",
     re.compile(r'(// shipped app always takes the version from its bundle above\.\n\s*\?\? ")([^"\n]+)(")')),
)


def main():
    originals = {}
    for relative, pattern in TARGETS:
        path = ROOT / relative
        content = path.read_bytes()
        matches = list(pattern.finditer(content.decode("utf-8")))
        if len(matches) != 1:
            raise RuntimeError(f"无法唯一定位版本号：{relative}。未修改文件。")
        originals[path] = (content, pattern, matches[0].group(2))

    print("DayVDO 版本号更新\n")
    for path, (_, _, current) in originals.items():
        print(f"{path.relative_to(ROOT)}：{current}")
    while True:
        version = input("\n请输入新版本号（例如 0.5.3，直接回车取消）：").strip()
        if not version:
            print("已取消，未修改文件。")
            return
        if VERSION.fullmatch(version):
            break
        print("格式不正确，请输入三段数字，例如 0.5.3 或 1.0.0。")

    updates = {}
    for path, (content, pattern, _) in originals.items():
        updated = pattern.sub(lambda match: match[1] + version + match[3], content.decode("utf-8")).encode("utf-8")
        if updated != content:
            updates[path] = updated
    if not updates:
        print(f"\n当前已是 {version}，无需修改。")
        return

    # Validate both files before writing; preserve any edits made while prompting.
    for path, (content, _, _) in originals.items():
        if path.read_bytes() != content:
            raise RuntimeError(f"文件在等待输入时发生变化：{path.name}。请重新运行。")
    written = []
    try:
        for path, updated in updates.items():
            written.append(path)
            path.write_bytes(updated)
    except OSError:
        for path in reversed(written):
            path.write_bytes(originals[path][0])
        raise
    print(f"\n已将版本号同步更新为 {version}。")
    print("重新运行或打包后生效；现有 App 需重新构建。")


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("\n已取消。")
        sys.exit(130)
    except (OSError, RuntimeError, UnicodeError) as error:
        print(f"\n更新失败：{error}", file=sys.stderr)
        sys.exit(1)
