// One ranking policy for everything that scores: sort by score descending, ties in the order they
// arrived, then cut to the limit. Every store and retriever funnels through here so that two backends
// cannot disagree about what "the top three" means.

///|
/// `hits` sorted by score descending — equal scores keep their arrival order — cut to `limit`.
///
/// The sort is stable on purpose: with a small corpus, several documents tie at cosine `1.0`, and a
/// caller re-running a search expects the same three each time.
pub fn rank(hits : Array[Scored], limit : Int32) -> Array[Scored] {
  if limit <= 0 {
    return []
  }
  let order : Array[(Double, Int32, Scored)] = []
  for i, hit in hits {
    order.push((-hit.score, i, hit))
  }
  order.sort_by(fn(left, right) {
    let by_score = left.0.compare(right.0)
    if by_score != 0 {
      by_score
    } else {
      left.1.compare(right.1)
    }
  })
  let out : Array[Scored] = []
  for entry in order {
    if out.length() >= limit {
      break
    }
    out.push(entry.2)
  }
  out
}
