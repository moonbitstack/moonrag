///|
/// Embedding vectors (Koog `embeddings-base`): the `Vector` similarity math —
/// dimension, magnitude, dot product, cosine similarity, euclidean distance — and
/// the `Embedder` contract, whose deterministic `MockEmbedder` turns text into a
/// fixed vector so equal text embeds equally and `diff` reports the cosine distance.
/// `embed` is async, so the work runs inside a task group.
///
///     moon run examples/22-embeddings --target native
#coverage.skip
async fn main {
  @async.with_task_group(_g => {
    let a : @moonrag.Vector = { values: [3.0, 4.0], }
    let b : @moonrag.Vector = { values: [4.0, 3.0], }
    let zero : @moonrag.Vector = { values: [0.0, 0.0], }
    println(
      "a: dim=\{a.dimension()} magnitude=" +
      a.magnitude().to_string() +
      " is_null=\{a.is_null()}",
    )
    println("zero is_null=\{zero.is_null()}")
    println("a . b = " + a.dot_product(b).to_string())
    try {
      println("cosine(a,b) = " + a.cosine_similarity(b).to_string())
      println("euclidean(a,b) = " + a.euclidean_distance(b).to_string())
    } catch {
      e => println("vector error: " + e.to_string())
    }

    // The deterministic embedder: equal text embeds equally.
    let embedder = @moonrag.MockEmbedder::new()
    let e1 = embedder.embed("heke1228")
    let e2 = embedder.embed("heke1228")
    let e3 = embedder.embed("a different string")
    println("embedding dim=\{e1.dimension()}, deterministic=\{e1 == e2}")
    println("diff(same text)      = " + embedder.diff(e1, e2).to_string())
    println("diff(different text) = " + embedder.diff(e1, e3).to_string())
  })
}
