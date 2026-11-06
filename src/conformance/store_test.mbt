// The vector-store behaviours the reference standard suite (`libs/standard-tests`, `vectorstores`)
// requires of an implementation, run against the in-memory store through its public API.
//
// Each block names the upstream behaviour it ports. Vectors come from the deterministic hashing
// embedder, so a document is found because of what it says, not because a model was called.

///|
/// A store over the hashing embedder with four documents about different subjects.
async fn corpus() -> (@moonrag.InMemoryVectorStore, &@moonrag.Embedder) {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = store.add([
    @moonrag.Document::new(
      "the harbour at dawn, fishing boats leaving",
      meta=Map([("topic", @json.Json::string("sea"))]),
    ),
    @moonrag.Document::new(
      "a mountain path in autumn, cold and clear",
      meta=Map([("topic", @json.Json::string("land"))]),
    ),
    @moonrag.Document::new(
      "fishing boats return to the harbour at dusk",
      meta=Map([("topic", @json.Json::string("sea"))]),
    ),
  ])
  (store, embedder)
}

///|
async test "similarity search returns the documents a query is about" {
  let (store, embedder) = corpus()
  let query = embedder.embed(["fishing boats in the harbour"])[0]
  let hits = store.search(query[:], limit=2)
  assert_eq(hits.length(), 2)
  // Both sea documents outrank the mountain one.
  for hit in hits {
    assert_eq(hit.document.str_meta("topic"), Some("sea"))
  }
}

///|
async test "similarity search returns a score with every hit" {
  let (store, embedder) = corpus()
  let query = embedder.embed(["fishing boats"])[0]
  let hits = store.search(query[:], limit=3)
  assert_eq(hits.length(), 3)
  // Scores are cosine similarities: in [-1, 1], descending, and identical text scores 1.
  for hit in hits {
    assert_true(hit.score <= 1.0 && hit.score >= -1.0)
  }
  for i = 1; i < hits.length(); i = i + 1 {
    assert_true(hits[i - 1].score >= hits[i].score)
  }
}

///|
async test "a store returns no more than the limit asked for" {
  let (store, embedder) = corpus()
  let query = embedder.embed(["harbour"])[0]
  assert_eq(store.search(query[:], limit=1).length(), 1)
  assert_eq(store.search(query[:], limit=100).length(), 3)
}

///|
async test "metadata filtering narrows the candidates" {
  let (store, embedder) = corpus()
  let query = embedder.embed(["harbour boats"])[0]
  let land = store.search(
    query[:],
    limit=10,
    filter=@moonrag.Filter::Equal("topic", @json.Json::string("land")),
  )
  assert_eq(land.length(), 1)
  assert_true(land[0].document.text.contains("mountain"))
  let missing = store.search(
    query[:],
    limit=10,
    filter=@moonrag.Filter::Equal("topic", @json.Json::string("air")),
  )
  assert_eq(missing, [])
}

///|
async test "deleting by id removes exactly those documents" {
  let (store, embedder) = corpus()
  let ids = store.ids()
  store.delete([ids[0]][:])
  assert_eq(store.len(), 2)
  assert_eq(store.get(ids[0]), None)
  let query = embedder.embed(["harbour"])[0]
  let hits = store.search(query[:], limit=10)
  assert_true(hits.length() == 2)
  assert_true(!hits.any(fn(hit) { hit.document.text.contains("dawn") }))
}

///|
async test "adding under an existing id updates rather than duplicates" {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = store.add([@moonrag.Document::new("original text", id="fixed")])
  let _ = store.add([@moonrag.Document::new("rewritten text", id="fixed")])
  assert_eq(store.len(), 1)
  assert_eq(store.get("fixed").unwrap().text, "rewritten text")
}

///|
async test "an empty store answers with nothing" {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let query = embedder.embed(["anything"])[0]
  assert_eq(store.search(query[:], limit=5), [])
  assert_eq(store.len(), 0)
}

///|
async test "searching with a vector of the wrong width is refused" {
  let (store, _) = corpus()
  let refused = try {
    let _ = store.search([1.0][:], limit=1)
    false
  } catch {
    @moonrag.Refused::Mismatch(..) => true
    _ => false
  }
  assert_true(refused)
}

///|
async test "the same documents in a different order produce the same ranking" {
  // A store keyed on insertion order must still rank by score, not by arrival.
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let forward = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = forward.add([
    @moonrag.Document::new("harbour dawn boats"),
    @moonrag.Document::new("mountain path snow"),
  ])
  let backward = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = backward.add([
    @moonrag.Document::new("mountain path snow"),
    @moonrag.Document::new("harbour dawn boats"),
  ])
  let query = embedder.embed(["harbour boats"])[0]
  let left = forward.search(query[:], limit=2)
  let right = backward.search(query[:], limit=2)
  assert_eq(left[0].document.text, right[0].document.text)
  assert_true((left[0].score - right[0].score).abs() < 1.0e-12)
}
