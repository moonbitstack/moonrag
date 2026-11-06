// The in-memory store: the reference implementation of `VectorStore`, and the one a test or a small
// corpus uses. It keeps documents and their vectors in insertion order, scores every candidate on each
// search, and applies metadata filters before ranking so a filtered search never pays for documents
// it will drop.

///|
/// A `VectorStore` held in memory, keyed by document id.
///
/// The store embeds what it is given, so `add` takes documents while a search takes the query's
/// vector. That split is deliberate: writing is the rare, batched, cacheable path, while a search
/// often reuses one query vector across several stores.
pub struct InMemoryVectorStore {
  embedder : &Embedder
  mut entries : Array[(String, Document, Array[Double])]
  mut counter : Int32
}

///|
/// An empty store that embeds with `embedder`.
pub fn InMemoryVectorStore::new(embedder : &Embedder) -> InMemoryVectorStore {
  { embedder, entries: [], counter: 0, }
}

///|
/// The id `document` is stored under: its own when it has one, otherwise the next free one. A document
/// that names its id keeps that identity across re-indexing.
fn InMemoryVectorStore::assign_id(
  self : InMemoryVectorStore,
  document : Document,
) -> String raise {
  match document.id {
    Some(id) => if id == "" { raise Empty(what="document id") } else { id }
    None => {
      // Skip ids a document named for itself: generating one that is taken would silently replace
      // that document.
      let mut id = "doc-" + self.counter.to_string()
      self.counter = self.counter + 1
      while self.contains(id) {
        id = "doc-" + self.counter.to_string()
        self.counter = self.counter + 1
      }
      id
    }
  }
}

///|
/// Store documents that already carry their vectors, returning their ids. An id already present is
/// replaced in place, which is what makes a re-index an update rather than a duplicate.
///
/// Raises `Mismatch` when the vector count differs from the document count or two vectors differ in
/// length, and `Empty` for a document whose id is the empty string.
pub fn InMemoryVectorStore::add_vectors(
  self : InMemoryVectorStore,
  documents : Array[Document],
  vectors : ArrayView[Array[Double]],
) -> Array[String] raise {
  guard documents.length() == vectors.length() else {
    raise Mismatch(got=vectors.length(), want=documents.length())
  }
  for i, vector in vectors {
    if i > 0 && vector.length() != vectors[0].length() {
      raise Mismatch(got=vector.length(), want=vectors[0].length())
    }
  }
  let ids : Array[String] = []
  for i, document in documents {
    let id = self.assign_id(document)
    self.remove(id)
    self.entries.push((id, document, vectors[i]))
    ids.push(id)
  }
  ids
}

///|
/// Whether an entry is stored under `id`.
fn InMemoryVectorStore::contains(
  self : InMemoryVectorStore,
  id : String,
) -> Bool {
  for entry in self.entries {
    if entry.0 == id {
      return true
    }
  }
  false
}

///|
/// Drop the entry stored under `id`, if any.
fn InMemoryVectorStore::remove(self : InMemoryVectorStore, id : String) -> Unit {
  let kept : Array[(String, Document, Array[Double])] = []
  for entry in self.entries {
    if entry.0 != id {
      kept.push(entry)
    }
  }
  self.entries = kept
}

///|
/// The number of stored documents.
pub fn InMemoryVectorStore::len(self : InMemoryVectorStore) -> Int32 {
  self.entries.length()
}

///|
/// The ids of the stored documents, in the order they were added.
pub fn InMemoryVectorStore::ids(self : InMemoryVectorStore) -> Array[String] {
  self.entries.map(fn(entry) { entry.0 })
}

///|
/// The document stored under `id`, or `None`. The returned document carries the id it is stored
/// under, so it can be deleted or refetched without keeping the id beside it.
pub fn InMemoryVectorStore::get(
  self : InMemoryVectorStore,
  id : String,
) -> Document? {
  for entry in self.entries {
    if entry.0 == id {
      return Some({ ..entry.1, id: Some(entry.0), })
    }
  }
  None
}

///|
/// The vector stored for `id`, or `None` — for a caller that reranks hits itself.
pub fn InMemoryVectorStore::vector_of(
  self : InMemoryVectorStore,
  id : String,
) -> Array[Double]? {
  for entry in self.entries {
    if entry.0 == id {
      return Some(entry.2)
    }
  }
  None
}

///|
/// Remove every stored document.
pub fn InMemoryVectorStore::clear(self : InMemoryVectorStore) -> Unit {
  self.entries = []
  self.counter = 0
}

///|
pub impl VectorStore for InMemoryVectorStore with fn add(self, documents) {
  let vectors = self.embedder.embed(
    documents.map(fn(document) { document.text })[:],
  )
  guard vectors.length() == documents.length() else {
    raise Mismatch(got=vectors.length(), want=documents.length())
  }
  self.add_vectors(documents, vectors[:])
}

///|
pub impl VectorStore for InMemoryVectorStore with fn delete(self, ids) {
  for id in ids {
    self.remove(id)
  }
}

///|
/// Hits carry the id each document is stored under — a caller that wants to delete one does not have
/// to remember which id came back from `add`.
pub impl VectorStore for InMemoryVectorStore with fn search(
  self,
  vector,
  limit~,
  filter?,
) {
  let hits : Array[Scored] = []
  for entry in self.entries {
    if filter is Some(filter) && !filter.matches(entry.1) {
      continue
    }
    let score = cosine_similarity(vector, entry.2[:])
    hits.push({ document: { ..entry.1, id: Some(entry.0), }, score, })
  }
  rank(hits, limit)
}

///|
pub extend InMemoryVectorStore with VectorStore::{add, delete, search}
