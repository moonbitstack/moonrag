// `moondb` has two driver contracts: the blocking one, and the asynchronous one this store is written
// against. A backend whose call returns when the row does — SQLite above all — implements the
// blocking one, and needs no thread park to be used here; this adapter is the whole of that bridge.

///|
/// An `AsyncDriver` over a driver that blocks.
///
/// SQLite reads a local file: there is nothing to wait for, so wrapping it in an async contract costs
/// one trait implementation and no threads. A network backend should implement `AsyncDriver` itself,
/// where the wait is real.
pub struct BlockingDriver[T] {
  inner : T
}

///|
/// `driver`, presented as an asynchronous driver.
pub fn[T] BlockingDriver::new(driver : T) -> BlockingDriver[T] {
  { inner: driver, }
}

///|
/// The driver this adapter wraps.
pub fn[T] BlockingDriver::inner(self : BlockingDriver[T]) -> T {
  self.inner
}

///|
pub impl[T : @moondb.Driver] @moondb.AsyncDriver for BlockingDriver[T] with fn execute(
  self : BlockingDriver[T],
  sql : String,
  params : Array[@moondb.Value],
) -> @moondb.ExecResult raise @moondb.DbError {
  self.inner.execute(sql, params)
}

///|
pub impl[T : @moondb.Driver] @moondb.AsyncDriver for BlockingDriver[T] with fn query(
  self : BlockingDriver[T],
  sql : String,
  params : Array[@moondb.Value],
) -> Array[@moondb.Row] raise @moondb.DbError {
  self.inner.query(sql, params)
}

///|
pub impl[T : @moondb.Driver] @moondb.AsyncDriver for BlockingDriver[T] with fn begin(
  self : BlockingDriver[T],
) -> Unit raise @moondb.DbError {
  self.inner.begin()
}

///|
pub impl[T : @moondb.Driver] @moondb.AsyncDriver for BlockingDriver[T] with fn commit(
  self : BlockingDriver[T],
) -> Unit raise @moondb.DbError {
  self.inner.commit()
}

///|
pub impl[T : @moondb.Driver] @moondb.AsyncDriver for BlockingDriver[T] with fn rollback(
  self : BlockingDriver[T],
) -> Unit raise @moondb.DbError {
  self.inner.rollback()
}

///|
pub impl[T : @moondb.Driver] @moondb.AsyncDriver for BlockingDriver[T] with fn close(
  self : BlockingDriver[T],
) -> Unit {
  self.inner.close()
}

///|
pub impl[T : @moondb.Driver] @moondb.AsyncDriver for BlockingDriver[T] with fn dialect(
  self : BlockingDriver[T],
) -> @moondb.Dialect {
  self.inner.dialect()
}

///|
pub impl[T : @moondb.Driver] @moondb.AsyncDriver for BlockingDriver[T] with fn capabilities(
  self : BlockingDriver[T],
) -> @moondb.Capabilities {
  self.inner.capabilities()
}

///|
pub impl[T : @moondb.Driver] @moondb.AsyncDriver for BlockingDriver[T] with fn ping(
  self : BlockingDriver[T],
) -> Bool {
  self.inner.ping()
}

///|
pub impl[T : @moondb.Driver] @moondb.AsyncDriver for BlockingDriver[T] with fn query_stream(
  self : BlockingDriver[T],
  sql : String,
  params : Array[@moondb.Value],
) -> &@moondb.AsyncCursor raise @moondb.DbError {
  let _ = (self, sql, params)
  raise @moondb.DbError::QueryError(
    "a blocking driver does not stream asynchronously",
  )
}

///|
pub extend BlockingDriver with @moondb.AsyncDriver::{
  execute,
  begin,
  ping,
  close,
  query_stream,
  commit,
  prepare,
  query,
  rollback,
  capabilities,
  dialect,
}
