///|
/// Deterministically choose count seeds per requested table, then include their
/// relational closure. The seed is public reproducibility input, not a secret.
/// Returned data retains original values; transform before sharing.
pub fn Plan::sample(
  self : Plan,
  source : String,
  request : String,
  seed : String,
  options? : String,
) -> String raise MaskError {
  let rows = load(self, source)
  validate_rows(self, rows)
  if seed.is_empty() || seed.length() > 4096 {
    reject("sample_seed_range", "sample.seed")
  }
  if request.length() > 1_000_000 {
    reject("sample_request_too_large", "sample.request")
  }
  let requested = fields(
    parse_json(request, "sample.request"),
    "sample.request",
  )
  if requested.is_empty() {
    reject("empty_sample_request", "sample.request")
  }
  only_keys(requested, self.tables.map(t => t.name), "sample.request")
  let selected = self.tables.map(_ => [])
  for ti, table in self.tables {
    if requested.get(table.name) is Some(value) {
      let location = "sample.request." + table.name
      let n = integer(value, location)
      if n < 0L {
        reject("sample_count_range", location)
      }
      if n > rows[ti].length().to_int64() {
        reject("sample_population_too_small", location)
      }
      if n == 0L {
        continue
      }
      let count = n.to_int()
      let heap : Array[SampleCandidate] = []
      for ri, row in rows[ti] {
        let key = tuple_key(row, table, table.primary).unwrap()
        let material = Json::array([
          Json::string("relmask-sample-1"),
          Json::string(seed),
          Json::string(table.name),
          Json::string(key),
        ]).stringify()
        let score = hex(sha256(@utf8.encode(material[:])))
        sample_offer(heap, { score, key, row: ri, }, count)
      }
      selected[ti] = heap.map(candidate => candidate.row)
    }
  }
  self.subset_rows(rows, Indexes(selected), options)
}
