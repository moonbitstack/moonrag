// The embedder contract (Koog `embeddings-base` `Embedder`): turn text into a `Vector` and measure
// the difference between two embeddings (lower means more similar). Real embedders call an LLM over
// the network; `MockEmbedder` is deterministic, for tests and offline similarity work.
// Source: embeddings/embeddings-base/.../base/Embedder.kt.

///|
/// Turns text into an embedding vector and scores the difference between two embeddings.
pub(open) trait Embedder {
  async fn embed(Self, text : String) -> Vector
  fn diff(Self, embedding1 : Vector, embedding2 : Vector) -> Double
}

///|
/// A deterministic embedder for tests and offline use: it maps text to a fixed 4-dimensional vector
/// by bucketing each code unit, so equal text yields equal vectors and shared characters pull two
/// texts' vectors together — no network. `diff` is the cosine distance (`1 - cosine similarity`).
pub struct MockEmbedder {
  dimension : Int32
}

///|
/// A fresh deterministic embedder producing `dimension`-component vectors (default 4).
pub fn MockEmbedder::new(dimension~ : Int32 = 4) -> MockEmbedder {
  { dimension, }
}

///|
pub impl Embedder for MockEmbedder with fn embed(self, text) {
  let buckets : Array[Double] = Array::make(self.dimension, 0.0)
  for i = 0; i < text.length(); i = i + 1 {
    let bucket = text[i].to_int() % self.dimension
    buckets[bucket] = buckets[bucket] + 1.0
  }
  { values: buckets, }
}

///|
pub impl Embedder for MockEmbedder with fn diff(self, embedding1, embedding2) {
  let _ = self
  // Cosine distance; a dimension mismatch counts as fully different.
  let similarity = embedding1.cosine_similarity(embedding2) catch { _ => 0.0 }
  1.0 - similarity
}

///|
pub extend MockEmbedder with Embedder::{embed, diff}
