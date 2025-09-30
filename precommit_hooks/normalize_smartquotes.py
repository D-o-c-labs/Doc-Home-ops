from __future__ import annotations

import sys
import unicodedata
from pathlib import Path
from typing import List

_REPLACEMENTS = {
    0x2018: "'",
    0x2019: "'",
    0x201C: '"',
    0x201D: '"',
}


def normalize_text(text: str) -> str:
    return unicodedata.normalize("NFKC", text).translate(_REPLACEMENTS)


def main(paths: List[str]) -> int:
    for name in paths:
        path = Path(name)
        try:
            original = path.read_text()
        except UnicodeDecodeError:
            continue

        normalized = normalize_text(original)
        if normalized != original:
            path.write_text(normalized)
            print(f"Normalized smart quotes in {path}")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
