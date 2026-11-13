// Metadata filters as SQL. Only PostgreSQL needs this: pgvector's `LIMIT` runs on the server, so the
// filter has to run there too or a narrow filter over a wide table would come back short. SQLite has
// no distance operator, its rows travel whole anyway, and its filter is `Filter::matches` — one
// definition of a match, applied where the data is or after it arrives.

///|
/// A statement under construction: the values bound so far and the dialect spelling their
/// placeholders.
priv struct Binder {
  dialect : @moondb.Dialect
  values : Array[@moondb.Value]
}

///|
fn Binder::new(dialect : @moondb.Dialect) -> Binder {
  { dialect, values: [], }
}

///|
/// Bind `value`, returning the placeholder that refers to it.
fn Binder::bind(self : Binder, value : @moondb.Value) -> String {
  self.values.push(value)
  self.dialect.placeholder(self.values.length())
}

///|
/// The metadata column. Quoted, because the table is quoted and a dialog either quotes both or
/// neither.
fn meta_column() -> String {
  "\"meta\""
}

///|
/// `filter` as a `WHERE` clause body, binding every value it needs into `binder`. An empty `All`
/// matches everything and an empty `Any` nothing, which is what the tree means in memory.
fn filter_sql(filter : @moonrag.Filter, binder : Binder) -> String raise {
  match filter {
    @moonrag.Filter::Equal(key, want) => {
      let at = binder.bind(@moondb.Value::Text(key))
      let value = binder.bind(@moondb.Value::Json(@moonjson.dumps(want)))
      "(" + meta_column() + " -> " + at + ") = " + value + "::jsonb"
    }
    @moonrag.Filter::OneOf(key, wants) => {
      if wants.length() == 0 {
        return "FALSE"
      }
      let at = binder.bind(@moondb.Value::Text(key))
      let parts : Array[String] = []
      for want in wants {
        let value = binder.bind(@moondb.Value::Json(@moonjson.dumps(want)))
        parts.push(value + "::jsonb")
      }
      "(" + meta_column() + " -> " + at + ") IN (" + parts.join(", ") + ")"
    }
    @moonrag.Filter::Exists(key) => {
      let at = binder.bind(@moondb.Value::Text(key))
      "jsonb_exists(" + meta_column() + ", " + at + ")"
    }
    @moonrag.Filter::Compare(key, order, want) => {
      let at = binder.bind(@moondb.Value::Text(key))
      let value = binder.bind(@moondb.Value::Double(want))
      let operator = match order {
        @moonrag.Order::Less => "<"
        @moonrag.Order::AtMost => "<="
        @moonrag.Order::AtLeast => ">="
        @moonrag.Order::Greater => ">"
      }
      // A key holding a string must not match a numeric comparison, and casting it would raise
      // instead of returning false: the type check comes first.
      "(jsonb_typeof(" +
      meta_column() +
      " -> " +
      at +
      ") = 'number' AND (" +
      meta_column() +
      " ->> " +
      at +
      ")::numeric " +
      operator +
      " " +
      value +
      ")"
    }
    @moonrag.Filter::All(filters) =>
      join_filters(filters, " AND ", "TRUE", binder)
    @moonrag.Filter::Any(filters) =>
      join_filters(filters, " OR ", "FALSE", binder)
    @moonrag.Filter::Not(inner) => "(NOT " + filter_sql(inner, binder) + ")"
  }
}

///|
/// `filters` joined by `operator`, or `empty` when there are none.
fn join_filters(
  filters : Array[@moonrag.Filter],
  operator : String,
  empty : String,
  binder : Binder,
) -> String raise {
  if filters.length() == 0 {
    return empty
  }
  let parts : Array[String] = []
  for filter in filters {
    parts.push(filter_sql(filter, binder))
  }
  "(" + parts.join(operator) + ")"
}
