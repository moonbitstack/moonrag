// A vector store in SQL. One implementation speaks to any `moondb` driver; the plan it runs is
// chosen from the dialect the driver reports, so a caller names the database once — when it opens the
// connection — and this file never asks again.
//
// Where the backend can rank vectors itself (PostgreSQL with pgvector) the ordering, the scoring and
// the metadata filter all happen in the statement, so `LIMIT` cuts before the rows travel. Where it
// cannot (SQLite) the rows come back whole, the distance is computed here with the same arithmetic
// the in-memory store uses, and the same filter tree is applied by the same code — so the two
// backends agree on what a match is, having only one definition of it.

///|
/// A `VectorStore` held in a SQL table, over any driver implementing `moondb`'s `AsyncDriver`.
///
/// `dimension` is the width of the vectors this store holds, fixed when it is constructed because the
/// column has to be declared with it. `table` is the name to keep rows in; it must be a plain
/// identifier, since it is written into the statement rather than bound as a value.
///
/// Raises `Empty` when `dimension` is not positive, `Malformed` when `table` is not an identifier, and
/// `Unsupported` for MySQL, which no test here reaches.
pub struct SqlVectorStore[T] {
  driver : T
  embedder : &@moonrag.Embedder
  dimension : Int32
  table : String
  mut counter : Int32
}

///|
pub fn[T : @moondb.AsyncDriver] SqlVectorStore::new(
  driver : T,
  embedder : &@moonrag.Embedder,
  dimension~ : Int32,
  table~ : String = "moonrag_documents",
) -> SqlVectorStore[T] raise {
  guard dimension > 0 else { raise @moonrag.Empty(what="dimension") }
  guard is_identifier(table) else {
    raise @moonrag.Malformed(at=0, why="table name")
  }
  guard driver.dialect() != @moondb.Mysql else {
    raise @moonrag.Unsupported(what="mysql")
  }
  { driver, embedder, dimension, table, counter: 0, }
}

///|
/// Whether `name` is a plain SQL identifier: a letter or underscore, then letters, digits and
/// underscores. Anything else would have to be quoted, and quoting a caller's string into DDL is how
/// an injection starts.
fn is_identifier(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  for i, char in name {
    let ok = if i == 0 {
      char.is_ascii_alphabetic() || char == '_'
    } else {
      (char.is_ascii_alphabetic() || char.is_ascii_digit()) || char == '_'
    }
    if !ok {
      return false
    }
  }
  true
}

///|
/// The store's table, quoted so a name that happens to be a keyword still works.
fn[T] SqlVectorStore::table_sql(self : SqlVectorStore[T]) -> String {
  "\"" + self.table + "\""
}

///|
/// The `CREATE TABLE` this store needs, in `dialect`'s spelling.
fn create_table_sql(
  dialect : @moondb.Dialect,
  table : String,
  dimension : Int32,
) -> String {
  let name = "\"" + table + "\""
  match dialect {
    @moondb.Postgres =>
      "CREATE TABLE IF NOT EXISTS " +
      name +
      " (" +
      "\"id\" TEXT PRIMARY KEY, " +
      "\"text\" TEXT NOT NULL, " +
      "\"meta\" JSONB NOT NULL, " +
      "\"embedding\" VECTOR(" +
      dimension.to_string() +
      ") NOT NULL)"
    _ =>
      "CREATE TABLE IF NOT EXISTS " +
      name +
      " (" +
      "\"id\" TEXT PRIMARY KEY, " +
      "\"text\" TEXT NOT NULL, " +
      "\"meta\" TEXT NOT NULL, " +
      "\"vector\" BLOB NOT NULL)"
  }
}

///|
/// The approximate-nearest-neighbour index pgvector needs to answer a search without reading the
/// table. HNSW is the one pgvector recommends for cosine distance; above 2000 dimensions the type
/// cannot be indexed at all, so no index is written there.
fn create_index_sql(table : String) -> String {
  "CREATE INDEX IF NOT EXISTS \"" +
  table +
  "_embedding_idx\" ON \"" +
  table +
  "\" USING hnsw (\"embedding\" vector_cosine_ops)"
}

///|
/// The upsert: one statement per document, so a re-index replaces a row instead of duplicating it.
fn upsert_sql(
  dialect : @moondb.Dialect,
  table : String,
  dimension : Int32,
) -> String {
  let name = "\"" + table + "\""
  let _ = dimension
  match dialect {
    @moondb.Postgres =>
      "INSERT INTO " +
      name +
      " (\"id\", \"text\", \"meta\", \"embedding\") VALUES ($1, $2, $3::jsonb, $4::vector)" +
      " ON CONFLICT (\"id\") DO UPDATE SET \"text\" = EXCLUDED.\"text\"," +
      " \"meta\" = EXCLUDED.\"meta\", \"embedding\" = EXCLUDED.\"embedding\""
    _ =>
      "INSERT INTO " +
      name +
      " (\"id\", \"text\", \"meta\", \"vector\") VALUES (?, ?, ?, ?)" +
      " ON CONFLICT (\"id\") DO UPDATE SET \"text\" = excluded.\"text\"," +
      " \"meta\" = excluded.\"meta\", \"vector\" = excluded.\"vector\""
  }
}

