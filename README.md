<div align="center">

# moonrag

**Documents, splitting, vectors and retrieval for MoonBit. Embeddings arrive through a contract, so nothing here calls a model.**

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
  "moonbitstack/moonrag/split",     // recursive, token and HTML splitters
  "moonbitstack/moonrag/load",      // text, CSV, JSON, Markdown, HTML loaders
  "moonbitstack/moonrag/load/file", // the same loaders, reading from disk
  "moonbitstack/moonrag/index",     // incremental indexing
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
let store = @moonrag.InMemoryVectorStore::new(embedder)
let ids = store.add([document])
let hits = store.search(query_vector, limit=5)
store.delete([ids[0]][:])
```

An id that is already stored is replaced in place, which is what makes a re-index an update rather than a duplicate. Hits carry the id they are stored under, so a caller can delete what it just retrieved.

Already have vectors? `add_vectors` takes them and skips the embedding.

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

**Token** measures in the units that will be billed, with a counter you supply:

```moonbit
let splitter = @split.TokenSplitter::new(count_tokens, chunk_size=512, chunk_overlap=64)
```

Each chunk is measured on its assembled text, so the promise holds for the real tokenizer rather than for an estimate.

**HTML** reads the parsed tree, one chunk per heading-delimited section, with the heading path in the metadata:

```moonbit
let splitter = @split.HtmlSplitter::new(chunk_size=1000)
let sections = splitter.split(@moonrag.Document::new(page_html))
// sections[1].str_meta("h1") == Some("Install"); .str_meta("h2") == Some("Search")
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
let documents = @moonrag.Loader::load(@load.CsvLoader::new("people.csv", csv_text))
```

CSV follows RFC 4180: quoted fields keep delimiters, doubled quotes and newlines. JSON takes a `text_key` to say which field is prose; without one it uses `text`, and failing that writes the object out so nothing is lost.

Reading from disk lives one level down, in `load/file`, because a filesystem is not something every target has:

```moonbit
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
- **Store and retrieval.** The behaviours a vector-store standard suite requires — add, search with scores, limit, metadata filtering, delete by id, update by id, empty store, dimension mismatch, order independence — plus a retriever's limit, descending scores, filters and MMR diversity.
- **End to end.** Load, split, index and retrieve as one test over a page and a note, including a second pass that must embed nothing.
- **Against a filesystem.** The file front end is tested by writing real files to a temporary directory and reading them back through all five loaders.

## Examples

| # | Example | What it shows |
|:--:|:--|:--|
| 01 | [`ingest`](src/examples/01-ingest/) | load, split, index, retrieve, then index again and embed nothing |
| 02 | [`store`](src/examples/02-store/) | add, filter, rank, rerank with MMR, delete |
| 03 | [`files`](src/examples/03-files/) | the file front end over a real temporary directory |

```shell
moon run src/examples/01-ingest --target native
```

## License

Apache-2.0.
