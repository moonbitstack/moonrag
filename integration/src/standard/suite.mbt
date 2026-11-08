// The standard cases for a `VectorStore`, in the order a reader would check them: write, read, rank,
// filter, delete, update. Each case starts from a fresh store, so a failure names one behaviour
// rather than the wreckage of the case before it.

///|
/// A case that did not hold, with what it expected and what it saw.
priv suberror Failed {
  Failed(String)
}

///|
/// Record a mismatch as a readable sentence instead of a bare boolean.
fn expect_string(got : String, want : String, what : String) -> Unit raise Failed {
  if got != want {
    raise Failed(what + ": want [" + want + "], got [" + got + "]")
  }
}

///|
fn expect_int(got : Int32, want : Int32, what : String) -> Unit raise Failed {
  if got != want {
    raise Failed(what + ": want " + want.to_string() + ", got " + got.to_string())
  }
}

///|
fn expect_strings(
  got : Array[String],
  want : Array[String],
  what : String,
) -> Unit raise Failed {
  if got.length() != want.length() {
    raise Failed(
      what +
      ": want " +
      want.length().to_string() +
      " entries, got " +
      got.length().to_string(),
    )
  }
  for i, value in got {
    if value != want[i] {
      raise Failed(
        what + ": entry " + i.to_string() + ": want [" + want[i] + "], got [" + value + "]",
      )
    }
  }
}

///|
fn expect_true(condition : Bool, what : String) -> Unit raise Failed {
  if !condition {
    raise Failed(what)
  }
}

///|
/// The bookkeeping around one run: the embedder every case shares, the way to get a fresh store, and
/// the failures collected so far.
pub struct Suite {
  embedder : &@moonrag.Embedder
  fresh : async () -> &@moonrag.VectorStore raise
  failures : Array[String]
  mut current : String
}

///|
async fn Suite::case(
  self : Suite,
  name : String,
  body : async () -> Unit raise,
) -> Unit {
  self.current = name
  let outcome = try {
    body()
    None
  } catch {
    Failed(reason) => Some(reason)
    error => Some(error.to_string())
  }
  match outcome {
    Some(reason) => self.failures.push(name + ": " + reason)
    None => ()
  }
}

///|
/// The sorted ids of `hits`: a ranking is compared as a set where the order is the backend's business.
fn sorted_ids(hits : Array[@moonrag.Scored]) -> Array[String] {
  let ids = hits.map(fn(hit) { hit.document.id.unwrap_or("") })
  ids.sort()
  ids
}

///|
/// The metadata filters the filter case runs, each against the in-memory store as the reference.
fn filters() -> Array[(String, @moonrag.Filter)] {
  [
    (
      "equal",
      @moonrag.Filter::Equal("topic", @json.Json::string("sea")),
    ),
    (
      "one of",
      @moonrag.Filter::OneOf("topic", [
        @json.Json::string("sea"),
        @json.Json::string("land"),
      ]),
    ),
    ("exists", @moonrag.Filter::Exists("tag")),
    (
      "compare at least",
      @moonrag.Filter::Compare("year", @moonrag.Order::AtLeast, 2024.0),
    ),
    (
      "all",
      @moonrag.Filter::All([
        @moonrag.Filter::Equal("topic", @json.Json::string("sea")),
        @moonrag.Filter::Compare("year", @moonrag.Order::AtLeast, 2020.0),
      ]),
    ),
    (
      "any",
      @moonrag.Filter::Any([
        @moonrag.Filter::Exists("tag"),
        @moonrag.Filter::Compare("year", @moonrag.Order::Less, 2020.0),
      ]),
    ),
    ("not", @moonrag.Filter::Not(@moonrag.Filter::Exists("tag"))),
    (
      "equal on a key nothing has",
      @moonrag.Filter::Equal("topic", @json.Json::string("air")),
    ),
    (
      "a number compared against a string",
      @moonrag.Filter::Compare("topic", @moonrag.Order::Greater, 0.0),
    ),
  ]
}

