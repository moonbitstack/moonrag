///|
/// Markdown splitting on its own: one chunk per heading, the path in the metadata, code kept whole.
///
///     moon run src/examples/04-markdown --target native
#coverage.skip
fn main raise {
  let note = "# Release notes\n\nThe library reads documents, splits them and ranks them.\n\n## Splitting\n\nA heading opens a section.\n\n```moonbit\nlet splitter = @split.MarkdownSplitter::new(chunk_size=80)\nlet chunks = splitter.split(@moonrag.Document::new(\"# Title\\n\\nBody.\\n\"))\n```\n\n### Code stays whole\n\nEven when it does not fit the budget, a code block is one chunk: half a program embeds to nothing.\n\n## Loading\n\nFive formats load into the same document.\n"

  let splitter = @split.MarkdownSplitter::new(chunk_size=120)
  let document = @moonrag.Document::new(note, id="notes.md")
  let chunks = splitter.split(document)
  println("chunks: \{chunks.length()}\n")

  for chunk in chunks {
    let path : Array[String] = []
    for level in ["h1", "h2", "h3"] {
      match chunk.str_meta(level) {
        Some(heading) => path.push(heading)
        None => ()
      }
    }
    println("[" + chunk.id.unwrap_or("?") + "] " + path.join(" > "))
    for line in chunk.text.split("\n") {
      println("    \{line}")
    }
    println("")
  }
}
