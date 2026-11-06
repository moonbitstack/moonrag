// The vector arithmetic: the numbers a store ranks by, checked against values computed by hand.

///|
test "cosine similarity: same direction, orthogonal, opposite, zero vector" {
  assert_eq(cosine_similarity([1.0, 2.0, 3.0][:], [1.0, 2.0, 3.0][:]), 1.0)
  assert_eq(cosine_similarity([1.0, 0.0][:], [0.0, 1.0][:]), 0.0)
  assert_eq(cosine_similarity([1.0, 0.0][:], [-1.0, 0.0][:]), -1.0)
  // A zero vector has no direction, so every similarity with it is zero rather than a NaN.
  assert_eq(cosine_similarity([0.0, 0.0][:], [3.0, 4.0][:]), 0.0)
  assert_eq(cosine_similarity([3.0, 4.0][:], [0.0, 0.0][:]), 0.0)
}

///|
test "cosine similarity ignores magnitude" {
  let small = cosine_similarity([1.0, 1.0][:], [1.0, 0.0][:])
  let large = cosine_similarity([1000.0, 1000.0][:], [0.5, 0.0][:])
  assert_true((small - large).abs() < 1.0e-12)
}

///|
test "dot product and magnitude of a 3-4-5 triangle" {
  assert_eq(dot_product([1.0, 2.0, 3.0][:], [4.0, 5.0, 6.0][:]), 32.0)
  assert_eq(magnitude([3.0, 4.0][:]), 5.0)
  assert_eq(magnitude([0.0, 0.0][:]), 0.0)
  assert_eq(dot_product([1.0, 0.0][:], [0.0, 1.0][:]), 0.0)
}

///|
test "euclidean distance" {
  assert_eq(euclidean_distance([0.0, 0.0][:], [3.0, 4.0][:]), 5.0)
  assert_eq(euclidean_distance([1.0, 2.0][:], [1.0, 2.0][:]), 0.0)
}

///|
test "normalized scales to unit length and leaves zero alone" {
  let unit = normalized([3.0, 4.0][:])
  assert_true((magnitude(unit[:]) - 1.0).abs() < 1.0e-12)
  assert_eq(unit[0], 0.6)
  assert_eq(normalized([0.0, 0.0][:]), [0.0, 0.0])
}

///|
test "sums stay accurate over many terms" {
  // A thousand 0.1s: plain left-to-right summation drifts, compensated summation does not.
  let values : Array[Double] = []
  for i = 0; i < 1000; i = i + 1 {
    values.push(0.1)
  }
  // sqrt(1000 * 0.1 * 0.1) = sqrt(10).
  assert_true((magnitude(values[:]) - 10.0.sqrt()).abs() < 1.0e-10)
}

///|
test "dimension mismatch raises Mismatch with both lengths" {
  let raised = try {
    cosine_similarity([1.0, 2.0][:], [1.0][:]) |> ignore
    None
  } catch {
    Refused::Mismatch(got~, want~) => Some((got, want))
    _ => None
  }
  assert_eq(raised, Some((1, 2)))
  let dot = try {
    dot_product([1.0][:], [1.0, 2.0][:]) |> ignore
    false
  } catch {
    Refused::Mismatch(_) => true
    _ => false
  }
  assert_true(dot)
  let distance = try {
    euclidean_distance([1.0][:], [1.0, 2.0][:]) |> ignore
    false
  } catch {
    Refused::Mismatch(_) => true
    _ => false
  }
  assert_true(distance)
}
