# Validate every data/*.json: strip comments the same way data_loader.gd
# (_strip_json_comments — taking strings into account), then parse the JSON.
# Usage: python tools/validate_json.py [root]   (root defaults to "data")
import json
import os
import sys


def strip_comments(text: str) -> str:
    result = []
    in_string = False
    in_single = False
    in_multi = False
    i = 0
    while i < len(text):
        c = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if not in_string and not in_single and not in_multi:
            if c == '"':
                in_string = True
                result.append(c)
                i += 1
                continue
            if c == "/" and nxt == "/":
                in_single = True
                i += 2
                continue
            if c == "/" and nxt == "*":
                in_multi = True
                i += 2
                continue
        if in_string:
            if c == '"':
                # A quote closes the literal only when an even number of backslashes
                # precedes it; an escaped backslash ("foo\\") must not end the string.
                backslashes = 0
                j = i - 1
                while j >= 0 and text[j] == "\\":
                    backslashes += 1
                    j -= 1
                if backslashes % 2 == 0:
                    in_string = False
            result.append(c)
            i += 1
            continue
        if in_single:
            if c == "\n":
                in_single = False
                result.append(c)
            i += 1
            continue
        if in_multi:
            if c == "*" and nxt == "/":
                in_multi = False
                i += 2
                continue
            i += 1
            continue
        result.append(c)
        i += 1
    return "".join(result)


def main(root: str) -> int:
    failed = 0
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            if not name.endswith(".json"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            try:
                json.loads(strip_comments(text))
                print("OK  ", os.path.relpath(path, root))
            except json.JSONDecodeError as exc:
                failed += 1
                print("FAIL", os.path.relpath(path, root), "-", exc)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "data"))
