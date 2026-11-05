// Text-to-vector storage composition (Koog `EmbeddingStorage`) — a blackbox test so the async
// embed-on-add / embed-on-search path can be driven by the `moonbitlang/async` test dependency.

///|
async test "embedding storage: embeds documents on add and ranks them on search" {
  let top : Ref[String] = { val: "", }
  let count : Ref[Int32] = { val: 0, }
  let top_score : Ref[Double] = { val: 0.0, }
  @async.with_task_group(g => {
    let _ = g.spawn(() => {
      let embedder : &Embedder = MockEmbedder::new()
      let storage : @rag.EmbeddingStorage[String] = @rag.EmbeddingStorage::new(
        embedder,
        fn(s) { s },
      )
      let _ = storage.add(["aaaa", "bbbb", "cccc"])
      let hits = storage.search("aaaa")
      count.val = hits.length()
      if hits.length() > 0 {
        top.val = hits[0].document
        top_score.val = hits[0].score.value
      }
    })
  })
  // "aaaa" is identical to the query, so it ranks first with cosine 1; the orthogonal documents
  // (cosine 0) still pass the default min_score of 0.0 but rank below it.
  assert_eq(count.val, 3)
  assert_eq(top.val, "aaaa")
  assert_eq(top_score.val > 0.99, true)
}
