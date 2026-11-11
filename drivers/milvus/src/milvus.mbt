// A `VectorStore` held in a Milvus collection, over Milvus's v2 REST API.
//
// `dimension` is the width of the vectors, fixed when the collection is created. Milvus is eventually
// consistent, so `add` and `delete` poll until the change is queryable and every query asks for
// `Strong`; the standard cases then behave as they do against the other backends.

///|
pub struct MilvusStore {
  base : String
  collection : String
  embedder : &@moonrag.Embedder
  dimension : Int32
  mut counter : Int32
}

///|
/// A store over the Milvus server at `base` (for example `http://127.0.0.1:19530`).
pub fn MilvusStore::new(
  base : String,
  embedder : &@moonrag.Embedder,
  dimension~ : Int32,
  collection~ : String = "moonrag_documents",
) -> MilvusStore raise {
  guard dimension > 0 else { raise @moonrag.Empty(what="dimension") }
  guard is_identifier(collection) else {
    raise @moonrag.Malformed(at=0, why="collection name")
  }
  { base, collection, embedder, dimension, counter: 0, }
}

///|
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
fn json_headers() -> Map[@http.CaseInsensitiveString, String] {
  Map([(@http.CaseInsensitiveString("Content-Type"), "application/json")])
}

///|
async fn call(
  verb : @http.RequestMethod,
  url : String,
  body : String,
) -> (Int32, String) {
  let headers = json_headers()
  let pair = @http.request(url, verb, headers, body)
  let response : @http.Response = pair.0
  let data : &@io.Data = pair.1
  (response.code, data.text())
}

///|
/// A Milvus join-list filter element: the id quoted for the filter language.
fn filter_quote(id : String) -> String {
  let mut escaped = ""
  for char in id {
    if char == '"' || char == '\\' {
      escaped = escaped + "\\"
    }
    escaped = escaped + char.to_string()
  }
  "\"" + escaped + "\""
}

///|
fn id_filter(ids : ArrayView[String]) -> String {
  let parts : Array[String] = []
  for id in ids {
    parts.push(filter_quote(id))
  }
  "id in [" + parts.join(", ") + "]"
}

///|
fn MilvusStore::assign_id(
  self : MilvusStore,
  document : @moonrag.Document,
) -> String raise {
  match document.id {
    Some(id) =>
      if id == "" {
        raise @moonrag.Empty(what="document id")
      } else {
        id
      }
    None => {
      let id = "doc-" + self.counter.to_string()
      self.counter = self.counter + 1
      id
    }
  }
}

///|
/// One row Milvus returns: its id, document text, metadata and vector.
priv struct MilvusRow {
  id : String
  text : String
  meta : Map[String, @json.Json]
  vector : Array[Double]
}

///|
/// The rows in `data` of a query response, decoded.
fn rows_of(body : String) -> Array[MilvusRow] raise {
  let out : Array[MilvusRow] = []
  let root = match @json.parse(body) {
    @json.Json::Object(fields) => fields
    _ => Map([])
  }
  let data = match root.get("data") {
    Some(@json.Json::Array(items)) => items
    _ => []
  }
  for item in data {
    let row = match item {
      @json.Json::Object(fields) => fields
      _ => Map([])
    }
    let id = match row.get("id") {
      Some(@json.Json::String(s)) => s
      _ => ""
    }
    let text = match row.get("text") {
      Some(@json.Json::String(s)) => s
      _ => ""
    }
    let meta = match row.get("meta") {
      Some(@json.Json::String(raw)) =>
        match @json.parse(raw) {
          @json.Json::Object(fields) => fields
          _ => Map([])
        }
      _ => Map([])
    }
    let vector : Array[Double] = []
    match row.get("vector") {
      Some(@json.Json::Array(items)) =>
        for v in items {
          match v {
            @json.Json::Number(n, ..) => vector.push(n)
            _ => ()
          }
        }
      _ => ()
    }
    if id != "" {
      out.push({ id, text, meta, vector, })
    }
  }
  out
}

///|
async fn MilvusStore::rows_with(
  self : MilvusStore,
  filter : String,
  fields : Array[@json.Json],
) -> Array[MilvusRow] {
  let body = @json.Json::object(
    Map([
      ("collectionName", @json.Json::string(self.collection)),
      ("filter", @json.Json::string(filter)),
      ("outputFields", @json.Json::array(fields)),
      ("limit", @json.Json::number(10000.0)),
      ("consistencyLevel", @json.Json::string("Strong")),
    ]),
  ).stringify()
  let (code, text) = call(
    @http.RequestMethod::Post,
    self.base + "/v2/vectordb/entities/query",
    body,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="milvus query: " + code.to_string())
  }
  rows_of(text)
}

