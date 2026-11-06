// HTML splitting by heading: a page is read as sections, each section carrying the heading path it
// sits under, so a retrieved chunk can say "h2: Ranking" instead of arriving without context. The
// sections come out of the parsed tree, not out of line matching, so a heading nested in a div is
// still a heading.

///|
/// Cuts an HTML document into one chunk per heading-delimited section.
///
/// Each chunk's metadata carries the headings above it as `h1` … `h6`, the path LangChain's
/// `HTMLHeaderTextSplitter` also records, and a section longer than `chunk_size` is cut again by the
/// recursive splitter with the same heading path, so no chunk outgrows an embedding window.
pub struct HtmlSplitter {
  chunk_size : Int32
  inner : RecursiveSplitter
}

///|
/// A splitter cutting sections of at most `chunk_size` code points; a section shorter than that stays
/// whole. Raises `Empty` when `chunk_size` is not positive, and `Exceeded` when `chunk_overlap` is
/// negative or larger than `chunk_size`.
pub fn HtmlSplitter::new(
  chunk_size~ : Int32 = 1000,
  chunk_overlap~ : Int32 = 0,
  strip_whitespace~ : Bool = true,
) -> HtmlSplitter raise {
  guard chunk_size > 0 else { raise @moonrag.Empty(what="chunk_size") }
  {
    chunk_size,
    inner: RecursiveSplitter::new(
      chunk_size~,
      chunk_overlap~,
      strip_whitespace~,
    ),
  }
}

///|
/// One heading-delimited section: the headings in force and the text under them.
priv struct Draft {
  headers : Array[String]
  text : String
}

///|
/// The walk state: the heading stack, the text gathered so far, and the sections already closed.
priv struct Outline {
  headers : Array[String]
  mut raw : String
  mut heading : String
  drafts : Array[Draft]
}

///|
fn Outline::new() -> Outline {
  { headers: ["", "", "", "", "", ""], raw: "", heading: "", drafts: [], }
}

///|
/// Close the section in progress, keeping its text unless it is nothing but the heading that opened
/// it — a heading with no body is a table of contents entry, not a passage worth embedding.
fn Outline::flush(self : Outline) -> Unit {
  let text = normalize(self.raw)
  if text != "" && text != self.heading {
    self.drafts.push({ headers: self.headers.copy(), text, })
  }
  self.raw = ""
}

///|
/// Open a section under `level` (0 for `h1`), dropping the deeper headings of the section before it.
fn Outline::open_section(self : Outline, level : Int32, title : String) -> Unit {
  self.flush()
  self.headers[level] = title
  for i = level + 1; i < 6; i = i + 1 {
    self.headers[i] = ""
  }
  self.heading = title
  self.raw = title + "\n"
}

///|
fn Outline::newline(self : Outline) -> Unit {
  if self.raw != "" && !self.raw.has_suffix("\n") {
    self.raw = self.raw + "\n"
  }
}

///|
/// Runs of whitespace become one space, lines are trimmed, empty lines dropped: HTML source puts
/// newlines wherever it likes and none of that should reach a chunk.
fn normalize(raw : String) -> String {
  let lines : Array[String] = []
  for line in raw.split("\n") {
    let line = line.trim()
    if line != "" {
      lines.push(line.to_owned())
    }
  }
  lines.join("\n")
}

///|
/// Every whitespace run becomes one space. Block breaks are added by the walk, not inherited from the
/// source, so the newlines a HTML file happens to contain do not survive as paragraph breaks.
fn collapse_whitespace(raw : String) -> String {
  let out = StringBuilder()
  let mut in_space = false
  for char in raw {
    if char.is_whitespace() {
      if !in_space {
        out.write_char(' ')
        in_space = true
      }
    } else {
      out.write_char(char)
      in_space = false
    }
  }
  out.to_string()
}

///|
/// The heading level of an element name, `None` when it is not a heading.
fn heading_level(name : String) -> Int32? {
  if name.length() != 2 {
    return None
  }
  if !name.has_prefix("h") {
    return None
  }
  let digit = name.exact_view(start=1, end=2).to_owned()
  match digit {
    "1" => Some(0)
    "2" => Some(1)
    "3" => Some(2)
    "4" => Some(3)
    "5" => Some(4)
    "6" => Some(5)
    _ => None
  }
}

