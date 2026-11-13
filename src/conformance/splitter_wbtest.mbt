// The recursive splitter against the reference implementation, case by case. The expected chunks in
// `split_cases.mbt` were produced by langchain-text-splitters 1.1.3; see scripts/gen_split_vectors.py.

///|
test "recursive splitter reproduces every reference case" {
  for case in split_cases() {
    let keep = match case.keep {
      "start" => @split.KeepSeparator::Start
      "end" => @split.KeepSeparator::End
      _ => @split.KeepSeparator::Drop
    }
    let splitter = @split.RecursiveSplitter::new(
      chunk_size=case.chunk_size,
      chunk_overlap=case.chunk_overlap,
      separators=case.separators,
      keep_separator=keep,
      strip_whitespace=case.strip_whitespace,
    )
    let got = splitter.split_text(case.text)
    if got != case.expected {
      let label = "\{case.name} size=\{case.chunk_size} overlap=\{case.chunk_overlap} keep=\{case.keep} strip=\{case.strip_whitespace}"
      abort("splitter case \{label}: \{first_difference(got, case.expected)}")
    }
  }
}

///|
/// Where two chunk lists stop agreeing, in terms a reader can act on.
fn first_difference(got : Array[String], want : Array[String]) -> String {
  if got.length() != want.length() {
    return "chunk count: want \{want.length()} got \{got.length()}"
  }
  for i, chunk in got {
    if chunk != want[i] {
      return "chunk \{i}: want [\{want[i]}] got [\{chunk}]"
    }
  }
  "identical"
}

///|
test "the corpus covers every separator level" {
  let cases = split_cases()
  assert_eq(cases.length(), 56)
  let names : Array[String] = []
  for case in cases {
    if !names.contains(case.name) {
      names.push(case.name)
    }
  }
  assert_eq(names, [
    "rag-overview", "code", "one-line", "no-separator", "cjk", "padded", "short",
    "long-word",
  ])
}

///|
/// The same corpus through a second implementation: LangChain's JavaScript splitter, over the
/// configuration it offers. Two projects agreeing on where every chunk ends is what makes these
/// fixtures evidence rather than one library's opinion.
test "the recursive splitter matches the second implementation case for case" {
  for case in js_split_cases() {
    let splitter = @split.RecursiveSplitter::new(
      chunk_size=case.chunk_size,
      chunk_overlap=case.chunk_overlap,
    )
    let got = splitter.split_text(case.text)
    if got != case.expected {
      let label = "\{case.name} size=\{case.chunk_size} overlap=\{case.chunk_overlap}"
      abort(
        "javascript splitter case \{label}: \{first_difference(got, case.expected)}",
      )
    }
  }
}
