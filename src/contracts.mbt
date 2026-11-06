// The four seams of the library. A pipeline is assembled by picking one implementation of each, so a
// user can replace the store — memory, SQL, a hosted vector database — without touching the splitter,
// the loader or the retriever above it.

///|
/// Where vectors live.
///
/// `add` takes documents, not vectors: the store owns the embedder it was built with, so a caller
/// never has to keep the two in step by hand. `search` takes the query's vector, because the query is
/// often embedded once and searched in several stores, and because an embedding call is the expensive
/// part a caller wants to place itself.
pub(open) trait VectorStore {
  async fn add(Self, documents : Array[Document]) -> Array[String]
  async fn delete(Self, ids : ArrayView[String]) -> Unit
  async fn search(
    Self,
    vector : ArrayView[Double],
    limit~ : Int32,
    filter? : Filter,
  ) -> Array[Scored]
}

///|
/// Answers a question in text: embeds it, searches, returns the best documents.
///
/// A retriever is the whole read path behind one call; a reranker, a query rewrite, or MMR is an
/// implementation of this trait and nothing above it changes.
pub(open) trait Retriever {
  async fn retrieve(Self, query : String, limit~ : Int32) -> Array[Scored]
}

///|
/// Cuts one document into smaller documents.
///
/// Splitting is not async: it is pure text work with no I/O, and keeping it synchronous lets it run
/// inside a parser or a test without an event loop.
pub(open) trait Splitter {
  fn split(Self, document : Document) -> Array[Document]
}

///|
/// Produces documents from somewhere — a file, a directory, an API, a literal string.
///
/// Failure is part of the contract because the source may be unreadable or malformed; a loader that
/// quietly returns nothing looks identical to an empty document and hides the problem.
pub(open) trait Loader {
  async fn load(Self) -> Array[Document]
}
