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
  "integration",
  "moonbit",
]

description = "The vector-store standard cases against real backends: the in-memory store, SQLite, and PostgreSQL with pgvector."

source = "src"

import {
  "moonbitlang/async@0.22.5",
  "moonbitstack/moondb@0.2.7",
  "moonbitstack/moonpostgres@0.6.10",
  "moonbitstack/moonrag@0.1.0",
  "moonbitstack/moonsqlite@0.3.6",
}
