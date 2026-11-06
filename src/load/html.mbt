// HTML as text: the page's readable content, with its title in the metadata. Parsing and text
// extraction happen once, in the splitter's page reader, so a loaded page and a split page say the
// same thing.

///|
/// A HTML page as one document of readable text.
pub struct HtmlLoader {
  source : String
  text : String
}

///|
/// A loader over a HTML text.
pub fn HtmlLoader::new(source : String, text : String) -> HtmlLoader {
  { source, text, }
}

///|
pub impl @moonrag.Loader for HtmlLoader with fn load(self) {
  let meta : Map[String, @json.Json] = Map([])
  meta["source"] = @json.Json::string(self.source)
  if @split.html_title(self.text) is Some(title) {
    meta["title"] = @json.Json::string(title)
  }
  [@moonrag.Document::new(@split.html_text(self.text), meta~)]
}

///|
pub extend HtmlLoader with @moonrag.Loader::{load}
