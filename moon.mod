name = "moonbitstack/moonrag"

version = "0.2.0"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonrag"

license = "Apache-2.0"

keywords = [
  "rag",
  "retrieval",
  "retrieval-augmented-generation",
  "vector",
  "vector-store",
  "vector-search",
  "vector-database",
  "embeddings",
  "embedding-store",
  "similarity-search",
  "semantic-search",
  "cosine-similarity",
  "euclidean-distance",
  "mmr",
  "maximal-marginal-relevance",
  "retriever",
  "document",
  "document-loader",
  "document-splitting",
  "text-splitter",
  "chunking",
  "chunk",
  "recursive-splitter",
  "token-splitter",
  "markdown-splitter",
  "heading-splitter",
  "html-splitter",
  "markdown",
  "csv",
  "json",
  "html",
  "sql",
  "sqlite",
  "pgvector",
  "mysql",
  "mysql9",
  "qdrant",
  "chroma",
  "weaviate",
  "milvus",
  "vector-type",
  "postgresql",
  "hnsw",
  "indexing",
  "incremental-index",
  "knowledge-base",
  "context-window",
  "async",
  "moonbit",
]

description = "Documents, splitting, vector stores and retrieval for MoonBit. Embeddings come through a contract, so no model is needed."

source = "src"

import {
  "moonbitlang/async@0.22.5",
  "moonbitstack/moondb@0.3.0",
  "moonbitstack/moonmd@0.2.0",
  "moonbitstack/moonxml@0.2.0",
  "moonbitstack/mooncrypt@0.5.0",
  "moonbitstack/moonbase@0.5.0",
  "moonbitstack/moonjson@0.5.0",
}
