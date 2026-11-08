// The unit a splitter measures in. One code point, which is what a reader counts and what the
// reference implementation's `len()` counts; a token counter is supplied by the caller because only
// the model's own tokenizer knows how many tokens a text will cost.

///|
/// The number of code points in `text`.
fn char_count(text : StringView) -> Int32 {
  let mut count = 0
  for _ in text {
    count = count + 1
  }
  count
}
