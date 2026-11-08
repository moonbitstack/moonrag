// The Markdown splitter: a section per heading, the path in the metadata, and two things it refuses
// to break — a code block, and the indentation inside it.

///|
/// The `h1`…`h6` keys of a chunk, in order.
fn heading_path(document : @moonrag.Document) -> Array[String] {
  let out : Array[String] = []
  for level in ["h1", "h2", "h3", "h4", "h5", "h6"] {
    match document.str_meta(level) {
      Some(value) => out.push(value)
      None => ()
    }
  }
  out
}

///|
test "a chunk per heading, with the path above it" {
  let markdown = "# Guide\n\nOpening words.\n\n## Install\n\nmoon add moonbitstack/moonrag.\n\n## Search\n\nBuild a store, then search.\n"
  let splitter = MarkdownSplitter::new()
  let chunks = splitter.split(@moonrag.Document::new(markdown))
  assert_eq(chunks.length(), 3)
  assert_eq(heading_path(chunks[0]), ["Guide"])
  assert_eq(chunks[0].text, "Opening words.")
  assert_eq(heading_path(chunks[1]), ["Guide", "Install"])
  assert_eq(chunks[1].text, "moon add moonbitstack/moonrag.")
  assert_eq(heading_path(chunks[2]), ["Guide", "Search"])
}

///|
test "text before the first heading is a chunk with no path" {
  let markdown = "A note to begin with.\n\n# Title\n\nBody.\n"
  let chunks = MarkdownSplitter::new().split(@moonrag.Document::new(markdown))
  assert_eq(chunks.length(), 2)
  assert_eq(heading_path(chunks[0]), [])
  assert_eq(chunks[0].text, "A note to begin with.")
  assert_eq(heading_path(chunks[1]), ["Title"])
}

///|
test "a level that does not split stays in the text of the section around it" {
  let markdown = "# Guide\n\n### Aside\n\nA detail.\n"
  let splitter = MarkdownSplitter::new(headings=[
    MarkdownHeading::new(1, "h1"),
    MarkdownHeading::new(2, "h2"),
  ])
  let chunks = splitter.split(@moonrag.Document::new(markdown))
  assert_eq(chunks.length(), 1)
  assert_eq(chunks[0].text, "### Aside\n\nA detail.")
}

///|
test "a hash inside a fenced code block is a comment, not a heading" {
  let markdown = "# Build\n\n```bash\n# install the tool\nmoon add moonbitstack/moonrag\n```\n\n## Run\n\nThen run it.\n"
  let chunks = MarkdownSplitter::new().split(@moonrag.Document::new(markdown))
  assert_eq(chunks.length(), 2)
  assert_eq(
    chunks[0].text,
    "```bash\n# install the tool\nmoon add moonbitstack/moonrag\n```",
  )
  assert_eq(heading_path(chunks[1]), ["Build", "Run"])
}

///|
test "code keeps its indentation through the split" {
  let markdown = "# Sample\n\n```moonbit\nfn main {\n  let values = [1, 2, 3]\n  println(values)\n}\n```\n"
  let chunks = MarkdownSplitter::new(chunk_size=10).split(
    @moonrag.Document::new(markdown),
  )
  assert_eq(chunks.length(), 1)
  assert_eq(
    chunks[0].text,
    "```moonbit\nfn main {\n  let values = [1, 2, 3]\n  println(values)\n}\n```",
  )
}

///|
test "a code block longer than the budget is kept whole" {
  let markdown = "# Sample\n\n```\nlet a = 1\nlet b = 2\nlet c = 3\nlet d = 4\n```\n"
  let chunks = MarkdownSplitter::new(chunk_size=20).split(
    @moonrag.Document::new(markdown),
  )
  assert_eq(chunks.length(), 1)
  assert_true(chunks[0].text.contains("let d = 4"))
}

///|
test "prose longer than the budget is cut, and no chunk outgrows it" {
  let sentence = "A retriever finds the passages that answer the question. "
  let markdown = "# Ranking\n\n" + sentence.repeat(6) + "\n"
  let chunks = MarkdownSplitter::new(chunk_size=80).split(
    @moonrag.Document::new(markdown),
  )
  assert_true(chunks.length() > 1)
  for chunk in chunks {
    assert_true(chunk.text.length() <= 80)
  }
}

