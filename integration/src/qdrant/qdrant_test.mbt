// Qdrant, over a server the tests do not start: `MOONRAG_LIVE` says one is there.
//
// Unset, every test here prints why it did nothing and returns. Set, a server has to answer: a
// request that fails takes the test down, because a live suite that passes when the server is
// missing is a suite that proves nothing.

///|
/// Whether a live server is expected. Set by CI, and by anyone who wants the Qdrant cases run.
fn live() -> Bool {
  @env.get_env_var("MOONRAG_LIVE") is Some(_)
}

///|
/// An environment variable, or `fallback` when it is unset.
fn setting(name : String, fallback : String) -> String {
  @env.get_env_var(name).unwrap_or(fallback)
}

///|
/// A store over a freshly emptied collection, so a case never sees what the previous one wrote.
async fn fresh_store(
  embedder : &@moonrag.Embedder,
) -> &@moonrag.VectorStore raise {
  let store = @qstore.QdrantStore::new(
    setting("MOONRAG_QDRANT_URL", "http://127.0.0.1:6333"),
    embedder,
    dimension=256,
    collection="moonrag_standard",
  )
  store.create()
  store.clear()
  store
}

///|
async test "the vector-store standard cases hold on Qdrant" {
  if !live() {
    println(
      "skipped: set MOONRAG_LIVE=1 and point MOONRAG_QDRANT_URL at a Qdrant server",
    )
    return
  }
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let failures = @standard.check(
    embedder,
    async fn() { fresh_store(embedder) },
  )
  if failures.length() > 0 {
    abort(failures.join("\n"))
  }
}
