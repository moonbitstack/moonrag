// A `VectorStore` held in a Qdrant collection, over Qdrant's REST API.
//
// `dimension` is the width of the vectors this store holds, fixed when the collection is created
// because Qdrant declares it then. `collection` is the name to keep points in.
//
// Qdrant ids are unsigned 64-bit integers or UUIDs, so a document's string id is folded into a
// number that fits in a JSON integer and travels back inside the payload as `id` — the document the
// store returns keeps the id the caller gave it.

///|
pub struct QdrantStore {
  base : String
  collection : String
  embedder : &@moonrag.Embedder
  dimension : Int32
  mut counter : Int32
}

///|
/// A store over the Qdrant server at `base` (for example `http://127.0.0.1:6333`).
pub fn QdrantStore::new(
  base : String,
  embedder : &@moonrag.Embedder,
  dimension~ : Int32,
  collection~ : String = "moonrag_documents",
) -> QdrantStore raise {
  guard dimension > 0 else { raise @moonrag.Empty(what="dimension") }
  guard is_identifier(collection) else {
    raise @moonrag.Malformed(at=0, why="collection name")
  }
  { base, collection, embedder, dimension, counter: 0, }
}

///|
/// Whether `name` is a plain identifier: a letter or underscore, then letters, digits, underscores.
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
/// The collection's URL, with `suffix` appended (`""` for the collection itself).
fn QdrantStore::url(self : QdrantStore, suffix : String) -> String {
  self.base + "/collections/" + self.collection + suffix
}

///|
/// The headers every Qdrant call carries.
fn json_headers() -> Map[@http.CaseInsensitiveString, String] {
  Map([(@http.CaseInsensitiveString("Content-Type"), "application/json")])
}

///|
/// One request, returning the status code and the body as text.
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
/// The number a document's string id is folded into: stable for a given string, below 2^53 so it
/// survives a round trip through JSON's number without losing a bit.
fn id_number(id : String) -> Int64 {
  let mask : Int64 = 9007199254740991L
  id.hash().to_int64() & mask
}

///|
/// The JSON value Qdrant stores a point's id under: an integer written exactly.
fn id_json(id : String) -> @json.Json {
  let n = id_number(id)
  @json.Json::number(n.to_double(), repr=n.to_string())
}

///|
/// The point id a document is stored under, generating one (as the other stores do) when it names
/// none.
fn QdrantStore::assign_id(
  self : QdrantStore,
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
/// One point as JSON: the folded id, the vector, and a payload carrying the document.
fn point_json(
  id : String,
  document : @moonrag.Document,
  vector : Array[Double],
) -> @json.Json {
  let payload = @json.Json::object(
    Map([
      ("id", @json.Json::string(id)),
      ("text", @json.Json::string(document.text)),
      ("meta", @json.Json::object(document.meta.copy())),
    ]),
  )
  let coordinates : Array[@json.Json] = []
  for x in vector {
    coordinates.push(@json.Json::number(x))
  }
  @json.Json::object(
    Map([
      ("id", id_json(id)),
      ("vector", @json.Json::array(coordinates)),
      ("payload", payload),
    ]),
  )
}

///|
/// The document and vector a returned point carries.
fn document_of_point(point : @json.Json) -> (@moonrag.Document, Array[Double]) {
  let outer = match point {
    @json.Json::Object(obj) => obj
    _ => Map([])
  }
  let payload = match outer.get("payload") {
    Some(@json.Json::Object(fields)) => fields
    _ => Map([])
  }
  let text = match payload.get("text") {
    Some(@json.Json::String(s)) => s
    _ => ""
  }
  let id = match payload.get("id") {
    Some(@json.Json::String(s)) => Some(s)
    _ => None
  }
  let meta = match payload.get("meta") {
    Some(@json.Json::Object(fields)) => fields
    _ => Map([])
  }
  let stored : Array[Double] = []
  match outer.get("vector") {
    Some(@json.Json::Array(items)) =>
      for item in items {
        match item {
          @json.Json::Number(n, ..) => stored.push(n)
          _ => ()
        }
      }
    _ => ()
  }
  let document = match id {
    Some(s) => @moonrag.Document::new(text, id=s, meta~)
    None => @moonrag.Document::new(text, meta~)
  }
  (document, stored)
}

///|
/// Create the collection this store needs. Safe to call on every start: an existing collection of
/// the same shape is left as it is.
pub async fn QdrantStore::create(self : QdrantStore) -> Unit {
  let body = @json.Json::object(
      Map([
        (
          "vectors",
          @json.Json::object(
            Map([
              ("size", @json.Json::number(self.dimension.to_double())),
              ("distance", @json.Json::string("Cosine")),
            ]),
          ),
        ),
      ]),
    )
    |> @moonjson.dumps
  let (code, _text) = call(@http.RequestMethod::Put, self.url(""), body)
  guard (code >= 200 && code < 300) || code == 409 else {
    raise @moonrag.Malformed(at=0, why="qdrant create: " + code.to_string())
  }
}

///|
/// Remove every stored point by recreating the collection empty.
pub async fn QdrantStore::clear(self : QdrantStore) -> Unit {
  let _ = call(@http.RequestMethod::Delete, self.url(""), "")
  self.create()
}

///|
/// The number of stored points.
pub async fn QdrantStore::len(self : QdrantStore) -> Int64 {
  let body = @json.Json::object(Map([("exact", @json.Json::boolean(true))]))
    |> @moonjson.dumps
  let (code, text) = call(
    @http.RequestMethod::Post,
    self.url("/points/count"),
    body,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="qdrant count: " + code.to_string())
  }
  let count = match @moonjson.loads(text[:], @moonjson.strict) {
    @json.Json::Object(root) =>
      match root.get("result") {
        Some(@json.Json::Object(result)) =>
          match result.get("count") {
            Some(@json.Json::Number(n, ..)) => n
            _ => 0.0
          }
        _ => 0.0
      }
    _ => 0.0
  }
  count.to_int64()
}

