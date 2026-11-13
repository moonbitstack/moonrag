// A `VectorStore` held in a Chroma collection, over Chroma's v2 REST API.
//
// Chroma v2 addresses a collection by the UUID it hands back on create, so `create` stores that id and
// the other calls use it. Document ids are Chroma's strings, so no mapping is needed; the cosine is
// recomputed here from the embeddings the server returns.

///|
pub struct ChromaStore {
  base : String
  tenant : String
  database : String
  collection : String
  embedder : &@moonrag.Embedder
  dimension : Int32
  mut id : String
  mut counter : Int32
}

///|
/// A store over the Chroma server at `base` (for example `http://127.0.0.1:8000`), in the default
/// tenant and database unless named.
pub fn ChromaStore::new(
  base : String,
  embedder : &@moonrag.Embedder,
  dimension~ : Int32,
  collection~ : String = "moonrag_documents",
  tenant~ : String = "default_tenant",
  database~ : String = "default_database",
) -> ChromaStore raise {
  guard dimension > 0 else { raise @moonrag.Empty(what="dimension") }
  guard is_identifier(collection) else {
    raise @moonrag.Malformed(at=0, why="collection name")
  }
  {
    base,
    tenant,
    database,
    collection,
    embedder,
    dimension,
    id: "",
    counter: 0,
  }
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
/// The collections endpoint for this tenant and database.
fn ChromaStore::collections_url(self : ChromaStore) -> String {
  self.base +
  "/api/v2/tenants/" +
  self.tenant +
  "/databases/" +
  self.database +
  "/collections"
}

///|
/// A collection's URL (by the id `create` was given), with `suffix` appended.
fn ChromaStore::item_url(self : ChromaStore, suffix : String) -> String {
  self.collections_url() + "/" + self.id + suffix
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
fn ChromaStore::assign_id(
  self : ChromaStore,
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
fn strings_of(value : @json.Json?) -> Array[String] {
  let out : Array[String] = []
  match value {
    Some(@json.Json::Array(items)) =>
      for item in items {
        match item {
          @json.Json::String(s) => out.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
fn array_of(value : @json.Json?) -> Array[@json.Json] {
  match value {
    Some(@json.Json::Array(items)) => items
    _ => []
  }
}

///|
fn vector_of(value : @json.Json) -> Array[Double] {
  let out : Array[Double] = []
  match value {
    @json.Json::Array(items) =>
      for item in items {
        match item {
          @json.Json::Number(n, ..) => out.push(n)
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
/// Create the collection (or reuse one of the same name) and remember the id Chroma assigns it.
pub async fn ChromaStore::create(self : ChromaStore) -> Unit {
  let body = @json.Json::object(
      Map([
        ("name", @json.Json::string(self.collection)),
        (
          "metadata",
          @json.Json::object(
            Map([("hnsw:space", @json.Json::string("cosine"))]),
          ),
        ),
        ("get_or_create", @json.Json::boolean(true)),
      ]),
    )
    |> @moonjson.dumps
  let (code, text) = call(
    @http.RequestMethod::Post,
    self.collections_url(),
    body,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="chroma create: " + code.to_string())
  }
  let id = match @moonjson.loads(text[:], @moonjson.strict) {
    @json.Json::Object(fields) =>
      match fields.get("id") {
        Some(@json.Json::String(s)) => s
        _ => ""
      }
    _ => ""
  }
  guard id != "" else {
    raise @moonrag.Malformed(at=0, why="chroma create: no id")
  }
  self.id = id
}

///|
/// Remove every stored document, leaving the collection.
pub async fn ChromaStore::clear(self : ChromaStore) -> Unit {
  let ids = self.all_ids()
  if ids.length() > 0 {
    let array : Array[@json.Json] = []
    for id in ids {
      array.push(@json.Json::string(id))
    }
    let body = @json.Json::object(Map([("ids", @json.Json::array(array))]))
      |> @moonjson.dumps
    let _ = call(@http.RequestMethod::Post, self.item_url("/delete"), body)
  }
}

///|
async fn ChromaStore::all_ids(self : ChromaStore) -> Array[String] {
  let body = @json.Json::object(
      Map([
        ("include", @json.Json::array([])),
        ("limit", @json.Json::number(10000.0)),
      ]),
    )
    |> @moonjson.dumps
  let (code, text) = call(
    @http.RequestMethod::Post,
    self.item_url("/get"),
    body,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="chroma get: " + code.to_string())
  }
  match @moonjson.loads(text[:], @moonjson.strict) {
    @json.Json::Object(fields) => strings_of(fields.get("ids"))
    _ => []
  }
}

///|
/// The number of stored documents.
pub async fn ChromaStore::len(self : ChromaStore) -> Int64 {
  let (code, text) = call(@http.RequestMethod::Get, self.item_url("/count"), "")
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="chroma count: " + code.to_string())
  }
  match @moonjson.loads(text[:], @moonjson.strict) {
    @json.Json::Number(n, ..) => n.to_int64()
    _ => 0L
  }
}

///|
/// Embed `documents`, add them, and return the ids they are stored under.
pub impl @moonrag.VectorStore for ChromaStore with fn add(self, documents) {
  let vectors = self.embedder.embed(
    documents.map(fn(document) { document.text })[:],
  )
  guard vectors.length() == documents.length() else {
    raise @moonrag.Mismatch(got=vectors.length(), want=documents.length())
  }
  let ids : Array[@json.Json] = []
  let embeddings : Array[@json.Json] = []
  let texts : Array[@json.Json] = []
  let metadatas : Array[@json.Json] = []
  let returned : Array[String] = []
  for i, document in documents {
    guard vectors[i].length() == self.dimension else {
      raise @moonrag.Mismatch(got=vectors[i].length(), want=self.dimension)
    }
    let id = self.assign_id(document)
    returned.push(id)
    ids.push(@json.Json::string(id))
    let coordinates : Array[@json.Json] = []
    for x in vectors[i] {
      coordinates.push(@json.Json::number(x))
    }
    embeddings.push(@json.Json::array(coordinates))
    texts.push(@json.Json::string(document.text))
    metadatas.push(@json.Json::object(document.meta.copy()))
  }
  let body = @json.Json::object(
      Map([
        ("ids", @json.Json::array(ids)),
        ("embeddings", @json.Json::array(embeddings)),
        ("documents", @json.Json::array(texts)),
        ("metadatas", @json.Json::array(metadatas)),
      ]),
    )
    |> @moonjson.dumps
  let (code, _text) = call(
    @http.RequestMethod::Post,
    self.item_url("/upsert"),
    body,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="chroma upsert: " + code.to_string())
  }
  returned
}

///|
/// Delete the documents stored under `ids`. An id not present is not an error.
pub impl @moonrag.VectorStore for ChromaStore with fn delete(self, ids) {
  if ids.length() == 0 {
    return
  }
  let array : Array[@json.Json] = []
  for id in ids {
    array.push(@json.Json::string(id))
  }
  let body = @json.Json::object(Map([("ids", @json.Json::array(array))]))
    |> @moonjson.dumps
  let _ = call(@http.RequestMethod::Post, self.item_url("/delete"), body)
}

///|
/// The best `limit` documents for `vector`, best first. Every document is read back with its
/// embedding, then filtered, scored and ranked here.
pub impl @moonrag.VectorStore for ChromaStore with fn search(
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
  let body = @json.Json::object(
      Map([
        (
          "include",
          @json.Json::array([
            @json.Json::string("documents"),
            @json.Json::string("metadatas"),
            @json.Json::string("embeddings"),
          ]),
        ),
        ("limit", @json.Json::number(10000.0)),
      ]),
    )
    |> @moonjson.dumps
  let (code, text) = call(
    @http.RequestMethod::Post,
    self.item_url("/get"),
    body,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="chroma get: " + code.to_string())
  }
  let root = match @moonjson.loads(text[:], @moonjson.strict) {
    @json.Json::Object(fields) => fields
    _ => Map([])
  }
  let ids = strings_of(root.get("ids"))
  let texts = strings_of(root.get("documents"))
  let metadatas = array_of(root.get("metadatas"))
  let embeddings = array_of(root.get("embeddings"))
  let hits : Array[@moonrag.Scored] = []
  for i, id in ids {
    let document_text = if i < texts.length() { texts[i] } else { "" }
    let meta = if i < metadatas.length() {
      match metadatas[i] {
        @json.Json::Object(fields) => fields
        _ => Map([])
      }
    } else {
      Map([])
    }
    let stored = if i < embeddings.length() {
      vector_of(embeddings[i])
    } else {
      []
    }
    let document = @moonrag.Document::new(document_text, id~, meta~)
    if filter is Some(f) && !f.matches(document) {
      continue
    }
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
pub extend ChromaStore with @moonrag.VectorStore::{add, delete, search}
