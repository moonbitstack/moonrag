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
  "integration",
  "moonbit",
]

description = "The vector-store standard cases against real backends: the in-memory store, SQLite, PostgreSQL with pgvector, and MySQL 9."

source = "src"

import {
  "moonbitlang/async@0.22.5",
  "moonbitstack/moondb@0.2.8",
  "moonbitstack/moonpostgres@0.6.10",
  "moonbitstack/moonrag@0.1.1",
  "moonbitstack/moonsqlite@0.3.6",
  "moonbitstack/moonmysql@0.7.11",
}
