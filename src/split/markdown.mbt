// Heading-aware splitting: one section per heading, the heading path carried in the metadata, and a
// section too long for the budget cut again by the recursive splitter — except for code, which is
// never cut, because half a program embeds to nothing useful.
//
// The document is read as a syntax tree rather than as lines, so a `#` inside a fenced code block is
// a comment, not a heading, and the indentation of code survives the trip.

///|
/// One heading level that starts a new section, and the metadata key its text is filed under.
///
/// The key is the caller's: `MarkdownHeading::new(2, "h2")` files an `## Install` heading as
/// `{"h2": "Install"}`. Levels are unique within a splitter, so a section's path has one entry per
/// level.
#derive(Eq, Debug)
pub(all) struct MarkdownHeading {
  level : Int32
  key : String
}

///|
/// A heading level `1` to `6` filed under `key`.
///
/// Raises `Exceeded` when `level` is outside that range and `Empty` when `key` is blank.
pub fn MarkdownHeading::new(
  level : Int32,
  key : String,
) -> MarkdownHeading raise {
  guard level >= 1 && level <= 6 else {
    raise @moonrag.Exceeded(limit=6, got=level)
  }
  guard key != "" else { raise @moonrag.Empty(what="heading key") }
  { level, key, }
}

///|
/// The six ATX levels, filed as `h1` … `h6`.
pub fn MarkdownHeading::defaults() -> Array[MarkdownHeading] {
  let out : Array[MarkdownHeading] = []
  for level in 1..<7 {
    out.push({ level, key: "h" + level.to_string(), })
  }
  out
}

///|
/// Cuts a Markdown document at its headings.
///
/// A chunk never crosses a heading, and carries the whole path down to it — `h1`, `h2` and so on — so
/// a retrieved passage can say which section of which page it came from. A section longer than
/// `chunk_size` is cut again by the recursive splitter at block boundaries; a code block is emitted
/// whole however long it is, because cutting it would leave a fragment that neither compiles nor
/// reads.
pub struct MarkdownSplitter {
  chunk_size : Int32
  chunk_overlap : Int32
  headings : Array[MarkdownHeading]
  strip_headers : Bool
  fallback : RecursiveSplitter
}

///|
/// A splitter producing sections of at most `chunk_size` code points.
///
/// `headings` is the set of levels that start a new chunk; a heading of a level not listed stays in
/// the text of the section around it. `strip_headers` drops the heading line itself from the chunk —
/// on by default, because the heading is in the metadata and repeating it wastes an embedding slot.
///
/// Raises `Empty` when `chunk_size` is not positive, `Exceeded` when `chunk_overlap` is negative or
/// larger than `chunk_size` or when two headings share a level.
pub fn MarkdownSplitter::new(
  chunk_size~ : Int32 = 4000,
  chunk_overlap~ : Int32 = 0,
  headings? : Array[MarkdownHeading],
  strip_headers~ : Bool = true,
) -> MarkdownSplitter raise {
  guard chunk_size > 0 else { raise @moonrag.Empty(what="chunk_size") }
  guard chunk_overlap >= 0 && chunk_overlap <= chunk_size else {
    raise @moonrag.Exceeded(limit=chunk_size, got=chunk_overlap)
  }
  let headings = headings.unwrap_or(MarkdownHeading::defaults())
  for i, heading in headings {
    for j = i + 1; j < headings.length(); j = j + 1 {
      guard headings[j].level != heading.level else {
        raise @moonrag.Exceeded(limit=6, got=heading.level)
      }
    }
  }
  {
    chunk_size,
    chunk_overlap,
    headings,
    strip_headers,
    fallback: RecursiveSplitter::new(chunk_size~, chunk_overlap~),
  }
}

///|
/// The key a heading of `level` is filed under, or `None` when that level does not split.
fn MarkdownSplitter::key_of(self : MarkdownSplitter, level : Int32) -> String? {
  for heading in self.headings {
    if heading.level == level {
      return Some(heading.key)
    }
  }
  None
}

///|
/// The blocks of one section, and the heading path it sits under.
priv struct MarkdownSection {
  blocks : Array[@moonmd.Block]
  path : Array[(String, String)]
}

///|
/// The text of one block on its own, trimmed, or `""` for a block that renders to nothing.
fn block_text(block : @moonmd.Block) -> String {
  @moonmd.Document::of_blocks([block]).markdown().trim().to_owned()
}

///|
/// The heading text of a level-`level` ATX heading, with the marks and the surrounding space gone.
fn heading_text(block : @moonmd.Block, level : Int32) -> String {
  let line = block_text(block)
  let mut start = 0
  while start < line.length() &&
        start < level &&
        line.exact_view(start~, end=start + 1) == "#" {
    start = start + 1
  }
  line.clamped_view(start~, end=line.length()).trim().to_owned()
}

