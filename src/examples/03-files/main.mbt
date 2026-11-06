///|
/// Reading real files: the example writes a small corpus to a temporary directory, loads it back
/// through the file front end, and removes what it wrote. Needs a filesystem, so it does not build for
/// the browser.
///
///     moon run src/examples/03-files --target native
#coverage.skip
async fn main {
  let dir = @fs.tmpdir(prefix="moonrag-example")
  let csv = dir + "/people.csv"
  @fs.write_file(csv, "name,city\nAda,London\nGrace,New York\n")
  let documents = @file.csv(csv)
  println("rows read: \{documents.length()}")
  for document in documents {
    println(
      "  \{document.text}   (source=\{document.str_meta("source").unwrap_or("?")})",
    )
  }
  @fs.remove(csv)
}
