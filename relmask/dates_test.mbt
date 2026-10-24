///|
fn date_policy(days : Int32) -> String {
  "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"},{\"name\":\"when\",\"type\":\"text\",\"nullable\":true,\"rule\":{\"shift_days\":" +
  days.to_string() +
  "}}],\"primary\":[\"id\"]}]}"
}

///|
test "equal day shifts preserve date key reference cycles" {
  let plan = @relmask.Plan::parse(
    "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"text\",\"rule\":{\"shift_days\":1}},{\"name\":\"parent\",\"type\":\"text\",\"rule\":{\"shift_days\":1}}],\"primary\":[\"id\"],\"references\":[{\"columns\":[\"parent\"],\"table\":\"t\",\"target\":[\"id\"]}]}]}",
  )
  let out = plan.transform(
    "{\"t\":[{\"id\":\"2024-02-28\",\"parent\":\"2024-02-29\"},{\"id\":\"2024-02-29\",\"parent\":\"2024-02-28\"}]}",
    secret,
  )
  ignore(plan.validate(out.to_json()))
  assert_true(out.to_json().contains("2024-03-01"))
}

///|
test "calendar shift preserves suffix and handles leap and century boundaries" {
  let plan = @relmask.Plan::parse(date_policy(1))
  for
    (old, new) in [
      ("2024-02-28T23:59:59.123456789Z", "2024-02-29T23:59:59.123456789Z"),
      ("1900-02-28", "1900-03-01"),
      ("2000-02-28", "2000-02-29"),
      ("2023-12-31 00:00:00", "2024-01-01 00:00:00"),
    ] {
    let data = "{\"t\":[{\"id\":1,\"when\":" +
      Json::string(old).stringify() +
      "}]}"
    let expected = "{\"t\":[{\"id\":1,\"when\":" +
      Json::string(new).stringify() +
      "}]}"
    let out = plan.transform(data, secret)
    assert_eq(out.to_json(), expected)
    assert_eq(
      @relmask.Plan::parse(date_policy(-1))
      .transform(expected, secret)
      .to_json(),
      data,
    )
    ignore(plan.verify_bundle(out.bundle_json()))
    assert_eq(plan.import_csv(plan.export_csv(expected)), expected)
  }
  assert_eq(
    plan.transform("{\"t\":[{\"id\":1,\"when\":null}]}", secret).to_json(),
    "{\"t\":[{\"id\":1,\"when\":null}]}",
  )
}

///|
test "invalid dates unsupported offsets and date overflows reject then recover" {
  let plan = @relmask.Plan::parse(date_policy(1))
  for
    value in [
      "2023-02-29", "1900-02-29", "0000-01-01", "2024-00-01", "2024-12-00", "2024-01-01T24:00:00",
      "2024-01-01T00:00:60Z", "2024-01-01T00:00:00+08:00", "2024-01-01T00:00:00.",
      "2024-01-01T00:00:00.1234567890Z", "短",
    ] {
    let input = "{\"t\":[{\"id\":1,\"when\":" +
      Json::string(value).stringify() +
      "}]}"
    assert_true(
      error_code(() => ignore(plan.transform(input, secret))) !=
      "unexpected success",
    )
  }
  assert_eq(
    error_code(() => {
      ignore(
        plan.transform("{\"t\":[{\"id\":1,\"when\":\"9999-12-31\"}]}", secret),
      )
    }),
    "date_range",
  )
  let inverse = @relmask.Plan::parse(date_policy(-1))
  assert_eq(
    error_code(() => {
      ignore(
        inverse.transform(
          "{\"t\":[{\"id\":1,\"when\":\"0001-01-01\"}]}", secret,
        ),
      )
    }),
    "date_range",
  )
  ignore(plan.transform("{\"t\":[{\"id\":1,\"when\":\"2024-01-01\"}]}", secret))
}
