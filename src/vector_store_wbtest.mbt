// In-memory vector storage and cosine-similarity ranking (Koog `rag-vector`).

///|
fn assert_close(a : Double, b : Double) -> Unit {
  let d = if a > b { a - b } else { b - a }
  if d > 1.0e-9 {
    abort("expected \{a} ≈ \{b}")
  }
}

///|
test "vector store: store, get, delete, size" {
  let store : VectorStore[String] = VectorStore::new()
  let id0 = store.store("hello", { values: [1.0, 0.0], })
  let id1 = store.store("world", { values: [0.0, 1.0], })
  assert_eq(id0, "doc-0")
  assert_eq(id1, "doc-1")
  assert_eq(store.size(), 2)
  assert_eq(store.get("doc-0"), Some("hello"))
  assert_eq(store.get("missing"), None)
  assert_eq(store.delete("doc-0"), true)
  assert_eq(store.delete("doc-0"), false)
  assert_eq(store.size(), 1)
}

///|
test "rag: rank_by_similarity orders by cosine similarity and honours min_score / limit / offset" {
  let query : Vector = { values: [1.0, 0.0], }
  let docs : Array[(String, Vector)] = [
    ("same", { values: [1.0, 0.0], }), // cosine 1
    ("orth", { values: [0.0, 1.0], }), // cosine 0
    ("near", { values: [1.0, 0.5], }), // cosine ≈ 0.894
    ("opp", { values: [-1.0, 0.0], }), // cosine -1
  ]
  // Full ranking (min_score below -1 keeps everything), descending by score.
  let ranked = rank_by_similarity(query, docs, min_score=-2.0)
  assert_eq(ranked.length(), 4)
  assert_eq(ranked[0].document, "same")
  assert_eq(ranked[1].document, "near")
  assert_eq(ranked[2].document, "orth")
  assert_eq(ranked[3].document, "opp")
  assert_close(ranked[0].score.value, 1.0)
  assert_eq(ranked[0].score.metric, CosineSimilarity)
  // The default min_score of 0.0 drops the opposite (negative-cosine) document, as Koog does.
  let defaulted = rank_by_similarity(query, docs)
  assert_eq(defaulted.length(), 3)
  assert_eq(defaulted[2].document, "orth")
  // A higher min_score keeps only the closest documents.
  let filtered = rank_by_similarity(query, docs, min_score=0.5)
  assert_eq(filtered.length(), 2)
  assert_eq(filtered[0].document, "same")
  assert_eq(filtered[1].document, "near")
  // limit + offset paginate the ranked results.
  let paged = rank_by_similarity(query, docs, limit=1, offset=1)
  assert_eq(paged.length(), 1)
  assert_eq(paged[0].document, "near")
}
