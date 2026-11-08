#!/usr/bin/env python3
"""Generate the cases this library must reproduce from LangChain, so the suite can replay them on
every target with no Python in the loop.

Three families of cases come out of here:

* **Splitting.** `MarkdownHeaderTextSplitter` reads a document and returns the chunks. The corpus is
  deliberately made of sections that hold exactly one block, because the reference writes a section
  that held several blocks by joining them with a Markdown hard break (`"  \\n"`) and strips each line
  as it goes, which changes the text of both prose and code. Those two behaviours are covered by this
  library's own tests, and the divergence is written down in the README.
* **Similarity.** `InMemoryVectorStore` ranks a fixed set of vectors against a query. The vectors are
  written down, so the expected order is arithmetic and not a model's opinion.
* **MMR.** `maximal_marginal_relevance` picks the candidates this library's `mmr` must pick, for
  several values of lambda.

    python3 -m venv .venv && .venv/bin/pip install langchain-text-splitters==1.1.3 langchain-core==1.7.6 numpy
    .venv/bin/python scripts/gen_langchain_cases.py > src/conformance/langchain_cases_wbtest.mbt

Pinned on purpose: the reference's splitter and its ranking both changed between releases, and
fixtures from another version would test a different algorithm.
"""

from __future__ import annotations

import sys

EXPECTED_SPLITTERS = "1.1.3"
EXPECTED_CORE = "1.7.6"

# (name, text, headers to split on, chunk size). Every section holds one block: see the docstring.
MARKDOWN_CASES = [
    (
        "guide",
        "# Guide\nOpening words.\n\n## Install\nmoon add moonbitstack/moonrag.\n\n## Search\nBuild a store, then search.\n",
        [("#", "h1"), ("##", "h2")],
        4000,
    ),
    (
        "preamble",
        "A note to begin with.\n\n# Title\nBody.\n",
        [("#", "h1")],
        4000,
    ),
    (
        "nested",
        "# Guide\nOpening words.\n\n## Install\nmoon add.\n\n### From source\nClone the repository.\n\n## Search\nThen search.\n",
        [("#", "h1"), ("##", "h2"), ("###", "h3")],
        4000,
    ),
    (
        "code",
        "# Build\n```moonbit\nlet x = 1\n```\n",
        [("#", "h1")],
        4000,
    ),
    (
        "code with a hash",
        "# Build\n```bash\n# install the tool\nmoon add moonbitstack/moonrag\n```\n",
        [("#", "h1")],
        4000,
    ),
    (
        "list",
        "# Notes\n- one\n- two\n",
        [("#", "h1")],
        4000,
    ),
    (
        "heading with no body",
        "# Empty\n# Filled\nBody.\n",
        [("#", "h1")],
        4000,
    ),
    (
        "two levels of one heading",
        "# A\nFirst.\n## B\nSecond.\n",
        [("#", "h1"), ("##", "h2")],
        4000,
    ),
]

# The documents the ranking cases search, with the vectors they are indexed under.
DOCUMENTS = [
    ("the harbour at dawn, fishing boats leaving", [1.0, 0.0, 0.0, 0.0]),
    ("fishing boats return to the harbour at dusk", [0.86, 0.5, 0.0, 0.0]),
    ("a mountain path in autumn, cold and clear", [0.0, 1.0, 0.0, 0.0]),
    ("an autumn afternoon on the ridge", [0.1, 0.9, 0.2, 0.0]),
    ("the harbour wall, repaired with granite", [0.7, 0.1, 0.6, 0.1]),
    ("granite and lime, a note on mortar", [0.0, 0.0, 1.0, 0.0]),
    ("a quiet room with a window", [0.0, 0.1, 0.0, 1.0]),
]

# (name, query vector, limit)
RANK_CASES = [
    ("boats, best one", [0.9, 0.1, 0.0, 0.1], 1),
    ("boats, three", [0.9, 0.1, 0.0, 0.1], 3),
    ("boats, everything", [0.9, 0.1, 0.0, 0.1], 7),
    ("the ridge", [0.2, 0.8, 0.3, 0.0], 4),
    ("stones", [0.0, 0.0, 0.9, 0.2], 2),
]

