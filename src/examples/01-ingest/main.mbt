///|
/// The whole path once: a page and a note go in, ranked passages come out. The embedder is the
/// deterministic hashing one, so the output below is the same on every machine and no model is
/// called.
///
///     moon run src/examples/01-ingest --target native
#coverage.skip
async fn main {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = @index.Indexer::new(store)

  // A page is split by its headings, which is what keeps a retrieved chunk attached to its section.
  let page = @moonrag.Document::new(
    "<html><body><h1>Install</h1><p>Add the package with moon add moonbitstack/moonrag.</p><h2>Search</h2><p>Build a store, add documents, then search with a query vector.</p></body></html>",
    meta=Map([("source", @json.Json::string("guide.html"))]),
  )
  let sections = @split.HtmlSplitter::new(chunk_size=120)
  let pieces : Array[@moonrag.Document] = []
  for chunk in sections.split(page) {
    pieces.push(chunk)
  }

  // A note is split by paragraphs, with the source the loader records.
  let note = @load.MarkdownLoader::new(
    "notes.md", "# Field notes\n\nCosine similarity ignores magnitude, so a long passage and a short one about the same subject compare fairly.\n",
  )
  let paragraphs = @split.RecursiveSplitter::new(
    chunk_size=200,
    chunk_overlap=0,
  )
  for document in @moonrag.Loader::load(note) {
    for chunk in paragraphs.split(document) {
      pieces.push(chunk)
    }
  }
  println("documents to index: \{pieces.length()}")

  let stats = indexer.index(pieces)
  println(
    "indexed: added=\{stats.added} updated=\{stats.updated} skipped=\{stats.skipped}",
  )

  let retriever : &@moonrag.Retriever = @moonrag.SimilarityRetriever::new(
    embedder, store,
  )
  for query in ["how do I add the package", "cosine and magnitude"] {
    println("\nquery: \{query}")
    for hit in retriever.retrieve(query, limit=2) {
      let section = match hit.document.str_meta("h2") {
        Some(section) => " > " + section
        None =>
          match hit.document.str_meta("title") {
            Some(title) => " > " + title
            None => ""
          }
      }
      println(
        "  \{hit.score}  [\{hit.document.str_meta("source").unwrap_or("?")}\{section}] \{hit.document.text}",
      )
    }
  }

  // Indexing the same documents again costs nothing: nothing changed.
  let again = indexer.index(pieces)
  println("\nsecond pass: added=\{again.added} skipped=\{again.skipped}")
}
