// In-memory vector storage and cosine-similarity ranking (Koog `rag-vector`): store documents with
// their embeddings, then rank them against a query embedding to retrieve the most relevant. The
// backend (`VectorStore`) and the ranking (`rank_by_similarity`) are pure — the embedding step that
// turns text into a `Vector` lives one layer up, on the async `Embedder`.
// Source: rag/rag-vector/.../backend/InMemoryVectorStorageBackend.kt and storage/EmbeddingStorage.kt.

///|
/// The metric a similarity score was computed with (Koog `ScoreMetric`).
pub(all) enum ScoreMetric {
  CosineSimilarity
} derive(Eq, Debug)

///|
/// A similarity score and the metric it was computed with (Koog `Score`).
pub(all) struct Score {
  value : Double
  metric : ScoreMetric
} derive(Eq, Debug)

///|
/// A search hit: a stored document and the score it earned against the query (Koog `SearchResult`).
pub(all) struct SearchResult[Doc] {
  document : Doc
  score : Score
}

///|
/// An in-memory store of documents keyed by a generated id, each paired with its embedding vector
/// (Koog `InMemoryVectorStorageBackend`). Ids are sequential (`doc-0`, `doc-1`, …) rather than random
/// UUIDs, so the store is deterministic.
pub struct VectorStore[Doc] {
  mut next_id : Int32
  entries : Map[String, (Doc, Vector)]
}

///|
/// A fresh empty store.
pub fn[Doc] VectorStore::new() -> VectorStore[Doc] {
  { next_id: 0, entries: {}, }
}

///|
/// Store `document` with its `vector`, returning the id assigned to it.
pub fn[Doc] VectorStore::store(
  self : VectorStore[Doc],
  document : Doc,
  vector : Vector,
) -> String {
  let id = "doc-" + self.next_id.to_string()
  self.next_id = self.next_id + 1
  self.entries[id] = (document, vector)
  id
}

///|
/// The document stored under `id`, or `None`.
pub fn[Doc] VectorStore::get(self : VectorStore[Doc], id : String) -> Doc? {
  match self.entries.get(id) {
    Some(pair) => Some(pair.0)
    None => None
  }
}

///|
/// Remove the document under `id`; returns whether it was present.
pub fn[Doc] VectorStore::delete(self : VectorStore[Doc], id : String) -> Bool {
  match self.entries.get(id) {
    Some(_) => {
      self.entries.remove(id)
      true
    }
    None => false
  }
}

///|
/// The number of stored documents.
pub fn[Doc] VectorStore::size(self : VectorStore[Doc]) -> Int32 {
  self.entries.length()
}

///|
/// Every stored `(document, vector)` pair — the input a similarity search ranks over.
pub fn[Doc] VectorStore::pairs(
  self : VectorStore[Doc],
) -> Array[(Doc, Vector)] {
  let out : Array[(Doc, Vector)] = []
  for _id, pair in self.entries {
    out.push(pair)
  }
  out
}

///|
/// Rank `documents` (each a document paired with its embedding) against `query` by cosine similarity
/// (Koog `EmbeddingStorage.search`): score each, keep those at or above `min_score`, sort by score
/// descending, then skip `offset` and keep at most `limit`. Raises `VectorError` on a
/// dimension mismatch.
pub fn[Doc] rank_by_similarity(
  query : Vector,
  documents : Array[(Doc, Vector)],
  limit~ : Int32 = 10,
  offset~ : Int32 = 0,
  min_score~ : Double = 0.0,
) -> Array[SearchResult[Doc]] raise {
  let hits : Array[SearchResult[Doc]] = []
  for pair in documents {
    let value = query.cosine_similarity(pair.1)
    if value >= min_score {
      hits.push({
        document: pair.0,
        score: { value, metric: CosineSimilarity, },
      })
    }
  }
  // Insertion sort, score descending (stable: equal scores keep their insertion order).
  for i = 1; i < hits.length(); i = i + 1 {
    let current = hits[i]
    let mut j = i - 1
    while j >= 0 && hits[j].score.value < current.score.value {
      hits[j + 1] = hits[j]
      j = j - 1
    }
    hits[j + 1] = current
  }
  let out : Array[SearchResult[Doc]] = []
  for i = offset; i < hits.length() && out.length() < limit; i = i + 1 {
    out.push(hits[i])
  }
  out
}

///|
pub extend Score with Debug::{to_repr}

///|
pub extend Score with Eq::{not_equal, equal}

///|
pub extend ScoreMetric with Debug::{to_repr}

///|
pub extend ScoreMetric with Eq::{not_equal, equal}