# (name, query vector, lambda, limit)
MMR_CASES = [
    ("boats, lambda 0", [0.9, 0.1, 0.0, 0.1], 0.0, 3),
    ("boats, lambda 0.25", [0.9, 0.1, 0.0, 0.1], 0.25, 3),
    ("boats, lambda 0.5", [0.9, 0.1, 0.0, 0.1], 0.5, 3),
    ("boats, lambda 0.75", [0.9, 0.1, 0.0, 0.1], 0.75, 3),
    ("boats, lambda 1", [0.9, 0.1, 0.0, 0.1], 1.0, 3),
    ("boats, five of seven", [0.9, 0.1, 0.0, 0.1], 0.3, 5),
    ("the ridge, lambda 0.2", [0.2, 0.8, 0.3, 0.0], 0.2, 4),
]


def moonbit_string(value: str) -> str:
    out = ['"']
    for char in value:
        if char == "\\":
            out.append("\\\\")
        elif char == '"':
            out.append('\\"')
        elif char == "\n":
            out.append("\\n")
        elif char == "\t":
            out.append("\\t")
        elif char == "\r":
            out.append("\\r")
        elif 0x20 <= ord(char) < 0x7F:
            out.append(char)
        else:
            out.append("\\u{%X}" % ord(char))
    out.append('"')
    return "".join(out)


def moonbit_double(value: float) -> str:
    text = repr(float(value))
    if "e" in text:
        raise SystemExit(f"a value in exponent form would not read well in the fixture: {text}")
    if "." not in text:
        text += ".0"
    return text


def markdown_cases() -> list:
    from langchain_text_splitters import MarkdownHeaderTextSplitter

    cases = []
    for name, text, headers, chunk_size in MARKDOWN_CASES:
        splitter = MarkdownHeaderTextSplitter(headers_to_split_on=headers)
        chunks = splitter.split_text(text)
        cases.append((name, text, headers, chunk_size, chunks))
    return cases


def rank_cases() -> list:
    from langchain_core.embeddings import Embeddings
    from langchain_core.vectorstores import InMemoryVectorStore

    class Table(Embeddings):
        def __init__(self, table):
            self.table = table

        def embed_documents(self, texts):
            return [self.table[text] for text in texts]

        def embed_query(self, text):
            return self.table[text]

    table = {text: vector for text, vector in DOCUMENTS}
    store = InMemoryVectorStore(embedding=Table(table))
    store.add_texts([text for text, _ in DOCUMENTS])
    cases = []
    for name, query, limit in RANK_CASES:
        query_vector = [float(value) for value in query]
        hits = store.similarity_search_with_score_by_vector(query_vector, k=limit)
        cases.append(
            (
                name,
                query_vector,
                limit,
                [document.page_content for document, _ in hits],
                [float(score) for _, score in hits],
            )
        )
    return cases


def mmr_cases() -> list:
    import numpy as np
    from langchain_core.vectorstores.utils import maximal_marginal_relevance

    vectors = [vector for _, vector in DOCUMENTS]
    texts = [text for text, _ in DOCUMENTS]
    cases = []
    for name, query, lambda_mult, limit in MMR_CASES:
        picks = maximal_marginal_relevance(
            np.array(query, dtype=np.float64),
            np.array(vectors, dtype=np.float64),
            lambda_mult=lambda_mult,
            k=limit,
        )
        cases.append((name, query, lambda_mult, limit, [texts[i] for i in picks]))
    return cases


