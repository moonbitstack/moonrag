---
name: moonrag
description: Build a retrieval pipeline in MoonBit with moonbitstack/moonrag — documents with metadata, loaders for text/CSV/JSON/Markdown/HTML, recursive/token/Markdown/HTML splitters, an in-memory or SQL vector store (SQLite, PostgreSQL with pgvector, MySQL 9) or a Qdrant collection, with filters, similarity and MMR retrievers, and incremental indexing. Use when chunking a corpus, storing embeddings, searching them, or wiring retrieval into an agent in MoonBit.
---

# moonrag

```bash
moon add moonbitstack/moonrag
moon add moonbitlang/async
```

```moonbit
import {
  "moonbitstack/moonrag",           // documents, contracts, memory store, retrievers
  "moonbitstack/moonrag/split",     // splitters
  "moonbitstack/moonrag/load",      // loaders over text already in memory
  "moonbitstack/moonrag/load/file", // the same loaders, reading from disk
  "moonbitstack/moonrag/index",     // incremental indexing
  "moonbitstack/moonrag/sql",       // a store in SQL, over any moondb driver
  "moonbitlang/async",
}
```

Everything moves `@moonrag.Document`: `text`, an optional `id`, and `meta : Map[String, @json.Json]`. The five contracts are `Embedder`, `VectorStore`, `Retriever`, `Splitter`, `Loader`; implement any of them and the rest of the pipeline takes it unchanged.

The examples below share one store, so start here:

```moonbit
let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
let store = @moonrag.InMemoryVectorStore::new(embedder)
let _ = store.add([
  @moonrag.Document::new("the harbour at dawn, fishing boats leaving", id="harbour"),
  @moonrag.Document::new("a mountain path in autumn, cold and clear", id="ridge"),
])
let query_vector = embedder.embed(["fishing boats"])[0]
```

`HashingEmbedder` is a deterministic stand-in — lexical, not semantic. Swap in an implementation of
`Embedder` that calls the model you actually use.

## Ingest a corpus and search it

```moonbit
async fn ingest(embedder : &@moonrag.Embedder, csv : String) -> Array[@moonrag.Scored] raise {
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = @index.Indexer::new(store)

  let documents = @moonrag.Loader::load(@load.CsvLoader::new("people.csv", csv))
  let splitter = @split.RecursiveSplitter::new(chunk_size=500, chunk_overlap=50)
  let pieces : Array[@moonrag.Document] = []
  for document in documents {
    for chunk in splitter.split(document) {
      pieces.push(chunk)
    }
  }
  let _ = indexer.index(pieces)

  let retriever : &@moonrag.Retriever = @moonrag.SimilarityRetriever::new(embedder, store)
  retriever.retrieve("who lives in London", limit=3)
}
```

Call it again with the same pieces and `indexer.index` reports `skipped` for everything: ids are kept per document and content is hashed, so nothing is embedded twice.

## Filter before ranking

A `Filter` is data, so the store applies it where the documents are:

```moonbit
let hits = store.search(
  query_vector,
  limit=5,
  filter=@moonrag.Filter::All([
    @moonrag.Filter::Equal("topic", @json.Json::string("sea")),
    @moonrag.Filter::Compare("year", @moonrag.Order::AtLeast, 2025.0),
  ]),
)
```

`Equal`, `OneOf`, `Exists`, `Compare` (`Less`/`AtMost`/`AtLeast`/`Greater`), combined with `All`, `Any`, `Not`.

## Avoid five copies of the same passage

Near-duplicate chunks win a plain similarity search. MMR reranks them against each other:

```moonbit
let diverse : &@moonrag.Retriever = @moonrag.MmrRetriever::new(
  embedder,
  store,
  lambda=0.3,     // 1.0 is a plain search, 0.0 is "most different"
  fetch_limit=20, // candidates fetched before reranking
)
```

## Split Markdown without breaking code

