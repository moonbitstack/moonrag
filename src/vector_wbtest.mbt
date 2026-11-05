// The embedding vector math (Koog `embeddings-base` `Vector`).

///|
/// Assert two doubles are within a small tolerance (the float results are not bit-exact).
fn assert_close(a : Double, b : Double) -> Unit {
  let d = if a > b { a - b } else { b - a }
  if d > 1.0e-9 {
    abort("expected \{a} ≈ \{b}")
  }
}

///|
test "vector: dimension, is_null, magnitude, and dot product" {
  assert_eq(Vector::{ values: [1.0, 2.0, 3.0], }.dimension(), 3)
  assert_eq(Vector::{ values: [0.0, 0.0, 0.0], }.is_null(), true)
  assert_eq(Vector::{ values: [0.0, 1.0], }.is_null(), false)
  // 3-4-5 right triangle.
  assert_close(Vector::{ values: [3.0, 4.0], }.magnitude(), 5.0)
  // 1*4 + 2*5 + 3*6 = 32.
  assert_close(
    Vector::{ values: [1.0, 2.0, 3.0], }.dot_product({
      values: [4.0, 5.0, 6.0],
    }),
    32.0,
  )
}

///|
test "vector: cosine similarity spans identical, orthogonal, and opposite" {
  // Identical direction → 1.
  assert_close(
    Vector::{ values: [1.0, 2.0, 3.0], }.cosine_similarity({
      values: [1.0, 2.0, 3.0],
    }),
    1.0,
  )
  // Orthogonal → 0.
  assert_close(
    Vector::{ values: [1.0, 0.0], }.cosine_similarity({ values: [0.0, 1.0], }),
    0.0,
  )
  // Opposite → -1.
  assert_close(
    Vector::{ values: [1.0, 0.0], }.cosine_similarity({ values: [-1.0, 0.0], }),
    -1.0,
  )
  // A null vector yields 0, not a division by zero.
  assert_close(
    Vector::{ values: [0.0, 0.0], }.cosine_similarity({ values: [1.0, 1.0], }),
    0.0,
  )
}

///|
test "vector: euclidean distance and dimension-mismatch error" {
  assert_close(
    Vector::{ values: [0.0, 0.0], }.euclidean_distance({ values: [3.0, 4.0], }),
    5.0,
  )
  assert_close(
    Vector::{ values: [1.0, 2.0, 3.0], }.euclidean_distance({
      values: [1.0, 2.0, 3.0],
    }),
    0.0,
  )
  // Mismatched dimensions raise.
  let raised = try {
    Vector::{ values: [1.0, 2.0], }.cosine_similarity({ values: [1.0], })
    |> ignore
    false
  } catch {
    _ => true
  }
  assert_eq(raised, true)
}
