// The recursive splitter's own behaviour: what a chunk carries, where it started, and what the
// constructor refuses. The chunk boundaries themselves are checked against the reference cases in
// src/conformance.

///|
test "chunks carry their number and a derived id" {
  let splitter = RecursiveSplitter::new(chunk_size=12, chunk_overlap=0)
  let document = @moonrag.Document::new(
    "aaa bbb ccc ddd",
    id="doc",
    meta=Map([("source", @json.Json::string("note.txt"))]),
  )
  let chunks = @moonrag.Splitter::split(splitter, document)
  assert_true(chunks.length() > 1)
  for i, chunk in chunks {
    assert_eq(chunk.id, Some("doc#\{i}"))
    assert_eq(
      chunk.meta_of("chunk"),
      Some(@json.Json::number(i.to_double(), repr=i.to_string())),
    )
    assert_eq(chunk.str_meta("source"), Some("note.txt"))
  }
}

///|
test "start offsets point at where the chunk actually begins" {
  let text = "alpha beta gamma delta epsilon zeta eta theta"
  let splitter = RecursiveSplitter::new(
    chunk_size=12,
    chunk_overlap=0,
    add_start_index=true,
  )
  let chunks = @moonrag.Splitter::split(splitter, @moonrag.Document::new(text))
  assert_true(chunks.length() > 1)
  for chunk in chunks {
    let start = match chunk.meta_of("start_index") {
      Some(@json.Json::Number(value, ..)) => value.to_int()
      _ => -1
    }
    assert_true(start >= 0)
    assert_eq(
      text.exact_view(start~, end=start + chunk.text.length()),
      chunk.text[:],
    )
  }
}

///|
test "an empty document splits into nothing" {
  let splitter = RecursiveSplitter::new()
  assert_eq(splitter.split_text(""), [])
  assert_eq(@moonrag.Splitter::split(splitter, @moonrag.Document::new("")), [])
}

///|
test "a custom measure changes what chunk_size counts" {
  // Two chunks of at most three words each, whatever their length in characters.
  let words = fn(text : StringView) {
    let mut count = 0
    for piece in text.to_owned().split(" ") {
      if piece.length() > 0 {
        count = count + 1
      }
    }
    count
  }

  let splitter = RecursiveSplitter::new(
    chunk_size=3,
    chunk_overlap=0,
    measure=words,
  )
  let chunks = splitter.split_text("one two three four five six seven")
  assert_true(chunks.length() >= 3)
  for chunk in chunks {
    assert_true(words(chunk[:]) <= 3)
  }
}

///|
test "the separator can be kept at the end instead of the start" {
  let text = "aaa bbb ccc ddd eee fff"
  let at_end = RecursiveSplitter::new(
    chunk_size=7,
    chunk_overlap=0,
    keep_separator=End,
    strip_whitespace=false,
  )
  let chunks = at_end.split_text(text)
  assert_true(chunks[0].has_suffix(" "))
  // Nothing is lost: the chunks still add up to the source text.
  assert_eq(chunks.join(""), text)
  let at_start = RecursiveSplitter::new(
    chunk_size=7,
    chunk_overlap=0,
    keep_separator=Start,
    strip_whitespace=false,
  )
  assert_true(at_start.split_text(text)[1].has_prefix(" "))
}

///|
test "the constructor refuses sizes that cannot work" {
  let zero = try {
    let _ = RecursiveSplitter::new(chunk_size=0)
    false
  } catch {
    @moonrag.Refused::Empty(what~) => what == "chunk_size"
    _ => false
  }
  assert_true(zero)
  let overlapping = try {
    let _ = RecursiveSplitter::new(chunk_size=10, chunk_overlap=11)
    false
  } catch {
    @moonrag.Refused::Exceeded(limit~, got~) => limit == 10 && got == 11
    _ => false
  }
  assert_true(overlapping)
  let negative = try {
    let _ = RecursiveSplitter::new(chunk_size=10, chunk_overlap=-1)
    false
  } catch {
    @moonrag.Refused::Exceeded(limit~, ..) => limit == 10
    _ => false
  }
  assert_true(negative)
  let no_separators = try {
    let _ = RecursiveSplitter::new(separators=[])
    false
  } catch {
    @moonrag.Refused::Empty(what~) => what == "separators"
    _ => false
  }
  assert_true(no_separators)
}

///|
test "a text with no separator at all is cut by characters" {
  let splitter = RecursiveSplitter::new(chunk_size=4, chunk_overlap=0)
  let chunks = splitter.split_text("abcdefgh")
  assert_eq(chunks, ["abcd", "efgh"])
}