```moonbit
let markdown = "# Install\n\nmoon add moonbitstack/moonrag.\n\n## Search\n\nBuild a store, then search.\n"
let splitter = @split.MarkdownSplitter::new(
  chunk_size=1000,
  headings=[@split.MarkdownHeading::new(1, "h1"), @split.MarkdownHeading::new(2, "h2")],
)
let chunks = splitter.split(@moonrag.Document::new(markdown, id="guide.md"))
assert_eq(chunks.length(), 2)
assert_eq(chunks[1].str_meta("h2"), Some("Search"))
```

Heading text lands in the metadata under the key you chose, and every chunk carries the whole path
down to it. A `#` inside a fenced code block is not a heading, and a code block is emitted whole however
long it is. A level you do not list does not split — it stays in the text of the section above.

## Keep the vectors in a database

```moonbit
pub async fn[T : @moondb.AsyncDriver] store_over(
  driver : T,
  embedder : &@moonrag.Embedder,
) -> @sql.SqlVectorStore[T] raise {
  let store = @sql.SqlVectorStore::new(driver, embedder, dimension=256, table="documents")
  store.create()
  store
}
```

`dimension` is the width of the embedding model, fixed at construction because the column is declared
with it. `create` is `IF NOT EXISTS` throughout, so it belongs on every start. On PostgreSQL with
pgvector the search is one statement, filter and `LIMIT` included; on SQLite and MySQL the rows come
back and the distance is computed in this process with the same filter tree the in-memory store uses.

`moonsqlite` implements the blocking driver contract, so wrap it: `@sql.BlockingDriver::new(driver)`.
`moonpostgres`'s `PgConn` and `moonmysql`'s `MysqlConn` are both asynchronous and go in as they are.
MySQL 9 keeps the vectors in its native `VECTOR(n)` column (`STRING_TO_VECTOR` writes, `VECTOR_TO_STRING`
reads); its Community build has no `DISTANCE`, so the cosine score is computed here, not in the server.

Qdrant is a backend of its own, `moonbitstack/moonrag/qdrant`, native only because it opens sockets:
`@qdrant.QdrantStore::new(url, embedder, dimension=256)` over its REST API. Like SQLite and MySQL it
recomputes the cosine here from the vector it reads back, so every backend ranks the same way.

Chroma is another, `moonbitstack/moonrag/chroma`, against its v2 REST API: `@chroma.ChromaStore::new(url,
embedder, dimension=256)`. Its document ids are Chroma's strings; `create` remembers the collection UUID.

## Bring your own model

```moonbit
struct MyEmbedder {
  model : String
}

impl @moonrag.Embedder for MyEmbedder with fn embed(self, texts) {
  // One request for the whole batch is where the model call goes.
  let vectors : Array[Array[Double]] = []
  for text in texts {
    vectors.push([text.length().to_double(), self.model.length().to_double()])
  }
  vectors
}
```

One call embeds a batch: that is the unit a model charges for. All vectors in a batch must have the same width, and the same text must always produce the same vector — ranking depends on it.

## Things that bite

- `VectorStore::add` takes documents and embeds them with the store's embedder; `search` takes the query vector, so embed the query yourself (`embedder.embed([query])[0]`).
- Hits carry the id they are stored under; `Document.id` on a chunk is `parent#index`, so deleting a parent does not delete its chunks — index the chunks, not the parent.
- `RecursiveSplitter`'s `chunk_size` counts code points unless you pass `measure=`; pass a token counter to split by tokens, or use `TokenSplitter`, which is built for exactly that.
- `HtmlSplitter` needs the raw markup, not the text an `HtmlLoader` already flattened: the headings are in the markup.
- `MmrRetriever` re-embeds its candidates, because a store returns documents and scores, never vectors. Keep `fetch_limit` modest.
- `MarkdownSplitter` splits on all six heading levels by default; pass `headings=` to split on chapters only.
- `SqlVectorStore` fixes the vector width at construction: a second model with another width needs another table.
- `SqlVectorStore::create` installs the `vector` extension on PostgreSQL, which needs a role allowed to create it. Where the database is managed by someone else, run `CREATE EXTENSION vector` once yourself.
- File reading lives in `load/file`, which does not build for `js` or `wasm-gc`; the parsers in `load` work on every target.
