#!/usr/bin/env python3
"""Fill the numbers the site states with numbers read from the repository.

A page that says "six packages" is wrong the day a seventh package exists. Each figure lives between
`<!--num:key-->` and `<!--/num-->` markers and is rewritten from the sources here, so the workflow can
regenerate the pages and fail on a diff.

    python scripts/gen_site_numbers.py          # rewrite docs/*.html
    python scripts/gen_site_numbers.py --check  # exit 1 when a page is out of date
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARKER = re.compile(r"<!--num:([a-z]+)-->.*?<!--/num-->", re.S)


def packages() -> int:
    """Library packages: everything under src/ that is not an example or a test-only package."""
    count = 0
    for moon_pkg in (ROOT / "src").rglob("moon.pkg"):
        parts = moon_pkg.relative_to(ROOT / "src").parts
        if "examples" in parts or "conformance" in parts:
            continue
        count += 1
    return count


def backends() -> int:
    """Vector stores the standard cases run against: the in-memory one plus each integration backend."""
    integration = ROOT / "integration" / "src"
    extra = 0
    if integration.is_dir():
        extra = sum(1 for path in integration.iterdir() if path.is_dir() and path.name != "standard")
    return 1 + extra


def cases() -> int:
    """Reference cases replayed: one `name: "..."` per entry in the generated fixtures."""
    total = 0
    for path in sorted((ROOT / "src" / "conformance").glob("*_cases_wbtest.mbt")):
        total += path.read_text(encoding="utf-8").count('name: "')
    return total


def examples() -> int:
    """Runnable examples: a package with an executable kind, outside the browser glue."""
    count = 0
    for moon_pkg in (ROOT / "src" / "examples").glob("*/moon.pkg"):
        if moon_pkg.parent.name == "browser":
            continue
        if 'kind: "executable"' in moon_pkg.read_text(encoding="utf-8"):
            count += 1
    return count


def values() -> dict[str, int]:
    return {
        "packages": packages(),
        "backends": backends(),
        "cases": cases(),
        "examples": examples(),
    }


def main() -> int:
    figures = values()
    stale: list[str] = []
    for page in sorted((ROOT / "docs").glob("*.html")):
        text = page.read_text(encoding="utf-8")

        def replace(match: re.Match) -> str:
            key = match.group(1)
            if key not in figures:
                raise SystemExit(f"{page.name}: no figure named {key}")
            return f"<!--num:{key}-->{figures[key]}<!--/num-->"

        updated = MARKER.sub(replace, text)
        if updated == text:
            continue
        stale.append(page.name)
        if "--check" in sys.argv:
            print(f"{page.name}: a figure is out of date", file=sys.stderr)
        else:
            page.write_text(updated, encoding="utf-8", newline="\n")
    if "--check" in sys.argv:
        return 1 if stale else 0
    print("numbers: " + ", ".join(f"{key}={value}" for key, value in figures.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
