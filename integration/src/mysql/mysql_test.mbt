// MySQL 9, over a server the tests do not start: `MOONRAG_LIVE` says one is there.
//
// Unset, every test here prints why it did nothing and returns — a developer without a database is
// not running a broken build. Set, a server has to answer: a connection that fails takes the test
// down, because a live suite that passes when the server is missing is a suite that proves nothing.
//
// MySQL 9 keeps the vectors in its native `VECTOR` column via `STRING_TO_VECTOR`. Its Community
// build ships no `DISTANCE`, so the cosine score is computed here from the column, the same
// arithmetic the in-memory store uses — the ranking agrees with the other backends.

///|
/// Whether a live server is expected. Set by CI, and by anyone who wants the MySQL cases run.
fn live() -> Bool {
  @env.get_env_var("MOONRAG_LIVE") is Some(_)
}

///|
/// An environment variable, or `fallback` when it is unset.
fn setting(name : String, fallback : String) -> String {
  @env.get_env_var(name).unwrap_or(fallback)
}

///|
/// The table the MySQL cases use. Named once, so a stale one from a previous run is reused and
/// cleared rather than piling up.
let table : String = "moonrag_standard"

///|
/// The port to knock on: a container's own 3306.
fn port() -> Int32 {
  match @env.get_env_var("MOONRAG_MYSQL_PORT") {
    Some(text) => parse_port(text)
    None => 3306
  }
}

///|
/// A decimal port, or 3306 for anything that is not one.
fn parse_port(text : String) -> Int32 {
  if text == "" {
    return 3306
  }
  let mut value = 0
  for char in text {
    if !char.is_ascii_digit() {
      return 3306
    }
    value = value * 10 + (char.to_int() - '0'.to_int())
  }
  value
}

///|
/// A connection to the server named by the environment, with the defaults a local container has.
async fn connect() -> @client.MysqlConn raise {
  @client.MysqlConn::connect(
    setting("MOONRAG_MYSQL_HOST", "127.0.0.1"),
    port(),
    setting("MOONRAG_MYSQL_USER", "root"),
    setting("MOONRAG_MYSQL_PASSWORD", "ragpass"),
    setting("MOONRAG_MYSQL_DATABASE", "moonrag"),
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
/// The vector read back out of a `VECTOR_TO_STRING` result: a JSON array of floats, the same shape
/// the metadata travels as.
fn decode_vector_string(text : String) -> Array[Double] raise {
  match @json.parse(text) {
    @json.Json::Array(items) => {
      let out : Array[Double] = []
      for item in items {
        match item {
          @json.Json::Number(value, ..) => out.push(value)
          _ => raise @moonrag.Malformed(at=3, why="vector entry is not a number")
        }
      }
      out
    }
    _ => raise @moonrag.Malformed(at=3, why="embedding is not an array")
  }
}

///|
async test "the vector-store standard cases hold on MySQL 9" {
  if !live() {
    println("skipped: set MOONRAG_LIVE=1 and point MOONRAG_MYSQL_* at a MySQL 9 server")
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
async test "the vectors are really in a MySQL 9 VECTOR column" {
  if !live() {
    println("skipped: no live server")
    return
  }
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let _ = fresh_store(embedder)
  let database = setting("MOONRAG_MYSQL_DATABASE", "moonrag")
  let rows = (connect()).query(
    "SELECT COLUMN_TYPE FROM information_schema.columns" +
    " WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = 'embedding'",
    [@moondb.Value::Text(database), @moondb.Value::Text(table)],
  )
  assert_eq(rows.length(), 1)
  assert_true(rows[0].text(0).contains("vector(256)"))
}

///|
async test "the score is the one the stored vector yields" {
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
  // Read the vector straight out of the VECTOR column and score it the way the store does: the store
  // reports the cosine of the stored vector, not an approximation it computed elsewhere.
  let rows = (connect()).query(
    "SELECT VECTOR_TO_STRING(`embedding`) FROM `" + table + "` WHERE `id` = ?",
    [@moondb.Value::Text("a")],
  )
  assert_eq(rows.length(), 1)
  let decoded = decode_vector_string(rows[0].text(0))
  let from_column = @moonrag.cosine_similarity(query[:], decoded[:])
  let from_search = hits[0].score
  // The store reports the cosine of the stored vector, bit for bit: a score that only approximates it
  // means the ranking happened somewhere else, or the column did not round-trip.
  assert_eq(from_search, from_column)
}
