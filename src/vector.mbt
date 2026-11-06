// The arithmetic a vector store needs and nothing else: magnitudes, dot products, cosine similarity,
// Euclidean distance. Sums over many terms use Neumaier compensation, because a retrieval score that
// drifts in the fourth digit reorders results silently and no test notices.

///|
/// The dot product of two vectors of the same length.
///
/// Raises `Mismatch` when the lengths differ.
pub fn dot_product(
  left : ArrayView[Double],
  right : ArrayView[Double],
) -> Double raise {
  guard left.length() == right.length() else {
    raise Mismatch(got=right.length(), want=left.length())
  }
  let mut sum = 0.0
  let mut compensation = 0.0
  for i, a in left {
    let term = a * right[i]
    let total = sum + term
    if total.abs() >= term.abs() {
      compensation = compensation + (sum - total + term)
    } else {
      compensation = compensation + (term - total + sum)
    }
    sum = total
  }
  sum + compensation
}

///|
/// The Euclidean norm of a vector.
pub fn magnitude(vector : ArrayView[Double]) -> Double {
  let mut sum = 0.0
  let mut compensation = 0.0
  for value in vector {
    let term = value * value
    let total = sum + term
    if total.abs() >= term.abs() {
      compensation = compensation + (sum - total + term)
    } else {
      compensation = compensation + (term - total + sum)
    }
    sum = total
  }
  (sum + compensation).sqrt()
}

///|
/// The cosine similarity of two vectors, in `[-1, 1]`: `1` for the same direction, `0` for
/// orthogonal vectors or when either is all zeros, `-1` for opposite directions.
///
/// Raises `Mismatch` when the lengths differ. Cosine ignores magnitude, so a long document and a
/// short one about the same thing score alike — which is why it is the usual ranking metric for text.
pub fn cosine_similarity(
  left : ArrayView[Double],
  right : ArrayView[Double],
) -> Double raise {
  guard left.length() == right.length() else {
    raise Mismatch(got=right.length(), want=left.length())
  }
  let left_norm = magnitude(left)
  let right_norm = magnitude(right)
  if left_norm == 0.0 || right_norm == 0.0 {
    return 0.0
  }
  dot_product(left, right) / (left_norm * right_norm)
}

///|
/// The Euclidean distance between two vectors: `0` for identical vectors, larger for further ones.
///
/// Raises `Mismatch` when the lengths differ. Use it when the embedding model was trained on it;
/// ranking by distance ascending and by similarity descending agree only for normalised vectors, so
/// the two are kept apart rather than folded into one.
pub fn euclidean_distance(
  left : ArrayView[Double],
  right : ArrayView[Double],
) -> Double raise {
  guard left.length() == right.length() else {
    raise Mismatch(got=right.length(), want=left.length())
  }
  let mut sum = 0.0
  let mut compensation = 0.0
  for i, value in left {
    let delta = value - right[i]
    let term = delta * delta
    let total = sum + term
    if total.abs() >= term.abs() {
      compensation = compensation + (sum - total + term)
    } else {
      compensation = compensation + (term - total + sum)
    }
    sum = total
  }
  (sum + compensation).sqrt()
}

///|
/// `vector` scaled to unit length; an all-zero vector comes back unchanged rather than as NaNs.
pub fn normalized(vector : ArrayView[Double]) -> Array[Double] {
  let norm = magnitude(vector)
  if norm == 0.0 {
    return vector.to_owned()
  }
  vector.map(fn(value) { value / norm })
}
