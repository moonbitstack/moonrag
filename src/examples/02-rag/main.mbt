///|
/// Retrieval (Koog `rag`): `EmbeddingStorage` embeds documents on add and ranks
/// them against a query on search; the lower-level `rank_by_similarity` scores a
/// query vector against stored vectors by cosine similarity, honouring min_score /
/// limit / offset; `VectorStore` is the in-memory index underneath. The embed path
/// is async, so it runs inside a task group.
///
///     moon run examples/23-rag --target native
#coverage.skip
async fn main {
  @async.with_task_group(_g => {
    // Text in, ranked text out — the embedder is applied on both add and search.
    let embedder : &@moonrag.Embedder = @moonrag.MockEmbedder::new()
    let storage : @moonrag.EmbeddingStorage[String] = @moonrag.EmbeddingStorage::new(
      embedder,
      s => s,
    )
    let ids = storage.add(["aaaa", "bbbb", "cccc"])
    println("added \{ids.length()} docs, storage size=\{storage.size()}")
    let hits = storage.search("aaaa")
    println("search 'aaaa' -> \{hits.length()} hits:")
    for h in hits {
      println("  " + h.document + " score=" + h.score.value.to_string())
    }
    println(
      "get(\{ids[0]}) = " +
      (match storage.get(ids[0]) {
        Some(d) => d
        None => "(gone)"
      }),
    )
    let _ = storage.delete(ids[0])
    println("after delete: size=\{storage.size()}")

    // The ranking primitive over pre-computed vectors.
    let query : @moonrag.Vector = { values: [1.0, 0.0], }
    let docs : Array[(String, @moonrag.Vector)] = [
      ("same", { values: [1.0, 0.0], }),
      ("orthogonal", { values: [0.0, 1.0], }),
      ("near", { values: [1.0, 0.5], }),
      ("opposite", { values: [-1.0, 0.0], }),
    ]
    try {
      // Default min_score 0.0 drops the negative-cosine document.
      let ranked = @moonrag.rank_by_similarity(query, docs)
      println("rank_by_similarity (default) -> \{ranked.length()} kept:")
      for r in ranked {
        println("  " + r.document + " = " + r.score.value.to_string())
      }
      // limit + offset paginate.
      let paged = @moonrag.rank_by_similarity(query, docs, limit=1, offset=1)
      println("page(limit=1, offset=1) -> " + paged[0].document)
    } catch {
      e => println("rank error: " + e.to_string())
    }

    // The raw index: store/get/delete/size over (doc, vector) pairs.
    let index : @moonrag.VectorStore[String] = @moonrag.VectorStore::new()
    let d0 = index.store("hello", { values: [1.0, 0.0], })
    let _ = index.store("world", { values: [0.0, 1.0], })
    println("VectorStore: first id=" + d0 + ", size=\{index.size()}")
    let _ = index.delete(d0)
    println("after delete(\{d0}): size=\{index.size()}")
  })
}
