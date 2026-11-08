// The three things that must agree with the reference implementation, replayed from
// `langchain_cases_wbtest.mbt`: heading-aware splitting, similarity ranking, and MMR.
//
// The failing message names the case, because a fixture set is only useful if a red test says which
// case went red — a chunk list of the wrong length says nothing on its own.

///|
/// The heading path a chunk carries, in level order.
fn path_of(chunk : @moonrag.Document) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for level in ["h1", "h2", "h3", "h4", "h5", "h6"] {
    match chunk.str_meta(level) {
      Some(text) => out.push((level, text))
      None => ()
    }
  }
  out
}

///|
/// A list of strings, for a failure message that names what differed.
fn texts_of(items : Array[String]) -> String {
  "[" + items.join(", ") + "]"
}

///|
/// A heading path, for a failure message that names what differed.
fn path_text(items : Array[(String, String)]) -> String {
  let parts : Array[String] = []
  for entry in items {
    parts.push(entry.0 + "=" + entry.1)
  }
  "[" + parts.join(", ") + "]"
}

///|
/// A splitter case: the chunks, in order, with the path each one was filed under.
test "the Markdown splitter reproduces every reference case" {
  for case in markdown_cases() {
    let headings : Array[@split.MarkdownHeading] = []
    for entry in case.headings {
      headings.push(@split.MarkdownHeading::new(entry.0, entry.1))
    }
    let splitter = @split.MarkdownSplitter::new(
      chunk_size=case.chunk_size,
      headings~,
    )
    let chunks = splitter.split(@moonrag.Document::new(case.text))
    if chunks.length() != case.texts.length() {
      abort(
        "markdown case [\{case.name}]: want \{case.texts.length()} chunks, got \{chunks.length()}",
      )
    }
    for i, chunk in chunks {
      if chunk.text != case.texts[i] {
        abort(
          "markdown case [\{case.name}] chunk \{i}: want [\{case.texts[i]}], got [\{chunk.text}]",
        )
      }
      if path_of(chunk) != case.paths[i] {
        abort(
          "markdown case [\{case.name}] chunk \{i}: heading path " +
          path_text(path_of(chunk)) +
          " is not " +
          path_text(case.paths[i]),
        )
      }
    }
  }
}

///|
/// A ranking case: the same order, and the same score for each hit.
async test "similarity ranking reproduces every reference case" {
  let embedder : &@moonrag.Embedder = @moonrag.HashingEmbedder::new()
  for case in rank_cases() {
    let store = @moonrag.InMemoryVectorStore::new(embedder)
    let documents = case.texts.map(fn(text) { @moonrag.Document::new(text) })
    let _ = store.add_vectors(documents, case.vectors[:])
    let hits = store.search(case.query[:], limit=case.limit)
    let order = hits.map(fn(hit) { hit.document.text })
    if order != case.order {
      abort(
        "ranking case [\{case.name}]: want " +
        texts_of(case.order) +
        ", got " +
        texts_of(order),
      )
    }
    for i, hit in hits {
      // The order is the whole of a ranking, and it matches exactly. A score is a cosine summed in
      // this library's order and in numpy's, so the last bit may differ; a difference beyond one
      // part in a trillion is a real disagreement.
      if (hit.score - case.scores[i]).abs() > 1.0e-12 {
        abort(
          "ranking case [\{case.name}] hit \{i}: want \{case.scores[i]}, got \{hit.score}",
        )
      }
    }
  }
}

///|
/// An MMR case: the same documents picked, in the same order.
test "MMR reproduces every reference case" {
  for case in mmr_cases() {
    let candidates : Array[@moonrag.Candidate] = []
    for i, text in case.texts {
      candidates.push({
        document: @moonrag.Document::new(text),
        vector: case.vectors[i],
      })
    }
    let picked = @moonrag.mmr(
      case.query[:],
      candidates[:],
      limit=case.limit,
      lambda=case.lambda,
    )
    let texts = picked.map(fn(hit) { hit.document.text })
    if texts != case.picks {
      abort(
        "MMR case [\{case.name}]: want " +
        texts_of(case.picks) +
        ", got " +
        texts_of(texts),
      )
    }
  }
}
