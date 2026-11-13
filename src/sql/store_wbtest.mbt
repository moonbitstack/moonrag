// The statements the SQL store writes, and the argument checks it makes before writing one. No
// database is open here: a statement is a string, and every case below is about its shape.

///|
/// A stand-in for a driver: only its shape is needed, since `new` checks the width and the table
/// before any statement runs, and never touches the connection.
struct DialectStub {}

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
test "a store refuses a bad width and a bad table name" {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let width = try {
    let _ = SqlVectorStore::new(DialectStub::{ }, embedder, dimension=0)
    "accepted"
  } catch {
    @moonrag.Empty(..) => "refused"
    _ => "other"
  }
  assert_eq(width, "refused")
  let table = try {
    let _ = SqlVectorStore::new(
      DialectStub::{ },
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
}

///|
test "MySQL is accepted, and stores vectors in a native VECTOR column" {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  let accepted = try {
    let _ = SqlVectorStore::new(DialectStub::{ }, embedder, dimension=8)
    true
  } catch {
    _ => false
  }
  assert_true(accepted)
  let sql = create_table_sql(@moondb.Dialect::Mysql, "docs", 256)
  assert_true(sql.contains("`embedding` VECTOR(256) NOT NULL"))
  assert_true(sql.contains("COLLATE utf8mb4_bin"))
  assert_false(sql.contains("BLOB NOT NULL"))
}

///|
test "the MySQL upsert writes the vector through STRING_TO_VECTOR" {
  let mysql = upsert_sql(@moondb.Dialect::Mysql, "docs", 8)
  assert_true(mysql.contains("VALUES (?, ?, ?, STRING_TO_VECTOR(?))"))
  assert_true(mysql.contains("ON DUPLICATE KEY UPDATE"))
}

///|
test "the MySQL search reads the vector back to score it here" {
  let sql = mysql_search_sql("`docs`", "")
  assert_true(sql.contains("VECTOR_TO_STRING(`embedding`) AS `embedding`"))
  assert_true(sql.contains("FROM `docs`"))
}

///|
/// A row as a driver hands one back: `id`, `text`, `meta`, in projection order.
fn row_of(id : String, text : String, meta : String) -> @moondb.Row {
  {
    columns: ["id", "text", "meta"],
    values: [
      @moondb.Value::Text(id),
      @moondb.Value::Text(text),
      @moondb.Value::Text(meta),
    ],
  }
}

///|
test "a row becomes a document, its metadata read out of the text column" {
  let document = document_of_row(
    row_of(
      "harbour", "the harbour at dawn", "{\"topic\":\"sea\",\"year\":2024}",
    ),
  )
  assert_eq(document.id, Some("harbour"))
  assert_eq(document.text, "the harbour at dawn")
  assert_eq(document.str_meta("topic"), Some("sea"))
  assert_eq(document.meta_of("year"), Some(@json.Json::number(2024.0)))
}

///|
test "metadata stored as jsonb is read the same way as metadata stored as text" {
  let row : @moondb.Row = {
    columns: ["id", "text", "meta"],
    values: [
      @moondb.Value::Text("ridge"),
      @moondb.Value::Text("a mountain path in autumn"),
      @moondb.Value::Json("{\"topic\":\"land\"}"),
    ],
  }
  let document = document_of_row(row)
  assert_eq(document.str_meta("topic"), Some("land"))
}

///|
test "metadata that is not JSON names the column it came from" {
  let refused = try {
    let _ = document_of_row(row_of("bad", "text", "{not json"))
    "accepted"
  } catch {
    @moonrag.Malformed(at~, ..) => "at " + at.to_string()
    _ => "other"
  }
  assert_eq(refused, "at 2")
}

///|
test "metadata that is JSON but not an object is refused" {
  let refused = try {
    let _ = document_of_row(row_of("bad", "text", "[1, 2]"))
    "accepted"
  } catch {
    @moonrag.Malformed(at=0, ..) => "not an object"
    _ => "other"
  }
  assert_eq(refused, "not an object")
}

///|
test "the metadata a document is stored as is the same text the reader reads back" {
  let document = @moonrag.Document::new(
    "text",
    meta=Map([
      ("topic", @json.Json::string("sea")),
      ("note", @json.Json::string("浪")),
    ]),
  )
  let round_trip = document_of_row(
    row_of("id", document.text, meta_json(document)),
  )
  assert_eq(round_trip.meta_of("topic"), document.meta_of("topic"))
  assert_eq(round_trip.str_meta("note"), Some("浪"))
}

///|
test "MySQL's text form of a vector is read back into the numbers it holds" {
  let vector = decode_vector_string("[1.00000e+00, 2.50000e+00, -3.00000e+00]")
  assert_eq(vector.length(), 3)
  assert_eq(vector[0], 1.0)
  assert_eq(vector[1], 2.5)
  assert_eq(vector[2], -3.0)
}

///|
test "a vector column that is not an array of numbers is refused" {
  let not_a_number = try {
    let _ = decode_vector_string("[1, \"two\"]")
    "accepted"
  } catch {
    @moonrag.Malformed(at=3, ..) => "not a number"
    _ => "other"
  }
  assert_eq(not_a_number, "not a number")
  let not_an_array = try {
    let _ = decode_vector_string("{\"x\":1}")
    "accepted"
  } catch {
    @moonrag.Malformed(at=3, ..) => "not an array"
    _ => "other"
  }
  assert_eq(not_an_array, "not an array")
}
