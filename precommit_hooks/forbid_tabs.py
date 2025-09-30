from __future__ import annotations

import sys
from pathlib import Path
from typing import List


def main(paths: List[str]) -> int:
    offending: List[Path] = []

    for name in paths:
        path = Path(name)
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue

        if "\t" in text:
            offending.append(path)

    if offending:
        for path in offending:
            print(f"Tabs found in {path}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
