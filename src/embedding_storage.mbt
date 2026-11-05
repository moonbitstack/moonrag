// Text-to-vector storage composition (Koog `EmbeddingStorage`): compose an `Embedder` with a
// `VectorStore` so documents are embedded on the way in and a query is embedded on the way out, then
// ranked by similarity. This is the layer that turns raw text into retrievable, ranked documents.
// Source: rag/rag-vector/.../storage/EmbeddingStorage.kt.

///|
/// A document store that embeds documents on insertion and queries on search (Koog
/// `EmbeddingStorage`): `to_text` extracts the text to embed from a document, the `Embedder` turns
/// text into vectors, and the `VectorStore` holds them for cosine-similarity retrieval.
pub struct EmbeddingStorage[Doc] {
  embedder : &Embedder
  to_text : (Doc) -> String
  store : VectorStore[Doc]
}

///|
/// A fresh storage over `embedder`, extracting embeddable text from each document with `to_text`.
pub fn[Doc] EmbeddingStorage::new(
  embedder : &Embedder,
  to_text : (Doc) -> String,
) -> EmbeddingStorage[Doc] {
  { embedder, to_text, store: VectorStore::new(), }
}

///|
/// Embed each document and store it, returning the assigned ids (Koog `EmbeddingStorage.add`).
pub async fn[Doc] EmbeddingStorage::add(
  self : EmbeddingStorage[Doc],
  documents : Array[Doc],
) -> Array[String] {
  let ids : Array[String] = []
  for doc in documents {
    let vector = self.embedder.embed((self.to_text)(doc))
    ids.push(self.store.store(doc, vector))
  }
  ids
}

///|
/// Embed `query_text` and return the stored documents most similar to it, ranked by cosine
/// similarity (Koog `EmbeddingStorage.search`). Raises `VectorError` on a dimension
/// mismatch between the query and a stored document.
pub async fn[Doc] EmbeddingStorage::search(
  self : EmbeddingStorage[Doc],
  query_text : String,
  limit~ : Int32 = 10,
  offset~ : Int32 = 0,
  min_score~ : Double = 0.0,
) -> Array[SearchResult[Doc]] {
  let query = self.embedder.embed(query_text)
  rank_by_similarity(query, self.store.pairs(), limit~, offset~, min_score~)
}

///|
/// The document stored under `id`, or `None`.
pub fn[Doc] EmbeddingStorage::get(
  self : EmbeddingStorage[Doc],
  id : String,
) -> Doc? {
  self.store.get(id)
}

///|
/// Remove the document under `id`; returns whether it was present.
pub fn[Doc] EmbeddingStorage::delete(
  self : EmbeddingStorage[Doc],
  id : String,
) -> Bool {
  self.store.delete(id)
}

///|
/// The number of stored documents.
pub fn[Doc] EmbeddingStorage::size(self : EmbeddingStorage[Doc]) -> Int32 {
  self.store.size()
}
