// The five loaders over text held in memory: what each format turns into, and what it refuses.

///|
async test "a text loader yields one document tagged with its source" {
  let loader = TextLoader::new("notes.txt", "first line\nsecond line")
  let documents = @moonrag.Loader::load(loader)
  assert_eq(documents.length(), 1)
  assert_eq(documents[0].text, "first line\nsecond line")
  assert_eq(documents[0].str_meta("source"), Some("notes.txt"))
}

///|
async test "csv: header names the columns and each row becomes a document" {
  let csv = "name,city\nAda,London\nGrace,New York\n"
  let documents = @moonrag.Loader::load(CsvLoader::new("people.csv", csv))
  assert_eq(documents.length(), 2)
  assert_eq(documents[0].text, "name: Ada\ncity: London")
  assert_eq(documents[0].str_meta("city"), Some("London"))
  assert_eq(documents[1].text, "name: Grace\ncity: New York")
  assert_eq(
    documents[1].meta_of("row"),
    Some(@json.Json::number(2.0, repr="2")),
  )
}

///|
async test "csv: quoted fields keep delimiters, quotes and newlines" {
  let csv = "id,note\n1,\"a, b\"\n2,\"say \"\"hi\"\"\"\n3,\"first\nsecond\"\n"
  let documents = @moonrag.Loader::load(CsvLoader::new("notes.csv", csv))
  assert_eq(documents.length(), 3)
  assert_eq(documents[0].str_meta("note"), Some("a, b"))
  assert_eq(documents[1].str_meta("note"), Some("say \"hi\""))
  assert_eq(documents[2].str_meta("note"), Some("first\nsecond"))
}

///|
async test "csv: CRLF, no header, and a missing trailing newline" {
  let csv = "1;alpha\r\n2;beta"
  let documents = @moonrag.Loader::load(
    CsvLoader::new("data.csv", csv, has_header=false, delimiter=';'),
  )
  assert_eq(documents.length(), 2)
  assert_eq(documents[0].str_meta("column_1"), Some("alpha"))
  assert_eq(documents[1].str_meta("column_0"), Some("2"))
  assert_eq(documents[0].text, "column_0: 1\ncolumn_1: alpha")
}

///|
async test "csv: an unterminated quote is refused, not guessed" {
  let refused = try {
    let _ = @moonrag.Loader::load(CsvLoader::new("bad.csv", "a,\"unclosed\n"))
    false
  } catch {
    @moonrag.Refused::Malformed(at~, ..) => at > 0
    _ => false
  }
  assert_true(refused)
}

///|
async test "json: an array of objects yields one document per element" {
  let json = "[{\"title\":\"One\",\"body\":\"first\"},{\"title\":\"Two\",\"body\":\"second\"}]"
  let documents = @moonrag.Loader::load(
    JsonLoader::new("corpus.json", json, text_key="body"),
  )
  assert_eq(documents.length(), 2)
  assert_eq(documents[0].text, "first")
  assert_eq(documents[0].str_meta("title"), Some("One"))
  assert_eq(documents[0].meta_of("body"), None)
  assert_eq(documents[1].text, "second")
}

///|
async test "json: an object without a text key keeps its fields and its JSON" {
  let documents = @moonrag.Loader::load(
    JsonLoader::new("one.json", "{\"a\":1,\"b\":[2,3]}"),
  )
  assert_eq(documents.length(), 1)
  assert_true(documents[0].text.contains("\"a\":1"))
  assert_eq(documents[0].meta_of("a"), Some(@json.Json::number(1.0)))
}

///|
async test "json: a bare string, number or array of strings" {
  assert_eq(
    @moonrag.Loader::load(JsonLoader::new("s.json", "\"plain\""))[0].text,
    "plain",
  )
  assert_eq(
    @moonrag.Loader::load(JsonLoader::new("n.json", "42"))[0].text,
    "42",
  )
  let strings = @moonrag.Loader::load(
    JsonLoader::new("a.json", "[\"x\",\"y\"]"),
  )
  assert_eq(strings.map(fn(document) { document.text }), ["x", "y"])
}

///|
async test "json: a syntax error reports an offset" {
  let refused = try {
    let _ = @moonrag.Loader::load(JsonLoader::new("bad.json", "{\"a\": }"))
    None
  } catch {
    @moonrag.Refused::Malformed(at~, ..) => Some(at)
    _ => None
  }
  assert_true(refused.unwrap() > 0)
}

///|
async test "markdown: the first heading titles the document" {
  let markdown = "# Guide\n\nText.\n\n```sh\n# not a heading\n```\n"
  let documents = @moonrag.Loader::load(
    MarkdownLoader::new("guide.md", markdown),
  )
  assert_eq(documents.length(), 1)
  assert_eq(documents[0].str_meta("title"), Some("Guide"))
  assert_eq(documents[0].text, markdown)
}

///|
async test "markdown: a document without a heading has no title" {
  let documents = @moonrag.Loader::load(
    MarkdownLoader::new("plain.md", "just text\n"),
  )
  assert_eq(documents[0].meta_of("title"), None)
}

///|
async test "html: readable text and the page title" {
  let html = "<html><head><title>RAG notes</title></head><body><h1>Intro</h1><p>One &amp; two.</p><script>bad()</script></body></html>"
  let documents = @moonrag.Loader::load(HtmlLoader::new("page.html", html))
  assert_eq(documents.length(), 1)
  assert_eq(documents[0].str_meta("title"), Some("RAG notes"))
  assert_true(documents[0].text.contains("One & two."))
  assert_true(!documents[0].text.contains("bad()"))
}
