// The statements the SQL store writes, and the argument checks it makes before writing one. No
// database is open here: a statement is a string, and every case below is about its shape.

///|
/// A driver that reports `dialect` and refuses every statement — enough to exercise the store's own
/// argument checks, and nothing else.
struct DialectStub {
  dialect : @moondb.Dialect
}

///|
impl @moondb.AsyncDriver for DialectStub with fn dialect(self : DialectStub) -> @moondb.Dialect {
  self.dialect
}

///|
impl @moondb.AsyncDriver for DialectStub with fn execute(
  self : DialectStub,
  sql : String,
  params : Array[@moondb.Value],
) -> @moondb.ExecResult raise @moondb.DbError {
  let _ = (self, sql, params)
  raise @moondb.DbError::QueryError("no database")
}

///|
impl @moondb.AsyncDriver for DialectStub with fn query(
  self : DialectStub,
  sql : String,
  params : Array[@moondb.Value],
) -> Array[@moondb.Row] raise @moondb.DbError {
  let _ = (self, sql, params)
  raise @moondb.DbError::QueryError("no database")
}

///|
impl @moondb.AsyncDriver for DialectStub with fn begin(self : DialectStub) -> Unit raise @moondb.DbError {
  let _ = self
  raise @moondb.DbError::QueryError("no database")
}

///|
impl @moondb.AsyncDriver for DialectStub with fn commit(self : DialectStub) -> Unit raise @moondb.DbError {
  let _ = self
  raise @moondb.DbError::QueryError("no database")
}

///|
impl @moondb.AsyncDriver for DialectStub with fn rollback(self : DialectStub) -> Unit raise @moondb.DbError {
  let _ = self
  raise @moondb.DbError::QueryError("no database")
}

///|
impl @moondb.AsyncDriver for DialectStub with fn close(self : DialectStub) -> Unit {
  let _ = self
}

///|
test "the SQLite table keeps a vector as a blob and the metadata as text" {
  let sql = create_table_sql(@moondb.Dialect::Sqlite, "docs", 8)
  assert_true(sql.contains("\"vector\" BLOB NOT NULL"))
  assert_true(sql.contains("\"meta\" TEXT NOT NULL"))
  assert_false(sql.contains("VECTOR("))
}

///|
test "the PostgreSQL table declares a pgvector column of the right width" {
  let sql = create_table_sql(@moondb.Dialect::Postgres, "docs", 256)
  assert_true(sql.contains("\"embedding\" VECTOR(256) NOT NULL"))
  assert_true(sql.contains("\"meta\" JSONB NOT NULL"))
}

///|
test "each dialect spells its own upsert and its own placeholders" {
  let sqlite = upsert_sql(@moondb.Dialect::Sqlite, "docs", 8)
  assert_true(sqlite.contains("VALUES (?, ?, ?, ?)"))
  assert_true(sqlite.contains("ON CONFLICT (\"id\") DO UPDATE SET"))
  let postgres = upsert_sql(@moondb.Dialect::Postgres, "docs", 8)
  assert_true(postgres.contains("VALUES ($1, $2, $3::jsonb, $4::vector)"))
}

///|
test "a filter becomes SQL and binds its values in order" {
  let binder = Binder::new(@moondb.Dialect::Postgres)
  let sql = filter_sql(
    @moonrag.Filter::Equal("topic", @json.Json::string("sea")),
    binder,
  )
  assert_eq(sql, "(\"meta\" -> $1) = $2::jsonb")
  assert_eq(binder.values, [
    @moondb.Value::Text("topic"),
    @moondb.Value::Json("\"sea\""),
  ])
}

///|
test "a comparison only matches numbers" {
  let binder = Binder::new(@moondb.Dialect::Postgres)
  let sql = filter_sql(
    @moonrag.Filter::Compare("year", @moonrag.Order::AtLeast, 2025.0),
    binder,
  )
  assert_eq(
    sql, "(jsonb_typeof(\"meta\" -> $1) = 'number' AND (\"meta\" ->> $1)::numeric >= $2)",
  )
  assert_eq(binder.values, [
    @moondb.Value::Text("year"),
    @moondb.Value::Double(2025.0),
  ])
}

///|
test "the combinators nest, and the empty ones mean what they mean in memory" {
  let binder = Binder::new(@moondb.Dialect::Postgres)
  let sql = filter_sql(
    @moonrag.Filter::All([
      @moonrag.Filter::Exists("topic"),
      @moonrag.Filter::Not(
        @moonrag.Filter::OneOf("tag", [@json.Json::string("draft")]),
      ),
    ]),
    binder,
  )
  assert_eq(
    sql, "(jsonb_exists(\"meta\", $1) AND (NOT (\"meta\" -> $2) IN ($3::jsonb)))",
  )
  assert_eq(binder.values.length(), 3)
  assert_eq(filter_sql(@moonrag.Filter::All([]), binder), "TRUE")
  assert_eq(filter_sql(@moonrag.Filter::Any([]), binder), "FALSE")
}

///|
test "an identifier is a letter or underscore and then word characters" {
  assert_true(is_identifier("docs"))
  assert_true(is_identifier("_docs2"))
  assert_false(is_identifier(""))
  assert_false(is_identifier("documents;"))
  assert_false(is_identifier("2docs"))
  assert_false(is_identifier("my table"))
}

///|
test "a store refuses a bad width, a bad table name, and MySQL" {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let width = try {
    let _ = SqlVectorStore::new(
      DialectStub::{ dialect: @moondb.Dialect::Sqlite, },
      embedder,
      dimension=0,
    )
    "accepted"
  } catch {
    @moonrag.Empty(..) => "refused"
    _ => "other"
  }
  assert_eq(width, "refused")
  let table = try {
    let _ = SqlVectorStore::new(
      DialectStub::{ dialect: @moondb.Dialect::Sqlite, },
      embedder,
      dimension=8,
      table="docs; DROP TABLE users",
    )
    "accepted"
  } catch {
    @moonrag.Malformed(..) => "refused"
    _ => "other"
  }
  assert_eq(table, "refused")
  let mysql = try {
    let _ = SqlVectorStore::new(
      DialectStub::{ dialect: @moondb.Dialect::Mysql, },
      embedder,
      dimension=8,
    )
    "accepted"
  } catch {
    @moonrag.Unsupported(..) => "refused"
    _ => "other"
  }
  assert_eq(mysql, "refused")
}
