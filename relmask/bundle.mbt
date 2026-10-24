///|
fn bundle_digest(policy : String, data : String, summary : String) -> String {
  let framed = Json::array([
    Json::string("relmask-bundle-1"),
    Json::string(policy),
    Json::string(data),
    Json::string(summary),
  ]).stringify()
  hex(sha256(@utf8.encode(framed[:])))
}

///|
/// Export an integrity-checked envelope. SHA-256 detects accidental corruption;
/// it does not authenticate the producer or prove that private values were removed.
pub fn CheckedDataset::bundle_json(self : CheckedDataset) -> String {
  let digest = bundle_digest(self.fingerprint, self.encoded, self.report)
  "{\"format\":\"relmask-bundle-1\",\"policy_sha256\":" +
  Json::string(self.fingerprint).stringify() +
  ",\"data\":" +
  Json::string(self.encoded).stringify() +
  ",\"report\":" +
  Json::string(self.report).stringify() +
  ",\"sha256\":" +
  Json::string(digest).stringify() +
  "}"
}

///|
/// Verify the envelope, exact policy fingerprint, counts and all declared
/// constraints. No secret is needed. Changed-cell counts cannot be independently
/// confirmed without original data; this is not a signature verification API.
pub fn Plan::verify_bundle(
  self : Plan,
  source : String,
) -> CheckedDataset raise MaskError {
  // JSON string escaping can expand each input code unit to six code units.
  if source.length() > self.max_input_units * 6 + 100_000 {
    reject("bundle_too_large", "bundle")
  }
  let obj = fields(parse_json(source, "bundle"), "bundle")
  only_keys(
    obj,
    ["format", "policy_sha256", "data", "report", "sha256"],
    "bundle",
  )
  let get = fn(name) raise MaskError {
    text(required(obj, name, "bundle"), "bundle." + name)
  }
  if get("format") != "relmask-bundle-1" {
    reject("bundle_version", "bundle.format")
  }
  let fingerprint = get("policy_sha256")
  if fingerprint != self.fingerprint {
    reject("bundle_policy_mismatch", "bundle.policy_sha256")
  }
  let encoded = get("data")
  let summary = get("report")
  if get("sha256") != bundle_digest(fingerprint, encoded, summary) {
    reject("bundle_digest_mismatch", "bundle.sha256")
  }
  let rows = load(self, encoded)
  validate_rows(self, rows)
  if encoded != encode_rows(self, rows) {
    reject("bundle_data_noncanonical", "bundle.data")
  }
  let summary_fields = fields(
    parse_json(summary, "bundle.report"),
    "bundle.report",
  )
  let changed = integer(
    required(summary_fields, "changed_cells", "bundle.report"),
    "bundle.report.changed_cells",
  )
  let mut cells = 0L
  for ti, table in self.tables {
    cells += rows[ti].length().to_int64() * table.columns.length().to_int64()
  }
  if changed < 0L || changed > cells || changed > 2147483647L {
    reject("bundle_report_mismatch", "bundle.report.changed_cells")
  }
  if summary != report(self, rows, changed.to_int()) {
    reject("bundle_report_mismatch", "bundle.report")
  }
  { encoded, report: summary, fingerprint, }
}
