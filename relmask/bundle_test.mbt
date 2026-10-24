///|
test "bundle round trip preserves exact data and report without a secret" {
  let plan = @relmask.Plan::parse(policy())
  let output = plan.transform(dataset(), secret)
  let bundle = output.bundle_json()
  let restored = plan.verify_bundle(bundle)
  assert_eq(restored.to_json(), output.to_json())
  assert_eq(restored.report_json(), output.report_json())
  assert_eq(restored.bundle_json(), bundle)
  assert_true(!bundle.contains(secret))
  assert_true(!bundle.contains("private"))
  assert_true(restored.to_json().contains("1e400"))
  assert_true(restored.to_json().contains("12.345678901234567890"))
  assert_eq(
    error_code(() => {
      ignore(@relmask.Plan::parse(policy() + " ").verify_bundle(bundle))
    }),
    "bundle_policy_mismatch",
  )
}

///|
test "bundle rejects corruption unknown format fields and truncated input then recovers" {
  let plan = @relmask.Plan::parse(policy())
  let bundle = plan.transform(dataset(), secret).bundle_json()
  assert_eq(
    error_code(() => {
      ignore(plan.verify_bundle(substitute(bundle, "1e400", "2e400")))
    }),
    "bundle_digest_mismatch",
  )
  assert_eq(
    error_code(() => {
      ignore(
        plan.verify_bundle(
          substitute(bundle, "relmask-bundle-1", "relmask-bundle-2"),
        ),
      )
    }),
    "bundle_version",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.verify_bundle("{\"extra\":true," + bundle[1:].to_owned()))
    }),
    "unknown_option",
  )
  for i in 0..<bundle.length() {
    assert_true(
      error_code(() => ignore(plan.verify_bundle(bundle[:i].to_owned()))) !=
      "unexpected success",
    )
  }
  assert_eq(plan.verify_bundle(bundle).bundle_json(), bundle)
}

///|
test "expanded output exceeding its policy budget is rejected without partial data" {
  let p = "{\"max_input_units\":60,\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"text\",\"rule\":{\"token\":{\"domain\":\"d\",\"prefix\":\"abcdefghijklmnopqrstuvwxyz\"}}}],\"primary\":[\"id\"]}]}"
  let plan = @relmask.Plan::parse(p)
  assert_eq(
    error_code(() => ignore(plan.transform("{\"t\":[{\"id\":\"x\"}]}", secret))),
    "output_too_large",
  )
  ignore(plan.transform("{\"t\":[]}", secret))
}

///|
test "bundle round trips generated boundary-valued batches" {
  let p = "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"},{\"name\":\"value\",\"type\":\"decimal\",\"rule\":\"keep\"}],\"primary\":[\"id\"]}]}"
  let plan = @relmask.Plan::parse(p)
  for n in 0..<=24 {
    let rows : Array[String] = []
    for i in 0..<n {
      rows.push(
        "{\"id\":" +
        (-9223372036854775808L + i.to_int64()).to_string() +
        ",\"value\":9.999999999999999999e399}",
      )
    }
    let data = "{\"t\":[" + rows.join(",") + "]}"
    let result = plan.transform(data, secret)
    let restored = plan.verify_bundle(result.bundle_json())
    assert_eq(restored.to_json(), data)
    assert_eq(restored.bundle_json(), result.bundle_json())
  }
}
