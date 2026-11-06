// Two ways to answer "what is relevant to this question?": rank by similarity alone, or rank by
// similarity while keeping the answers unlike each other (maximal marginal relevance). Both sit on the
// same two pieces — an `Embedder` and a `VectorStore` — so either works against any store.

///|
/// A document together with the vector it was embedded to.
///
/// MMR reranks by comparing candidates with each other, and a score alone cannot do that: the vectors
/// have to travel with the documents.
pub(all) struct Candidate {
  document : Document
  vector : Array[Double]
}

///|
/// Pick up to `limit` candidates that are relevant to `query` and unlike each other.
///
/// Each round scores every remaining candidate as `lambda * similarity to the query - (1 - lambda) *
/// highest similarity to an already picked one`, and takes the best; `lambda = 1` degenerates to plain
/// similarity, `lambda = 0` to "show me the most novel document". Ties go to the earlier candidate, so
/// the result is deterministic.
///
/// Raises `Mismatch` when a candidate vector's length differs from the query's.
pub fn mmr(
  query : ArrayView[Double],
  candidates : ArrayView[Candidate],
  limit~ : Int32,
  lambda~ : Double = 0.5,
) -> Array[Scored] raise {
  let remaining : Array[Int32] = []
  for i, candidate in candidates {
    guard candidate.vector.length() == query.length() else {
      raise Mismatch(got=candidate.vector.length(), want=query.length())
    }
    remaining.push(i)
  }
  let relevance : Array[Double] = []
  for candidate in candidates {
    relevance.push(cosine_similarity(query, candidate.vector[:]))
  }
  let picked : Array[Int32] = []
  while picked.length() < limit && remaining.length() > 0 {
    let mut best_at = 0
    let mut best_score = 0.0
    for position, index in remaining {
      let score = if picked.length() == 0 || lambda >= 1.0 {
        relevance[index]
      } else {
        let mut overlap = -2.0
        for chosen in picked {
          let similarity = cosine_similarity(
            candidates[index].vector[:],
            candidates[chosen].vector[:],
          )
          if similarity > overlap {
            overlap = similarity
          }
        }
        lambda * relevance[index] - (1.0 - lambda) * overlap
      }
      if position == 0 || score > best_score {
        best_at = position
        best_score = score
      }
    }
    let chosen = remaining[best_at]
    picked.push(chosen)
    let rest : Array[Int32] = []
    for position, index in remaining {
      if position != best_at {
        rest.push(index)
      }
    }
    remaining.clear()
    remaining.push_iter(rest.iter())
  }
  let out : Array[Scored] = []
  for index in picked {
    out.push({ document: candidates[index].document, score: relevance[index], })
  }
  out
}
