// Chroma, over a server the tests do not start: `MOONRAG_LIVE` says one is there.

///|
/// Whether a live server is expected. Set by CI, and by anyone who wants the Chroma cases run.
fn live() -> Bool {
  @env.get_env_var("MOONRAG_LIVE") is Some(_)
}

///|
/// An environment variable, or `fallback` when it is unset.
fn setting(name : String, fallback : String) -> String {
  @env.get_env_var(name).unwrap_or(fallback)
}

///|
/// A store over a freshly emptied collection.
async fn fresh_store(
  embedder : &@moonrag.Embedder,
) -> &@moonrag.VectorStore raise {
  let store = @cstore.ChromaStore::new(
    setting("MOONRAG_CHROMA_URL", "http://127.0.0.1:8000"),
    embedder,
    dimension=256,
    collection="moonrag_standard",
  )
  store.create()
  store.clear()
  store
}

///|
async test "the vector-store standard cases hold on Chroma" {
  if !live() {
    println(
      "skipped: set MOONRAG_LIVE=1 and point MOONRAG_CHROMA_URL at a Chroma server",
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
