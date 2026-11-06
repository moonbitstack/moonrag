// The whole path end to end: bytes in, ranked passages out. Each stage is one package, and this test
// fails if any pair of them disagrees about a document.

///|
/// The raw text of the HTML page the site test indexes. It is split as HTML — the markup is where the
/// headings live — so this is the page as it comes off disk, not the loader's flattened text.
fn page_html() -> String {
  "<html><head><title>Guide</title></head><body><h1>Install</h1><p>Add the package with moon add moonbitstack/moonrag.</p><h2>Search</h2><p>Build a store, add documents, then search with a query vector.</p></body></html>"
}

///|
/// The pieces a page becomes: split by heading, with the source recorded so a filter can tell pages
/// apart.
fn page_pieces() -> Array[@moonrag.Document] raise {
  let splitter = @split.HtmlSplitter::new(chunk_size=200)
  let page = @moonrag.Document::new(
    page_html(),
    meta=Map([("source", @json.Json::string("guide.html"))]),
  )
  splitter.split(page)
}

///|
/// The documents a small site produces: a HTML page and a Markdown note, loaded, split, indexed and
/// searched through the public API only.
async fn site() -> (
  &@moonrag.Retriever,
  @moonrag.InMemoryVectorStore,
  @index.Indexer,
) {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let indexer = @index.Indexer::new(store)
  let note = @load.MarkdownLoader::new(
    "notes.md", "# Field notes\n\nRanking by cosine similarity ignores magnitude, so long and short passages compare fairly.\n",
  )
  let pieces = page_pieces()
  let text_splitter = @split.RecursiveSplitter::new(
    chunk_size=200,
    chunk_overlap=0,
  )
  for document in @moonrag.Loader::load(note) {
    for chunk in text_splitter.split(document) {
      pieces.push(chunk)
    }
  }
  let _ = indexer.index(pieces)
  let retriever : &@moonrag.Retriever = @moonrag.SimilarityRetriever::new(
    embedder, store,
  )
  (retriever, store, indexer)
}

///|
async test "a page loaded, split and indexed comes back with its heading path" {
  let (retriever, store, indexer) = site()
  assert_true(store.len() >= 3)
  assert_eq(indexer.len(), store.len())
  let hits = retriever.retrieve("moon add the package", limit=1)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].document.str_meta("h1"), Some("Install"))
  assert_eq(hits[0].document.str_meta("source"), Some("guide.html"))
}

///|
async test "the Markdown note is findable by what it says" {
  let (retriever, _, _) = site()
  let hits = retriever.retrieve("cosine similarity ignores magnitude", limit=1)
  assert_eq(hits.length(), 1)
  assert_true(hits[0].document.text.contains("cosine"))
  assert_eq(hits[0].document.str_meta("title"), Some("Field notes"))
}

///|
async test "re-indexing the same site changes nothing" {
  let (_, store, indexer) = site()
  let before = store.len()
  // The second pass rebuilds the same documents and indexes them again.
  let pieces = page_pieces()
  let stats = indexer.index(pieces)
  assert_eq(stats.added, 0)
  assert_eq(stats.updated, 0)
  assert_eq(stats.skipped, pieces.length())
  // The Markdown chunks were not part of this run, and their source was not either: they stay.
  assert_true(store.len() >= before)
}
