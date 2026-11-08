// Recursive character splitting: try the coarsest separator, and any piece still too long is split
// again by the next one, down to single characters. Every rule here — which separator is searched
// for, where the separator is kept, how the overlap is popped back — is pinned by the differential
// fixtures in src/conformance, because a splitter that differs by one character changes every
// embedding downstream.

///|
/// Where a separator goes relative to the piece it separated.
pub(all) enum KeepSeparator {
  Drop
  Start
  End
}

///|
/// Cuts text by trying a list of separators from coarse to fine.
///
/// Paragraphs first, then lines, then words, then characters: a piece that still does not fit is
/// split again by the next separator, so the result respects natural boundaries for as long as it can
/// and only cuts mid-word when the text leaves no choice.
pub struct RecursiveSplitter {
  chunk_size : Int32
  chunk_overlap : Int32
  separators : Array[String]
  keep_separator : KeepSeparator
  strip_whitespace : Bool
  add_start_index : Bool
  measure : (StringView) -> Int32
}

///|
/// A splitter producing pieces of at most `chunk_size` units, where a unit is one code point unless
/// `measure` says otherwise.
///
/// `chunk_overlap` carries that many units of the previous piece into the next one so a sentence cut
/// across a boundary is still readable in one of them; the defaults (`4000` and `200`) are the ones
/// most chunking pipelines assume. `keep_separator` decides whether the separator stays at the start
/// of the following piece, at the end of the preceding one, or is dropped.
///
/// Raises `Empty` when `chunk_size` is not positive, and `Exceeded` when `chunk_overlap` is negative
/// or larger than `chunk_size`.
pub fn RecursiveSplitter::new(
  chunk_size~ : Int32 = 4000,
  chunk_overlap~ : Int32 = 200,
  separators? : Array[String],
  keep_separator~ : KeepSeparator = Start,
  strip_whitespace~ : Bool = true,
  add_start_index~ : Bool = false,
  measure? : (StringView) -> Int32,
) -> RecursiveSplitter raise {
  guard chunk_size > 0 else { raise @moonrag.Empty(what="chunk_size") }
  guard chunk_overlap >= 0 && chunk_overlap <= chunk_size else {
    raise @moonrag.Exceeded(limit=chunk_size, got=chunk_overlap)
  }
  let separators = separators.unwrap_or(["\n\n", "\n", " ", ""])
  guard separators.length() > 0 else { raise @moonrag.Empty(what="separators") }
  {
    chunk_size,
    chunk_overlap,
    separators,
    keep_separator,
    strip_whitespace,
    add_start_index,
    measure: measure.unwrap_or(char_count),
  }
}

///|
/// `text` split at each occurrence of the literal `separator`, with the separator kept on the side
/// `keep_separator` names. An empty separator splits into single code points.
fn split_at_separator(
  text : String,
  separator : String,
  keep : KeepSeparator,
) -> Array[String] {
  if separator == "" {
    let out : Array[String] = []
    for char in text {
      out.push(char.to_string())
    }
    return out
  }
  let pieces : Array[String] = []
  for piece in text.split(separator[:]) {
    pieces.push(piece.to_owned())
  }
  let out : Array[String] = []
  for i, piece in pieces {
    let joined = match keep {
      Drop => piece
      Start => if i == 0 { piece } else { separator + piece }
      End => if i + 1 == pieces.length() { piece } else { piece + separator }
    }
    if joined != "" {
      out.push(joined)
    }
  }
  out
}

///|
/// `pieces` joined by `separator`, whitespace trimmed when configured, or `None` when the result is
/// empty — an empty chunk is noise in a store, not a document.
fn join_pieces(
  pieces : Array[String],
  separator : String,
  strip_whitespace : Bool,
) -> String? {
  let text = pieces.join(separator[:])
  let text = if strip_whitespace { text.trim().to_owned() } else { text }
  if text == "" {
    None
  } else {
    Some(text)
  }
}

