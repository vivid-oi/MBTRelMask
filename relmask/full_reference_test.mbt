///|
test "MATCH FULL accepts complete keys or all null and rejects partial null" {
  let plan = @relmask.Plan::parse(
    substitute(
      compound_policy(),
      "\"target\":[\"tenant\",\"account\"]",
      "\"target\":[\"tenant\",\"account\"],\"match\":\"full\"",
    ),
  )
  assert_eq(
    error_code(() => ignore(plan.validate(compound_data()))),
    "partial_null_reference",
  )
  assert_eq(
    error_code(() => ignore(plan.subset(compound_data(), "{}"))),
    "partial_null_reference",
  )
  let data = substitute(
    compound_data(),
    "\"tenant\":null,\"account\":999",
    "\"tenant\":null,\"account\":null",
  )
  let data = substitute(
    data, "\"tenant\":\"missing\",\"account\":null", "\"tenant\":null,\"account\":null",
  )
  let masked = plan.transform(data, secret)
  ignore(plan.verify_bundle(masked.bundle_json()))
  assert_eq(
    plan.import_csv(plan.export_csv(masked.to_json())),
    masked.to_json(),
  )
  let partial_csv = plan.export_csv(data)
  partial_csv["events"] = partial_csv["events"].replace(
    old="2,\\N,\\N",
    new="2,\\N,7",
  )
  assert_eq(
    error_code(() => ignore(plan.import_csv(partial_csv))),
    "partial_null_reference",
  )
}

///|
test "reference match syntax is strict and SIMPLE preserves prior behavior" {
  let full = substitute(
    compound_policy(),
    "\"target\":[\"tenant\",\"account\"]",
    "\"target\":[\"tenant\",\"account\"],\"match\":\"full\"",
  )
  assert_eq(
    error_code(() => {
      ignore(
        @relmask.Plan::parse(
          substitute(full, "\"match\":\"full\"", "\"match\":\"partial\""),
        ),
      )
    }),
    "unsupported_reference_match",
  )
  let simple = @relmask.Plan::parse(
    substitute(full, "\"match\":\"full\"", "\"match\":\"simple\""),
  )
  assert_eq(
    simple.transform(compound_data(), secret).to_json(),
    @relmask.Plan::parse(compound_policy())
    .transform(compound_data(), secret)
    .to_json(),
  )
}
