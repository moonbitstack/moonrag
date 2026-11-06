---
name: moonrag
description: Build a retrieval pipeline in MoonBit with moonbitstack/moonrag — documents with metadata, loaders for text/CSV/JSON/Markdown/HTML, recursive/token/HTML splitters, an in-memory vector store with filters, similarity and MMR retrievers, and incremental indexing. Use when chunking a corpus, storing embeddings, searching them, or wiring retrieval into an agent in MoonBit.
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
  "moonbitlang/async",
}
```

Everything moves `@moonrag.Document`: `text`, an optional `id`, and `meta : Map[String, @json.Json]`. The four contracts are `Embedder`, `VectorStore`, `Retriever`, `Splitter`, `Loader`; implement any of them and the rest of the pipeline takes it unchanged.

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

## Bring your own model

```moonbit
pub impl @moonrag.Embedder for MyEmbedder with fn embed(self, texts) {
  // ... call the model once for the whole batch ...
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
- File reading lives in `load/file`, which does not build for `js` or `wasm-gc`; the parsers in `load` work on every target.
