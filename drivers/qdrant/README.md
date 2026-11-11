# moonqdrant

A Qdrant vector store for [moonrag](https://moonbitstack.github.io/moonrag/), over its REST API.
Native only: it opens sockets, so it is not built for js or wasm.

```shell
moon add moonbitstack/moonqdrant
```

```moonbit
let store = @moonqdrant.QdrantStore::new("http://127.0.0.1:6333", embedder, dimension=256)
```

It implements moonrag's `VectorStore`. Like the in-memory, SQLite and MySQL stores it recomputes the
cosine in this process and ranks by the same `Filter::matches`, so its results agree with the other
backends rather than trusting the server.

See this store's [page](https://moonbitstack.github.io/moonrag/qdrant.html), the
[guide](https://moonbitstack.github.io/moonrag/guide.html) and the
[API](https://moonbitstack.github.io/moonrag/api.html).