///|
/// The JSON a document's metadata is stored as.
fn meta_json(document : @moonrag.Document) -> String {
  @json.Json::object(document.meta.copy()).stringify()
}

///|
/// A document read back out of a row: columns are `id`, `text`, `meta`, in that order.
fn document_of_row(row : @moondb.Row) -> @moonrag.Document raise {
  let id = row.text(0)
  let text = row.text(1)
  let meta = match row.get(2) {
    @moondb.Value::Text(text) | @moondb.Value::Json(text) =>
      match @json.parse(text) {
        @json.Json::Object(fields) => fields
        _ => raise @moonrag.Malformed(at=0, why="metadata is not an object")
      }
    other => raise @moonrag.Malformed(at=2, why="metadata is " + other.kind())
  }
  @moonrag.Document::new(text, id~, meta~)
}

///|
/// The id a document is stored under, generating one when it names none, the way the in-memory store
/// does — re-indexing keeps a document's identity, and two stores keyed the same way can be swapped.
async fn[T : @moondb.AsyncDriver] SqlVectorStore::assign_id(
  self : SqlVectorStore[T],
  document : @moonrag.Document,
) -> String {
  match document.id {
    Some(id) =>
      if id == "" {
        raise @moonrag.Empty(what="document id")
      } else {
        id
      }
    None => {
      let mut id = "doc-" + self.counter.to_string()
      self.counter = self.counter + 1
      while self.get(id) is Some(_) {
        id = "doc-" + self.counter.to_string()
        self.counter = self.counter + 1
      }
      id
    }
  }
}

///|
/// Create the table this store needs, and on PostgreSQL the extension and the index. Safe to call on
/// every start: every statement is `IF NOT EXISTS`.
pub async fn[T : @moondb.AsyncDriver] SqlVectorStore::create(
  self : SqlVectorStore[T],
) -> Unit {
  let dialect = self.driver.dialect()
  if dialect == @moondb.Postgres {
    let _ = self.driver.execute("CREATE EXTENSION IF NOT EXISTS vector", [])
  }
  let _ = self.driver.execute(
    create_table_sql(dialect, self.table, self.dimension),
    [],
  )
  if dialect == @moondb.Postgres && self.dimension <= 2000 {
    let _ = self.driver.execute(create_index_sql(self.table), [])
  }
}

///|
/// The number of stored documents.
pub async fn[T : @moondb.AsyncDriver] SqlVectorStore::len(
  self : SqlVectorStore[T],
) -> Int64 {
  let rows = self.driver.query("SELECT COUNT(*) FROM " + self.table_sql(), [])
  guard rows.length() == 1 else {
    raise @moonrag.Malformed(at=0, why="count returned no row")
  }
  rows[0].int64(0)
}

///|
/// Remove every stored document, keeping the table.
pub async fn[T : @moondb.AsyncDriver] SqlVectorStore::clear(
  self : SqlVectorStore[T],
) -> Unit {
  let _ = self.driver.execute("DELETE FROM " + self.table_sql(), [])
}

///|
/// The document stored under `id`, or `None`.
pub async fn[T : @moondb.AsyncDriver] SqlVectorStore::get(
  self : SqlVectorStore[T],
  id : String,
) -> @moonrag.Document? {
  let rows = self.driver.query(
    "SELECT \"id\", \"text\", \"meta\" FROM " +
    self.table_sql() +
    " WHERE \"id\" = " +
    self.driver.dialect().placeholder(1),
    [@moondb.Value::Text(id)],
  )
  if rows.length() == 0 {
    None
  } else {
    Some(document_of_row(rows[0]))
  }
}

///|
/// Embed `documents`, store them, and return the ids they are stored under.
pub impl[T : @moondb.AsyncDriver] @moonrag.VectorStore for SqlVectorStore[T] with fn add(
  self,
  documents,
) {
  let vectors = self.embedder.embed(
    documents.map(fn(document) { document.text })[:],
  )
  guard vectors.length() == documents.length() else {
    raise @moonrag.Mismatch(got=vectors.length(), want=documents.length())
  }
  for vector in vectors {
    guard vector.length() == self.dimension else {
      raise @moonrag.Mismatch(got=vector.length(), want=self.dimension)
    }
  }
  let dialect = self.driver.dialect()
  let sql = upsert_sql(dialect, self.table, self.dimension)
  // Ids are settled before the transaction opens: generating one reads the table and may refuse a
  // blank id, and an error that is not the driver's cannot travel out of a driver transaction.
  let ids : Array[String] = []
  let rows : Array[Array[@moondb.Value]] = []
  for i, document in documents {
    let id = self.assign_id(document)
    let vector = match dialect {
      @moondb.Postgres => @moondb.Value::Text(vector_literal(vectors[i][:]))
      _ => @moondb.Value::Blob(encode_vector(vectors[i][:]))
    }
    rows.push([
      @moondb.Value::Text(id),
      @moondb.Value::Text(document.text),
      @moondb.Value::Text(meta_json(document)),
      vector,
    ])
    ids.push(id)
  }
  let txn = @moondb.AsyncTxn::new(self.driver)
  txn.run(async fn(txn) -> Unit raise @moondb.DbError {
    for values in rows {
      let _ = txn.driver().execute(sql, values)
    }
  })
  ids
}

