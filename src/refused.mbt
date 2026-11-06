// One error family for the whole root package: a refusal names the numbers that did not line up, so
// a caller can tell a bad vector from a bad argument without sniffing strings.

///|
/// A request the library will not carry out.
///
/// `Mismatch` is two vectors of different length meeting where one length is needed, `Empty` a blank
/// string where one has to be non-blank, `Exceeded` a number outside the range `limit` bounds,
/// `Malformed` unreadable input at `at`, and `Unsupported` a request this build does not serve.
#derive(Eq, Debug)
pub(all) suberror Refused {
  Mismatch(got~ : Int32, want~ : Int32)
  Empty(what~ : String)
  Exceeded(limit~ : Int32, got~ : Int32)
  Malformed(at~ : Int32, why~ : String)
  Unsupported(what~ : String)
}

///|
pub extend Refused with Eq::{not_equal, equal}

///|
pub extend Refused with Debug::{to_repr}
