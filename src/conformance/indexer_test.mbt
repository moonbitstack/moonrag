// The indexing behaviours the reference standard suite (`indexer`) requires: a second run over the same
// documents does nothing, changed content replaces the stored copy, and each cleanup mode removes what
// it promises to.

///|
/// An indexer over a fresh store: a deterministic embedder, so a second pass changes nothing.
fn fresh_indexer() -> (@index.Indexer, @moonrag.InMemoryVectorStore) raise {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  (@index.Indexer::new(store), store)
}

///|
fn sourced(text : String, id : String, source : String) -> @moonrag.Document {
  @moonrag.Document::new(
    text,
    id~,
    meta=Map([("source", @json.Json::string(source))]),
  )
}

///|
async test "indexing the same documents twice adds nothing the second time" {
  let (indexer, store) = fresh_indexer()
  let documents = [
    sourced("alpha", "a", "one.txt"),
    sourced("beta", "b", "one.txt"),
  ]
  let first = indexer.index(documents)
  assert_eq(first.added, 2)
  let second = indexer.index(documents)
  assert_eq(second.added, 0)
  assert_eq(second.updated, 0)
  assert_eq(second.skipped, 2)
  assert_eq(store.len(), 2)
}

///|
async test "changed content updates in place instead of duplicating" {
  let (indexer, store) = fresh_indexer()
  let _ = indexer.index([sourced("alpha", "a", "one.txt")])
  let stats = indexer.index([sourced("alpha revised", "a", "one.txt")])
  assert_eq(stats.updated, 1)
  assert_eq(stats.added, 0)
  assert_eq(store.len(), 1)
  assert_eq(store.get("a").unwrap().text, "alpha revised")
}

///|
async test "cleanup modes delete exactly what they promise" {
  let (indexer, store) = fresh_indexer()
  let full_set = [
    sourced("a1", "a", "doc.txt"),
    sourced("a2", "b", "doc.txt"),
    sourced("other", "z", "other.txt"),
  ]
  let _ = indexer.index(full_set)
  assert_eq(store.len(), 3)
  // Incremental: only documents of a source present in this run are swept.
  let incremental = indexer.index([sourced("a1", "a", "doc.txt")])
  assert_eq(incremental.deleted, 1)
  assert_eq(store.get("b"), None)
  assert_eq(store.get("z").unwrap().text, "other")
  // None: nothing is swept, however stale.
  let kept = indexer.index(
    [sourced("a1", "a", "doc.txt")],
    cleanup=@index.Cleanup::None,
  )
  assert_eq(kept.deleted, 0)
  assert_eq(store.len(), 2)
  // Full: everything this run did not produce goes, whatever its source.
  let full = indexer.index(
    [sourced("a1", "a", "doc.txt")],
    cleanup=@index.Cleanup::Full,
  )
  assert_eq(full.deleted, 1)
  assert_eq(store.len(), 1)
  assert_eq(store.get("z"), None)
}
