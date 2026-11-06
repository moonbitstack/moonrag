///|
/// The store on its own: add, filter, search, rerank with MMR, delete. Vectors are written down by
/// hand here, so every score below is arithmetic you can check.
///
///     moon run src/examples/02-store --target native
#coverage.skip
async fn main {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  // Two paragraphs about the sea and one about the mountains, each with a topic for filtering.
  let documents : Array[@moonrag.Document] = [
    @moonrag.Document::new(
      "the harbour at dawn, fishing boats leaving",
      meta=Map([
        ("topic", @json.Json::string("sea")),
        ("year", @json.Json::number(2024.0)),
      ]),
    ),
    @moonrag.Document::new(
      "fishing boats return to the harbour at dusk",
      meta=Map([
        ("topic", @json.Json::string("sea")),
        ("year", @json.Json::number(2025.0)),
      ]),
    ),
    @moonrag.Document::new(
      "a mountain path in autumn, cold and clear",
      meta=Map([
        ("topic", @json.Json::string("land")),
        ("year", @json.Json::number(2025.0)),
      ]),
    ),
  ]
  let ids = store.add(documents)
  println("stored documents: \{ids.length()}")

  let query = embedder.embed(["fishing boats in the harbour"])[0]

  println("\nranked by similarity:")
  for hit in store.search(query[:], limit=3) {
    println("  \{hit.score}  \{hit.document.text}")
  }

  println("\nonly what is about the sea, from 2025:")
  let filtered = store.search(
    query[:],
    limit=3,
    filter=@moonrag.Filter::All([
      @moonrag.Filter::Equal("topic", @json.Json::string("sea")),
      @moonrag.Filter::Compare("year", @moonrag.Order::AtLeast, 2025.0),
    ]),
  )
  for hit in filtered {
    println("  \{hit.score}  \{hit.document.text}")
  }

  // MMR: the two sea passages say nearly the same thing, so a diverse answer takes the mountain one.
  println("\nreranked with MMR (lambda 0.2):")
  let candidates : Array[@moonrag.Candidate] = []
  for hit in store.search(query[:], limit=3) {
    let id = hit.document.id.unwrap_or("")
    candidates.push({
      document: hit.document,
      vector: store.vector_of(id).unwrap(),
    })
  }
  for hit in @moonrag.mmr(query[:], candidates[:], limit=2, lambda=0.2) {
    println("  \{hit.score}  \{hit.document.text}")
  }

  let _ = store.delete([ids[0]][:])
  println("\nafter deleting \{ids[0]}: \{store.len()} documents left")
}
