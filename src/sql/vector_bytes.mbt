// Reading and writing a vector as bytes and as pgvector's text form.
//
// SQLite has no vector type, so a vector is a BLOB of little-endian `f64`s — the layout every other
// database and numpy array uses, and the one that costs nothing to scan. PostgreSQL's pgvector takes
// its own text form, `[1,2,3]`, which needs no encoding beyond a short write.

///|
/// `vector` as little-endian `f64` bytes.
fn encode_vector(vector : ArrayView[Double]) -> Bytes {
  let buffer = @buffer.Buffer::Buffer(size_hint=vector.length() * 8)
  for value in vector {
    buffer.write_double_le(value)
  }
  buffer.to_bytes()
}

///|
/// The vector held in `bytes`, or `Malformed` when the length is not a whole number of `f64`s.
fn decode_vector(bytes : BytesView) -> Array[Double] raise {
  guard bytes.length() % 8 == 0 else {
    raise @moonrag.Malformed(
      at=0,
      why="vector blob is not a whole number of f64s",
    )
  }
  let out : Array[Double] = []
  let mut at = 0
  while at < bytes.length() {
    let mut bits : UInt64 = 0UL
    for i in 0..<8 {
      bits = bits | (bytes[at + i].to_uint64() << (i * 8))
    }
    out.push(bits.reinterpret_as_double())
    at = at + 8
  }
  out
}

///|
/// `vector` in pgvector's text form, `[1,2,3]`.
fn vector_literal(vector : ArrayView[Double]) -> String {
  let parts : Array[String] = []
  for value in vector {
    parts.push(value.to_string())
  }
  "[" + parts.join(",") + "]"
}
