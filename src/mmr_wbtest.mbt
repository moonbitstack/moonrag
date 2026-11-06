// Maximal marginal relevance: the same query, two weights, two different answers.

///|
fn candidate(text : String, vector : Array[Double]) -> Candidate {
  { document: Document::new(text), vector, }
}

///|
test "mmr with lambda 1 is plain similarity ranking" {
  let query = [1.0, 0.0][:]
  let pool = [
    candidate("duplicate", [0.99, 0.01]),
    candidate("other", [0.0, 1.0]),
    candidate("exact", [1.0, 0.0]),
  ]
  let picked = mmr(query, pool[:], limit=3, lambda=1.0)
  assert_eq(picked.map(fn(hit) { hit.document.text }), [
    "exact", "duplicate", "other",
  ])
  assert_true((picked[0].score - 1.0).abs() < 1.0e-12)
}

///|
test "mmr with lambda 0 drops near-duplicates for novelty" {
  let query = [1.0, 0.0][:]
  let pool = [
    candidate("exact", [1.0, 0.0]),
    candidate("almost exact", [0.99, 0.01]),
    candidate("sideways", [0.0, 1.0]),
  ]
  let picked = mmr(query, pool[:], limit=3, lambda=0.0)
  assert_eq(picked.map(fn(hit) { hit.document.text }), [
    "exact", "sideways", "almost exact",
  ])
}

///|
test "mmr returns at most limit candidates and keeps the query score" {
  let query = [1.0, 0.0][:]
  let pool = [
    candidate("a", [1.0, 0.0]),
    candidate("b", [0.9, 0.1]),
    candidate("c", [0.8, 0.2]),
  ]
  let picked = mmr(query, pool[:], limit=2, lambda=0.5)
  assert_eq(picked.length(), 2)
  // The reported score is relevance to the query, not the MMR objective, so a caller can still see
  // how far the diverse pick had to drift.
  assert_true(picked[0].score > picked[1].score)
  let none = mmr(query, pool[:], limit=0)
  assert_eq(none, [])
  let more = mmr(query, pool[:], limit=10)
  assert_eq(more.length(), 3)
}

///|
test "mmr on an empty pool" {
  let picked = mmr([1.0, 0.0][:], [], limit=3)
  assert_eq(picked, [])
}

///|
test "mmr refuses vectors of the wrong length" {
  let pool = [candidate("short", [1.0])]
  let raised = try {
    mmr([1.0, 0.0][:], pool[:], limit=1) |> ignore
    false
  } catch {
    Refused::Mismatch(got~, want~) => got == 1 && want == 2
    _ => false
  }
  assert_true(raised)
}
