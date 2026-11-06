// The file front end, against a real filesystem: every loader reads what was actually written, and the
// temporary files are removed afterwards so nothing is left behind.

///|
async test "every loader reads a real file" {
  let dir = @fs.tmpdir(prefix="moonrag-load")
  let path_of = fn(name : String) { dir + "/" + name }
  @fs.write_file(path_of("note.txt"), "hello file")
  @fs.write_file(path_of("table.csv"), "k,v\na,1\n")
  @fs.write_file(path_of("corpus.json"), "[{\"text\":\"from json\"}]")
  @fs.write_file(path_of("guide.md"), "# Title\n\nbody\n")
  @fs.write_file(
    path_of("page.html"),
    "<html><head><title>T</title></head><body><p>from html</p></body></html>",
  )

  assert_eq(@file.text(path_of("note.txt"))[0].text, "hello file")
  assert_eq(@file.csv(path_of("table.csv"))[0].str_meta("v"), Some("1"))
  assert_eq(@file.json(path_of("corpus.json"))[0].text, "from json")
  assert_eq(
    @file.markdown(path_of("guide.md"))[0].str_meta("title"),
    Some("Title"),
  )
  assert_eq(@file.html(path_of("page.html"))[0].text, "from html")

  // The source the loader recorded is the path it was given.
  assert_eq(
    @file.text(path_of("note.txt"))[0].str_meta("source"),
    Some(path_of("note.txt")),
  )

  for name in ["note.txt", "table.csv", "corpus.json", "guide.md", "page.html"] {
    @fs.remove(path_of(name))
  }
}

///|
async test "a missing file fails instead of returning nothing" {
  let dir = @fs.tmpdir(prefix="moonrag-load")
  let missing = try {
    let _ = @file.read(dir + "/absent.txt")
    false
  } catch {
    _ => true
  }
  assert_true(missing)
}
