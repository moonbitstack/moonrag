// Plain text: one file, one document. The simplest loader, and the one every other format's loader
// is shaped like.

///|
/// A whole text as a single document, with `source` recorded in its metadata.
///
/// Use it for a note, a log line, a field already read from somewhere else: anything whose text is
/// the document rather than a container for documents.
pub struct TextLoader {
  source : String
  text : String
}

///|
/// A loader over `text`, labelling the document with `source`.
pub fn TextLoader::new(source : String, text : String) -> TextLoader {
  { source, text, }
}

///|
pub impl @moonrag.Loader for TextLoader with fn load(self) {
  [
    @moonrag.Document::new(
      self.text,
      meta=Map([("source", @json.Json::string(self.source))]),
    ),
  ]
}

///|
pub extend TextLoader with @moonrag.Loader::{load}