///|
async fn MilvusStore::ids_where(
  self : MilvusStore,
  filter : String,
) -> Array[String] {
  let ids : Array[String] = []
  for row in self.rows_with(filter, [@json.Json::string("id")]) {
    ids.push(row.id)
  }
  ids
}

///|
/// Create the collection (tolerating one that already exists) and load it for querying.
pub async fn MilvusStore::create(self : MilvusStore) -> Unit {
  let body = @json.Json::object(
    Map([
      ("collectionName", @json.Json::string(self.collection)),
      (
        "schema",
        @json.Json::object(
          Map([
            ("autoId", @json.Json::boolean(false)),
            (
              "fields",
              @json.Json::array([
                @json.Json::object(
                  Map([
                    ("fieldName", @json.Json::string("id")),
                    ("dataType", @json.Json::string("VarChar")),
                    ("isPrimary", @json.Json::boolean(true)),
                    (
                      "elementTypeParams",
                      @json.Json::object(
                        Map([("max_length", @json.Json::number(65535.0))]),
                      ),
                    ),
                  ]),
                ),
                @json.Json::object(
                  Map([
                    ("fieldName", @json.Json::string("vector")),
                    ("dataType", @json.Json::string("FloatVector")),
                    (
                      "elementTypeParams",
                      @json.Json::object(
                        Map([
                          (
                            "dim",
                            @json.Json::number(self.dimension.to_double()),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                ),
                @json.Json::object(
                  Map([
                    ("fieldName", @json.Json::string("text")),
                    ("dataType", @json.Json::string("VarChar")),
                    (
                      "elementTypeParams",
                      @json.Json::object(
                        Map([("max_length", @json.Json::number(65535.0))]),
                      ),
                    ),
                  ]),
                ),
                @json.Json::object(
                  Map([
                    ("fieldName", @json.Json::string("meta")),
                    ("dataType", @json.Json::string("VarChar")),
                    (
                      "elementTypeParams",
                      @json.Json::object(
                        Map([("max_length", @json.Json::number(65535.0))]),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
      (
        "indexParams",
        @json.Json::array([
          @json.Json::object(
            Map([
              ("metricType", @json.Json::string("COSINE")),
              ("fieldName", @json.Json::string("vector")),
              ("indexName", @json.Json::string("vector")),
              (
                "params",
                @json.Json::object(
                  Map([("index_type", @json.Json::string("AUTOINDEX"))]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ]),
  ).stringify()
  // A collection that already exists answers with an error, which is fine here.
  let _ = call(
    @http.RequestMethod::Post,
    self.base + "/v2/vectordb/collections/create",
    body,
  )
  let load = @json.Json::object(
    Map([("collectionName", @json.Json::string(self.collection))]),
  ).stringify()
  let (code, text) = call(
    @http.RequestMethod::Post,
    self.base + "/v2/vectordb/collections/load",
    load,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(
      at=0,
      why="milvus load: " + code.to_string() + " " + text,
    )
  }
}

///|
/// Remove every stored row, leaving the collection.
pub async fn MilvusStore::clear(self : MilvusStore) -> Unit {
  let ids = self.ids_where("")
  if ids.length() > 0 {
    self.delete_rows(ids)
  }
}

///|
/// The rows in the collection, with their vectors.
async fn MilvusStore::all_rows(self : MilvusStore) -> Array[MilvusRow] {
  let body = @json.Json::object(
    Map([
      ("collectionName", @json.Json::string(self.collection)),
      ("filter", @json.Json::string("")),
      (
        "outputFields",
        @json.Json::array([
          @json.Json::string("id"),
          @json.Json::string("text"),
          @json.Json::string("meta"),
          @json.Json::string("vector"),
        ]),
      ),
      ("limit", @json.Json::number(10000.0)),
      ("consistencyLevel", @json.Json::string("Strong")),
    ]),
  ).stringify()
  let (code, text) = call(
    @http.RequestMethod::Post,
    self.base + "/v2/vectordb/entities/query",
    body,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="milvus query: " + code.to_string())
  }
  rows_of(text)
}

///|
/// The number of stored rows.
pub async fn MilvusStore::len(self : MilvusStore) -> Int64 {
  let body = @json.Json::object(
    Map([
      ("collectionName", @json.Json::string(self.collection)),
      ("filter", @json.Json::string("")),
      ("outputFields", @json.Json::array([@json.Json::string("count(*)")])),
      ("consistencyLevel", @json.Json::string("Strong")),
    ]),
  ).stringify()
  let (code, text) = call(
    @http.RequestMethod::Post,
    self.base + "/v2/vectordb/entities/query",
    body,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="milvus count: " + code.to_string())
  }
  match @json.parse(text) {
    @json.Json::Object(fields) =>
      match fields.get("data") {
        Some(@json.Json::Array(items)) =>
          match items.get(0) {
            Some(@json.Json::Object(row)) =>
              match row.get("count(*)") {
                Some(@json.Json::Number(n, ..)) => n.to_int64()
                _ => 0L
              }
            _ => 0L
          }
        _ => 0L
      }
    _ => 0L
  }
}

///|
/// Delete rows by id and wait until they are gone.
async fn MilvusStore::delete_rows(
  self : MilvusStore,
  ids : Array[String],
) -> Unit {
  if ids.length() == 0 {
    return
  }
  let body = @json.Json::object(
    Map([
      ("collectionName", @json.Json::string(self.collection)),
      ("filter", @json.Json::string(id_filter(ids[:]))),
    ]),
  ).stringify()
  let _ = call(
    @http.RequestMethod::Post,
    self.base + "/v2/vectordb/entities/delete",
    body,
  )
  for i = 0; i < 100; i = i + 1 {
    if self.ids_where(id_filter(ids[:])).length() == 0 {
      return
    }
    @async.sleep(50)
  }
}

///|
/// Wait until each id is queryable under its new text — an upsert is a delete then an insert, so the
/// old row can answer for a moment; this returns only once the new one does.
async fn MilvusStore::await_upserted(
  self : MilvusStore,
  ids : Array[String],
  texts : Array[String],
) -> Unit {
  for iter = 0; iter < 200; iter = iter + 1 {
    let rows = self.rows_with(id_filter(ids[:]), [
      @json.Json::string("id"),
      @json.Json::string("text"),
    ])
    if rows.length() == ids.length() {
      let mut ok = true
      for row in rows {
        let mut found = false
        for j, id in ids {
          if id == row.id {
            found = true
            if texts[j] != row.text {
              ok = false
            }
          }
        }
        if !found {
          ok = false
        }
      }
      if ok {
        return
      }
    }
    @async.sleep(50)
  }
}

///|
/// Embed `documents`, upsert them, and return the ids they are stored under.
pub impl @moonrag.VectorStore for MilvusStore with fn add(self, documents) {
  let vectors = self.embedder.embed(
    documents.map(fn(document) { document.text })[:],
  )
  guard vectors.length() == documents.length() else {
    raise @moonrag.Mismatch(got=vectors.length(), want=documents.length())
  }
  let data : Array[@json.Json] = []
  let returned : Array[String] = []
  let texts : Array[String] = []
  for i, document in documents {
    guard vectors[i].length() == self.dimension else {
      raise @moonrag.Mismatch(got=vectors[i].length(), want=self.dimension)
    }
    let id = self.assign_id(document)
    returned.push(id)
    texts.push(document.text)
    let coordinates : Array[@json.Json] = []
    for x in vectors[i] {
      coordinates.push(@json.Json::number(x))
    }
    data.push(
      @json.Json::object(
        Map([
          ("id", @json.Json::string(id)),
          ("vector", @json.Json::array(coordinates)),
          ("text", @json.Json::string(document.text)),
          (
            "meta",
            @json.Json::string(
              @json.Json::object(document.meta.copy()).stringify(),
            ),
          ),
        ]),
      ),
    )
  }
  let body = @json.Json::object(
    Map([
      ("collectionName", @json.Json::string(self.collection)),
      ("data", @json.Json::array(data)),
    ]),
  ).stringify()
  let (code, text) = call(
    @http.RequestMethod::Post,
    self.base + "/v2/vectordb/entities/upsert",
    body,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(
      at=0,
      why="milvus upsert: " + code.to_string() + " " + text,
    )
  }
  self.await_upserted(returned, texts)
  returned
}

///|
/// Delete the rows stored under `ids`. An id not present is not an error.
pub impl @moonrag.VectorStore for MilvusStore with fn delete(self, ids) {
  let owned : Array[String] = []
  for id in ids {
    owned.push(id)
  }
  self.delete_rows(owned)
}

///|
/// The best `limit` documents for `vector`, best first. Every row is read back with its vector, then
/// filtered, scored and ranked here.
pub impl @moonrag.VectorStore for MilvusStore with fn search(
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
  let hits : Array[@moonrag.Scored] = []
  for row in self.all_rows() {
    let document = @moonrag.Document::new(row.text, id=row.id, meta=row.meta)
    if filter is Some(f) && !f.matches(document) {
      continue
    }
    guard row.vector.length() == vector.length() else {
      raise @moonrag.Mismatch(got=row.vector.length(), want=vector.length())
    }
    hits.push({
      document,
      score: @moonrag.cosine_similarity(vector, row.vector[:]),
    })
  }
  @moonrag.rank(hits, limit)
}

///|
pub extend MilvusStore with @moonrag.VectorStore::{add, delete, search}
