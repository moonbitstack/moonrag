// Text-embedding vectors (Koog `embeddings-base` `Vector`): a vector of doubles with the similarity
// math RAG needs — magnitude, dot product, cosine similarity, Euclidean distance — each sum computed
// with Kahan compensation to keep numerical error small over many terms.
// Source: embeddings/embeddings-base/.../base/Vector.kt.

///|
/// A dimension mismatch in an operation that requires two vectors of equal length.
pub suberror VectorError {
  VectorError(String)
}

///|
/// A vector of floating-point values — the embedding of a piece of text.
pub(all) struct Vector {
  values : Array[Double]
} derive(Eq, Debug)

///|
/// The Kahan-compensated sum of `values`, reducing the numerical error that plain summation
/// accumulates over many floating-point additions.
fn kahan_sum(values : Array[Double]) -> Double {
  let mut sum = 0.0
  let mut compensation = 0.0
  for value in values {
    let y = value - compensation
    let t = sum + y
    compensation = t - sum - y
    sum = t
  }
  sum
}

///|
/// The number of components in the vector.
pub fn Vector::dimension(self : Vector) -> Int32 {
  self.values.length()
}

///|
/// Whether every component is `0.0`.
pub fn Vector::is_null(self : Vector) -> Bool {
  for v in self.values {
    if v != 0.0 {
      return false
    }
  }
  true
}

///|
/// The Euclidean norm — the square root of the sum of squared components.
pub fn Vector::magnitude(self : Vector) -> Double {
  kahan_sum(self.values.map(fn(v) { v * v })).sqrt()
}

///|
/// The dot product with `other` — the sum of products of corresponding components (over the shorter
/// length when the dimensions differ, matching Koog's `zip`).
pub fn Vector::dot_product(self : Vector, other : Vector) -> Double {
  let a = self.values.length()
  let b = other.values.length()
  let n = if a < b { a } else { b }
  let products : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    products.push(self.values[i] * other.values[i])
  }
  kahan_sum(products)
}

///|
/// The cosine similarity with `other`, in `[-1, 1]`: `1` for identical directions, `0` for
/// orthogonal (or either vector null), `-1` for opposite. Raises `VectorError` on a dimension
/// mismatch.
pub fn Vector::cosine_similarity(self : Vector, other : Vector) -> Double raise {
  guard self.dimension() == other.dimension() else {
    raise VectorError("Vectors must have the same dimension")
  }
  if self.is_null() || other.is_null() {
    return 0.0
  }
  self.dot_product(other) / (self.magnitude() * other.magnitude())
}

///|
/// The Euclidean distance to `other` — `0` for identical vectors. Raises `VectorError` on a
/// dimension mismatch.
pub fn Vector::euclidean_distance(
  self : Vector,
  other : Vector,
) -> Double raise {
  guard self.dimension() == other.dimension() else {
    raise VectorError("Vectors must have the same dimension")
  }
  let squares : Array[Double] = []
  for i = 0; i < self.values.length(); i = i + 1 {
    let d = self.values[i] - other.values[i]
    squares.push(d * d)
  }
  kahan_sum(squares).sqrt()
}

///|
pub extend Vector with Debug::{to_repr}

///|
pub extend Vector with Eq::{not_equal, equal}