///|
/// Whether an element starts a new visual block — the cue to break a line in the extracted text.
fn is_block(name : String) -> Bool {
  match name {
    "p"
    | "div"
    | "section"
    | "article"
    | "header"
    | "footer"
    | "nav"
    | "main"
    | "aside"
    | "ul"
    | "ol"
    | "li"
    | "table"
    | "tr"
    | "td"
    | "th"
    | "thead"
    | "tbody"
    | "blockquote"
    | "pre"
    | "figure"
    | "figcaption"
    | "form"
    | "fieldset"
    | "dl"
    | "dt"
    | "dd"
    | "hr"
    | "br"
    | "body"
    | "html" => true
    _ => false
  }
}

///|
/// Whether an element's content is code or markup rather than prose.
fn is_skipped(name : String) -> Bool {
  match name {
    "script" | "style" | "template" | "noscript" | "head" | "title" => true
    _ => false
  }
}

///|
fn Outline::walk(self : Outline, node : @moonxml.Node) -> Unit {
  match node {
    @moonxml.ElementNode(_) => {
      let name = node.name().to_lower()
      if is_skipped(name) {
        return
      }
      match heading_level(name) {
        Some(level) => {
          self.open_section(
            level,
            collapse_whitespace(node.text()).trim().to_owned(),
          )
          return
        }
        None => ()
      }
      let block = is_block(name)
      if block {
        self.newline()
      }
      for child in node.children() {
        self.walk(child)
      }
      if block {
        self.newline()
      }
    }
    @moonxml.TextNode(text) => self.raw = self.raw + collapse_whitespace(text)
    _ => ()
  }
}

///|
/// The sections of `html`, in document order.
fn outline_of(html : String) -> Array[Draft] {
  let outline = Outline::new()
  let document = @html.loads(html)
  for node in document.children().items {
    outline.walk(node)
  }
  outline.flush()
  outline.drafts
}

///|
/// The chunks `html` splits into: one per section, or several when a section is over budget.
pub fn HtmlSplitter::split_html(
  self : HtmlSplitter,
  html : String,
  meta? : Map[String, Json],
) -> Array[@moonrag.Document] {
  let documents : Array[@moonrag.Document] = []
  let base = meta.unwrap_or(Map([]))
  for draft in outline_of(html) {
    let section_meta = base.copy()
    for i, header in draft.headers {
      if header != "" {
        section_meta["h" + (i + 1).to_string()] = Json::string(header)
      }
    }
    let pieces = if draft.text.length() > self.chunk_size {
      self.inner.split_text(draft.text)
    } else {
      [draft.text]
    }
    for piece in pieces {
      documents.push(@moonrag.Document::new(piece, meta=section_meta.copy()))
    }
  }
  documents
}

///|
pub impl @moonrag.Splitter for HtmlSplitter with fn split(self, document) {
  let documents : Array[@moonrag.Document] = []
  for i, chunk in self.split_html(document.text, meta=document.meta) {
    let id = match document.id {
      Some(id) => Some(id + "#" + i.to_string())
      None => None
    }
    documents.push({ ..chunk, id, })
  }
  documents
}

///|
pub extend HtmlSplitter with @moonrag.Splitter::{split}

///|
/// The readable text of a HTML page: block boundaries become line breaks, markup, scripts, styles and
/// headings-of-nothing are dropped. A loader and a splitter both read a page through this, so they
/// cannot disagree about what it says.
pub fn html_text(html : String) -> String {
  let parts : Array[String] = []
  for draft in outline_of(html) {
    parts.push(draft.text)
  }
  parts.join("\n\n")
}

///|
/// The page title: `<title>`, or the first `h1` when the page has none.
pub fn html_title(html : String) -> String? {
  let document = @html.loads(html)
  for tag in ["title", "h1"] {
    let candidates = document.by_tag(tag)
    if candidates.length() > 0 {
      let title = collapse_whitespace(candidates.first().text())
        .trim()
        .to_owned()
      if title != "" {
        return Some(title)
      }
    }
  }
  None
}
