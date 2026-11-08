#!/usr/bin/env python3
"""Write docs/api.html from each package's interface file and the `///` comments in its sources.

The interface file is the authority on *what* exists: every `pub` line in it is listed, including
generic functions (`pub fn[T] f`), methods hung off a type, traits, values and error types. The
sources are the authority on *why*: each item's doc comment is read from the `///|` block above it.

    python scripts/gen_api.py          # writes docs/api.html
    python scripts/gen_api.py --check  # exits 1 when docs/api.html is out of date
"""

from __future__ import annotations

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

PACKAGES = [
    (
        "moonbitstack/moonrag",
        "src",
        "Documents, the five contracts, the in-memory store, the retrievers, vector arithmetic and metadata filters.",
    ),
    (
        "moonbitstack/moonrag/split",
        "src/split",
        "Cutting a document into chunks: recursive separators, a token budget, Markdown sections and HTML sections.",
    ),
    (
        "moonbitstack/moonrag/load",
        "src/load",
        "Text, CSV, JSON, Markdown and HTML into documents, from bytes already in memory.",
    ),
    (
        "moonbitstack/moonrag/load/file",
        "src/load/file",
        "The same loaders reading from disk. Native only: a filesystem is not something every target has.",
    ),
    (
        "moonbitstack/moonrag/index",
        "src/index",
        "Incremental indexing: a content hash per id, so a second run over an unchanged corpus embeds nothing.",
    ),
    (
        "moonbitstack/moonrag/sql",
        "src/sql",
        "The same store over a table, for any driver implementing moondb's AsyncDriver. PostgreSQL with pgvector ranks in the statement; SQLite ranks in this process.",
    ),
]

DECL = re.compile(
    r"^pub(?:\((?:all|open)\))?\s+(?:async\s+)?"
    r"(fn(?:\[[^\]]*\])?|let|struct|enum|suberror|trait|type)\s+"
    r"([A-Za-z_][\w]*(?:::[A-Za-z_][\w]*)?)"
)


def docs_of(folder: pathlib.Path) -> dict[str, str]:
    """Doc comments by declared name, and by `Type.field` for fields, variants and methods."""
    out: dict[str, str] = {}
    for path in sorted(folder.glob("*.mbt")):
        if path.name.endswith("_test.mbt") or path.name.endswith("_wbtest.mbt"):
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        pending: list[str] = []
        owner: str | None = None
        for line in lines:
            stripped = line.strip()
            if stripped == "///|":
                pending = []
                continue
            if stripped.startswith("///"):
                pending.append(stripped[3:].strip())
                continue
            if stripped.startswith("#"):
                continue
            match = DECL.match(line)
            if match:
                name = match.group(2)
                if pending:
                    out[name] = " ".join(pending)
                owner = (
                    name
                    if match.group(1) in ("struct", "enum", "suberror", "trait")
                    and line.rstrip().endswith("{")
                    else None
                )
                pending = []
                continue
            if owner and line.startswith("}"):
                owner = None
            elif owner and pending:
                field = re.match(r"\s+(?:fn\s+)?(?:mut\s+)?([A-Za-z_]\w*)", line)
                if field:
                    out[owner + "." + field.group(1)] = " ".join(pending)
            pending = []
    return out


def items_of(folder: pathlib.Path) -> list[tuple[str, str, str, str | None]]:
    """Declarations from the interface file: (kind, name, text, owner)."""
    text = (folder / "pkg.generated.mbti").read_text(encoding="utf-8").splitlines()
    items: list[tuple[str, str, str, str | None]] = []
    block: list | None = None
    for line in text:
        if block is not None:
            block[2].append(line)
            if line.startswith("}"):
                items.append((block[0], block[1], "\n".join(block[2]), None))
                block = None
            continue
        if not line.startswith("pub"):
            continue
        match = re.match(r"pub(?:\((?:all|open)\))?\s+(struct|enum|suberror|trait)\s+(\w+)", line)
        if match and line.rstrip().endswith("{"):
            block = [match.group(1), match.group(2), [line]]
            continue
        if match:
            items.append((match.group(1), match.group(2), line, None))
            continue
        match = re.match(r"pub (?:async )?fn(?:\[[^\]]*\])?\s+(\w+)::(\w+)", line)
        if match:
            items.append(("method", match.group(1) + "::" + match.group(2), line, match.group(1)))
            continue
        match = re.match(r"pub (?:async )?fn(?:\[[^\]]*\])?\s+(\w+)", line)
        if match:
            items.append(("fn", match.group(1), line, None))
            continue
        match = re.match(r"pub let (\w+)", line)
        if match:
            items.append(("let", match.group(1), line, None))
            continue
        match = re.match(r"pub type (\w+)", line)
        if match:
            items.append(("type", match.group(1), line, None))
            continue
        match = re.match(r"pub using @(\w+) \{(.*)\}", line)
        if match:
            items.append(("using", match.group(1), line, None))
    return items


