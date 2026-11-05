// The deterministic embedder (Koog `Embedder` contract) — a blackbox test so the async `embed` can
// be driven by the `moonbitlang/async` test dependency.

///|
async test "mock embedder: deterministic embedding and cosine-distance diff" {
  let same : Ref[Bool] = { val: false, }
  let dim : Ref[Int32] = { val: 0, }
  let diff : Ref[Double] = { val: 1.0, }
  @async.with_task_group(g => {
    let _ = g.spawn(() => {
      let embedder = @embeddings.MockEmbedder::new()
      let a = embedder.embed("abcd")
      let b = embedder.embed("abcd")
      same.val = a == b
      dim.val = a.dimension()
      diff.val = embedder.diff(a, b)
    })
  })
  // Equal text yields equal 4-component vectors, and identical embeddings have zero cosine distance.
  assert_eq(same.val, true)
  assert_eq(dim.val, 4)
  assert_eq(diff.val < 1.0e-9, true)
}
