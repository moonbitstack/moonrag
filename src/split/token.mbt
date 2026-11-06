// Splitting by token budget. A token is whatever the caller's counter says it is — a BPE vocabulary,
// a word-piece model, a character counter — so this splitter never has to know which model will read
// the chunks, and the size it promises is measured in the units that will actually be billed.

///|
/// Cuts text into chunks of at most `chunk_size` tokens, where `measure` counts tokens.
///
/// The pieces the text is cut into are the units `separator` delimits (a space by default), and each
/// chunk is measured with `measure` on the assembled text, so the promise holds for the caller's real
/// tokenizer rather than for an estimate.
pub struct TokenSplitter {
  chunk_size : Int32
  chunk_overlap : Int32
  separator : String
  strip_whitespace : Bool
  measure : (StringView) -> Int32
}

///|
/// A splitter whose `chunk_size` and `chunk_overlap` are counted in `measure`'s units.
///
/// Defaults are `512` and `64` tokens, the window most embedding models accept. Raises `Empty` when
/// `chunk_size` is not positive, and `Exceeded` when `chunk_overlap` is negative or larger than
/// `chunk_size`.
pub fn TokenSplitter::new(
  measure : (StringView) -> Int32,
  chunk_size~ : Int32 = 512,
  chunk_overlap~ : Int32 = 64,
  separator~ : String = " ",
  strip_whitespace~ : Bool = true,
) -> TokenSplitter raise {
  guard chunk_size > 0 else { raise @moonrag.Empty(what="chunk_size") }
  guard chunk_overlap >= 0 && chunk_overlap <= chunk_size else {
    raise @moonrag.Exceeded(limit=chunk_size, got=chunk_overlap)
  }
  { chunk_size, chunk_overlap, separator, strip_whitespace, measure, }
}

///|
/// The chunks `text` splits into, each within the token budget.
pub fn TokenSplitter::split_text(
  self : TokenSplitter,
  text : String,
) -> Array[String] {
  if text == "" {
    return []
  }
  let pieces = split_at_separator(text, self.separator, Start)
  merge_pieces(
    self.chunk_size,
    self.chunk_overlap,
    self.measure,
    self.strip_whitespace,
    pieces,
    "",
  )
}

///|
pub impl @moonrag.Splitter for TokenSplitter with fn split(self, document) {
  let chunks : Array[@moonrag.Document] = []
  for i, piece in self.split_text(document.text) {
    chunks.push(document.derived(i, piece))
  }
  chunks
}

///|
pub extend TokenSplitter with @moonrag.Splitter::{split}
