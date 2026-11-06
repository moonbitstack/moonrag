// The retriever behaviours the reference standard suite (`retrievers`) requires: a limit is a limit,
// scores come back sorted, metadata filters apply, and MMR returns documents that differ from each
// other.

///|
/// A store holding three passages, two of them about the same thing.
async fn passages() -> (
  &@moonrag.Retriever,
  &@moonrag.Retriever,
  &@moonrag.Retriever,
) {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = store.add([
    @moonrag.Document::new(
      "the harbour at dawn, fishing boats leaving",
      meta=Map([("topic", @json.Json::string("sea"))]),
    ),
    @moonrag.Document::new(
      "fishing boats leave the harbour at first light",
      meta=Map([("topic", @json.Json::string("sea"))]),
    ),
    @moonrag.Document::new(
      "a mountain path in autumn, cold and clear",
      meta=Map([("topic", @json.Json::string("land"))]),
    ),
  ])
  let plain : &@moonrag.Retriever = @moonrag.SimilarityRetriever::new(
    embedder, store,
  )
  let diverse : &@moonrag.Retriever = @moonrag.MmrRetriever::new(
    embedder,
    store,
    lambda=0.2,
  )
  let land : &@moonrag.Retriever = @moonrag.SimilarityRetriever::new(
    embedder,
    store,
    filter=@moonrag.Filter::Equal("topic", @json.Json::string("land")),
  )
  (plain, diverse, land)
}

///|
async test "a retriever returns at most the limit it was given" {
  let (plain, _, _) = passages()
  assert_eq(plain.retrieve("fishing boats", limit=1).length(), 1)
  assert_eq(plain.retrieve("fishing boats", limit=2).length(), 2)
  assert_eq(plain.retrieve("fishing boats", limit=10).length(), 3)
}

///|
async test "a retriever returns documents in descending score order" {
  let (plain, _, _) = passages()
  let hits = plain.retrieve("fishing boats leave the harbour", limit=3)
  for i = 1; i < hits.length(); i = i + 1 {
    assert_true(hits[i - 1].score >= hits[i].score)
  }
}

///|
async test "a retriever honours its filter" {
  let (_, _, land) = passages()
  let hits = land.retrieve("fishing boats", limit=5)
  assert_eq(hits.length(), 1)
  assert_true(hits[0].document.text.contains("mountain"))
}

///|
async test "mmr trades a near duplicate for a different passage" {
  let (plain, diverse, _) = passages()
  let ranked = plain.retrieve("fishing boats leave the harbour", limit=2)
  assert_eq(ranked.length(), 2)
  // Both plain hits are the two sea passages.
  for hit in ranked {
    assert_eq(hit.document.str_meta("topic"), Some("sea"))
  }
  let spread = diverse.retrieve("fishing boats leave the harbour", limit=2)
  assert_eq(spread.length(), 2)
  assert_true(
    spread.any(fn(hit) { hit.document.str_meta("topic") == Some("land") }),
  )
}

///|
async test "an empty retriever answers with nothing" {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let retriever : &@moonrag.Retriever = @moonrag.SimilarityRetriever::new(
    embedder, store,
  )
  assert_eq(retriever.retrieve("anything", limit=3), [])
}
