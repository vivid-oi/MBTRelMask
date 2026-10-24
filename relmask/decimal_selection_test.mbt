///|
fn decimal_policy() -> String {
  (
    #|{"tables":[{"name":"t","columns":[{"name":"id","type":"integer","rule":"keep"},{"name":"value","type":"decimal","nullable":true,"rule":"keep"}],"primary":["id"]}]}
  )
}

///|
test "decimal predicates distinguish adjacent precision and preserve source lexemes" {
  let plan = @relmask.Plan::parse(decimal_policy())
  let a = "{\"id\":1,\"value\":9007199254740993.00000000000000000001}"
  let b = "{\"id\":2,\"value\":9007199254740993.00000000000000000002}"
  let data = "{\"t\":[" + a + "," + b + "]}"
  let filter = "{\"t\":[{\"value\":{\"gt\":9007199254740993.00000000000000000001,\"lte\":9007199254740993.00000000000000000002}}]}"
  assert_eq(plan.subset_where(data, filter), "{\"t\":[" + b + "]}")
  assert_eq(
    plan.subset_where(
      data, "{\"t\":[{\"value\":{\"eq\":900719925474099300000000000000000001e-20}}]}",
    ),
    "{\"t\":[" + a + "]}",
  )
  assert_eq(
    plan.subset_where(
      data, "{\"t\":[{\"value\":{\"neq\":9007199254740993.00000000000000000001}}]}",
    ),
    "{\"t\":[" + b + "]}",
  )
}

///|
test "decimal equality accepts equivalent spellings but output retains every spelling" {
  let plan = @relmask.Plan::parse(decimal_policy())
  let data = "{\"t\":[{\"id\":1,\"value\":1e400},{\"id\":2,\"value\":10e399},{\"id\":3,\"value\":0.01e402},{\"id\":4,\"value\":-0.000},{\"id\":5,\"value\":0e99999999999999999999},{\"id\":6,\"value\":null}]}"
  assert_eq(
    plan.subset_where(data, "{\"t\":[{\"value\":{\"eq\":1e+0400}}]}"),
    "{\"t\":[{\"id\":1,\"value\":1e400},{\"id\":2,\"value\":10e399},{\"id\":3,\"value\":0.01e402}]}",
  )
  assert_eq(
    plan.subset_where(data, "{\"t\":[{\"value\":{\"eq\":0}}]}"),
    "{\"t\":[{\"id\":4,\"value\":-0.000},{\"id\":5,\"value\":0e99999999999999999999}]}",
  )
  assert_eq(
    plan.subset_where(data, "{\"t\":[{\"value\":{\"eq\":null}}]}"),
    "{\"t\":[{\"id\":6,\"value\":null}]}",
  )
  let checked = plan.transform(data, secret)
  assert_eq(plan.verify_bundle(checked.bundle_json()).to_json(), data)
}

///|
test "decimal predicates compare unbounded exponents and reject coercions" {
  let plan = @relmask.Plan::parse(decimal_policy())
  let data = "{\"t\":[{\"id\":1,\"value\":1e9223372036854775808},{\"id\":2,\"value\":9e9223372036854775807},{\"id\":3,\"value\":1e-9223372036854775808}]}"
  assert_eq(
    plan.subset_where(
      data, "{\"t\":[{\"value\":{\"gte\":1e9223372036854775808}}]}",
    ),
    "{\"t\":[{\"id\":1,\"value\":1e9223372036854775808}]}",
  )
  assert_eq(
    plan.subset_where(
      data, "{\"t\":[{\"value\":{\"lt\":1e-9223372036854775807}}]}",
    ),
    "{\"t\":[{\"id\":3,\"value\":1e-9223372036854775808}]}",
  )
  for
    (filter, code) in [
      ("{\"t\":[{\"value\":{\"eq\":\"1.00\"}}]}", "selector_type"),
      ("{\"t\":[{\"value\":{\"eq\":true}}]}", "selector_type"),
      ("{\"t\":[{\"value\":{\"lt\":null}}]}", "selector_order_type"),
      ("{\"t\":[{\"value\":{\"prefix\":1}}]}", "selector_type"),
      ("{\"t\":[{\"value\":{\"eq\":NaN}}]}", "invalid_json"),
    ] {
    assert_eq(error_code(() => ignore(plan.subset_where(data, filter))), code)
  }
  assert_eq(
    plan.subset_where(data, "{\"t\":[{\"value\":{\"is_null\":false}}]}"),
    data,
  )
}
