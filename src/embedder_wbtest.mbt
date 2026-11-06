// The hashing embedder: deterministic, unit length, and lexical enough to rank a keyword query.

///|
async test "the same text embeds to the same unit-length vector" {
  let embedder : &Embedder = HashingEmbedder::new()
  let first = embedder.embed(["the quick brown fox"])
  let second = embedder.embed(["the quick brown fox"])
  assert_eq(first, second)
  assert_eq(first[0].length(), 256)
  assert_true((magnitude(first[0][:]) - 1.0).abs() < 1.0e-12)
  // A different text lands elsewhere.
  let other = embedder.embed(["an unrelated sentence"])
  assert_true(cosine_similarity(first[0][:], other[0][:]) < 0.9)
}

///|
async test "a text that shares words scores higher than one that shares nothing" {
  let embedder : &Embedder = HashingEmbedder::new()
  let vectors = embedder.embed([
    "vector store retrieval", "vector store ranking", "banana bread recipe",
  ])
  let related = cosine_similarity(vectors[0][:], vectors[1][:])
  let unrelated = cosine_similarity(vectors[0][:], vectors[2][:])
  assert_true(related > unrelated)
}

///|
async test "the dimension is configurable and an empty text has no direction" {
  let embedder : &Embedder = HashingEmbedder::new(dimension=16)
  let vectors = embedder.embed(["", "some words"])
  assert_eq(vectors[0].length(), 16)
  assert_eq(magnitude(vectors[0][:]), 0.0)
  assert_eq(vectors[1].length(), 16)
}

///|
async test "a non-positive dimension is refused" {
  let raised = try {
    let _ = HashingEmbedder::new(dimension=0)
    false
  } catch {
    Refused::Empty(what~) => what == "dimension"
    _ => false
  }
  assert_true(raised)
}

///|
async test "Chinese text is hashed by characters, not by whitespace" {
  // No spaces to split on: the trigrams are what give each phrase its own buckets.
  let embedder : &Embedder = HashingEmbedder::new()
  let vectors = embedder.embed(["向量检索", "向量检索", "香蕉面包"])
  assert_eq(vectors[0], vectors[1])
  assert_true(cosine_similarity(vectors[0][:], vectors[2][:]) < 1.0)
}
