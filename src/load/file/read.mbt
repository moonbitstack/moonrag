// Reading a file and handing it to the loader that understands its format. Kept apart from the
// loaders themselves because only these functions need a filesystem: a build without one still gets
// every parser.

///|
/// The whole file at `path` as text.
///
/// Raises whatever the filesystem raises for a missing or unreadable file, and refuses text that is
/// not valid UTF-8 rather than substituting replacement characters — a corpus with a silently
/// mangled encoding is worse than one that fails to load.
pub async fn read(path : String) -> String {
  let data = @fs.read_file(path)
  data.text()
}

///|
/// The file at `path` as one document.
pub async fn text(path : String) -> Array[@moonrag.Document] {
  @moonrag.Loader::load(@load.TextLoader::new(path, read(path)))
}

///|
/// The CSV file at `path`, one document per row.
pub async fn csv(
  path : String,
  has_header~ : Bool = true,
) -> Array[@moonrag.Document] {
  @moonrag.Loader::load(@load.CsvLoader::new(path, read(path), has_header~))
}

///|
/// The JSON file at `path`, one document per element when it holds an array.
pub async fn json(
  path : String,
  text_key? : String,
) -> Array[@moonrag.Document] {
  @moonrag.Loader::load(@load.JsonLoader::new(path, read(path), text_key?))
}

///|
/// The Markdown file at `path`, titled by its first heading.
pub async fn markdown(path : String) -> Array[@moonrag.Document] {
  @moonrag.Loader::load(@load.MarkdownLoader::new(path, read(path)))
}

///|
/// The HTML file at `path`, as readable text.
pub async fn html(path : String) -> Array[@moonrag.Document] {
  @moonrag.Loader::load(@load.HtmlLoader::new(path, read(path)))
}
