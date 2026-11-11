// A `VectorStore` held in a Weaviate class, over Weaviate's REST API.
//
// Weaviate needs object ids to be UUIDs, so `uuid_of` folds a document's string id into one
// deterministically and the original id rides back in the `docid` property.

///|
pub struct WeaviateStore {
  base : String
  class_name : String
  embedder : &@moonrag.Embedder
  dimension : Int32
  mut counter : Int32
}

///|
/// A store over the Weaviate server at `base` (for example `http://127.0.0.1:8080`), in class
/// `class_name`.
pub fn WeaviateStore::new(
  base : String,
  embedder : &@moonrag.Embedder,
  dimension~ : Int32,
  class_name~ : String = "MoonragDocument",
) -> WeaviateStore raise {
  guard dimension > 0 else { raise @moonrag.Empty(what="dimension") }
  guard is_identifier(class_name) else {
    raise @moonrag.Malformed(at=0, why="class name")
  }
  { base, class_name, embedder, dimension, counter: 0, }
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
/// Sixteen hex digits of a small non-negative value, left-padded with zeros.
fn hex16(value : Int64) -> String {
  let mut s = value.reinterpret_as_uint64().to_string(radix=16)
  while s.length() < 16 {
    s = "0" + s
  }
  s
}

///|
/// A UUID for a document's string id: two bounded hashes, formatted 8-4-4-4-12.
fn uuid_of(id : String) -> String {
  let mut a : Int64 = 0L
  let mut b : Int64 = 7L
  for char in id {
    let code = char.to_int().to_int64()
    a = (a * 131L + code) & 1099511627775L
    b = (b * 65599L + (code ^ 0x5AL)) & 1099511627775L
  }
  let hex = hex16(a) + hex16(b)
  let mut out = ""
  for i, char in hex {
    out = out + char.to_string()
    if i == 7 || i == 11 || i == 15 || i == 19 {
      out = out + "-"
    }
  }
  out
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
fn WeaviateStore::assign_id(
  self : WeaviateStore,
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
/// Create the class this store needs. Safe on every start: an existing class answers 422, which is
/// not an error here.
pub async fn WeaviateStore::create(self : WeaviateStore) -> Unit {
  let body = @json.Json::object(
    Map([
      ("class", @json.Json::string(self.class_name)),
      ("vectorizer", @json.Json::string("none")),
      (
        "properties",
        @json.Json::array([
          @json.Json::object(
            Map([
              ("name", @json.Json::string("docid")),
              ("dataType", @json.Json::array([@json.Json::string("text")])),
            ]),
          ),
          @json.Json::object(
            Map([
              ("name", @json.Json::string("body")),
              ("dataType", @json.Json::array([@json.Json::string("text")])),
            ]),
          ),
          @json.Json::object(
            Map([
              ("name", @json.Json::string("meta")),
              ("dataType", @json.Json::array([@json.Json::string("text")])),
            ]),
          ),
        ]),
      ),
    ]),
  ).stringify()
  let (code, _text) = call(
    @http.RequestMethod::Post,
    self.base + "/v1/schema",
    body,
  )
  guard (code >= 200 && code < 300) || code == 422 else {
    raise @moonrag.Malformed(at=0, why="weaviate schema: " + code.to_string())
  }
}

///|
/// Remove every stored object, leaving the class.
pub async fn WeaviateStore::clear(self : WeaviateStore) -> Unit {
  let objects = self.all_objects()
  for object in objects {
    let uuid = match object.id {
      Some(id) => id
      None => continue
    }
    let _ = call(
      @http.RequestMethod::Delete,
      self.base + "/v1/objects/" + self.class_name + "/" + uuid,
      "",
    )
  }
}

///|
/// One object as Weaviate returns it: its UUID, its document, and its vector.
priv struct WeaviateObject {
  id : String?
  document : @moonrag.Document
  vector : Array[Double]
}

///|
/// Every object in the class, with its vector.
async fn WeaviateStore::all_objects(
  self : WeaviateStore,
) -> Array[WeaviateObject] {
  let url = self.base +
    "/v1/objects?class=" +
    self.class_name +
    "&include=vector&limit=10000"
  let (code, text) = call(@http.RequestMethod::Get, url, "")
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="weaviate objects: " + code.to_string())
  }
  let out : Array[WeaviateObject] = []
  let root = match @json.parse(text) {
    @json.Json::Object(fields) => fields
    _ => Map([])
  }
  let objects = match root.get("objects") {
    Some(@json.Json::Array(items)) => items
    _ => []
  }
  for item in objects {
    let object = match item {
      @json.Json::Object(fields) => fields
      _ => Map([])
    }
    let uuid = match object.get("id") {
      Some(@json.Json::String(s)) => Some(s)
      _ => None
    }
    let properties = match object.get("properties") {
      Some(@json.Json::Object(fields)) => fields
      _ => Map([])
    }
    let doc_id = match properties.get("docid") {
      Some(@json.Json::String(s)) => Some(s)
      _ => None
    }
    let text_body = match properties.get("body") {
      Some(@json.Json::String(s)) => s
      _ => ""
    }
    let meta = match properties.get("meta") {
      Some(@json.Json::String(raw)) =>
        match @json.parse(raw) {
          @json.Json::Object(fields) => fields
          _ => Map([])
        }
      _ => Map([])
    }
    let vector : Array[Double] = []
    match object.get("vector") {
      Some(@json.Json::Array(items)) =>
        for v in items {
          match v {
            @json.Json::Number(n, ..) => vector.push(n)
            _ => ()
          }
        }
      _ => ()
    }
    let document = match doc_id {
      Some(id) => @moonrag.Document::new(text_body, id~, meta~)
      None => @moonrag.Document::new(text_body, meta~)
    }
    out.push({ id: uuid, document, vector, })
  }
  out
}

///|
/// The number of stored objects.
pub async fn WeaviateStore::len(self : WeaviateStore) -> Int64 {
  let url = self.base + "/v1/objects?class=" + self.class_name + "&limit=1"
  let (code, text) = call(@http.RequestMethod::Get, url, "")
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="weaviate count: " + code.to_string())
  }
  match @json.parse(text) {
    @json.Json::Object(fields) =>
      match fields.get("totalResults") {
        Some(@json.Json::Number(n, ..)) => n.to_int64()
        _ => 0L
      }
    _ => 0L
  }
}

