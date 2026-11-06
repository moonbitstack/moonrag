// The unit every stage of the pipeline moves: a piece of text with an optional identity and
// arbitrary metadata. Split, load, embed, store and retrieve all read or write only this type, so a
// document outlives the pipeline that produced it.

///|
/// A piece of text, with an optional identity and metadata.
///
/// `id` is what a store keys a document by. Leave it `None` and the store assigns one; set it and the
/// document keeps the same identity across re-indexing, which is what makes an update replace the old
/// copy instead of piling up beside it. `meta` carries whatever the caller needs — a source path, a
/// page number, a heading path — and is what a `Filter` reads.
#derive(Eq, Debug)
pub(all) struct Document {
  id : String?
  text : String
  meta : Map[String, Json]
}

///|
/// A document with `text`, no identity, and no metadata.
pub fn Document::new(
  text : String,
  id? : String,
  meta? : Map[String, Json],
) -> Document {
  { id, text, meta: meta.unwrap_or(Map([])), }
}

///|
/// The same document carrying `metadata`, for a filter to match on.
pub fn Document::with_meta(
  self : Document,
  metadata : Map[String, Json],
) -> Document {
  { ..self, meta: metadata, }
}

///|
/// The same document with `key` set to `value`; a key already present is replaced.
pub fn Document::set_meta(
  self : Document,
  key : String,
  value : Json,
) -> Document {
  let meta = self.meta.copy()
  meta[key] = value
  { ..self, meta, }
}

///|
/// The metadata value stored under `key`, or `None`.
pub fn Document::meta_of(self : Document, key : String) -> Json? {
  self.meta.get(key)
}

///|
/// The metadata value stored under `key` when it is a string, or `None`.
pub fn Document::str_meta(self : Document, key : String) -> String? {
  match self.meta.get(key) {
    Some(Json::String(text)) => Some(text)
    Some(_) => None
    None => None
  }
}

///|
/// The same document under `id`, for a store that keys by caller-chosen identity.
pub fn Document::with_id(self : Document, id : String) -> Document {
  { ..self, id: Some(id), }
}

///|
/// A document cut out of `parent`: same metadata plus the chunk number, a derived id when the parent
/// had one, and the offset it started at when the splitter knows it.
///
/// Splitters are not the only producers of chunks — a caller streaming pages out of a PDF has the same
/// needs — so the bookkeeping lives here rather than in each of them.
pub fn Document::derived(
  self : Document,
  index : Int32,
  text : String,
  start_index? : Int32,
) -> Document {
  let meta = self.meta.copy()
  meta["chunk"] = Json::number(index.to_double(), repr=index.to_string())
  if start_index is Some(start) {
    meta["start_index"] = Json::number(
      start.to_double(),
      repr=start.to_string(),
    )
  }
  let id = match self.id {
    Some(id) => Some(id + "#" + index.to_string())
    None => None
  }
  { id, text, meta, }
}

///|
/// A document and the score it earned: what one search returns.
#derive(Eq, Debug)
pub(all) struct Scored {
  document : Document
  score : Double
}

///|
/// The documents in `hits`, dropping the scores.
pub fn Scored::documents(hits : ArrayView[Scored]) -> Array[Document] {
  hits.map(fn(hit) { hit.document })
}

///|
pub impl ToJson for Document with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  match self.id {
    Some(id) => fields["id"] = Json::string(id)
    None => ()
  }
  fields["text"] = Json::string(self.text)
  fields["meta"] = Json::object(self.meta.copy())
  Json::object(fields)
}

///|
pub impl ToJson for Scored with fn to_json(self) {
  Json::object(
    Map([
      ("document", ToJson::to_json(self.document)),
      ("score", Json::number(self.score)),
    ]),
  )
}

///|
pub impl FromJson for Document with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "want an object"))
  }
  let id = match fields.get("id") {
    Some(Json::String(id)) => Some(id)
    Some(_) => raise JsonDecodeError((path.add_key("id"), "want a string"))
    None => None
  }
  let text = match fields.get("text") {
    Some(Json::String(text)) => text
    Some(_) => raise JsonDecodeError((path.add_key("text"), "want a string"))
    None => raise JsonDecodeError((path.add_key("text"), "want a string"))
  }
  let meta = match fields.get("meta") {
    Some(Json::Object(meta)) => meta
    Some(_) => raise JsonDecodeError((path.add_key("meta"), "want an object"))
    None => Map([])
  }
  { id, text, meta, }
}

///|
pub impl FromJson for Scored with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "want an object"))
  }
  let document = match fields.get("document") {
    Some(value) => @json.from_json(value, path=path.add_key("document"))
    None => raise JsonDecodeError((path.add_key("document"), "want a document"))
  }
  let score = match fields.get("score") {
    Some(Json::Number(score, ..)) => score
    Some(_) => raise JsonDecodeError((path.add_key("score"), "want a number"))
    None => raise JsonDecodeError((path.add_key("score"), "want a number"))
  }
  { document, score, }
}

///|
pub extend Document with Eq::{not_equal, equal}

///|
pub extend Document with Debug::{to_repr}

///|
pub extend Document with ToJson::{to_json}

///|
pub extend Document with FromJson::{from_json}

///|
pub extend Scored with Eq::{not_equal, equal}

///|
pub extend Scored with Debug::{to_repr}

///|
pub extend Scored with ToJson::{to_json}

///|
pub extend Scored with FromJson::{from_json}
