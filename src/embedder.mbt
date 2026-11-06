// The embedding contract: text in, numbers out. Everything above this file — stores, retrievers,
// indexes — works on vectors and never learns which model produced them, so the same pipeline runs on
// a hosted model, a local one, or a deterministic stand-in.

///|
/// Turns batches of text into vectors of equal length.
///
/// One call embeds a batch, not a string: every model worth calling charges per request, and a batch
/// is also what makes a re-index affordable. All vectors in a batch must have the same length, and the
/// same text must embed to the same vector — ranking is keyed on that.
pub(open) trait Embedder {
  async fn embed(Self, texts : ArrayView[String]) -> Array[Array[Double]]
}

///|
/// A deterministic embedder that needs neither a model nor a network: it hashes the words and the
/// character trigrams of a text into a fixed-width vector.
///
/// It is lexical, not semantic — "cat" and "feline" land far apart — so it suits tests, offline
/// examples and keyword-ish retrieval, not production ranking. Being deterministic, it is also the
/// vector source for differential tests: the same text yields the same vector on every target.
#derive(Debug)
pub struct HashingEmbedder {
  dimension : Int32
}

///|
/// A hashing embedder producing `dimension`-component vectors. `256` is wide enough that a handful of
/// documents rarely collide and narrow enough to keep a fixture readable.
///
/// Raises `Empty` when `dimension` is not positive.
pub fn HashingEmbedder::new(dimension~ : Int32 = 256) -> HashingEmbedder raise {
  guard dimension > 0 else { raise Empty(what="dimension") }
  { dimension, }
}

///|
/// FNV-1a over the UTF-8 bytes of `text` — the bucket hash the embedder uses. Chosen over a keyed
/// hash because the embedding must be identical across processes and targets.
fn fnv1a(text : StringView) -> UInt32 {
  let mut hash : UInt32 = 2166136261U
  for byte in @utf8.encode(text) {
    hash = (hash ^ byte.to_uint()) * 16777619U
  }
  hash
}

///|
/// The features a text is hashed by: runs of letters and digits, lowercased, plus the character
/// trigrams of each run. Trigrams are what give a script without spaces — Chinese, Japanese — more
/// than one bucket per word.
fn features(text : String) -> Array[String] {
  let features : Array[String] = []
  let mut word = ""
  for char in text {
    if is_word_char(char) {
      word = word + char.to_string()
    } else {
      push_features(features, word)
      word = ""
    }
  }
  push_features(features, word)
  features
}

///|
/// Whether `char` belongs to a word: ASCII letters and digits, and any printable non-ASCII character
/// that is not a space — so a run of Chinese is one word rather than a run of punctuation.
fn is_word_char(char : Char) -> Bool {
  if char.is_ascii() {
    char.is_ascii_alphabetic() || char.is_ascii_digit()
  } else {
    !char.is_whitespace() && char.is_printable()
  }
}

///|
/// Append `word` lowercased and its trigrams, if it has any.
fn push_features(features : Array[String], word : String) -> Unit {
  if word.length() == 0 {
    return
  }
  let word = word.to_lower()
  features.push(word)
  let trigrams = word.length() - 2
  for i = 0; i < trigrams; i = i + 1 {
    features.push(word.exact_view(start=i, end=i + 3).to_owned())
  }
}

///|
pub impl Embedder for HashingEmbedder with fn embed(self, texts) {
  let out : Array[Array[Double]] = []
  for text in texts {
    let vector : Array[Double] = Array::make(self.dimension, 0.0)
    for feature in features(text) {
      let hash = fnv1a(feature[:])
      let bucket = (hash % self.dimension.reinterpret_as_uint()).reinterpret_as_int()
      // The high bit picks the sign, so two features colliding in one bucket cancel as often as
      // they reinforce.
      let sign = if hash.land(0x80000000U) != 0U { -1.0 } else { 1.0 }
      vector[bucket] = vector[bucket] + sign
    }
    out.push(normalized(vector[:]))
  }
  out
}

///|
pub extend HashingEmbedder with Debug::{to_repr}

///|
pub extend HashingEmbedder with Embedder::{embed}