///|
/// Embed `documents`, store them, and return the ids they are stored under.
pub impl @moonrag.VectorStore for WeaviateStore with fn add(self, documents) {
  let vectors = self.embedder.embed(
    documents.map(fn(document) { document.text })[:],
  )
  guard vectors.length() == documents.length() else {
    raise @moonrag.Mismatch(got=vectors.length(), want=documents.length())
  }
  let returned : Array[String] = []
  for i, document in documents {
    guard vectors[i].length() == self.dimension else {
      raise @moonrag.Mismatch(got=vectors[i].length(), want=self.dimension)
    }
    let id = self.assign_id(document)
    returned.push(id)
    let uuid = uuid_of(id)
    // Upsert: remove a previous object with this id, then create the new one.
    let _ = call(
      @http.RequestMethod::Delete,
      self.base + "/v1/objects/" + self.class_name + "/" + uuid,
      "",
    )
    let coordinates : Array[@json.Json] = []
    for x in vectors[i] {
      coordinates.push(@json.Json::number(x))
    }
    let meta_text = @json.Json::object(document.meta.copy()).stringify()
    let body = @json.Json::object(
      Map([
        ("class", @json.Json::string(self.class_name)),
        ("id", @json.Json::string(uuid)),
        (
          "properties",
          @json.Json::object(
            Map([
              ("docid", @json.Json::string(id)),
              ("body", @json.Json::string(document.text)),
              ("meta", @json.Json::string(meta_text)),
            ]),
          ),
        ),
        ("vector", @json.Json::array(coordinates)),
      ]),
    ).stringify()
    let (code, text) = call(
      @http.RequestMethod::Post,
      self.base + "/v1/objects",
      body,
    )
    guard code >= 200 && code < 300 else {
      raise @moonrag.Malformed(
        at=0,
        why="weaviate object: " + code.to_string() + " " + text,
      )
    }
  }
  returned
}

///|
/// Delete the objects stored under `ids`. An id not present is not an error.
pub impl @moonrag.VectorStore for WeaviateStore with fn delete(self, ids) {
  for id in ids {
    let _ = call(
      @http.RequestMethod::Delete,
      self.base + "/v1/objects/" + self.class_name + "/" + uuid_of(id),
      "",
    )
  }
}

///|
/// The best `limit` documents for `vector`, best first. Every object is read back with its vector,
/// then filtered, scored and ranked here.
pub impl @moonrag.VectorStore for WeaviateStore with fn search(
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
  let objects = self.all_objects()
  let hits : Array[@moonrag.Scored] = []
  for object in objects {
    if filter is Some(f) && !f.matches(object.document) {
      continue
    }
    guard object.vector.length() == vector.length() else {
      raise @moonrag.Mismatch(got=object.vector.length(), want=vector.length())
    }
    hits.push({
      document: object.document,
      score: @moonrag.cosine_similarity(vector, object.vector[:]),
    })
  }
  @moonrag.rank(hits, limit)
}

///|
pub extend WeaviateStore with @moonrag.VectorStore::{add, delete, search}
