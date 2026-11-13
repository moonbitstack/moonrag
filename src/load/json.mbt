// JSON: an array yields one document per element, an object one document, and a text key says which
// field is prose and which fields are metadata.

///|
/// A JSON document, one document per element when the top level is an array.
///
/// With `text_key` the named field becomes the text and the rest of the object becomes metadata —
/// which is how a corpus exported as `[{"title": ..., "body": ...}]` becomes documents without a
/// transformation step. Without it, an object's `text` field is used, and failing that the object is
/// written out as JSON so nothing is silently lost.
pub struct JsonLoader {
  source : String
  text : String
  text_key : String?
}

///|
/// A loader over a JSON text.
pub fn JsonLoader::new(
  source : String,
  text : String,
  text_key? : String,
) -> JsonLoader {
  { source, text, text_key, }
}

///|
/// `json` as a document: prose in the text, the remaining fields in the metadata.
fn document_of(
  json : @json.Json,
  text_key : String?,
  source : String,
) -> @moonrag.Document {
  let meta : Map[String, @json.Json] = Map([])
  meta["source"] = @json.Json::string(source)
  match json {
    @json.Json::String(text) => @moonrag.Document::new(text, meta~)
    @json.Json::Object(fields) => {
      let key = match text_key {
        Some(key) => Some(key)
        None => if fields.get("text") is Some(_) { Some("text") } else { None }
      }
      let mut text = @moonjson.dumps(json)
      match key {
        Some(key) =>
          match fields.get(key) {
            Some(@json.Json::String(value)) => text = value
            Some(value) => text = @moonjson.dumps(value)
            None => ()
          }
        None => ()
      }
      for field, value in fields {
        if key is Some(key) && field == key {
          continue
        }
        meta[field] = value
      }
      @moonrag.Document::new(text, meta~)
    }
    _ => @moonrag.Document::new(@moonjson.dumps(json), meta~)
  }
}

///|
/// What a corpus is read with: RFC 8259, and a repeated member name refused.
///
/// A JSON export that writes `"id"` twice has a defect in the exporting program, and last-one-wins —
/// the reader's default — would store half the object without a word. The loader is where a corpus
/// enters, so it is the place to say so.
let corpus_flavor : @moonjson.Flavor = {
  ..@moonjson.strict,
  duplicates: @moonjson.Reject,
}

///|
/// A refusal from the JSON reader, in this library's error family: the offset the reader stopped at,
/// and the sentence it would have printed. Keeping the reader's own wording means the reason names the
/// character or the missing bracket, which a hand-written mapping would either lose or guess at.
fn malformed_of(refused : @moonjson.Refused) -> @moonrag.Refused {
  let at = match refused.at() {
    Some(position) => position.at
    None => 0
  }
  @moonrag.Malformed(at~, why=refused.message())
}

///|
pub impl @moonrag.Loader for JsonLoader with fn load(self) {
  let json = @moonjson.loads(self.text[:], corpus_flavor) catch {
    (refused : @moonjson.Refused) => raise malformed_of(refused)
  }
  match json {
    @json.Json::Array(items) =>
      items.map(fn(item) { document_of(item, self.text_key, self.source) })
    _ => [document_of(json, self.text_key, self.source)]
  }
}

///|
pub extend JsonLoader with @moonrag.Loader::{load}
