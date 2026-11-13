// Indexing is the difference between "embed everything again" and "embed what changed". The indexer
// remembers a content hash per stored id, so a re-run touches only documents whose text or metadata
// moved, and a source that shrank leaves nothing stale behind.

///|
/// What to do about documents that were indexed before and are absent from this run.
pub(all) enum Cleanup {
  /// Delete the ones whose source appears in this run and whose id does not — the file was rewritten.
  Incremental
  /// Delete every one whose id does not appear, whoever its source.
  Full
  /// Delete nothing: the run only adds and updates.
  None
}

///|
/// What one `index` call did.
#derive(Eq, Debug)
pub(all) struct Stats {
  mut added : Int32
  mut updated : Int32
  mut skipped : Int32
  mut deleted : Int32
}

///|
/// Keeps a store and a record of what it holds in step.
///
/// `index` is the only operation: hand it the documents a source produces now, and it adds the new
/// ones, replaces the changed ones, leaves the unchanged ones alone, and — depending on `cleanup` —
/// removes the ones that disappeared.
pub struct Indexer {
  store : &@moonrag.VectorStore
  source_key : String
  mut records : Array[(String, Bytes, String?)]
}

///|
/// An indexer over `store`. `source_key` names the metadata key that identifies where a document came
/// from; the default is `source`, the key every loader writes.
pub fn Indexer::new(
  store : &@moonrag.VectorStore,
  source_key~ : String = "source",
) -> Indexer {
  { store, source_key, records: [], }
}

///|
/// The number of documents this indexer has recorded.
pub fn Indexer::len(self : Indexer) -> Int32 {
  self.records.length()
}

///|
/// The ids the indexer holds, in the order they were first indexed.
pub fn Indexer::ids(self : Indexer) -> Array[String] {
  self.records.map(fn(record) { record.0 })
}

///|
/// The id of a document that did not bring one: derived from its content, so the same document
/// produces the same id on every run and a second pass recognises what it already stored.
fn content_id(hash : Bytes) -> String {
  "doc-" + @base16.encode(hash).exact_view(start=0, end=16).to_owned()
}

///|
/// The metadata a hash covers: everything except the source key, which changes when a file moves
/// without its content changing. Keys are sorted so the hash does not depend on map iteration order.
fn hashable_meta(meta : Map[String, @json.Json], source_key : String) -> String {
  let keys : Array[String] = []
  for key, _ in meta {
    if key != source_key {
      keys.push(key)
    }
  }
  keys.sort()
  let parts : Array[String] = []
  for key in keys {
    match meta.get(key) {
      Some(value) => parts.push(key + "=" + @moonjson.dumps(value))
      None => ()
    }
  }
  parts.join(";")
}

///|
/// The content hash of a document: its text and its metadata, without the source key.
fn content_hash(document : @moonrag.Document, source_key : String) -> Bytes {
  @sha2.hash(
    @utf8.encode(
      document.text + "\u{0}" + hashable_meta(document.meta, source_key),
    ),
  )
}

///|
/// The source a document came from, when its metadata says.
fn source_of(document : @moonrag.Document, source_key : String) -> String? {
  document.str_meta(source_key)
}

///|
/// The record under `id`, if any.
fn Indexer::record_of(self : Indexer, id : String) -> (Bytes, String?)? {
  for record in self.records {
    if record.0 == id {
      return Some((record.1, record.2))
    }
  }
  None
}

///|
fn Indexer::forget(self : Indexer, id : String) -> Unit {
  let kept : Array[(String, Bytes, String?)] = []
  for record in self.records {
    if record.0 != id {
      kept.push(record)
    }
  }
  self.records = kept
}

///|
/// The id `document` is indexed under: its own when it has one, otherwise one derived from its
/// content.
fn assign_id(document : @moonrag.Document, hash : Bytes) -> String {
  match document.id {
    Some(id) => if id == "" { content_id(hash) } else { id }
    None => content_id(hash)
  }
}

///|
/// Bring the store in line with `documents`, returning what changed.
///
/// A document whose id is already indexed with the same content is skipped, so the expensive part —
/// embedding — does not happen twice. A document with the same id and different content replaces the
/// stored one; there is never a second copy of one id.
pub async fn Indexer::index(
  self : Indexer,
  documents : Array[@moonrag.Document],
  cleanup~ : Cleanup = Incremental,
) -> Stats {
  let mut stats : Stats = { added: 0, updated: 0, skipped: 0, deleted: 0, }
  let incoming_ids : Array[String] = []
  let incoming_sources : Array[String] = []
  for document in documents {
    let hash = content_hash(document, self.source_key)
    let id = assign_id(document, hash)
    let source = source_of(document, self.source_key)
    incoming_ids.push(id)
    match source {
      Some(source) =>
        if !incoming_sources.contains(source) {
          incoming_sources.push(source)
        }
      None => ()
    }
    match self.record_of(id) {
      Some((stored_hash, _)) =>
        if stored_hash == hash {
          stats.skipped = stats.skipped + 1
          continue
        } else {
          // The old copy goes first: a store keyed by id would overwrite it anyway, but a store that
          // keys by its own handle would otherwise keep both.
          self.store.delete([id][:])
          let _ = self.store.add([document.with_id(id)])
          self.forget(id)
          self.records.push((id, hash, source))
          stats.updated = stats.updated + 1
        }
      None => {
        let _ = self.store.add([document.with_id(id)])
        self.records.push((id, hash, source))
        stats.added = stats.added + 1
      }
    }
  }
  let stale : Array[String] = []
  for record in self.records {
    if incoming_ids.contains(record.0) {
      continue
    }
    let remove = match cleanup {
      None => false
      Full => true
      Incremental =>
        match record.2 {
          Some(source) => incoming_sources.contains(source)
          None => false
        }
    }
    if remove {
      stale.push(record.0)
    }
  }
  if stale.length() > 0 {
    self.store.delete(stale[:])
    for id in stale {
      self.forget(id)
    }
    stats = { ..stats, deleted: stale.length(), }
  }
  stats
}

///|
pub extend Stats with Eq::{not_equal, equal}

///|
pub extend Stats with Debug::{to_repr}
