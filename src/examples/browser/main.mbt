// The page's glue: the library compiled to JavaScript, so the demo on the site runs this code and not
// a second implementation of it. Four functions, all returning JSON the page renders.
//
// Nothing here is a model. The vectors below are written down, four numbers per passage, and they are
// the ones the conformance suite replays — so a reader who drags the sliders sees the numbers the
// tests pin, not numbers invented for a screenshot.

///|
/// A string as a JSON value, with the escapes JSON requires.
fn jstr(s : String) -> String {
  let out = StringBuilder::StringBuilder()
  out.write_char('"')
  for char in s {
    match char {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ => out.write_char(char)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// A double as a JSON number.
fn jnum(value : Double) -> String {
  value.to_string()
}

///|
/// A vector as a JSON array of numbers.
fn jvec(vector : ArrayView[Double]) -> String {
  let parts : Array[String] = []
  for value in vector {
    parts.push(jnum(value))
  }
  "[" + parts.join(",") + "]"
}

///|
/// The number of code points in `text` — the unit `chunk_size` counts.
fn codepoints(text : StringView) -> Int32 {
  let mut count = 0
  for _ in text {
    count = count + 1
  }
  count
}

///|
/// One passage of the demo corpus: what it says, where it sits, and the vector it is filed under.
let demo_docs : Array[(String, String, Array[Double])] = [
  (
    "the harbour at dawn, fishing boats leaving",
    "guide.md > Harbour",
    [1.0, 0.0, 0.0, 0.0],
  ),
  (
    "fishing boats return to the harbour at dusk",
    "guide.md > Harbour",
    [0.86, 0.5, 0.0, 0.0],
  ),
  (
    "a mountain path in autumn, cold and clear",
    "notes.md > Ridge",
    [0.0, 1.0, 0.0, 0.0],
  ),
  ("an autumn afternoon on the ridge", "notes.md > Ridge", [0.1, 0.9, 0.2, 0.0]),
  (
    "the harbour wall, repaired with granite",
    "notes.md > Wall",
    [0.7, 0.1, 0.6, 0.1],
  ),
  (
    "granite and lime, a note on mortar",
    "notes.md > Wall",
    [0.0, 0.0, 1.0, 0.0],
  ),
  ("a quiet room with a window", "notes.md > Room", [0.0, 0.1, 0.0, 1.0]),
]

///|
/// The two questions the demo asks the corpus.
let demo_queries : Array[(String, Array[Double])] = [
  ("fishing boats in the harbour", [0.9, 0.1, 0.0, 0.1]),
  ("a walk on the mountain path", [0.2, 0.8, 0.3, 0.0]),
]

///|
/// The index of the corpus entry that says `text`, or `-1`.
fn index_of(text : String) -> Int32 {
  for i, entry in demo_docs {
    if entry.0 == text {
      return i
    }
  }
  -1
}

///|
/// A document for one corpus entry, carrying the source a hit reports.
fn document_of(entry : (String, String, Array[Double])) -> @moonrag.Document {
  @moonrag.Document::new(
    entry.0,
    meta=Map([("source", @json.Json::string(entry.1))]),
  )
}

///|
/// A hit list as JSON: the corpus index, the passage, its source, and the score the library gave it.
fn hits_json(hits : Array[@moonrag.Scored]) -> String {
  let out = StringBuilder::StringBuilder()
  out.write_string("{\"hits\":[")
  for i, hit in hits {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string(
      "{\"i\":" +
      index_of(hit.document.text).to_string() +
      ",\"t\":" +
      jstr(hit.document.text) +
      ",\"src\":" +
      jstr(hit.document.str_meta("source").unwrap_or("")) +
      ",\"score\":" +
      jnum(hit.score) +
      "}",
    )
  }
  out.write_string("]}")
  out.to_string()
}

///|
/// The corpus and the queries, so the page can draw the passages before anything is dragged.
pub fn browser_corpus() -> String {
  let docs = StringBuilder::StringBuilder()
  docs.write_char('[')
  for i, entry in demo_docs {
    if i > 0 {
      docs.write_char(',')
    }
    docs.write_string(
      "{\"t\":" +
      jstr(entry.0) +
      ",\"src\":" +
      jstr(entry.1) +
      ",\"v\":" +
      jvec(entry.2[:]) +
      "}",
    )
  }
  docs.write_char(']')
  let queries = StringBuilder::StringBuilder()
  queries.write_char('[')
  for i, entry in demo_queries {
    if i > 0 {
      queries.write_char(',')
    }
    queries.write_string(
      "{\"label\":" + jstr(entry.0) + ",\"v\":" + jvec(entry.1[:]) + "}",
    )
  }
  queries.write_char(']')
  "{\"docs\":" + docs.to_string() + ",\"queries\":" + queries.to_string() + "}"
}

///|
/// The corpus ranked by cosine similarity to query `q`, cut to `limit`.
pub fn browser_rank(q : Int32, limit : Int32) -> String raise {
  let query = demo_queries[q].1
  let hits : Array[@moonrag.Scored] = []
  for entry in demo_docs {
    hits.push({
      document: document_of(entry),
      score: @moonrag.cosine_similarity(query[:], entry.2[:]),
    })
  }
  hits_json(@moonrag.rank(hits, limit))
}

///|
/// The same candidates reranked by maximal marginal relevance, `lambda` weighting relevance against
/// diversity.
pub fn browser_mmr(q : Int32, lambda : Double, limit : Int32) -> String raise {
  let query = demo_queries[q].1
  let candidates : Array[@moonrag.Candidate] = []
  for entry in demo_docs {
    candidates.push({ document: document_of(entry), vector: entry.2, })
  }
  hits_json(@moonrag.mmr(query[:], candidates[:], limit~, lambda~))
}

///|
/// Whether a chunk is a fenced code block, which the page marks as uncut on purpose.
fn is_code_chunk(text : String) -> Bool {
  text.has_prefix("```") || text.has_prefix("~~~")
}

///|
/// The token counter the page uses with the token splitter: one unit per word.
fn count_words(text : StringView) -> Int32 {
  let mut count = 0
  for word in text.to_owned().split(" ") {
    if word != "" {
      count = count + 1
    }
  }
  count
}

///|
/// `text` split by `mode` — `"markdown"`, `"text"` or `"token"` — into chunks of at most `size`
/// code points, with `overlap` carried between them.
pub fn browser_split(
  text : String,
  mode : String,
  size : Int32,
  overlap : Int32,
) -> String raise {
  let document = @moonrag.Document::new(text)
  let documents : Array[@moonrag.Document] = match mode {
    "markdown" => {
      let splitter = @split.MarkdownSplitter::new(
        chunk_size=size,
        chunk_overlap=overlap,
      )
      splitter.split(document)
    }
    "token" => {
      let splitter = @split.TokenSplitter::new(
        count_words,
        chunk_size=size,
        chunk_overlap=overlap,
      )
      splitter.split(document)
    }
    _ => {
      let splitter = @split.RecursiveSplitter::new(
        chunk_size=size,
        chunk_overlap=overlap,
      )
      splitter.split(document)
    }
  }
  let out = StringBuilder::StringBuilder()
  out.write_string("{\"chunks\":[")
  for i, chunk in documents {
    if i > 0 {
      out.write_char(',')
    }
    let path : Array[String] = []
    for level in ["h1", "h2", "h3"] {
      match chunk.str_meta(level) {
        Some(heading) => path.push(heading)
        None => ()
      }
    }
    out.write_string(
      "{\"t\":" +
      jstr(chunk.text) +
      ",\"path\":" +
      jstr(path.join(" > ")) +
      ",\"n\":" +
      codepoints(chunk.text[:]).to_string() +
      ",\"code\":" +
      (if is_code_chunk(chunk.text) { "true" } else { "false" }) +
      "}",
    )
  }
  out.write_string("],\"count\":" + documents.length().to_string() + "}")
  out.to_string()
}

///|
/// The entry point an executable package needs; the page calls the exported functions instead.
fn main {
  ignore(browser_corpus())
}
