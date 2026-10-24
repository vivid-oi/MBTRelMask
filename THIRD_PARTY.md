# Sources and licenses

| Resource | Use | License / source |
| --- | --- | --- |
| MoonBit core | JSON parser with duplicate rejection and preserved number representations; collections and UTF-8 | Apache-2.0, https://github.com/moonbitlang/core |
| moonbitlang/async 0.22.5 | Native/moonrun file I/O, runtime exit import binding and development command execution | Apache-2.0, https://github.com/moonbitlang/async |
| Chinook | Complete public example dataset; unchanged source file and retained license | MIT, commit `7f67772503d71ba90f19283c38e93923addb43fa`, https://github.com/lerocha/chinook-database |
| FIPS 180-4 | SHA-256 algorithm and standard constants; implementation written for this package | https://csrc.nist.gov/pubs/fips/180-4/upd1/final |
| RFC 2104 and RFC 4231 | HMAC construction and conformance vectors 1, 2, 6 | RFC 4231 §4 permits use of vectors for conformance testing; https://www.rfc-editor.org/rfc/rfc4231 |

No Greenmask, Presidio, MoonFixture, MoonScrub or LunaSieve implementation or test code is included. They informed the project boundary: existing-data transformation with declared relational invariants, rather than text scanning or synthetic data generation.

The SHA-256 empty/abc/multi-block/million-a digests are standard conformance values. Other boundary fixtures in the tests were constructed for this repository. Passing these vectors is not an independent cryptographic audit.
