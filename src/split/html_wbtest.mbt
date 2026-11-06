// The HTML splitter: headings open sections, metadata remembers the path, and nothing from a script
// tag reaches a chunk.

///|
/// The `h1`…`h6` keys of a chunk, in order.
fn headers_of(document : @moonrag.Document) -> Array[String] {
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
test "sections follow the heading structure" {
  let html = "<html><body><h1>Guide</h1><p>Opening words.</p><h2>Install</h2><p>moon add.</p><h2>Use</h2><p>Then call it.</p></body></html>"
  let splitter = HtmlSplitter::new(chunk_size=1000)
  let chunks = @moonrag.Splitter::split(splitter, @moonrag.Document::new(html))
  assert_eq(chunks.length(), 3)
  assert_eq(headers_of(chunks[0]), ["Guide"])
  assert_true(chunks[0].text.contains("Opening words."))
  assert_eq(headers_of(chunks[1]), ["Guide", "Install"])
  assert_true(chunks[1].text.contains("moon add."))
  assert_true(chunks[1].text.has_prefix("Install"))
  assert_eq(headers_of(chunks[2]), ["Guide", "Use"])
}

///|
test "a deeper heading is forgotten when a shallower one opens" {
  let html = "<h1>A</h1><h2>B</h2><h3>C</h3><p>deep</p><h2>D</h2><p>up again</p>"
  let splitter = HtmlSplitter::new()
  let chunks = splitter.split_html(html)
  assert_eq(headers_of(chunks[0]), ["A", "B", "C"])
  assert_eq(headers_of(chunks[1]), ["A", "D"])
}

///|
test "scripts, styles and titles never reach the text" {
  let html = "<html><head><title>t</title><style>p { color: red }</style></head><body><script>alert(1)</script><p>Real text</p></body></html>"
  let chunks = HtmlSplitter::new().split_html(html)
  assert_eq(chunks.length(), 1)
  assert_eq(chunks[0].text, "Real text")
}

///|
test "source newlines are normalised and blocks break lines" {
  let html = "<div><p>first\n   paragraph</p><p>second   paragraph</p></div>"
  let chunks = HtmlSplitter::new().split_html(html)
  assert_eq(chunks[0].text, "first paragraph\nsecond paragraph")
}

///|
test "a section longer than the budget is split further, keeping its headings" {
  let paragraph = "This sentence is here to take up room in the section body."
  let html = "<h1>Long</h1><p>\{paragraph}</p><p>\{paragraph}</p><p>\{paragraph}</p>"
  let splitter = HtmlSplitter::new(chunk_size=60, chunk_overlap=0)
  let chunks = splitter.split_html(html)
  assert_true(chunks.length() > 1)
  for chunk in chunks {
    assert_true(chunk.text.length() <= 60)
    assert_eq(chunk.str_meta("h1"), Some("Long"))
  }
}

///|
test "document metadata survives and ids are derived" {
  let html = "<h1>One</h1><p>a</p><h2>Two</h2><p>b</p>"
  let splitter = HtmlSplitter::new()
  let document = @moonrag.Document::new(
    html,
    id="page",
    meta=Map([("source", @json.Json::string("page.html"))]),
  )
  let chunks = @moonrag.Splitter::split(splitter, document)
  assert_eq(chunks.length(), 2)
  assert_eq(chunks[0].id, Some("page#0"))
  assert_eq(chunks[1].id, Some("page#1"))
  assert_eq(chunks[0].str_meta("source"), Some("page.html"))
  assert_eq(chunks[0].str_meta("h1"), Some("One"))
}

///|
test "a page without headings is one chunk" {
  let chunks = HtmlSplitter::new().split_html("<p>only text</p>")
  assert_eq(chunks.length(), 1)
  assert_eq(chunks[0].text, "only text")
  assert_eq(headers_of(chunks[0]), [])
}