///|
/// Run every standard case, returning one line per failure — empty when the backend behaves.
pub async fn check(
  embedder : &@moonrag.Embedder,
  fresh : async () -> &@moonrag.VectorStore raise,
) -> Array[String] {
  let suite : Suite = { embedder, fresh, failures: [], current: "", }

  suite.case("add returns an id for every document", async fn() {
    let store = (suite.fresh)()
    let ids = store.add(corpus())
    expect_int(ids.length(), 4, "ids")
    expect_true(ids.all(fn(id) { id != "" }), "an id is blank")
    let distinct = ids.copy()
    distinct.sort()
    for i = 1; i < distinct.length(); i = i + 1 {
      expect_true(distinct[i] != distinct[i - 1], "two documents share an id")
    }
  })

  suite.case("search returns the documents the query is about", async fn() {
    let store = (suite.fresh)()
    let _ = store.add(corpus())
    let query = (suite.embedder).embed([sea_query()])[0]
    let hits = store.search(query[:], limit=2)
    expect_int(hits.length(), 2, "hits")
    for hit in hits {
      expect_string(
        hit.document.str_meta("topic").unwrap_or(""),
        "sea",
        "the topic of [" + hit.document.text + "]",
      )
    }
  })

  suite.case("every hit carries its score, and scores descend", async fn() {
    let store = (suite.fresh)()
    let _ = store.add(corpus())
    let query = (suite.embedder).embed([sea_query()])[0]
    let hits = store.search(query[:], limit=4)
    for hit in hits {
      expect_true(hit.score <= 1.0, "a score above one")
      expect_true(hit.score >= -1.0, "a score below minus one")
    }
    for i = 1; i < hits.length(); i = i + 1 {
      expect_true(hits[i - 1].score >= hits[i].score, "scores are not descending")
    }
  })

  suite.case("the limit is honoured, and a limit above the corpus returns the corpus", async fn() {
    let store = (suite.fresh)()
    let _ = store.add(corpus())
    let query = (suite.embedder).embed([sea_query()])[0]
    expect_int(store.search(query[:], limit=1).length(), 1, "limit 1")
    expect_int(store.search(query[:], limit=10).length(), 4, "limit 10")
    expect_int(store.search(query[:], limit=0).length(), 0, "limit 0")
  })

  suite.case("an empty store returns nothing", async fn() {
    let store = (suite.fresh)()
    let query = (suite.embedder).embed([sea_query()])[0]
    expect_int(store.search(query[:], limit=5).length(), 0, "hits")
  })

  suite.case("ids come back with the hits", async fn() {
    let store = (suite.fresh)()
    let _ = store.add(corpus_with_ids())
    let query = (suite.embedder).embed([sea_query()])[0]
    let hits = store.search(query[:], limit=4)
    expect_strings(
      sorted_ids(hits),
      ["doc-0", "doc-1", "doc-2", "doc-3"],
      "ids",
    )
  })

  suite.case("a document can be deleted by id", async fn() {
    let store = (suite.fresh)()
    let ids = store.add(corpus_with_ids())
    store.delete([ids[1]][:])
    let query = (suite.embedder).embed([land_query()])[0]
    let hits = store.search(query[:], limit=10)
    expect_int(hits.length(), 3, "hits")
    expect_true(
      hits.all(fn(hit) { hit.document.id != Some(ids[1]) }),
      "the deleted document came back",
    )
  })

  suite.case("adding an id twice replaces the document", async fn() {
    let store = (suite.fresh)()
    let _ = store.add([
      @moonrag.Document::new("the old text", id="same"),
    ])
    let _ = store.add([
      @moonrag.Document::new("the new text", id="same"),
    ])
    let query = (suite.embedder).embed(["the new text"])[0]
    let hits = store.search(query[:], limit=10)
    expect_int(hits.length(), 1, "hits")
    expect_string(hits[0].document.text, "the new text", "the surviving text")
  })

  suite.case("a metadata filter narrows the search, as it does in memory", async fn() {
    let store = (suite.fresh)()
    let _ = store.add(corpus_with_ids())
    let reference = @moonrag.InMemoryVectorStore::new(suite.embedder)
    let _ = reference.add(corpus_with_ids())
    let query = (suite.embedder).embed([sea_query()])[0]
    for entry in filters() {
      let name = entry.0
      let filter = entry.1
      let got = store.search(query[:], limit=10, filter=filter)
      let want = reference.search(query[:], limit=10, filter=filter)
      expect_strings(sorted_ids(got), sorted_ids(want), "filter " + name)
    }
  })

  suite.case("a vector of the wrong width is refused", async fn() {
    let store = (suite.fresh)()
    let _ = store.add(corpus())
    let outcome = try {
      let _ = store.search([1.0][:], limit=1)
      "accepted"
    } catch {
      @moonrag.Mismatch(..) => "refused"
      _ => "other"
    }
    expect_string(outcome, "refused", "a one-component query")
  })

  suite.case("the order documents arrive in does not change the ranking", async fn() {
    let forward = (suite.fresh)()
    let _ = forward.add(corpus_with_ids())
    let backward = (suite.fresh)()
    let reversed = corpus_with_ids().rev()
    let _ = backward.add(reversed)
    let query = (suite.embedder).embed([land_query()])[0]
    let left = forward.search(query[:], limit=4).map(fn(hit) {
      hit.document.text
    })
    let right = backward.search(query[:], limit=4).map(fn(hit) {
      hit.document.text
    })
    expect_strings(left, right, "the ranking")
  })

  suite.failures
}
