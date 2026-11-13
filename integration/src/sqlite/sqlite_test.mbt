// The vector-store standard cases on SQLite. The store keeps vectors as blobs, computes cosine
// similarity in this process and filters with the same tree every other store reads, so what is
// exercised here is the SQL round trip, not a second ranking policy.

///|
/// A store over a fresh in-memory database: each `:memory:` connection is its own database, so a case
/// never sees what the previous one wrote.
async fn fresh_store(
  embedder : &@moonrag.Embedder,
) -> &@moonrag.VectorStore raise {
  let driver = @moonsqlite.SqliteDriver::open(":memory:")
  let store = @sql.SqlVectorStore::new(
    @blocking.Blocking::new(driver),
    embedder,
    dimension=256,
    table="moonrag_standard",
  )
  store.create()
  store
}

///|
async test "the vector-store standard cases hold on SQLite" {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let failures = @standard.check(
    embedder,
    async fn() { fresh_store(embedder) },
  )
  if failures.length() > 0 {
    abort(failures.join("\n"))
  }
}

///|
async test "a document written once is read back with its text and metadata" {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = fresh_store(embedder)
  let _ = store.add([
    @moonrag.Document::new(
      "the harbour at dawn",
      id="harbour",
      meta=Map([
        ("topic", @json.Json::string("sea")),
        ("depth", @json.Json::number(12.5)),
      ]),
    ),
  ])
  let driver = @moonsqlite.SqliteDriver::open(":memory:")
  let _ = driver
  let query = embedder.embed(["the harbour at dawn"])[0]
  let hits = store.search(query[:], limit=1)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].document.id, Some("harbour"))
  assert_eq(hits[0].document.str_meta("topic"), Some("sea"))
  assert_eq(hits[0].document.meta_of("depth"), Some(@json.Json::number(12.5)))
  // The same text is the same vector, so the store's own copy scores a cosine of one, to within the
  // rounding of the norm.
  assert_true(hits[0].score > 0.999)
}

///|
async test "a re-index replaces a row instead of piling up beside it" {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = fresh_store(embedder)
  let first = store.add([@moonrag.Document::new("first", id="a")])
  let second = store.add([@moonrag.Document::new("second", id="a")])
  assert_eq(first, ["a"])
  assert_eq(second, ["a"])
  let query = embedder.embed(["second"])[0]
  let hits = store.search(query[:], limit=10)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].document.text, "second")
}

///|
async test "the store reports what it holds, and can be emptied" {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let driver = @moonsqlite.SqliteDriver::open(":memory:")
  let store = @sql.SqlVectorStore::new(
    @blocking.Blocking::new(driver),
    embedder,
    dimension=256,
    table="moonrag_counts",
  )
  store.create()
  assert_eq(store.len(), 0L)
  let _ = store.add([
    @moonrag.Document::new("the harbour at dawn", id="a"),
    @moonrag.Document::new("a mountain path in autumn", id="b"),
  ])
  assert_eq(store.len(), 2L)
  assert_eq(store.get("b").unwrap().text, "a mountain path in autumn")
  assert_eq(store.get("missing"), None)
  store.clear()
  assert_eq(store.len(), 0L)
}
