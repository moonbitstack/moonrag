name = "moonbitstack/moonrag-integration"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonrag"

license = "Apache-2.0"

keywords = [
  "moonrag",
  "vector-store",
  "sqlite",
  "postgresql",
  "pgvector",
  "mysql",
  "mysql9",
  "ms9vc",
  "qdrant",
  "chroma",
  "weaviate",
  "milvus",
  "integration",
  "moonbit",
]

description = "The vector-store standard cases against real backends: the in-memory store, SQLite, PostgreSQL with pgvector, and MySQL 9."

source = "src"

import {
  "moonbitlang/async@0.22.5",
  "moonbitstack/moondb@0.3.0",
  "moonbitstack/moonpostgres@0.7.0",
  "moonbitstack/moonrag@0.2.0",
  "moonbitstack/moonqdrant@0.0.1",
  "moonbitstack/moonchroma@0.0.1",
  "moonbitstack/moonweavte@0.0.1",
  "moonbitstack/moonmilvus@0.0.1",
  "moonbitstack/moonsqlite@0.4.0",
  "moonbitstack/moonmysql@0.8.0",
}
