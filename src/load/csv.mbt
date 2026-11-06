// CSV, parsed the way RFC 4180 says: quoted fields may hold the delimiter, a quote is escaped by
// doubling it, and a record ends at CRLF or LF. One row becomes one document, with the columns in
// metadata so a filter can select rows without parsing the text again.

///|
/// A CSV table, one document per row.
///
/// The document text is the row spelled out as `column: value` lines, which reads better to a model
/// than a comma-separated line, and every column is also in the metadata under its header name.
pub struct CsvLoader {
  source : String
  text : String
  has_header : Bool
  delimiter : Char
}

///|
/// A loader over `text`. With `has_header` the first record names the columns; without it the columns
/// are `column_0`, `column_1`, … Raises `Malformed` when a quoted field is never closed.
pub fn CsvLoader::new(
  source : String,
  text : String,
  has_header~ : Bool = true,
  delimiter~ : Char = ',',
) -> CsvLoader {
  { source, text, has_header, delimiter, }
}

///|
/// The records of a CSV text, each a list of fields.
fn parse_csv(text : String, delimiter : Char) -> Array[Array[String]] raise {
  let records : Array[Array[String]] = []
  let fields : Array[String] = []
  let field = StringBuilder()
  let chars = text.to_array()
  let mut quoted = false
  let mut started = false
  let mut i = 0
  let end_field = () => {
    fields.push(field.to_string())
    field.reset()
    started = true
  }

  while i < chars.length() {
    let char = chars[i]
    if quoted {
      if char == '"' {
        if i + 1 < chars.length() && chars[i + 1] == '"' {
          // A doubled quote inside a quoted field is one quote.
          field.write_char('"')
          i = i + 2
          continue
        }
        quoted = false
      } else {
        field.write_char(char)
      }
    } else if char == '"' && field.to_string() == "" {
      quoted = true
      started = true
    } else if char == delimiter {
      end_field()
    } else if char == '\n' {
      end_field()
      records.push(fields.copy())
      fields.clear()
      started = false
    } else if char == '\r' {
      // Half of a CRLF pair, or a stray carriage return: either way not content.
      ()
    } else {
      field.write_char(char)
      started = true
    }
    i = i + 1
  }
  if quoted {
    raise @moonrag.Malformed(at=i, why="unterminated quoted field")
  }
  if started || field.to_string() != "" || fields.length() > 0 {
    fields.push(field.to_string())
    if fields.length() > 1 || fields[0] != "" {
      records.push(fields)
    }
  }
  records
}

///|
pub impl @moonrag.Loader for CsvLoader with fn load(self) {
  let records = parse_csv(self.text, self.delimiter)
  let documents : Array[@moonrag.Document] = []
  let mut header : Array[String] = []
  let mut first = 0
  if self.has_header && records.length() > 0 {
    header = records[0]
    first = 1
  }
  for row_index = first; row_index < records.length(); row_index = row_index + 1 {
    let record = records[row_index]
    let meta : Map[String, @json.Json] = Map([])
    meta["source"] = @json.Json::string(self.source)
    meta["row"] = @json.Json::number(
      row_index.to_double(),
      repr=row_index.to_string(),
    )
    let lines : Array[String] = []
    for i, value in record {
      let key = if i < header.length() {
        header[i]
      } else {
        "column_" + i.to_string()
      }
      if key != "" {
        meta[key] = @json.Json::string(value)
        if value != "" {
          lines.push(key + ": " + value)
        }
      }
    }
    documents.push(@moonrag.Document::new(lines.join("\n"), meta~))
  }
  documents
}

///|
pub extend CsvLoader with @moonrag.Loader::{load}
