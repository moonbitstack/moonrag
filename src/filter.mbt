// Metadata filtering, expressed as data so it can travel: a store applies it where the documents live
// (in memory, in SQL, in pgvector) instead of the caller re-ranking afterwards. Every store reads the
// same tree, so a filter written for one store means the same in another.

///|
/// How `Compare` orders a metadata number against its operand.
#derive(Eq, Debug)
pub(all) enum Order {
  Less
  AtMost
  AtLeast
  Greater
}

///|
/// A condition on a document's metadata.
///
/// `Equal` matches a whole JSON value, `OneOf` any of a list, `Exists` only that the key is present,
/// and `Compare` a number against an operand. `All` and `Any` nest, `Not` negates. A document whose
/// metadata lacks the key matches nothing except `Not` of a filter it would otherwise fail.
#derive(Eq, Debug)
pub(all) enum Filter {
  Equal(String, Json)
  OneOf(String, Array[Json])
  Exists(String)
  Compare(String, Order, Double)
  All(Array[Filter])
  Any(Array[Filter])
  Not(Filter)
}

///|
/// Whether `document` satisfies the filter.
pub fn Filter::matches(self : Filter, document : Document) -> Bool {
  match self {
    Equal(key, want) =>
      match document.meta.get(key) {
        Some(got) => got == want
        None => false
      }
    OneOf(key, wants) =>
      match document.meta.get(key) {
        Some(got) => wants.iter().any(fn(want) { want == got })
        None => false
      }
    Exists(key) => document.meta.contains(key)
    Compare(key, order, want) =>
      match document.meta.get(key) {
        Some(Json::Number(got, ..)) =>
          match order {
            Less => got < want
            AtMost => got <= want
            AtLeast => got >= want
            Greater => got > want
          }
        Some(_) => false
        None => false
      }
    All(filters) => filters.iter().all(fn(filter) { filter.matches(document) })
    Any(filters) => filters.iter().any(fn(filter) { filter.matches(document) })
    Not(filter) => !filter.matches(document)
  }
}

///|
pub extend Order with Eq::{not_equal, equal}

///|
pub extend Order with Debug::{to_repr}

///|
pub extend Filter with Eq::{not_equal, equal}

///|
pub extend Filter with Debug::{to_repr}
