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
      let mut text = json.stringify()
      match key {
        Some(key) =>
          match fields.get(key) {
            Some(@json.Json::String(value)) => text = value
            Some(value) => text = value.stringify()
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
    _ => @moonrag.Document::new(json.stringify(), meta~)
  }
}

///|
/// The offset of the line and column a parse error named, so the error type stays in offsets.
fn offset_of(text : String, line : Int32, column : Int32) -> Int32 {
  let mut current_line = 1
  let mut index = 0
  for char in text {
    if current_line >= line {
      break
    }
    if char == '\n' {
      current_line = current_line + 1
    }
    index = index + 1
  }
  if current_line < line {
    return text.length()
  }
  let start = index
  let mut offset = start
  for i = start; i < text.length(); i = i + 1 {
    if offset - start >= column - 1 {
      break
    }
    offset = offset + 1
  }
  offset
}

///|
pub impl @moonrag.Loader for JsonLoader with fn load(self) {
  let json = @json.parse(self.text) catch {
    @json.ParseError::InvalidChar(position, char) =>
      raise @moonrag.Malformed(
        at=offset_of(self.text, position.line, position.column),
        why="invalid character \{char}",
      )
    @json.ParseError::InvalidEof =>
      raise @moonrag.Malformed(
        at=self.text.length(),
        why="unexpected end of input",
      )
    @json.ParseError::InvalidNumber(position, text) =>
      raise @moonrag.Malformed(
        at=offset_of(self.text, position.line, position.column),
        why="invalid number \{text}",
      )
    @json.ParseError::InvalidIdentEscape(position) =>
      raise @moonrag.Malformed(
        at=offset_of(self.text, position.line, position.column),
        why="invalid escape",
      )
    @json.ParseError::DuplicateKey(position, key) =>
      raise @moonrag.Malformed(
        at=offset_of(self.text, position.line, position.column),
        why="duplicate key \{key}",
      )
    @json.ParseError::DepthLimitExceeded =>
      raise @moonrag.Malformed(at=0, why="nesting too deep")
  }
  match json {
    @json.Json::Array(items) =>
      items.map(fn(item) { document_of(item, self.text_key, self.source) })
    _ => [document_of(json, self.text_key, self.source)]
  }
}

///|
pub extend JsonLoader with @moonrag.Loader::{load}