///|
/// Delete the documents stored under `ids`. An id not in the table is not an error: a caller
/// re-running a cleanup should not have to know what is already gone.
pub impl[T : @moondb.AsyncDriver] @moonrag.VectorStore for SqlVectorStore[T] with fn delete(
  self,
  ids,
) {
  if ids.length() == 0 {
    return
  }
  let dialect = self.driver.dialect()
  let placeholders : Array[String] = []
  let values : Array[@moondb.Value] = []
  for i, id in ids {
    let _ = i
    values.push(@moondb.Value::Text(id))
    placeholders.push(dialect.placeholder(values.length()))
  }
  let sql = "DELETE FROM " +
    self.table_sql() +
    " WHERE \"id\" IN (" +
    placeholders.join(", ") +
    ")"
  let _ = self.driver.execute(sql, values)
}

///|
/// The best `limit` documents for `vector`, best first.
///
/// PostgreSQL ranks in the statement, `LIMIT` included, with the filter applied there too. SQLite
/// ranks here, because a SQLite column has no distance operator: the rows come back, the filter tree
/// is read by the same `Filter::matches` every other store uses, and cosine similarity is computed by
/// the same function — the numbers agree with the in-memory store to the last bit.
pub impl[T : @moondb.AsyncDriver] @moonrag.VectorStore for SqlVectorStore[T] with fn search(
  self,
  vector,
  limit~,
  filter?,
) {
  guard vector.length() == self.dimension else {
    raise @moonrag.Mismatch(got=vector.length(), want=self.dimension)
  }
  if limit <= 0 {
    return []
  }
  match self.driver.dialect() {
    @moondb.Postgres => self.search_ranked(vector, limit~, filter?)
    _ => self.search_here(vector, limit~, filter?)
  }
}

///|
/// The statement pgvector can answer on its own: `1 - cosine distance` is the same cosine similarity
/// the rest of the library ranks by, so a hit means the same number whichever store produced it.
async fn[T : @moondb.AsyncDriver] SqlVectorStore::search_ranked(
  self : SqlVectorStore[T],
  vector : ArrayView[Double],
  limit~ : Int32,
  filter? : @moonrag.Filter,
) -> Array[@moonrag.Scored] {
  let binder = Binder::new(@moondb.Dialect::Postgres)
  let at = binder.bind(@moondb.Value::Text(vector_literal(vector)))
  let clause = match filter {
    Some(filter) => " WHERE " + filter_sql(filter, binder)
    None => ""
  }
  let limit_at = binder.bind(@moondb.Value::Int(limit))
  let sql = "SELECT \"id\", \"text\", \"meta\", 1 - (\"embedding\" <=> " +
    at +
    "::vector) AS \"score\"" +
    " FROM " +
    self.table_sql() +
    clause +
    " ORDER BY \"embedding\" <=> " +
    at +
    "::vector, \"id\" LIMIT " +
    limit_at
  let hits : Array[@moonrag.Scored] = []
  for row in self.driver.query(sql, binder.values) {
    hits.push({ document: document_of_row(row), score: row.double(3), })
  }
  hits
}

///|
/// The statement SQLite can answer: every row, filtered and scored here.
async fn[T : @moondb.AsyncDriver] SqlVectorStore::search_here(
  self : SqlVectorStore[T],
  vector : ArrayView[Double],
  limit~ : Int32,
  filter? : @moonrag.Filter,
) -> Array[@moonrag.Scored] {
  let sql = "SELECT \"id\", \"text\", \"meta\", \"vector\" FROM " +
    self.table_sql()
  let hits : Array[@moonrag.Scored] = []
  for row in self.driver.query(sql, []) {
    let document = document_of_row(row)
    if filter is Some(filter) && !filter.matches(document) {
      continue
    }
    let stored = decode_vector(row.blob(3)[:])
    guard stored.length() == vector.length() else {
      raise @moonrag.Mismatch(got=stored.length(), want=vector.length())
    }
    hits.push({
      document,
      score: @moonrag.cosine_similarity(vector, stored[:]),
    })
  }
  @moonrag.rank(hits, limit)
}

///|
pub extend SqlVectorStore with @moonrag.VectorStore::{add, delete, search}
