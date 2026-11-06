// The root types on their own: documents, their metadata, and their JSON form.

///|
test "a new document has no id and empty metadata" {
  let document = Document::new("hello")
  assert_eq(document.id, None)
  assert_eq(document.text, "hello")
  assert_eq(document.meta.length(), 0)
}

///|
test "metadata is set, replaced and read back" {
  let document = Document::new("hello")
    .set_meta("source", Json::string("a.txt"))
    .set_meta("page", Json::number(3.0))
    .set_meta("source", Json::string("b.txt"))
  assert_eq(document.meta.length(), 2)
  assert_eq(document.str_meta("source"), Some("b.txt"))
  assert_eq(document.str_meta("page"), None)
  assert_eq(document.meta_of("page"), Some(Json::number(3.0)))
  assert_eq(document.meta_of("absent"), None)
  // Setting metadata leaves the original alone.
  let base = Document::new("hello")
  let _ = base.set_meta("k", Json::string("v"))
  assert_eq(base.meta.length(), 0)
}

///|
test "a derived chunk carries the parent metadata and its own number" {
  let parent = Document::new(
    "a long text",
    id="s1",
    meta=Map([("source", Json::string("a.txt"))]),
  )
  let chunk = parent.derived(2, "long", start_index=17)
  assert_eq(chunk.text, "long")
  assert_eq(chunk.id, Some("s1#2"))
  assert_eq(chunk.str_meta("source"), Some("a.txt"))
  assert_eq(chunk.meta_of("chunk"), Some(Json::number(2.0, repr="2")))
  assert_eq(chunk.meta_of("start_index"), Some(Json::number(17.0, repr="17")))
  let anonymous = Document::new("x").derived(0, "x")
  assert_eq(anonymous.id, None)
  assert_eq(anonymous.meta_of("start_index"), None)
}

///|
test "document survives a JSON round trip" {
  let document = Document::new(
    "text",
    id="d1",
    meta=Map([("source", Json::string("a.txt")), ("page", Json::number(2.0))]),
  )
  let json = document.to_json()
  let back : Document = @json.from_json(json)
  assert_eq(back, document)
  let rendered = json.stringify()
  assert_true(rendered.contains("\"text\":\"text\""))
  assert_true(rendered.contains("\"id\":\"d1\""))
}

///|
test "a scored hit survives a JSON round trip" {
  let hit = { document: Document::new("text"), score: 0.5, }
  let back : Scored = @json.from_json(hit.to_json())
  assert_eq(back.document.text, "text")
  assert_eq(back.score, 0.5)
  assert_eq(Scored::documents([hit]), [Document::new("text")])
}

///|
test "malformed document JSON is refused with a path" {
  let path_of = fn(text : String) -> String? {
    try {
      let _ : Document = @json.from_json(@json.parse(text))
      None
    } catch {
      @json.JsonDecodeError((path, _)) => Some(path.to_string())
      _ => None
    }
  }

  assert_eq(path_of("{\"id\":\"a\"}").unwrap().contains("text"), true)
  assert_eq(path_of("{\"text\":3}").unwrap().contains("text"), true)
  assert_eq(path_of("[]"), Some(""))
}
