# Examples

| # | Example | What it shows |
|:--:|:--|:--|
| 01 | [`ingest`](01-ingest/) | the whole path: a page split by heading and a note split by paragraph, indexed, searched, then indexed again with nothing to do |
| 02 | [`store`](02-store/) | the store on its own: rank by similarity, filter by metadata, rerank with MMR, delete |
| 03 | [`files`](03-files/) | the file front end over a real temporary directory |

Run one with `moon run src/examples/01-ingest --target native`. The embedder in every example is the
deterministic hashing one, so the output is the same on every machine and no model is called.
