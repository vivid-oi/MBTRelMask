///|
fn nullable_policy(mode : String) -> String {
  "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"},{\"name\":\"tenant\",\"type\":\"text\",\"nullable\":true,\"rule\":\"keep\"},{\"name\":\"alias\",\"type\":\"text\",\"nullable\":true,\"rule\":\"keep\"}],\"primary\":[\"id\"],\"unique\":[" +
  mode +
  "]}]}"
}

///|
test "NULLS NOT DISTINCT compares complete nullable tuples without collisions" {
  let plan = @relmask.Plan::parse(
    nullable_policy(
      "{\"columns\":[\"tenant\",\"alias\"],\"nulls\":\"not_distinct\"}",
    ),
  )
  let valid = "{\"t\":[{\"id\":1,\"tenant\":\"north\",\"alias\":null},{\"id\":2,\"tenant\":\"south\",\"alias\":null}]}"
  let result = plan.transform(valid, secret)
  assert_eq(
    plan.import_csv(plan.export_csv(result.to_json())),
    result.to_json(),
  )
  ignore(plan.verify_bundle(result.bundle_json()))
  let duplicate = substitute(valid, "south", "north")
  assert_eq(error_code(() => ignore(plan.validate(duplicate))), "duplicate_key")
  assert_eq(
    error_code(() => ignore(plan.subset(duplicate, "{}"))),
    "duplicate_key",
  )
  let all_null = "{\"t\":[{\"id\":1,\"tenant\":null,\"alias\":null},{\"id\":2,\"tenant\":null,\"alias\":null}]}"
  assert_eq(error_code(() => ignore(plan.validate(all_null))), "duplicate_key")
  let text = "{\"t\":[{\"id\":1,\"tenant\":\"null\",\"alias\":null},{\"id\":2,\"tenant\":null,\"alias\":\"null\"}]}"
  ignore(plan.validate(text))
  ignore(plan.validate(valid))
}

///|
test "default UNIQUE keeps NULLS DISTINCT and unsupported options reject" {
  let duplicate = "{\"t\":[{\"id\":1,\"tenant\":null,\"alias\":null},{\"id\":2,\"tenant\":null,\"alias\":null}]}"
  let legacy = @relmask.Plan::parse(nullable_policy("[\"tenant\",\"alias\"]"))
  let explicit = @relmask.Plan::parse(
    nullable_policy(
      "{\"columns\":[\"tenant\",\"alias\"],\"nulls\":\"distinct\"}",
    ),
  )
  assert_eq(
    legacy.transform(duplicate, secret).to_json(),
    explicit.transform(duplicate, secret).to_json(),
  )
  assert_eq(
    error_code(() => {
      ignore(
        @relmask.Plan::parse(
          nullable_policy("{\"columns\":[\"alias\"],\"nulls\":\"ignore\"}"),
        ),
      )
    }),
    "unsupported_unique_nulls",
  )
  assert_eq(
    error_code(() => {
      ignore(
        @relmask.Plan::parse(
          nullable_policy("{\"columns\":[\"alias\"],\"extra\":true}"),
        ),
      )
    }),
    "unknown_option",
  )
}

///|
test "nullable uniqueness is checked again after clearing and can be FK target" {
  let p = nullable_policy(
    "{\"columns\":[\"tenant\",\"alias\"],\"nulls\":\"not_distinct\"}",
  )
  let p = substitute(
    p, "\"name\":\"alias\",\"type\":\"text\",\"nullable\":true,\"rule\":\"keep\"",
    "\"name\":\"alias\",\"type\":\"text\",\"nullable\":true,\"rule\":\"null\"",
  )
  let plan = @relmask.Plan::parse(p)
  let data = "{\"t\":[{\"id\":1,\"tenant\":\"north\",\"alias\":\"a\"},{\"id\":2,\"tenant\":\"north\",\"alias\":\"b\"}]}"
  assert_eq(
    error_code(() => ignore(plan.transform(data, secret))),
    "duplicate_key",
  )
  ignore(plan.transform("{\"t\":[]}", secret))
  let p = substitute(
    compound_policy(),
    "\"primary\":[\"tenant\",\"account\"]",
    "\"primary\":[\"tenant\",\"account\"],\"unique\":[{\"columns\":[\"tenant\",\"account\"],\"nulls\":\"not_distinct\"}]",
  )
  let p = substitute(
    p, "\"columns\":[\"tenant\",\"account\"],\"nulls\"", "\"columns\":[\"account\",\"tenant\"],\"nulls\"",
  )
  let p = substitute(
    p, "\"columns\":[\"tenant\",\"account\"]", "\"columns\":[\"account\",\"tenant\"]",
  )
  let p = substitute(
    p, "\"target\":[\"tenant\",\"account\"]", "\"target\":[\"account\",\"tenant\"]",
  )
  ignore(@relmask.Plan::parse(p).transform(compound_data(), secret))
}