def signature(text: str) -> str:
    return '<pre class="sig scroll"><code>%s</code></pre>' % html.escape(text.strip())


def prose(text: str | None) -> str:
    if not text:
        return ""
    escaped = html.escape(text)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    return "<p>%s</p>" % escaped


def anchor(package: str, name: str) -> str:
    return (package.split("/")[-1] + "-" + name).replace("::", "-").lower()


DERIVED = re.compile(
    r"::(equal|not_equal|output|to_string|to_repr|hash|hash_combine|compare|op_\w+)\("
)
DERIVED_NAME = re.compile(
    r"::(equal|not_equal|output|to_string|to_repr|hash|hash_combine|compare|op_\w+)$"
)


def render() -> str:
    nav: list[str] = []
    body: list[str] = []
    missing: list[str] = []
    for package, folder_name, intro in PACKAGES:
        folder = ROOT / folder_name
        docs = docs_of(folder)
        items = items_of(folder)
        short = package.split("/moonrag", 1)[1].lstrip("/") or "moonrag"
        nav.append('<div class="group"><b>%s</b>' % html.escape(short))
        body.append(
            '<section id="%s"><h2>%s</h2>%s'
            % (anchor(package, "top"), html.escape(short), prose(intro))
        )
        types = [item for item in items if item[0] in ("struct", "enum", "suberror", "trait", "type")]
        methods: dict[str, list[tuple[str, str]]] = {}
        for kind, name, text, owner in items:
            if kind == "method" and owner:
                methods.setdefault(owner, []).append((name, text))
        values = [item for item in items if item[0] == "let"]
        functions = [item for item in items if item[0] == "fn"]
        usings = [item for item in items if item[0] == "using"]

        if usings:
            body.append("<h3>Re-exported</h3>")
            body.append(
                prose(
                    "Reachable from this package as well; each is documented in the package it comes from."
                )
            )
            body.append(signature("\n".join(item[2] for item in usings)))

        listed = {
            item[1]
            for item in items
            if item[0] != "using" and not DERIVED_NAME.search(item[1])
        }
        seen: set[str] = set()
        for kind, name, text, _ in types:
            seen.add(name)
            nav.append('<a href="#%s">%s</a>' % (anchor(package, name), html.escape(name)))
            body.append(
                '<article class="api" id="%s"><h3><span class="kind">%s</span>%s</h3>'
                % (anchor(package, name), kind, html.escape(name))
            )
            body.append(prose(docs.get(name)))
            body.append(signature(text))
            fields = [
                (key.split(".", 1)[1], value)
                for key, value in docs.items()
                if key.startswith(name + ".")
            ]
            if fields:
                body.append(
                    '<dl class="fields">%s</dl>'
                    % "".join(
                        "<dt><code>%s</code></dt><dd>%s</dd>"
                        % (html.escape(field), prose(description))
                        for field, description in fields
                    )
                )
            for method_name, method_text in methods.get(name, []):
                if DERIVED.search(method_text):
                    continue
                seen.add(method_name)
                body.append(
                    '<div class="member" id="%s">%s%s</div>'
                    % (
                        anchor(package, method_name),
                        signature(method_text),
                        prose(docs.get(method_name)),
                    )
                )
            body.append("</article>")

        for title, group, kind in (
            ("Functions", functions, "fn"),
            ("Values", values, "let"),
        ):
            if not group:
                continue
            nav.append('<a href="#%s">%s</a>' % (anchor(package, kind + "s"), title))
            body.append('<h3 id="%s">%s</h3>' % (anchor(package, kind + "s"), title))
            for _, name, text, _ in group:
                seen.add(name)
                body.append(
                    '<div class="member" id="%s">%s%s</div>'
                    % (anchor(package, name), signature(text), prose(docs.get(name)))
                )
        for name in sorted(listed - seen):
            missing.append(package + "." + name)
        nav.append("</div>")
        body.append("</section>")

    if missing:
        raise SystemExit(
            "these public names were not rendered: " + ", ".join(missing)
        )
    page = (ROOT / "docs" / "api.template.html").read_text(encoding="utf-8")
    page = page.replace("<!-- nav -->", "\n".join(nav)).replace("<!-- body -->", "\n".join(body))
    return page


def main() -> int:
    rendered = render()
    target = ROOT / "docs" / "api.html"
    if "--check" in sys.argv:
        current = target.read_text(encoding="utf-8") if target.exists() else ""
        if current != rendered:
            print("docs/api.html is out of date: run python scripts/gen_api.py", file=sys.stderr)
            return 1
        return 0
    target.write_text(rendered, encoding="utf-8", newline="\n")
    print("wrote docs/api.html")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
