// The token splitter's own behaviour: the budget is measured, not assumed, and bad sizes are refused.

///|
/// The space-delimited words of `text`.
fn words_of(text : StringView) -> Array[String] {
  let out : Array[String] = []
  for piece in text.to_owned().split(" ") {
    if piece.length() > 0 {
      out.push(piece.to_owned())
    }
  }
  out
}

///|
fn word_count(text : StringView) -> Int32 {
  words_of(text).length()
}

///|
test "chunks respect the token budget and overlap by whole words" {
  let splitter = TokenSplitter::new(word_count, chunk_size=3, chunk_overlap=1)
  let chunks = splitter.split_text("one two three four five six seven")
  for chunk in chunks {
    assert_true(word_count(chunk[:]) <= 3)
  }
  // The last word of one chunk opens the next one.
  assert_true(chunks.length() > 1)
  let first = words_of(chunks[0][:])
  let carried = first[first.length() - 1]
  assert_true(chunks[1].has_prefix(carried))
}

///|
test "a chunk longer than the budget still comes out whole" {
  // A single word cannot be cut, so the splitter keeps it rather than dropping text.
  let splitter = TokenSplitter::new(word_count, chunk_size=1, chunk_overlap=0)
  let chunks = splitter.split_text("supercalifragilisticexpialidocious")
  assert_eq(chunks, ["supercalifragilisticexpialidocious"])
}

///|
test "the measure decides the cost, not the character count" {
  // Every word costs five, so a budget of ten fits exactly two words.
  let expensive = fn(text : StringView) { word_count(text) * 5 }
  let splitter = TokenSplitter::new(expensive, chunk_size=10, chunk_overlap=0)
  let chunks = splitter.split_text("aa bb cc dd ee")
  assert_eq(chunks, ["aa bb", "cc dd", "ee"])
}

///|
test "documents split into numbered chunks" {
  let splitter = TokenSplitter::new(word_count, chunk_size=2, chunk_overlap=0)
  let document = @moonrag.Document::new("aa bb cc", id="t")
  let chunks = @moonrag.Splitter::split(splitter, document)
  assert_eq(chunks.length(), 2)
  assert_eq(chunks[1].id, Some("t#1"))
  assert_eq(chunks[0].text, "aa bb")
}

///|
test "the constructor refuses sizes that cannot work" {
  let zero = try {
    let _ = TokenSplitter::new(word_count, chunk_size=0)
    false
  } catch {
    @moonrag.Refused::Empty(_) => true
    _ => false
  }
  assert_true(zero)
  let overlapping = try {
    let _ = TokenSplitter::new(word_count, chunk_size=4, chunk_overlap=5)
    false
  } catch {
    @moonrag.Refused::Exceeded(limit~, got~) => limit == 4 && got == 5
    _ => false
  }
  assert_true(overlapping)
}
