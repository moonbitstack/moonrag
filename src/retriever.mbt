// The two retrievers that ship with the library: plain similarity, and MMR for when near-duplicates
// would fill the result. Both hold an embedder and a store rather than inheriting from one, so a
// different store only changes what is passed in.

///|
/// Ranks documents by cosine similarity to the query, and returns the best `limit`.
pub struct SimilarityRetriever {
  embedder : &Embedder
  store : &VectorStore
  filter : Filter?
}

///|
/// A similarity retriever over `store`, embedding queries with `embedder`. `filter` narrows the
/// candidates before ranking, in the store where the documents live.
pub fn SimilarityRetriever::new(
  embedder : &Embedder,
  store : &VectorStore,
  filter? : Filter,
) -> SimilarityRetriever {
  { embedder, store, filter, }
}

///|
pub impl Retriever for SimilarityRetriever with fn retrieve(self, query, limit~) {
  let vectors = self.embedder.embed([query][:])
  guard vectors.length() == 1 else { raise Empty(what="query embedding") }
  match self.filter {
    Some(filter) => self.store.search(vectors[0][:], limit~, filter~)
    None => self.store.search(vectors[0][:], limit~)
  }
}

///|
pub extend SimilarityRetriever with Retriever::{retrieve}

///|
/// Returns relevant documents that are also unlike each other, by maximal marginal relevance.
///
/// A plain search on a corpus of near-duplicates returns the same paragraph five times. MMR trades
/// some relevance for coverage: `lambda` near `1` behaves like a plain search, near `0` like "the most
/// different thing that is still related".
pub struct MmrRetriever {
  embedder : &Embedder
  store : &VectorStore
  filter : Filter?
  lambda : Double
  fetch_limit : Int32
}

///|
/// An MMR retriever over `store`. `fetch_limit` candidates are ranked by similarity first and then
/// reranked by MMR, so it must be at least the `limit` a caller asks for; `lambda` weights relevance
/// against diversity.
pub fn MmrRetriever::new(
  embedder : &Embedder,
  store : &VectorStore,
  lambda~ : Double = 0.5,
  fetch_limit~ : Int32 = 20,
  filter? : Filter,
) -> MmrRetriever {
  { embedder, store, lambda, fetch_limit, filter, }
}

///|
pub impl Retriever for MmrRetriever with fn retrieve(self, query, limit~) {
  let query_vector = self.embedder.embed([query][:])
  guard query_vector.length() == 1 else { raise Empty(what="query embedding") }
  let fetched = match self.filter {
    Some(filter) =>
      self.store.search(query_vector[0][:], limit=self.fetch_limit, filter~)
    None => self.store.search(query_vector[0][:], limit=self.fetch_limit)
  }
  // A store hands back documents and scores, never vectors: MMR needs the vectors, and re-embedding
  // the few candidates is the price of working against any store rather than only the in-memory one.
  let vectors = self.embedder.embed(
    fetched.map(fn(hit) { hit.document.text })[:],
  )
  let candidates : Array[Candidate] = []
  for i, hit in fetched {
    candidates.push({ document: hit.document, vector: vectors[i], })
  }
  mmr(query_vector[0][:], candidates[:], limit~, lambda=self.lambda)
}

///|
pub extend MmrRetriever with Retriever::{retrieve}
