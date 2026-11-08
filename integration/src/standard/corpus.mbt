// The corpus the standard cases search: four short passages about two subjects, and two queries that
// one subject answers. Small enough to reason about by hand, distinct enough that a ranking is either
// right or wrong, never a near-tie.

///|
/// The documents every case starts from, with the metadata the filter cases read.
pub fn corpus() -> Array[@moonrag.Document] {
  [
    @moonrag.Document::new(
      "the harbour at dawn, fishing boats leaving",
      meta=Map([
        ("topic", @json.Json::string("sea")),
        ("year", @json.Json::number(2019.0)),
      ]),
    ),
    @moonrag.Document::new(
      "a mountain path in autumn, cold and clear",
      meta=Map([
        ("topic", @json.Json::string("land")),
        ("year", @json.Json::number(2021.0)),
      ]),
    ),
    @moonrag.Document::new(
      "fishing boats return to the harbour at dusk",
      meta=Map([
        ("topic", @json.Json::string("sea")),
        ("year", @json.Json::number(2024.0)),
      ]),
    ),
    @moonrag.Document::new(
      "the harbour wall, repaired with granite",
      meta=Map([
        ("topic", @json.Json::string("sea")),
        ("year", @json.Json::number(2025.0)),
        ("tag", @json.Json::string("draft")),
      ]),
    ),
  ]
}

///|
/// A query about boats and harbours.
pub fn sea_query() -> String {
  "fishing boats in the harbour"
}

///|
/// A query about walking uphill.
pub fn land_query() -> String {
  "a walk on a mountain path"
}

///|
/// The documents every case starts from, filed under ids that say which is which.
pub fn corpus_with_ids() -> Array[@moonrag.Document] {
  let documents : Array[@moonrag.Document] = []
  for i, document in corpus() {
    documents.push(document.with_id("doc-" + i.to_string()))
  }
  documents
}
