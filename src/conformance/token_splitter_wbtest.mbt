// The token splitter against the reference merge policy. The expected chunks were produced by
// langchain-text-splitters 1.1.3 `CharacterTextSplitter` with a word-count length function, which is
// the same accumulate-and-overlap rule this splitter applies with a token counter.

///|
/// The counter the fixtures were measured with: space-delimited words.
fn words(text : StringView) -> Int32 {
  let mut count = 0
  for piece in text.to_owned().split(" ") {
    if piece.length() > 0 {
      count = count + 1
    }
  }
  count
}

///|
test "token splitter reproduces every reference case" {
  for case in token_cases() {
    let splitter = @split.TokenSplitter::new(
      words,
      chunk_size=case.chunk_size,
      chunk_overlap=case.chunk_overlap,
    )
    let got = splitter.split_text(case.text)
    if got != case.expected {
      let label = "\{case.name} size=\{case.chunk_size} overlap=\{case.chunk_overlap}"
      abort("token case \{label}: \{first_difference(got, case.expected)}")
    }
  }
}

///|
test "every chunk stays inside the token budget" {
  let splitter = @split.TokenSplitter::new(words, chunk_size=6, chunk_overlap=2)
  for case in token_cases() {
    for chunk in splitter.split_text(case.text) {
      assert_true(words(chunk[:]) <= 6)
    }
  }
}
