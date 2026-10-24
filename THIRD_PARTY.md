# Sources and licenses

| Resource | Use | License / source |
| --- | --- | --- |
| PostgreSQL 18 | SQL type/identifier/constraint semantics and real database validation; exporter and probe tests written here | PostgreSQL License, https://www.postgresql.org/about/licence/ ; numeric limits https://www.postgresql.org/docs/18/datatype-numeric.html ; identifiers https://www.postgresql.org/docs/18/sql-syntax-lexical.html ; no implementation or example text copied |
| Official postgres Docker image / EDB Windows binaries | CI PostgreSQL 18 service / local isolated PostgreSQL 18.6 validation; not redistributed here | PostgreSQL and bundled components retain their respective licenses; https://hub.docker.com/_/postgres ; https://www.enterprisedb.com/download-postgresql-binaries |
| RFC 3339 | Date/time component format reference for a documented strict subset; Gregorian arithmetic and fixtures written here | No implementation or example text copied; https://www.rfc-editor.org/rfc/rfc3339 |
| MoonBit core | JSON parser with duplicate rejection and preserved number representations; collections and UTF-8 | Apache-2.0, https://github.com/moonbitlang/core |
| moonbitlang/async 0.22.5 | Native/moonrun file I/O, runtime exit import binding and development command execution | Apache-2.0, https://github.com/moonbitlang/async |
| Chinook | Complete public example dataset; unchanged source file and retained license | MIT, commit `7f67772503d71ba90f19283c38e93923addb43fa`, https://github.com/lerocha/chinook-database |
| FIPS 180-4 | SHA-256 algorithm and standard constants; implementation written for this package | https://csrc.nist.gov/pubs/fips/180-4/upd1/final |
| RFC 2104 and RFC 4231 | HMAC construction and conformance vectors 1, 2, 6 | RFC 4231 §4 permits use of vectors for conformance testing; https://www.rfc-editor.org/rfc/rfc4231 |
| RFC 4180 | Reference for comma, quote and record boundaries; private CSV reader and test fixtures written for this package | No implementation or example text copied; https://www.rfc-editor.org/rfc/rfc4180 |
| PostgreSQL foreign-key documentation | Semantic reference for MATCH SIMPLE / MATCH FULL; tests constructed here | No implementation or example text copied; https://www.postgresql.org/docs/current/ddl-constraints.html#DDL-CONSTRAINTS-FK |

NyaCSV's public API was inspected as ecosystem context (Apache-2.0, https://github.com/moonbit-community/NyaCSV). No NyaCSV code or tests are included. RelMask's private reader retains quote metadata for its explicit null marker; its public CSV boundary is a typed, relational dataset workflow.

No Greenmask, Presidio, MoonFixture, MoonScrub or LunaSieve implementation or test code is included. They informed the project boundary: existing-data transformation with declared relational invariants, rather than text scanning or synthetic data generation.

The SHA-256 empty/abc/multi-block/million-a digests are standard conformance values. Other boundary fixtures in the tests were constructed for this repository. Passing these vectors is not an independent cryptographic audit.

The private decimal predicate comparator, signed exponent digit arithmetic and associated tests were written in this repository. No external decimal implementation or test corpus is included. It uses the existing MoonBit core JSON number representations; its normalization is used only for comparison and does not rewrite dataset values.

Deterministic sampling reuses this repository's SHA-256 and relational closure implementations. The bounded max heap, sorting reference tests and public request fixtures were written here; no external sampler or sampling test corpus is included. The Chinook workflow retains the existing upstream fixture and its MIT notice.