///|
test "blocks are packed up to the budget and then split at a block boundary" {
  let markdown = "# Notes\n\nFirst paragraph.\n\n- one\n- two\n\nSecond paragraph.\n"
  let chunks = MarkdownSplitter::new(chunk_size=40).split(
    @moonrag.Document::new(markdown),
  )
  assert_eq(chunks.length(), 2)
  assert_eq(chunks[0].text, "First paragraph.\n\n- one\n- two")
  assert_eq(chunks[1].text, "Second paragraph.")
}

///|
test "stripping can be turned off, and then the heading line is the first line" {
  let markdown = "# Guide\n\nBody.\n"
  let chunks = MarkdownSplitter::new(strip_headers=false).split(
    @moonrag.Document::new(markdown),
  )
  assert_eq(chunks.length(), 1)
  assert_eq(chunks[0].text, "# Guide\n\nBody.")
}

///|
test "a document id carries down to its chunks" {
  let markdown = "# Guide\n\nOne.\n\n## Two\n\nTwo.\n"
  let chunks = MarkdownSplitter::new().split(
    @moonrag.Document::new(markdown, id="guide.md"),
  )
  assert_eq(chunks.map(fn(chunk) { chunk.id }), [
    Some("guide.md#0"),
    Some("guide.md#1"),
  ])
  assert_eq(chunks[1].meta_of("chunk"), Some(@json.Json::number(1.0, repr="1")))
}

///|
test "split_markdown files the chunks under the metadata it is given" {
  let chunks = MarkdownSplitter::new().split_markdown(
    "# Guide\n\nBody.\n",
    meta=Map([("source", @json.Json::string("guide.md"))]),
  )
  assert_eq(chunks.length(), 1)
  assert_eq(chunks[0].str_meta("source"), Some("guide.md"))
  assert_eq(chunks[0].str_meta("h1"), Some("Guide"))
}

///|
test "a heading with no body produces no chunk" {
  let markdown = "# Empty\n\n# Filled\n\nBody.\n"
  let chunks = MarkdownSplitter::new().split(@moonrag.Document::new(markdown))
  assert_eq(chunks.length(), 1)
  assert_eq(heading_path(chunks[0]), ["Filled"])
}

///|
test "levels are checked: range, uniqueness and a blank key" {
  let levels = try {
    let _ = MarkdownHeading::new(7, "h7")
    "accepted"
  } catch {
    @moonrag.Exceeded(..) => "refused"
    _ => "other"
  }
  assert_eq(levels, "refused")
  let blank = try {
    let _ = MarkdownHeading::new(1, "")
    "accepted"
  } catch {
    @moonrag.Empty(..) => "refused"
    _ => "other"
  }
  assert_eq(blank, "refused")
  let duplicate = try {
    let _ = MarkdownSplitter::new(headings=[
      MarkdownHeading::new(1, "a"),
      MarkdownHeading::new(1, "b"),
    ])
    "accepted"
  } catch {
    @moonrag.Exceeded(..) => "refused"
    _ => "other"
  }
  assert_eq(duplicate, "refused")
}

///|
test "the overlap carries the last whole block into the next chunk" {
  let markdown = "# Notes\n\nFirst paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n"
  let chunks = MarkdownSplitter::new(chunk_size=40, chunk_overlap=20).split(
    @moonrag.Document::new(markdown),
  )
  assert_eq(chunks.length(), 2)
  assert_eq(chunks[0].text, "First paragraph.\n\nSecond paragraph.")
  // "First paragraph." no longer fits the overlap together with the one after it, so only the last
  // block travels.
  assert_eq(chunks[1].text, "Second paragraph.\n\nThird paragraph.")
}

///|
test "an overlap of zero leaves the blocks where they are" {
  let markdown = "# Notes\n\nFirst paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n"
  let chunks = MarkdownSplitter::new(chunk_size=40).split(
    @moonrag.Document::new(markdown),
  )
  assert_eq(chunks.map(fn(chunk) { chunk.text }), [
    "First paragraph.\n\nSecond paragraph.", "Third paragraph.",
  ])
}

///|
test "a deeper heading is forgotten when a shallower one opens" {
  let markdown = "# A\n\ntop.\n\n## B\n\nmiddle.\n\n### C\n\ndeep.\n\n## D\n\nup again.\n"
  let chunks = MarkdownSplitter::new().split(@moonrag.Document::new(markdown))
  assert_eq(chunks.length(), 4)
  assert_eq(heading_path(chunks[2]), ["A", "B", "C"])
  // D is a sibling of B, so C must not still be in force when D opens.
  assert_eq(heading_path(chunks[3]), ["A", "D"])
}
