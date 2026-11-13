<div align="center">

# moonrag

**Documents, splitting, vectors and retrieval for MoonBit. Embeddings arrive through a contract, so nothing here calls a model.**

[**site**](https://moonbitstack.github.io/moonrag/) &nbsp;·&nbsp; [**guide**](https://moonbitstack.github.io/moonrag/guide.html) &nbsp;·&nbsp; [**api**](https://moonbitstack.github.io/moonrag/api.html) &nbsp;·&nbsp; [**demo**](https://moonbitstack.github.io/moonrag/demo.html) &nbsp;·&nbsp; [**mooncakes**](https://mooncakes.io/docs/moonbitstack/moonrag)

[![CI](https://github.com/moonbitstack/moonrag/actions/workflows/ci.yml/badge.svg)](https://github.com/moonbitstack/moonrag/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-b23a1f.svg)](LICENSE)

</div>

---

```moonbit
async fn answer(embedder : &@moonrag.Embedder) -> Array[@moonrag.Scored] raise {
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = store.add([
    @moonrag.Document::new(
      "the harbour at dawn, fishing boats leaving",
      meta=Map([("topic", @json.Json::string("sea"))]),
    ),
    @moonrag.Document::new("a mountain path in autumn, cold and clear"),
  ])
  let query = embedder.embed(["boats in the harbour"])[0]
  store.search(
    query[:],
    limit=1,
    filter=@moonrag.Filter::Equal("topic", @json.Json::string("sea")),
  )
}
```

Five stages, five contracts: load bytes into documents, split them into chunks, embed the chunks, store the vectors, retrieve the best. Every stage is replaceable without touching the others, and none of them knows which embedding model is in use.

## Install

```shell
moon add moonbitstack/moonrag
```

```moonbit
import {
  "moonbitstack/moonrag",           // documents, contracts, memory store, retrieval
  "moonbitstack/moonrag/split",     // recursive, token, Markdown and HTML splitters
  "moonbitstack/moonrag/load",      // text, CSV, JSON, Markdown, HTML loaders
  "moonbitstack/moonrag/load/file", // the same loaders, reading from disk
  "moonbitstack/moonrag/index",     // incremental indexing
  "moonbitstack/moonrag/sql",       // a store in SQL, over any moondb driver
}
```

## A document is the unit

Everything moves `Document`: some text, an optional id, and metadata. The id is what a store keys by — set it and a re-index updates in place; leave it empty and an id is derived from the content. The metadata is what a filter reads, and what a retrieved chunk uses to say where it came from.

```moonbit
let document = @moonrag.Document::new("some text", id="guide.md#2")
  .set_meta("source", @json.Json::string("guide.md"))
  .set_meta("page", @json.Json::number(3.0))
```

Splitters add `chunk` and, when asked, `start_index`; the HTML splitter adds `h1` … `h6`. Nothing else is reserved.

## Filters travel with the query

A `Filter` is data, so a store applies it where the documents live instead of the caller re-ranking afterwards:

```moonbit
let recent = @moonrag.Filter::All([
  @moonrag.Filter::Equal("topic", @json.Json::string("sea")),
  @moonrag.Filter::Compare("year", @moonrag.Order::AtLeast, 2025.0),
])
```

`Equal`, `OneOf`, `Exists`, `Compare` against `Less`/`AtMost`/`AtLeast`/`Greater`, combined with `All`, `Any`, `Not`. A document missing the key matches nothing except a `Not` of a filter it fails.

## Embedding is a contract

```moonbit
pub(open) trait Embedder {
  async fn embed(Self, texts : ArrayView[String]) -> Array[Array[Double]] raise
}
```

One call embeds a batch, because that is what a model charges for and what makes a re-index affordable. Implement it over a hosted model, a local one, or a deterministic stand-in: the rest of the library never learns which.

`HashingEmbedder` is such a stand-in: it hashes words and character trigrams into a fixed-width vector, needs no network, and returns the same vector for the same text on every target. It is lexical rather than semantic — useful for tests, examples and keyword-ish retrieval, not for production ranking.

## Storing

`InMemoryVectorStore` is the reference implementation of `VectorStore`: documents in insertion order, every candidate scored on each search, filters applied before ranking.

```moonbit
let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
let store = @moonrag.InMemoryVectorStore::new(embedder)
let query_vector = embedder.embed(["boats in the harbour"])[0]
let ids = store.add([document])
let hits = store.search(query_vector, limit=5)
store.delete([ids[0]][:])
```

An id that is already stored is replaced in place, which is what makes a re-index an update rather than a duplicate. Hits carry the id they are stored under, so a caller can delete what it just retrieved.

Already have vectors? `add_vectors` takes them and skips the embedding.

## Storing in SQL

`SqlVectorStore` is the same contract over a table, for a corpus that has to outlive the process. It is
written against `moondb`'s driver contract, so the database is chosen when the connection is opened and
nothing here names it again: the store asks the driver for its dialect and picks a plan.

```moonbit
pub async fn[T : @moondb.AsyncDriver] search_with(
  driver : T,
  embedder : &@moonrag.Embedder,
) -> Array[@moonrag.Scored] raise {
  let store = @sql.SqlVectorStore::new(driver, embedder, dimension=256)
  store.create()
  let _ = store.add([@moonrag.Document::new("the harbour at dawn")])
  let query = embedder.embed(["the harbour"])[0]
  store.search(query[:], limit=3)
}
```

`dimension` is the width of the vectors, fixed when the store is built because the column is declared
with it; a document whose vector is another width is refused rather than stored. `create` writes the
table, and whatever else the backend needs, with `IF NOT EXISTS` throughout, so it is safe on every
start.

The SQL store, in three plans:

- **PostgreSQL with pgvector.** The vectors live in a `vector(n)` column. `search` is one statement:
  `1 - (embedding <=> $1)` is the cosine similarity the rest of the library ranks by, the metadata
  filter is a `WHERE` clause over `jsonb`, and `LIMIT` cuts in the database. `create` also adds an HNSW
  index for cosine distance; above 2000 components the type cannot be indexed and the index is left out.
- **SQLite.** There is no distance operator, so the rows come back, the filter runs in this process —
  the same `Filter::matches` the in-memory store calls — and the cosine is computed by the same
  function. Vectors are stored as little-endian `f64` blobs. A local table read whole per query is the
  right shape for the sizes SQLite is asked to hold; for a corpus that outgrows it, use PostgreSQL.
- **MySQL 9.** The vectors live in a native `VECTOR(n)` column; `STRING_TO_VECTOR` writes a vector and
  `VECTOR_TO_STRING` reads it back. Its Community build ships no `DISTANCE`, so the cosine similarity is
  computed in this process with the same `cosine_similarity` the in-memory store uses, and the metadata
  filter runs here too. `create` needs nothing beyond the table — there is no extension and no vector
  index. `moonmysql`'s `MysqlConn` is asynchronous and goes in as it is; CI starts a MySQL 9 container.

SQLite's driver blocks: a local read returns when the row does. `moonbitstack/moondb/blocking` presents
a blocking driver as the asynchronous one this store is written against — the two contracts are
method-for-method identical, so the bridge is a delegation and no thread is parked to wait for a file.
Add `moonbitstack/moonsqlite` (or `moonbitstack/moonpostgres`) to the project and the store is one line:

<!-- nocheck -->
```moonbit
let driver = @blocking.Blocking::new(@moonsqlite.SqliteDriver::open("app.db"))
```

MySQL's driver is asynchronous, like PostgreSQL's:

<!-- nocheck -->
```moonbit
let driver = @client.MysqlConn::connect("127.0.0.1", 3306, "root", "ragpass", "moonrag")
```

Qdrant is a backend of its own, `moonbitstack/moonrag/moonqdrant`, native only because it opens sockets.
It keeps each document as a point in a collection; its string id is folded into a number Qdrant
accepts and rides back inside the payload. Like SQLite and MySQL, the cosine is recomputed in this
process from the vector the store reads back, and the filter is the same `Filter::matches` — so
every backend ranks the same way rather than each trusting its server. CI starts a Qdrant container.

<!-- nocheck -->
```moonbit
let store = @moonqdrant.QdrantStore::new("http://127.0.0.1:6333", embedder, dimension=256)
```

Chroma is a backend too, `moonbitstack/moonrag/moonchroma`, against its v2 REST API. It keeps the document
ids Chroma's own strings, so nothing is folded; `create` remembers the collection UUID Chroma assigns,
`upsert` replaces by id, and search reads every embedding back and ranks here, as the others do.

<!-- nocheck -->
```moonbit
let store = @moonchroma.ChromaStore::new("http://127.0.0.1:8000", embedder, dimension=256)
```

Weaviate rounds out the set, `moonbitstack/moonrag/moonweavte`. Its objects must be UUIDs, so a document's
id is folded into one deterministically and kept in a `docid` property; upsert is a delete then a create
by that UUID, and search reads every vector back and ranks here.

<!-- nocheck -->
```moonbit
let store = @moonweavte.WeaviateStore::new("http://127.0.0.1:8080", embedder, dimension=256)
```

Milvus, `moonbitstack/moonrag/moonmilvus`, is the last: `@moonmilvus.MilvusStore::new(url, embedder, dimension=256)`
over its v2 REST API. Milvus is eventually consistent, so `add` and `delete` wait until the change is
visible and every query asks for `Strong`, which keeps the standard cases deterministic.

<!-- nocheck -->
```moonbit
let store = @moonmilvus.MilvusStore::new("http://127.0.0.1:19530", embedder, dimension=256)
```

## Retrieving

`SimilarityRetriever` embeds the query and ranks by cosine similarity.

`MmrRetriever` reranks by maximal marginal relevance: each round scores every remaining candidate as `lambda × similarity to the query − (1 − lambda) × highest similarity to something already picked`. Near `lambda = 1` it behaves like a plain search, near `0` like "the most different thing that is still related" — which is what stops a corpus of near-duplicates from filling the answer with the same paragraph five times.

```moonbit
let plain : &@moonrag.Retriever = @moonrag.SimilarityRetriever::new(embedder, store)
let diverse : &@moonrag.Retriever = @moonrag.MmrRetriever::new(embedder, store, lambda=0.3)
```

The MMR function itself is public (`mmr`) for callers that rerank their own candidates.

## Splitting

**Recursive** tries separators from coarse to fine — paragraph, line, word, character — and merges the pieces back to the chunk size with an overlap. A piece that still does not fit is split again by the next separator, so the result follows natural boundaries for as long as it can.

```moonbit
let splitter = @split.RecursiveSplitter::new(chunk_size=1000, chunk_overlap=200)
let chunks = splitter.split(document)
```

The defaults (`4000`/`200`, separator kept at the start of the following chunk, whitespace trimmed) and the arithmetic follow a reference Python implementation of the same rules, and the fixtures in `src/conformance` replay it case for case.

**Token** measures in the units that will be billed, with a counter you supply — here one unit per
word, which is what a chat model bills as a token only roughly:

```moonbit
fn count_tokens(text : StringView) -> Int32 {
  let mut count = 0
  for word in text.to_owned().split(" ") {
    if word != "" {
      count = count + 1
    }
  }
  count
}
```

```moonbit
let splitter = @split.TokenSplitter::new(count_tokens, chunk_size=512, chunk_overlap=64)
```

Each chunk is measured on its assembled text, so the promise holds for the real tokenizer rather than for an estimate.

**Markdown** reads the document as a syntax tree, one chunk per heading, with the path down to it in
the metadata. A `#` inside a fenced code block is a comment, not a heading, and a code block is never
cut — half a program embeds to nothing useful, and its indentation survives the trip. A section over
the budget is cut at block boundaries; prose that fits in no chunk at all is handed to the recursive
splitter, which can break a sentence and still leave something readable.

```moonbit
let markdown = "# Install\n\nmoon add moonbitstack/moonrag.\n\n## Search\n\nBuild a store, then search.\n"
let splitter = @split.MarkdownSplitter::new(chunk_size=1000)
let chunks = splitter.split(@moonrag.Document::new(markdown))
assert_eq(chunks.length(), 2)
assert_eq(chunks[1].str_meta("h1"), Some("Install"))
assert_eq(chunks[1].str_meta("h2"), Some("Search"))
```

A level that is not listed in `headings` does not split: `MarkdownSplitter::new(headings=[MarkdownHeading::new(1, "h1")])`
keeps `## Search` in the text of the section above it, which is what a caller who only wants chapters
is asking for.

**HTML** reads the parsed tree, one chunk per heading-delimited section, with the heading path in the metadata:

```moonbit
let page_html = "<html><body><h1>Install</h1><p>moon add moonbitstack/moonrag.</p><h2>Search</h2><p>Build a store, then search.</p></body></html>"
let splitter = @split.HtmlSplitter::new(chunk_size=1000)
let sections = splitter.split(@moonrag.Document::new(page_html))
assert_eq(sections.length(), 2)
assert_eq(sections[0].str_meta("h1"), Some("Install"))
assert_eq(sections[1].str_meta("h2"), Some("Search"))
```

A section longer than the budget is cut again by the recursive splitter with the same heading path, so no chunk outgrows an embedding window.

## Loading

| Format | What a document is | Metadata |
|:--|:--|:--|
| `TextLoader` | the whole text | `source` |
| `CsvLoader` | one row, written as `column: value` lines | `source`, `row`, every column |
| `JsonLoader` | one element of an array, or the object | `source`, every field except the text key |
| `MarkdownLoader` | the whole file | `source`, `title` from the first heading |
| `HtmlLoader` | the readable text of the page | `source`, `title` |

```moonbit
let csv_text = "name,city\nalice,London\nbob,Paris\n"
let documents = @moonrag.Loader::load(@load.CsvLoader::new("people.csv", csv_text))
```

CSV follows RFC 4180: quoted fields keep delimiters, doubled quotes and newlines. JSON is read as RFC 8259, and a member name that appears twice is refused rather than letting the last one win — a corpus with two `id` fields is a defect in whatever exported it. A `text_key` says which field is prose; without one the loader uses `text`, and failing that writes the object out so nothing is lost.

Reading from disk lives one level down, in `load/file`, because a filesystem is not something every target has. It builds for the native target; the loaders above it build everywhere:

```mbt native
let documents = @file.csv("people.csv")
let text = @file.markdown("notes.md")
```

## Indexing

Re-running a pipeline should not re-embed a corpus that has not changed. The indexer keeps a content hash per stored id:

```moonbit
let indexer = @index.Indexer::new(store)
let stats = indexer.index(chunks)                        // added / updated / skipped / deleted
let cleaned = indexer.index(chunks, cleanup=@index.Cleanup::Full)
```

- **unchanged** — same id, same content hash: skipped, nothing embedded.
- **changed** — same id, different text or metadata: the old copy is deleted, the new one added.
- **gone** — `Incremental` deletes documents whose source appears in this run and whose id does not; `Full` deletes everything this run did not produce; `None` deletes nothing.

The source key defaults to `source`, the metadata key every loader writes. Moving a file changes the source but not the hash, so a moved file is not re-embedded.

## Interface

| | |
|:--|:--|
| `Document` | `id : String?`, `text : String`, `meta : Map[String, Json]` |
| `Scored` | `document : Document`, `score : Double` |
| `Filter` | `Equal`, `OneOf`, `Exists`, `Compare`, `All`, `Any`, `Not` |
| `Embedder` | `async embed(texts : ArrayView[String]) -> Array[Array[Double]] raise` |
| `VectorStore` | `async add(Array[Document]) -> Array[String] raise`, `async delete(ids) raise`, `async search(vector, limit~, filter?) -> Array[Scored] raise` |
| `Retriever` | `async retrieve(query : String, limit~ : Int32) -> Array[Scored] raise` |
| `Splitter` | `split(Document) -> Array[Document]` |
| `Loader` | `async load() -> Array[Document] raise` |
| `Refused` | `Mismatch`, `Empty`, `Exceeded`, `Malformed`, `Unsupported` |

`VectorStore::add` takes documents and `search` takes a vector: writing is the batched, cacheable path, while a search often reuses one query vector across stores.

## Conformance

- **Splitters.** The recursive splitter replays 56 cases and the token splitter 32 — prose, code, CJK, whitespace-heavy and separator-free text, across four sizes, three separator placements and both whitespace settings — produced by a reference Python implementation of the same rules (1.1.3). Chunks match exactly; `scripts/gen_split_vectors.py` regenerates them.
- **Markdown splitting.** Eight cases from the header splitter of the same reference release — a preamble, nested levels, adjacent headings, a section that is one code block, and a `#` inside a fence that must not split — replay chunk text and heading path. Two of the reference's behaviours are deliberately not followed, and are covered by this library's own tests instead: it joins the blocks of a section with a Markdown hard break (`"  \n"`), and it strips every line, which flattens the indentation of code. `scripts/gen_langchain_cases.py` regenerates the fixtures.
- **Ranking and MMR.** Five ranking cases and seven MMR cases over fixed vectors: the same documents in the same order, and the same `lambda` trade-offs, as the reference returns. A score is a cosine summed in a different order, so the fixtures are compared to one part in a trillion; the order is compared exactly.
- **Store and retrieval.** The behaviours a vector-store standard suite requires — add, search with scores, limit, metadata filtering, delete by id, update by id, empty store, dimension mismatch, order independence — plus a retriever's limit, descending scores, filters and MMR diversity.
- **Every backend.** The same standard cases run against the in-memory store, SQLite, PostgreSQL with pgvector, MySQL 9, and a Qdrant collection — which is the only way to know that one contract holds over one table, one server and one process. The pgvector cases read the column type back out of the catalogue and compare the store's score with the one the database computed, so a store that ranked in this process and said otherwise would fail.
- **End to end.** Load, split, index and retrieve as one test over a page and a note, including a second pass that must embed nothing.
- **Against a filesystem.** The file front end is tested by writing real files to a temporary directory and reading them back through all five loaders.

The backend cases live in `integration/`, a module of its own, so a program that uses this
library does not download a SQLite amalgamation and a PostgreSQL driver for the sake of a test:

```shell
cd integration && moon test --target native
```

The pgvector, MySQL and Qdrant cases need a server; `MOONRAG_LIVE=1` says one is there, and then one
has to answer. Without it they print why they did nothing and return.

## Examples

| # | Example | What it shows |
|:--:|:--|:--|
| 01 | [`ingest`](src/examples/01-ingest/) | load, split, index, retrieve, then index again and embed nothing |
| 02 | [`store`](src/examples/02-store/) | add, filter, rank, rerank with MMR, delete |
| 03 | [`files`](src/examples/03-files/) | the file front end over a real temporary directory |
| 04 | [`markdown`](src/examples/04-markdown/) | one chunk per heading, the path in the metadata, a code block kept whole |

```shell
moon run src/examples/01-ingest --target native
```

## License

Apache-2.0.