///|
/// Embed `documents`, store them as points, and return the ids they are stored under.
pub impl @moonrag.VectorStore for QdrantStore with fn add(self, documents) {
  let vectors = self.embedder.embed(
    documents.map(fn(document) { document.text })[:],
  )
  guard vectors.length() == documents.length() else {
    raise @moonrag.Mismatch(got=vectors.length(), want=documents.length())
  }
  let points : Array[@json.Json] = []
  let ids : Array[String] = []
  for i, document in documents {
    guard vectors[i].length() == self.dimension else {
      raise @moonrag.Mismatch(got=vectors[i].length(), want=self.dimension)
    }
    let id = self.assign_id(document)
    ids.push(id)
    points.push(point_json(id, document, vectors[i]))
  }
  let body = @json.Json::object(Map([("points", @json.Json::array(points))]))
    |> @moonjson.dumps
  let (code, _text) = call(
    @http.RequestMethod::Put,
    self.url("/points?wait=true"),
    body,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="qdrant upsert: " + code.to_string())
  }
  ids
}

///|
/// Delete the points stored under `ids`. An id not present is not an error.
pub impl @moonrag.VectorStore for QdrantStore with fn delete(self, ids) {
  if ids.length() == 0 {
    return
  }
  let points : Array[@json.Json] = []
  for id in ids {
    points.push(id_json(id))
  }
  let body = @json.Json::object(Map([("points", @json.Json::array(points))]))
    |> @moonjson.dumps
  let _ = call(
    @http.RequestMethod::Post,
    self.url("/points/delete?wait=true"),
    body,
  )
}

///|
/// The best `limit` documents for `vector`, best first. Every point is read back with its vector,
/// then filtered, scored and ranked here — the same arithmetic the in-memory store uses.
pub impl @moonrag.VectorStore for QdrantStore with fn search(
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
        ("limit", @json.Json::number(10000.0)),
        ("with_payload", @json.Json::boolean(true)),
        ("with_vector", @json.Json::boolean(true)),
      ]),
    )
    |> @moonjson.dumps
  let (code, text) = call(
    @http.RequestMethod::Post,
    self.url("/points/scroll"),
    body,
  )
  guard code >= 200 && code < 300 else {
    raise @moonrag.Malformed(at=0, why="qdrant scroll: " + code.to_string())
  }
  let points : Array[@json.Json] = match
    @moonjson.loads(text[:], @moonjson.strict) {
    @json.Json::Object(root) =>
      match root.get("result") {
        Some(@json.Json::Object(result)) =>
          match result.get("points") {
            Some(@json.Json::Array(items)) => items
            _ => []
          }
        _ => []
      }
    _ => []
  }
  let hits : Array[@moonrag.Scored] = []
  for point in points {
    let (document, stored) = document_of_point(point)
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
pub extend QdrantStore with @moonrag.VectorStore::{add, delete, search}
