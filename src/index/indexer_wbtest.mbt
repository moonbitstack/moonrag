// Incremental indexing, the behaviours the reference indexer tests cover: a second run does nothing,
// changed content replaces the old copy, and cleanup removes what a source no longer produces.

///|
/// An embedder that counts the texts it was asked to embed and hands back a fixed vector, so a test can
/// tell "embedded again" from "left alone".
pub struct CountingEmbedder {
  mut batches : Int32
  mut texts : Int32
}

///|
pub fn CountingEmbedder::new() -> CountingEmbedder {
  { batches: 0, texts: 0, }
}

///|
pub impl @moonrag.Embedder for CountingEmbedder with fn embed(self, texts) {
  self.batches = self.batches + 1
  self.texts = self.texts + texts.length()
  let out : Array[Array[Double]] = []
  for text in texts {
    // A vector that depends on the text, so replacing a document also changes what a search finds.
    out.push([text.length().to_double(), 1.0])
  }
  out
}

///|
fn document(text : String, id : String, source : String) -> @moonrag.Document {
  @moonrag.Document::new(
    text,
    id~,
    meta=Map([("source", @json.Json::string(source))]),
  )
}

///|
async test "a second run over unchanged documents embeds nothing" {
  let embedder = CountingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = Indexer::new(store)
  let documents = [
    document("alpha", "a", "one.txt"),
    document("beta", "b", "one.txt"),
  ]
  let first = indexer.index(documents)
  assert_eq(first.added, 2)
  assert_eq(first.updated, 0)
  assert_eq(first.skipped, 0)
  assert_eq(store.len(), 2)
  let texts_after_first = embedder.texts

  let second = indexer.index(documents)
  assert_eq(second.added, 0)
  assert_eq(second.skipped, 2)
  assert_eq(embedder.texts, texts_after_first)
  assert_eq(store.len(), 2)
  assert_eq(indexer.len(), 2)
}

///|
async test "changed text replaces the stored document instead of adding another" {
  let embedder = CountingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = Indexer::new(store)
  let _ = indexer.index([document("alpha", "a", "one.txt")])
  let second = indexer.index([document("alpha, revised", "a", "one.txt")])
  assert_eq(second.updated, 1)
  assert_eq(second.added, 0)
  assert_eq(store.len(), 1)
  let hits = store.search([12.0, 1.0][:], limit=1)
  assert_eq(hits[0].document.text, "alpha, revised")
}

///|
async test "changed metadata is a change, the source key alone is not" {
  let embedder = CountingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = Indexer::new(store)
  let _ = indexer.index([document("alpha", "a", "one.txt")])
  // Moving the file without touching it: same id, same text, same other metadata.
  let moved = indexer.index([document("alpha", "a", "moved/one.txt")])
  assert_eq(moved.skipped, 1)
  // A real metadata change is an update.
  let tagged = @moonrag.Document::new(
    "alpha",
    id="a",
    meta=Map([
      ("source", @json.Json::string("one.txt")),
      ("lang", @json.Json::string("en")),
    ]),
  )
  let retagged = indexer.index([tagged])
  assert_eq(retagged.updated, 1)
}

///|
async test "incremental cleanup removes what a rewritten source no longer produces" {
  let embedder = CountingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = Indexer::new(store)
  let _ = indexer.index([
    document("a1", "a", "doc.txt"),
    document("a2", "b", "doc.txt"),
    document("a3", "c", "doc.txt"),
    document("other", "z", "other.txt"),
  ])
  assert_eq(store.len(), 4)
  let shrunk = indexer.index([
    document("a1", "a", "doc.txt"),
    document("a3", "c", "doc.txt"),
  ])
  assert_eq(shrunk.deleted, 1)
  assert_eq(shrunk.skipped, 2)
  assert_eq(store.len(), 3)
  // The document from the other source survives: that source was not part of this run.
  assert_eq(store.get("z").unwrap().text, "other")
  assert_eq(indexer.ids(), ["a", "c", "z"])
}

///|
async test "full cleanup removes everything this run did not produce" {
  let embedder = CountingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = Indexer::new(store)
  let _ = indexer.index([
    document("a1", "a", "doc.txt"),
    document("other", "z", "other.txt"),
  ])
  let run = indexer.index(
    [document("a1", "a", "doc.txt")],
    cleanup=Cleanup::Full,
  )
  assert_eq(run.deleted, 1)
  assert_eq(store.len(), 1)
  assert_eq(store.get("z"), None)
}

///|
async test "no cleanup leaves stale documents alone" {
  let embedder = CountingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = Indexer::new(store)
  let _ = indexer.index([
    document("a1", "a", "doc.txt"),
    document("a2", "b", "doc.txt"),
  ])
  let run = indexer.index(
    [document("a1", "a", "doc.txt")],
    cleanup=Cleanup::None,
  )
  assert_eq(run.deleted, 0)
  assert_eq(store.len(), 2)
}

///|
async test "a document without a source is not swept by incremental cleanup" {
  let embedder = CountingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = Indexer::new(store)
  let _ = indexer.index([
    @moonrag.Document::new("anonymous", id="anon"),
    document("named", "n", "doc.txt"),
  ])
  let run = indexer.index([document("named", "n", "doc.txt")])
  assert_eq(run.deleted, 0)
  assert_eq(store.get("anon").unwrap().text, "anonymous")
}

///|
async test "the same id twice in one run leaves one copy" {
  let embedder = CountingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = Indexer::new(store)
  let run = indexer.index([
    document("first version", "a", "doc.txt"),
    document("second version", "a", "doc.txt"),
  ])
  assert_eq(run.added, 1)
  assert_eq(run.updated, 1)
  assert_eq(store.len(), 1)
  assert_eq(store.get("a").unwrap().text, "second version")
}

///|
async test "documents without ids get stable generated ones" {
  let embedder = CountingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = Indexer::new(store)
  let run = indexer.index([
    @moonrag.Document::new("one"),
    @moonrag.Document::new("two"),
  ])
  assert_eq(run.added, 2)
  assert_eq(store.len(), 2)
  assert_eq(indexer.ids().length(), 2)
  // The same texts again produce the same ids, so a second pass skips them instead of duplicating.
  let again = indexer.index([
    @moonrag.Document::new("one"),
    @moonrag.Document::new("two"),
  ])
  assert_eq(again.skipped, 2)
  assert_eq(store.len(), 2)
}

///|
pub extend CountingEmbedder with @moonrag.Embedder::{embed}