///|
/// The blocks of `text` grouped by heading, in document order.
fn MarkdownSplitter::sections(
  self : MarkdownSplitter,
  text : String,
) -> Array[MarkdownSection] {
  let sections : Array[MarkdownSection] = []
  let current : Array[@moonmd.Block] = []
  let stack : Array[(Int32, String, String)] = []
  let flush = fn() {
    if current.length() > 0 {
      let path : Array[(String, String)] = []
      for entry in stack {
        path.push((entry.1, entry.2))
      }
      sections.push({ blocks: current.copy(), path, })
      current.clear()
    }
  }
  for block in @moonmd.parse(text).blocks() {
    let level = match block {
      @moonmd.Heading(heading) => heading.level
      _ => 0
    }
    match (if level > 0 { self.key_of(level) } else { None }) {
      Some(key) => {
        flush()
        while stack.length() > 0 && stack[stack.length() - 1].0 >= level {
          let _ = stack.pop()
        }
        stack.push((level, key, heading_text(block, level)))
        if !self.strip_headers {
          current.push(block)
        }
      }
      None => current.push(block)
    }
  }
  flush()
  sections
}

///|
/// Whether a block is code, which is never cut.
fn is_code(block : @moonmd.Block) -> Bool {
  match block {
    @moonmd.Code(_) => true
    _ => false
  }
}

///|
/// `blocks` packed into chunks of at most `chunk_size`, never cutting a block unless the block is
/// prose that fits nowhere.
///
/// `chunk_overlap` carries as many whole blocks from the end of one chunk into the next as fit in it,
/// which is the same promise the recursive splitter keeps, except that here a block is indivisible:
/// half a list or half a fence is worse than a gap between chunks.
fn MarkdownSplitter::pack(
  self : MarkdownSplitter,
  blocks : Array[@moonmd.Block],
) -> Array[String] {
  let out : Array[String] = []
  let current : Array[String] = []
  let mut total = 0
  let gap = 2
  for block in blocks {
    let piece = block_text(block)
    if piece == "" {
      continue
    }
    let length = char_count(piece[:])
    if length >= self.chunk_size && !is_code(block) {
      // Prose that does not fit in any chunk: the recursive splitter can cut it mid-sentence and
      // still leave something readable, so it does.
      if current.length() > 0 {
        out.push(current.join("\n\n"))
        current.clear()
        total = 0
      }
      out.push_iter(self.fallback.split_text(piece).iter())
      continue
    }
    if current.length() > 0 && total + length + gap > self.chunk_size {
      let tail : Array[String] = []
      let mut tail_total = 0
      let mut at = current.length() - 1
      while at >= 0 {
        let candidate = current[at]
        let candidate_len = char_count(candidate[:])
        let extra = if tail.length() > 0 {
          candidate_len + gap
        } else {
          candidate_len
        }
        if tail_total + extra > self.chunk_overlap {
          break
        }
        tail.push(candidate)
        tail_total = tail_total + extra
        at = at - 1
      }
      out.push(current.join("\n\n"))
      current.clear()
      current.push_iter(tail.rev().iter())
      total = tail_total
    }
    current.push(piece)
    total = total + length + (if current.length() > 1 { gap } else { 0 })
  }
  if current.length() > 0 {
    out.push(current.join("\n\n"))
  }
  out
}

///|
/// The text of the chunks `text` splits into.
pub fn MarkdownSplitter::split_text(
  self : MarkdownSplitter,
  text : String,
) -> Array[String] {
  let out : Array[String] = []
  for section in self.sections(text) {
    out.push_iter(self.pack(section.blocks).iter())
  }
  out
}

///|
/// The documents `markdown` splits into, filed under `meta` as well as their heading path — the same
/// result as `split` on a document, for a caller that has the text and nothing else.
pub fn MarkdownSplitter::split_markdown(
  self : MarkdownSplitter,
  markdown : String,
  meta? : Map[String, Json],
) -> Array[@moonrag.Document] {
  self.split(@moonrag.Document::new(markdown, meta?))
}

///|
pub impl @moonrag.Splitter for MarkdownSplitter with fn split(self, document) {
  let chunks : Array[@moonrag.Document] = []
  let mut index = 0
  for section in self.sections(document.text) {
    for text in self.pack(section.blocks) {
      let mut chunk = document.derived(index, text)
      for entry in section.path {
        chunk = chunk.set_meta(entry.0, @json.Json::string(entry.1))
      }
      chunks.push(chunk)
      index = index + 1
    }
  }
  chunks
}

///|
pub extend MarkdownSplitter with @moonrag.Splitter::{split}

///|
pub extend MarkdownHeading with Eq::{not_equal, equal}

///|
pub extend MarkdownHeading with Debug::{to_repr}
