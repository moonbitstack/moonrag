// The in-memory store, over vectors fixed in a table rather than produced by a model: every expected
// score below is a number that can be checked by hand.

///|
/// An embedder that hands back a vector written down for each text, so a test states its vectors
/// instead of depending on a model.
pub struct TableEmbedder {
  table : Map[String, Array[Double]]
  fallback : Array[Double]
}

///|
pub fn TableEmbedder::new(
  entries : Array[(String, Array[Double])],
) -> TableEmbedder {
  let table : Map[String, Array[Double]] = Map([])
  for entry in entries {
    table[entry.0] = entry.1
  }
  { table, fallback: [0.0, 0.0], }
}

///|
pub impl @moonrag.Embedder for TableEmbedder with fn embed(self, texts) {
  let out : Array[Array[Double]] = []
  for text in texts {
    out.push(
      match self.table.get(text) {
        Some(vector) => vector.copy()
        None => self.fallback.copy()
      },
    )
  }
  out
}

///|
async test "add assigns sequential ids and keeps documents addressable" {
  let embedder : &@moonrag.Embedder = TableEmbedder::new([
    ("apple", [1.0, 0.0]),
    ("banana", [0.0, 1.0]),
  ])
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let ids = store.add([
    @moonrag.Document::new("apple"),
    @moonrag.Document::new("banana"),
  ])
  assert_eq(ids, ["doc-0", "doc-1"])
  assert_eq(store.len(), 2)
  assert_eq(store.ids(), ["doc-0", "doc-1"])
  assert_eq(store.get("doc-1").unwrap().text, "banana")
  assert_eq(store.get("doc-9"), None)
}

///|
async test "add honours an id the document already carries and replaces the old copy" {
  let embedder : &@moonrag.Embedder = TableEmbedder::new([
    ("first", [1.0, 0.0]),
    ("second", [0.0, 1.0]),
  ])
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = store.add([@moonrag.Document::new("first", id="a")])
  let _ = store.add([@moonrag.Document::new("second", id="a")])
  assert_eq(store.len(), 1)
  assert_eq(store.get("a").unwrap().text, "second")
  assert_eq(store.vector_of("a").unwrap(), [0.0, 1.0])
}

///|
async test "search ranks by cosine similarity, highest first" {
  let embedder : &@moonrag.Embedder = TableEmbedder::new([
    ("same", [1.0, 0.0]),
    ("near", [1.0, 1.0]),
    ("orthogonal", [0.0, 1.0]),
    ("opposite", [-1.0, 0.0]),
  ])
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = store.add([
    @moonrag.Document::new("opposite"),
    @moonrag.Document::new("orthogonal"),
    @moonrag.Document::new("near"),
    @moonrag.Document::new("same"),
  ])
  let hits = store.search([2.0, 0.0][:], limit=10)
  assert_eq(hits.map(fn(hit) { hit.document.text }), [
    "same", "near", "orthogonal", "opposite",
  ])
  assert_eq(hits[0].score, 1.0)
  assert_true((hits[1].score - (1.0 / 2.0).sqrt()).abs() < 1.0e-12)
  assert_eq(hits[3].score, -1.0)
}

///|
async test "search cuts to the limit and keeps arrival order on a tie" {
  let embedder : &@moonrag.Embedder = TableEmbedder::new([
    ("a", [1.0, 0.0]),
    ("b", [1.0, 0.0]),
    ("c", [1.0, 0.0]),
  ])
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = store.add([
    @moonrag.Document::new("a"),
    @moonrag.Document::new("b"),
    @moonrag.Document::new("c"),
  ])
  let top = store.search([1.0, 0.0][:], limit=2)
  assert_eq(top.map(fn(hit) { hit.document.text }), ["a", "b"])
  assert_eq(store.search([1.0, 0.0][:], limit=0), [])
  assert_eq(store.search([1.0, 0.0][:], limit=99).length(), 3)
}

///|
async test "search applies metadata filters before ranking" {
  let embedder : &@moonrag.Embedder = TableEmbedder::new([
    ("chapter one", [1.0, 0.0]),
    ("chapter two", [0.9, 0.1]),
    ("appendix", [0.8, 0.2]),
  ])
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = store.add([
    @moonrag.Document::new(
      "chapter one",
      meta=Map([
        ("part", @json.Json::string("body")),
        ("page", @json.Json::number(1.0)),
      ]),
    ),
    @moonrag.Document::new(
      "chapter two",
      meta=Map([
        ("part", @json.Json::string("body")),
        ("page", @json.Json::number(2.0)),
      ]),
    ),
    @moonrag.Document::new(
      "appendix",
      meta=Map([
        ("part", @json.Json::string("back")),
        ("page", @json.Json::number(9.0)),
      ]),
    ),
  ])
  let query = [1.0, 0.0][:]
  let body = store.search(
    query,
    limit=10,
    filter=@moonrag.Filter::Equal("part", @json.Json::string("body")),
  )
  assert_eq(body.map(fn(hit) { hit.document.text }), [
    "chapter one", "chapter two",
  ])
  let back = store.search(
    query,
    limit=10,
    filter=@moonrag.Filter::Equal("part", @json.Json::string("back")),
  )
  assert_eq(back.length(), 1)
  assert_eq(back[0].document.text, "appendix")
  let either = store.search(
    query,
    limit=10,
    filter=@moonrag.Filter::OneOf("part", [@json.Json::string("back")]),
  )
  assert_eq(either.length(), 1)
  let absent = store.search(
    query,
    limit=10,
    filter=@moonrag.Filter::Equal("part", @json.Json::string("missing")),
  )
  assert_eq(absent, [])
}

