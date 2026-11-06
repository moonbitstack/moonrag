// The two retrievers end to end: embed a query, search a store, come back with ranked documents.

///|
/// An embedder that answers from a table, so the expected order below is arithmetic rather than a
/// model's opinion.
pub struct LookupEmbedder {
  table : Map[String, Array[Double]]
  width : Int32
}

///|
pub fn LookupEmbedder::new() -> LookupEmbedder {
  { table: Map([]), width: 2, }
}

///|
pub fn LookupEmbedder::set(
  self : LookupEmbedder,
  text : String,
  vector : Array[Double],
) -> Unit {
  self.table[text] = vector
}

///|
pub impl @moonrag.Embedder for LookupEmbedder with fn embed(self, texts) {
  let out : Array[Array[Double]] = []
  for text in texts {
    out.push(
      match self.table.get(text) {
        Some(vector) => vector.copy()
        None => Array::make(self.width, 0.0)
      },
    )
  }
  out
}

///|
async test "similarity retriever ranks the store and honours the limit" {
  let embedder = LookupEmbedder::new()
  embedder.set("query", [1.0, 0.0])
  embedder.set("best", [1.0, 0.0])
  embedder.set("second", [1.0, 1.0])
  embedder.set("worst", [0.0, 1.0])
  let e : &@moonrag.Embedder = embedder
  let store = @moonrag.InMemoryVectorStore::new(e)
  let _ = store.add([
    @moonrag.Document::new("worst"),
    @moonrag.Document::new("second"),
    @moonrag.Document::new("best"),
  ])
  let retriever : &@moonrag.Retriever = @moonrag.SimilarityRetriever::new(
    e, store,
  )
  let hits = retriever.retrieve("query", limit=2)
  assert_eq(hits.map(fn(hit) { hit.document.text }), ["best", "second"])
  let only = retriever.retrieve("query", limit=1)
  assert_eq(only.length(), 1)
  assert_eq(only[0].document.text, "best")
}

///|
async test "similarity retriever filters in the store" {
  let embedder = LookupEmbedder::new()
  embedder.set("query", [1.0, 0.0])
  embedder.set("kept", [1.0, 0.0])
  embedder.set("dropped", [1.0, 0.0])
  let e : &@moonrag.Embedder = embedder
  let store = @moonrag.InMemoryVectorStore::new(e)
  let _ = store.add([
    @moonrag.Document::new(
      "kept",
      meta=Map([("kind", @json.Json::string("keep"))]),
    ),
    @moonrag.Document::new(
      "dropped",
      meta=Map([("kind", @json.Json::string("drop"))]),
    ),
  ])
  let retriever : &@moonrag.Retriever = @moonrag.SimilarityRetriever::new(
    e,
    store,
    filter=@moonrag.Filter::Equal("kind", @json.Json::string("keep")),
  )
  let hits = retriever.retrieve("query", limit=5)
  assert_eq(hits.map(fn(hit) { hit.document.text }), ["kept"])
}

///|
async test "mmr retriever trades a near-duplicate for a different document" {
  let embedder = LookupEmbedder::new()
  embedder.set("query", [1.0, 0.0])
  embedder.set("copy one", [1.0, 0.0])
  embedder.set("copy two", [0.999, 0.001])
  embedder.set("elsewhere", [0.0, 1.0])
  let e : &@moonrag.Embedder = embedder
  let store = @moonrag.InMemoryVectorStore::new(e)
  let _ = store.add([
    @moonrag.Document::new("copy one"),
    @moonrag.Document::new("copy two"),
    @moonrag.Document::new("elsewhere"),
  ])
  let plain : &@moonrag.Retriever = @moonrag.SimilarityRetriever::new(e, store)
  let diverse : &@moonrag.Retriever = @moonrag.MmrRetriever::new(
    e,
    store,
    lambda=0.1,
  )
  let ranked = plain.retrieve("query", limit=2)
  assert_eq(ranked.map(fn(hit) { hit.document.text }), ["copy one", "copy two"])
  let spread = diverse.retrieve("query", limit=2)
  assert_eq(spread.map(fn(hit) { hit.document.text }), ["copy one", "elsewhere"])
}

///|
async test "mmr retriever never returns more than the fetch limit" {
  let embedder = LookupEmbedder::new()
  embedder.set("query", [1.0, 0.0])
  let e : &@moonrag.Embedder = embedder
  let store = @moonrag.InMemoryVectorStore::new(e)
  let _ = store.add([
    @moonrag.Document::new("a"),
    @moonrag.Document::new("b"),
    @moonrag.Document::new("c"),
  ])
  let retriever : &@moonrag.Retriever = @moonrag.MmrRetriever::new(
    e,
    store,
    fetch_limit=2,
  )
  let hits = retriever.retrieve("query", limit=10)
  assert_eq(hits.length(), 2)
}
