#!/usr/bin/env python3
# 极连远程 CI 专用：干掉 Flutter SDK material/app.dart 里 _errorTextStyle 的黄色双下划线。
# 该下划线会让无 Material 祖先的 Text 继承诡异黄线（V45~V50 反复踩坑，只有改 SDK 才根治）。
# 采用块级正则替换，幂等、不依赖精确 diff、不破坏其它代码。
import sys
import re


def patch(path: str) -> bool:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    pat = re.compile(
        r"(const TextStyle _errorTextStyle = TextStyle\()"
        r"(.*?)"
        r"(\);)",
        re.DOTALL,
    )

    m = pat.search(content)
    if not m:
        print("WARN: _errorTextStyle not found, skip", path)
        return False

    body = m.group(2)
    changed = False

    new_body, n = re.subn(
        r"decoration:\s*TextDecoration\.underline",
        "decoration: TextDecoration.none",
        body,
    )
    if n:
        changed = True
        body = new_body

    new_body, n = re.subn(
        r"decorationColor:\s*Color\(0xFFFFFF00\)",
        "decorationColor: Color(0x00000000)",
        body,
    )
    if n:
        changed = True
        body = new_body

    if changed and "jilian-remote patched" not in body:
        body = body.rstrip()
        if not body.endswith(","):
            body += ","
        body += "\n  // jilian-remote patched: yellow underline removed\n"

    if changed:
        content = content[: m.start()] + m.group(1) + body + m.group(3) + content[m.end() :]
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print("PATCHED:", path)
        return True

    print("ALREADY PATCHED (no-op):", path)
    return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: fix_error_text_style.py <path-to-material/app.dart>")
        sys.exit(2)
    patch(sys.argv[1])
