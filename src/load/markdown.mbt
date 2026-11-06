// Markdown as text: the loader keeps the source, records the title the first heading gives it, and
// leaves the block structure to whoever reads it next. Section splitting needs a Markdown parser and
// arrives with one; loading does not.

///|
/// A Markdown file as one document, with its first heading as the `title` metadata.
pub struct MarkdownLoader {
  source : String
  text : String
}

///|
/// A loader over a Markdown text.
pub fn MarkdownLoader::new(source : String, text : String) -> MarkdownLoader {
  { source, text, }
}

///|
/// The text of the first ATX heading, `None` for a file without one.
///
/// Fenced code is skipped: a `#` inside a shell snippet is a comment, not a heading.
fn first_heading(text : String) -> String? {
  let mut fenced = false
  for line in text.split("\n") {
    let line = line.trim()
    if line.has_prefix("```") || line.has_prefix("~~~") {
      fenced = !fenced
      continue
    }
    if fenced || !line.has_prefix("#") {
      continue
    }
    let title = line.trim(chars="#").trim()
    if title != "" {
      return Some(title.to_owned())
    }
  }
  None
}

///|
pub impl @moonrag.Loader for MarkdownLoader with fn load(self) {
  let meta : Map[String, @json.Json] = Map([])
  meta["source"] = @json.Json::string(self.source)
  if first_heading(self.text) is Some(title) {
    meta["title"] = @json.Json::string(title)
  }
  [@moonrag.Document::new(self.text, meta~)]
}

///|
pub extend MarkdownLoader with @moonrag.Loader::{load}
