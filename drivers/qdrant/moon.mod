name = "moonbitstack/moonqdrant"

version = "0.0.1"

readme = "README.md"

license = "Apache-2.0"

repository = "https://github.com/moonbitstack/moonrag"

keywords = [ "moonrag", "qdrant", "vector-store", "vector-database", "moonbit" ]

description = "A Qdrant vector store for moonbitstack/moonrag, over Qdrant's REST API."

source = "src"

preferred_target = "native"

import {
  "moonbitstack/moonrag@0.2.0",
  "moonbitstack/moonjson@0.5.0",
  "moonbitlang/async@0.22.5",
}
