// PostgreSQL with pgvector, over a server the tests do not start: `MOONRAG_LIVE` says one is there.
//
// Unset, every test here prints why it did nothing and returns — a developer without a database is
// not running a broken build. Set, a server has to answer: a connection that fails takes the test
// down, because a live suite that passes when the server is missing is a suite that proves nothing.

///|
/// Whether a live server is expected. Set by CI, and by anyone who wants the pgvector cases run.
fn live() -> Bool {
  @env.get_env_var("MOONRAG_LIVE") is Some(_)
}

///|
/// An environment variable, or `fallback` when it is unset.
fn setting(name : String, fallback : String) -> String {
  @env.get_env_var(name).unwrap_or(fallback)
}

///|
/// The table the pgvector cases use. Named once, so a stale one from a previous run is reused and
/// cleared rather than piling up.
let table : String = "moonrag_standard"

///|
/// The port to knock on: the container's own 5432, published as 55433 on a developer's machine.
fn port() -> Int32 {
  match @env.get_env_var("MOONRAG_PG_PORT") {
    Some(text) => parse_port(text)
    None => 55433
  }
}

///|
/// A decimal port, or 55433 for anything that is not one.
fn parse_port(text : String) -> Int32 {
  if text == "" {
    return 55433
  }
  let mut value = 0
  for char in text {
    if !char.is_ascii_digit() {
      return 55433
    }
    value = value * 10 + (char.to_int() - '0'.to_int())
  }
  value
}

///|
/// A connection to the server named by the environment, with the defaults a local container has.
async fn connect() -> @moonpostgres.PgConn raise {
  @moonpostgres.PgConn::connect(
    setting("MOONRAG_PG_HOST", "127.0.0.1"),
    port(),
    setting("MOONRAG_PG_USER", "postgres"),
    setting("MOONRAG_PG_PASSWORD", "ragpass"),
    setting("MOONRAG_PG_DATABASE", "moonrag"),
  )
}

///|
/// A store over a cleared table, so a case never sees what the previous one wrote.
async fn fresh_store(
  embedder : &@moonrag.Embedder,
) -> &@moonrag.VectorStore raise {
  let store = @sql.SqlVectorStore::new(
    connect(),
    embedder,
    dimension=256,
    table~,
  )
  store.create()
  store.clear()
  store
}

///|
async test "the vector-store standard cases hold on pgvector" {
  if !live() {
    println("skipped: set MOONRAG_LIVE=1 and point MOONRAG_PG_* at a PostgreSQL with pgvector")
    return
  }
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
/// A vector in pgvector's text form, written here so the test compares the store's statement with a
/// statement of its own rather than with the store's own helper.
fn literal_of(vector : ArrayView[Double]) -> String {
  let parts : Array[String] = []
  for value in vector {
    parts.push(value.to_string())
  }
  "[" + parts.join(",") + "]"
}

///|
async test "the vectors are really in a pgvector column" {
  if !live() {
    println("skipped: no live server")
    return
  }
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = fresh_store(embedder)
  let _ = store.add([@moonrag.Document::new("the harbour at dawn", id="a")])
  let rows = (connect()).query(
    "SELECT format_type(a.atttypid, a.atttypmod) FROM pg_attribute a" +
    " WHERE a.attrelid = '" +
    table +
    "'::regclass AND a.attname = 'embedding'",
    [],
  )
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].text(0), "vector(256)")
}

///|
async test "the score is the one the database computed" {
  if !live() {
    println("skipped: no live server")
    return
  }
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let store = fresh_store(embedder)
  let _ = store.add([
    @moonrag.Document::new("the harbour at dawn, fishing boats leaving", id="a"),
    @moonrag.Document::new("a mountain path in autumn, cold and clear", id="b"),
  ])
  let query = embedder.embed(["fishing boats in the harbour"])[0]
  let hits = store.search(query[:], limit=2)
  let literal = literal_of(query[:])
  let rows = (connect()).query(
    "SELECT 1 - (\"embedding\" <=> $1::vector) FROM \"" +
    table +
    "\" WHERE \"id\" = $2",
    [@moondb.Value::Text(literal), @moondb.Value::Text("a")],
  )
  assert_eq(rows.length(), 1)
  let from_database = rows[0].double(0)
  let from_search = hits[0].score
  // The store reports what `<=>` computed, bit for bit: a score that only approximates the
  // distance means the ranking happened somewhere else.
  assert_eq(from_search, from_database)
}
