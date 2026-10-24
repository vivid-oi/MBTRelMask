///|
test "recomputed checksums cannot bypass relation or report validation" {
  let policy = "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"}],\"primary\":[\"id\"]}]}"
  let plan = Plan::parse(policy)
  let result = plan.transform(
    "{\"t\":[{\"id\":1}]}", "test-key-32-bytes-for-relmask-suite",
  )
  let spaced : CheckedDataset = {
    encoded: "{ \"t\" : [{\"id\":1}] }",
    report: result.report,
    fingerprint: result.fingerprint,
  }
  try {
    ignore(plan.verify_bundle(spaced.bundle_json()))
    fail("accepted noncanonical data")
  } catch {
    Invalid(code~, ..) => assert_eq(code, "bundle_data_noncanonical")
    _ => fail("unexpected error")
  }
  let invalid : CheckedDataset = {
    encoded: "{\"t\":[{\"id\":1},{\"id\":1}]}",
    report: result.report,
    fingerprint: result.fingerprint,
  }
  try {
    ignore(plan.verify_bundle(invalid.bundle_json()))
    fail("accepted duplicate")
  } catch {
    Invalid(code~, ..) => assert_eq(code, "duplicate_key")
    _ => fail("unexpected error")
  }
  let report = "{\"algorithm\":\"relmask-1\",\"constraints\":\"passed\",\"changed_cells\":0,\"tables\":[{\"name\":\"t\",\"rows\":9}]}"
  let invalid : CheckedDataset = {
    encoded: result.encoded,
    report,
    fingerprint: result.fingerprint,
  }
  try {
    ignore(plan.verify_bundle(invalid.bundle_json()))
    fail("accepted wrong counts")
  } catch {
    Invalid(code~, ..) => assert_eq(code, "bundle_report_mismatch")
    _ => fail("unexpected error")
  }
  let invalid : CheckedDataset = {
    encoded: result.encoded,
    report: report.replace(old="\"changed_cells\":0", new="\"changed_cells\":2"),
    fingerprint: result.fingerprint,
  }
  try {
    ignore(plan.verify_bundle(invalid.bundle_json()))
    fail("accepted changed count")
  } catch {
    Invalid(code~, ..) => assert_eq(code, "bundle_report_mismatch")
    _ => fail("unexpected error")
  }
}