///|
/// Accumulate `pieces` into chunks of at most `chunk_size` units, carrying `chunk_overlap` units of
/// the previous chunk into the next one.
///
/// Shared by every splitter that ends up merging: the recursive one, the token one, and anything a
/// caller writes on top of them.
fn merge_pieces(
  chunk_size : Int32,
  chunk_overlap : Int32,
  measure : (StringView) -> Int32,
  strip_whitespace : Bool,
  pieces : Array[String],
  separator : String,
) -> Array[String] {
  let separator_len = measure(separator[:])
  let docs : Array[String] = []
  let current : Array[String] = []
  let mut total = 0
  for piece in pieces {
    let piece_len = measure(piece[:])
    let gap = if current.length() > 0 { separator_len } else { 0 }
    if total + piece_len + gap > chunk_size {
      if current.length() > 0 {
        match join_pieces(current, separator, strip_whitespace) {
          Some(doc) => docs.push(doc)
          None => ()
        }
        while total > chunk_overlap ||
              (
                total +
                piece_len +
                (if current.length() > 0 { separator_len } else { 0 }) >
                chunk_size &&
                total > 0
              ) {
          total = total -
            measure(current[0][:]) -
            (if current.length() > 1 { separator_len } else { 0 })
          let _ = current.remove(0)
        }
      }
    }
    current.push(piece)
    total = total +
      piece_len +
      (if current.length() > 1 { separator_len } else { 0 })
  }
  match join_pieces(current, separator, strip_whitespace) {
    Some(doc) => docs.push(doc)
    None => ()
  }
  docs
}

///|
/// This splitter's `merge_pieces`.
fn RecursiveSplitter::merge(
  self : RecursiveSplitter,
  pieces : Array[String],
  separator : String,
) -> Array[String] {
  merge_pieces(
    self.chunk_size,
    self.chunk_overlap,
    self.measure,
    self.strip_whitespace,
    pieces,
    separator,
  )
}

///|
/// Split `text` using `separators` from `from` onwards; called again on any piece that is still too
/// long, which is what makes the split recursive.
fn RecursiveSplitter::split_from(
  self : RecursiveSplitter,
  text : String,
  from : Int32,
) -> Array[String] {
  let last = self.separators.length() - 1
  let mut separator = self.separators[last]
  let mut next = self.separators.length()
  for i = from; i <= last; i = i + 1 {
    let candidate = self.separators[i]
    if candidate == "" {
      separator = candidate
      next = self.separators.length()
      break
    }
    if text.contains(candidate[:]) {
      separator = candidate
      next = i + 1
      break
    }
  }
  let pieces = split_at_separator(text, separator, self.keep_separator)
  let join_separator = match self.keep_separator {
    Drop => separator
    Start | End => ""
  }
  let chunks : Array[String] = []
  let good : Array[String] = []
  for piece in pieces {
    if (self.measure)(piece[:]) < self.chunk_size {
      good.push(piece)
    } else {
      if good.length() > 0 {
        chunks.push_iter(self.merge(good, join_separator).iter())
        good.clear()
      }
      if next >= self.separators.length() {
        chunks.push(piece)
      } else {
        chunks.push_iter(self.split_from(piece, next).iter())
      }
    }
  }
  if good.length() > 0 {
    chunks.push_iter(self.merge(good, join_separator).iter())
  }
  chunks
}

///|
/// The offset of `piece` in `text` at or after `from`, used to record where a chunk started.
fn find_from(text : String, piece : String, from : Int32) -> Int32 {
  let start = if from < 0 {
    0
  } else if from > text.length() {
    text.length()
  } else {
    from
  }
  match text.exact_view(start~, end=text.length()).find(piece[:]) {
    Some(offset) => start + offset
    None => start
  }
}

///|
/// The chunks `text` splits into. Public because a caller sometimes wants the strings without the
/// document bookkeeping.
pub fn RecursiveSplitter::split_text(
  self : RecursiveSplitter,
  text : String,
) -> Array[String] {
  if text == "" {
    return []
  }
  self.split_from(text, 0)
}

///|
/// The chunks `text` splits into, paired with the offset each started at.
pub fn RecursiveSplitter::split_with_offsets(
  self : RecursiveSplitter,
  text : String,
) -> Array[(String, Int32)] {
  let out : Array[(String, Int32)] = []
  let pieces = self.split_text(text)
  let mut index = 0
  let mut previous_len = 0
  for piece in pieces {
    let offset = index + previous_len - self.chunk_overlap
    let start = find_from(text, piece, offset)
    out.push((piece, start))
    index = start
    previous_len = (self.measure)(piece[:])
  }
  out
}

///|
pub impl @moonrag.Splitter for RecursiveSplitter with fn split(self, document) {
  let chunks : Array[@moonrag.Document] = []
  if self.add_start_index {
    for i, entry in self.split_with_offsets(document.text) {
      chunks.push(document.derived(i, entry.0, start_index=entry.1))
    }
  } else {
    for i, piece in self.split_text(document.text) {
      chunks.push(document.derived(i, piece))
    }
  }
  chunks
}

///|
pub extend RecursiveSplitter with @moonrag.Splitter::{split}
