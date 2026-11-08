// The two vector encodings: little-endian bytes for SQLite, pgvector's text form for PostgreSQL.

///|
test "a vector survives the round trip through bytes" {
  let vector = [1.0, -2.5, 0.0, 3.25, 1.0e-9, -1.0e9]
  let back = decode_vector(encode_vector(vector[:])[:])
  assert_eq(back, vector)
}

///|
test "the bytes are little endian f64s" {
  // 1.0 is 0x3FF0000000000000; little endian puts the low byte first.
  let bytes = encode_vector([1.0][:])
  assert_eq(bytes.length(), 8)
  assert_eq(bytes[0].to_hex(), "00")
  assert_eq(bytes[6].to_hex(), "f0")
  assert_eq(bytes[7].to_hex(), "3f")
}

///|
test "a blob that is not a whole number of doubles is refused" {
  let outcome = try {
    let _ = decode_vector(b"\x00\x00\x00")
    "accepted"
  } catch {
    @moonrag.Malformed(..) => "refused"
    _ => "other"
  }
  assert_eq(outcome, "refused")
}

///|
test "the pgvector literal is a bracketed comma-separated list" {
  assert_eq(vector_literal([1.0, 2.5, -0.5][:]), "[1,2.5,-0.5]")
  assert_eq(vector_literal([]), "[]")
}