def generate() -> str:
    marks = markdown_cases()
    ranks = rank_cases()
    mmrs = mmr_cases()

    lines = [
        "// Generated by scripts/gen_langchain_cases.py from langchain-text-splitters "
        + EXPECTED_SPLITTERS,
        "// and langchain-core " + EXPECTED_CORE + ". Do not edit: change the script and regenerate.",
        "",
        "///|",
        "/// One Markdown case: the document, the levels that split, and the chunks the reference",
        "/// produced, each with the heading path it was filed under.",
        "pub(all) struct MarkdownCase {",
        "  name : String",
        "  text : String",
        "  headings : Array[(Int32, String)]",
        "  chunk_size : Int32",
        "  texts : Array[String]",
        "  paths : Array[Array[(String, String)]]",
        "}",
        "",
        "///|",
        f"/// The {len(marks)} splitting cases, replayed by the conformance suite.",
        "pub fn markdown_cases() -> Array[MarkdownCase] {",
        "  [",
    ]
    for name, text, headers, chunk_size, chunks in marks:
        own_headers = ", ".join(
            "(%d, %s)" % (len(mark), moonbit_string(key)) for mark, key in headers
        )
        texts = ", ".join(moonbit_string(chunk.page_content) for chunk in chunks)
        paths = []
        for chunk in chunks:
            entries = sorted(chunk.metadata.items())
            rendered = ", ".join(
                "(%s, %s)" % (moonbit_string(key), moonbit_string(value))
                for key, value in entries
            )
            paths.append("[" + rendered + "]")
        lines.append(
            "    { name: %s, text: %s, headings: [%s], chunk_size: %d, texts: [%s], paths: [%s] },"
            % (
                moonbit_string(name),
                moonbit_string(text),
                own_headers,
                chunk_size,
                texts,
                ", ".join(paths),
            )
        )
    lines += [
        "  ]",
        "}",
        "",
        "///|",
        "/// One ranking case: fixed vectors, a query, and the order and scores the reference returned.",
        "pub(all) struct RankCase {",
        "  name : String",
        "  texts : Array[String]",
        "  vectors : Array[Array[Double]]",
        "  query : Array[Double]",
        "  limit : Int32",
        "  order : Array[String]",
        "  scores : Array[Double]",
        "}",
        "",
        "///|",
        f"/// The {len(ranks)} ranking cases, replayed by the conformance suite.",
        "pub fn rank_cases() -> Array[RankCase] {",
        "  [",
    ]
    documents = ", ".join(moonbit_string(text) for text, _ in DOCUMENTS)
    vectors = ", ".join(
        "[" + ", ".join(moonbit_double(value) for value in vector) + "]"
        for _, vector in DOCUMENTS
    )
    for name, query, limit, order, scores in ranks:
        lines.append(
            "    { name: %s, texts: [%s], vectors: [%s], query: [%s], limit: %d, order: [%s], scores: [%s] },"
            % (
                moonbit_string(name),
                documents,
                vectors,
                ", ".join(moonbit_double(value) for value in query),
                limit,
                ", ".join(moonbit_string(text) for text in order),
                ", ".join(moonbit_double(score) for score in scores),
            )
        )
    lines += [
        "  ]",
        "}",
        "",
        "///|",
        "/// One MMR case: the same vectors, a lambda, and the picks the reference made.",
        "pub(all) struct MmrCase {",
        "  name : String",
        "  texts : Array[String]",
        "  vectors : Array[Array[Double]]",
        "  query : Array[Double]",
        "  lambda : Double",
        "  limit : Int32",
        "  picks : Array[String]",
        "}",
        "",
        "///|",
        f"/// The {len(mmrs)} MMR cases, replayed by the conformance suite.",
        "pub fn mmr_cases() -> Array[MmrCase] {",
        "  [",
    ]
    for name, query, lambda_mult, limit, picks in mmrs:
        lines.append(
            "    { name: %s, texts: [%s], vectors: [%s], query: [%s], lambda: %s, limit: %d, picks: [%s] },"
            % (
                moonbit_string(name),
                documents,
                vectors,
                ", ".join(moonbit_double(value) for value in query),
                moonbit_double(lambda_mult),
                limit,
                ", ".join(moonbit_string(text) for text in picks),
            )
        )
    lines += ["  ]", "}", ""]
    return "\n".join(lines)


def main() -> int:
    import importlib.metadata

    for package, expected in (
        ("langchain-text-splitters", EXPECTED_SPLITTERS),
        ("langchain-core", EXPECTED_CORE),
    ):
        installed = importlib.metadata.version(package)
        if installed != expected:
            print(
                f"warning: generating from {package} {installed}, the fixtures were written for {expected}",
                file=sys.stderr,
            )
    sys.stdout.write(generate())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