///|
async test "filters compose with All, Any, Not, Exists and Compare" {
  let embedder : &@moonrag.Embedder = TableEmbedder::new([
    ("one", [1.0, 0.0]),
    ("two", [1.0, 0.0]),
    ("three", [1.0, 0.0]),
  ])
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = store.add([
    @moonrag.Document::new(
      "one",
      meta=Map([
        ("year", @json.Json::number(2020.0)),
        ("lang", @json.Json::string("en")),
      ]),
    ),
    @moonrag.Document::new(
      "two",
      meta=Map([
        ("year", @json.Json::number(2024.0)),
        ("lang", @json.Json::string("zh")),
      ]),
    ),
    @moonrag.Document::new(
      "three",
      meta=Map([("year", @json.Json::number(2024.0))]),
    ),
  ])
  let query = [1.0, 0.0][:]
  let both = store.search(
    query,
    limit=10,
    filter=@moonrag.Filter::All([
      @moonrag.Filter::Compare("year", @moonrag.Order::AtLeast, 2024.0),
      @moonrag.Filter::Exists("lang"),
    ]),
  )
  assert_eq(both.map(fn(hit) { hit.document.text }), ["two"])
  let either = store.search(
    query,
    limit=10,
    filter=@moonrag.Filter::Any([
      @moonrag.Filter::Equal("lang", @json.Json::string("zh")),
      @moonrag.Filter::Compare("year", @moonrag.Order::Less, 2021.0),
    ]),
  )
  assert_eq(either.map(fn(hit) { hit.document.text }), ["one", "two"])
  let without_lang = store.search(
    query,
    limit=10,
    filter=@moonrag.Filter::Not(@moonrag.Filter::Exists("lang")),
  )
  assert_eq(without_lang.map(fn(hit) { hit.document.text }), ["three"])
  let after = store.search(
    query,
    limit=10,
    filter=@moonrag.Filter::Compare("year", @moonrag.Order::Greater, 2024.0),
  )
  assert_eq(after, [])
}

///|
async test "delete removes by id and ignores unknown ids" {
  let embedder : &@moonrag.Embedder = TableEmbedder::new([("a", [1.0, 0.0])])
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let ids = store.add([@moonrag.Document::new("a"), @moonrag.Document::new("a")])
  store.delete(ids[:])
  assert_eq(store.len(), 0)
  store.delete(["never-there"][:])
  assert_eq(store.len(), 0)
}

///|
async test "clear empties the store and restarts the counter" {
  let embedder : &@moonrag.Embedder = TableEmbedder::new([("a", [1.0, 0.0])])
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let _ = store.add([@moonrag.Document::new("a")])
  store.clear()
  assert_eq(store.len(), 0)
  assert_eq(store.add([@moonrag.Document::new("a")]), ["doc-0"])
}

///|
async test "add_vectors stores vectors the caller already has" {
  let embedder : &@moonrag.Embedder = TableEmbedder::new([])
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let ids = store.add_vectors([@moonrag.Document::new("precomputed")], [
    [0.0, 5.0],
  ])
  assert_eq(ids, ["doc-0"])
  let hits = store.search([0.0, 1.0][:], limit=1)
  assert_eq(hits[0].document.text, "precomputed")
  // The count and the lengths both have to line up.
  let short = try {
    store.add_vectors([], [[]]) |> ignore
    false
  } catch {
    @moonrag.Refused::Mismatch(_) => true
    _ => false
  }
  assert_true(short)
  let ragged = try {
    store.add_vectors(
      [@moonrag.Document::new("x"), @moonrag.Document::new("y")],
      [[1.0, 0.0], [1.0]],
    )
    |> ignore
    false
  } catch {
    @moonrag.Refused::Mismatch(_) => true
    _ => false
  }
  assert_true(ragged)
}

///|
async test "an empty id is refused" {
  let embedder : &@moonrag.Embedder = TableEmbedder::new([("a", [1.0, 0.0])])
  let store = @moonrag.InMemoryVectorStore::new(embedder)
  let raised = try {
    store.add([@moonrag.Document::new("a", id="")]) |> ignore
    false
  } catch {
    @moonrag.Refused::Empty(_) => true
    _ => false
  }
  assert_true(raised)
}
