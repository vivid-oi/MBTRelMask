///|
test "typed selection composes AND OR predicates with parent and child closure" {
  let plan = @relmask.Plan::parse(policy())
  let selector = "{\"orders\":[{\"id\":{\"gte\":2,\"lt\":3}}]}"
  assert_eq(
    plan.subset_where(dataset(), selector),
    plan.subset(dataset(), "{\"orders\":[{\"id\":2}]}"),
  )
  let either = "{\"orders\":[{\"id\":{\"eq\":2}},{\"id\":{\"eq\":1}},{\"id\":{\"eq\":2}}]}"
  let swapped = "{\"orders\":[{\"id\":{\"eq\":1}},{\"id\":{\"eq\":2}}]}"
  let result = plan.subset_where(dataset(), either)
  assert_eq(result, plan.subset_where(dataset(), swapped))
  assert_eq(result, plan.subset_where(result, either))
  assert_eq(
    result,
    plan.subset(dataset(), "{\"orders\":[{\"id\":1},{\"id\":2}]}"),
  )
  let child = plan.subset_where(
    dataset(),
    "{\"people\":[{\"email\":{\"prefix\":\"甲\"}}]}",
    options="{\"descendants\":[\"orders\"]}",
  )
  assert_eq(
    child,
    plan.subset(
      dataset(),
      "{\"people\":[{\"id\":9007199254740993}]}",
      options="{\"descendants\":[\"orders\"]}",
    ),
  )
  assert_true(child.contains("12.345678901234567890"))
}

///|
test "selection uses exact text bounds and total null equality" {
  let plan = @relmask.Plan::parse(policy())
  assert_eq(
    plan.subset_where(
      dataset(),
      "{\"people\":[{\"email\":{\"gte\":\"a\",\"lt\":\"c\"},\"note\":{\"eq\":null}}]}",
    ),
    plan.subset(dataset(), "{\"people\":[{\"id\":42}]}"),
  )
  assert_eq(
    plan.subset_where(
      dataset(),
      "{\"orders\":[{\"person\":{\"neq\":9007199254740993}}]}",
    ),
    plan.subset(dataset(), "{\"orders\":[{\"id\":2},{\"id\":3}]}"),
  )
  assert_eq(
    plan.subset_where(
      dataset(),
      "{\"orders\":[{\"person\":{\"is_null\":true}}]}",
    ),
    plan.subset(dataset(), "{\"orders\":[{\"id\":3}]}"),
  )
  assert_eq(
    plan.subset_where(
      dataset(),
      "{\"orders\":[{\"person\":{\"gt\":0,\"is_null\":false}}]}",
    ),
    plan.subset(dataset(), "{\"orders\":[{\"id\":1},{\"id\":2}]}"),
  )
  assert_eq(
    plan.subset_where(dataset(), "{\"orders\":[{\"id\":{\"eq\":999}}]}"),
    "{\"people\":[],\"orders\":[]}",
  )
}

///|
test "selection integers include Int64 endpoints and adjacent large values" {
  let plan = @relmask.Plan::parse(merge_policy())
  let data = "{\"t\":[{\"id\":-9223372036854775808},{\"id\":9007199254740992},{\"id\":9007199254740993},{\"id\":9223372036854775807}]}"
  assert_eq(
    plan.subset_where(
      data, "{\"t\":[{\"id\":{\"gt\":9007199254740992,\"lte\":9007199254740993}}]}",
    ),
    "{\"t\":[{\"id\":9007199254740993}]}",
  )
  assert_eq(
    plan.subset_where(
      data, "{\"t\":[{\"id\":{\"eq\":-9223372036854775808}},{\"id\":{\"gte\":9223372036854775807}}]}",
    ),
    "{\"t\":[{\"id\":-9223372036854775808},{\"id\":9223372036854775807}]}",
  )
  assert_eq(
    plan.subset_where("{\"t\":[{\"id\":-0}]}", "{\"t\":[{\"id\":{\"eq\":0}}]}"),
    "{\"t\":[{\"id\":-0}]}",
  )
  assert_eq(
    error_code(() => {
      ignore(
        plan.subset_where(
          data, "{\"t\":[{\"id\":{\"gt\":9223372036854775808}}]}",
        ),
      )
    }),
    "integer_range",
  )
}

///|
test "selection supports Boolean equality and decimal null checks without coercion" {
  let plan = @relmask.Plan::parse(
    (
      #|{"tables":[{"name":"t","columns":[{"name":"id","type":"integer","rule":"keep"},{"name":"flag","type":"boolean","nullable":true,"rule":"keep"},{"name":"amount","type":"decimal","nullable":true,"rule":"keep"}],"primary":["id"]}]}
    ),
  )
  let data = "{\"t\":[{\"id\":1,\"flag\":true,\"amount\":1e400},{\"id\":2,\"flag\":false,\"amount\":null},{\"id\":3,\"flag\":null,\"amount\":0.000}]}"
  assert_eq(
    plan.subset_where(
      data, "{\"t\":[{\"flag\":{\"eq\":false},\"amount\":{\"is_null\":true}}]}",
    ),
    "{\"t\":[{\"id\":2,\"flag\":false,\"amount\":null}]}",
  )
  assert_eq(
    plan.subset_where(
      data, "{\"t\":[{\"flag\":{\"neq\":true},\"amount\":{\"is_null\":false}}]}",
    ),
    "{\"t\":[{\"id\":3,\"flag\":null,\"amount\":0.000}]}",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.subset_where(data, "{\"t\":[{\"amount\":{\"eq\":1e400}}]}"))
    }),
    "selector_decimal_unsupported",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.subset_where(data, "{\"t\":[{\"flag\":{\"lt\":true}}]}"))
    }),
    "selector_order_type",
  )
}

///|
test "selection rejects malformed unsupported and empty branches before scanning" {
  let plan = @relmask.Plan::parse(policy())
  for
    (selector, code) in [
      ("{", "invalid_json"),
      ("{\"people\":[],\"people\":[]}", "invalid_json"),
      ("{}", "empty_selector"),
      ("{\"people\":[]}", "empty_selector"),
      ("{\"people\":[{}]}", "empty_selector"),
      ("{\"people\":[{\"id\":{}}]}", "empty_selector"),
      ("{\"absent\":[{\"id\":{\"eq\":1}}]}", "unknown_option"),
      ("{\"people\":[{\"absent\":{\"eq\":1}}]}", "unknown_option"),
      (
        "{\"people\":[{\"email\":{\"regex\":\"sensitive-filter\"}}]}", "unknown_option",
      ),
      ("{\"people\":[{\"id\":{\"eq\":1.0}}]}", "expected_integer"),
      ("{\"people\":[{\"id\":{\"eq\":\"1\"}}]}", "expected_integer"),
      ("{\"people\":[{\"id\":{\"gt\":null}}]}", "selector_order_type"),
      ("{\"people\":[{\"id\":{\"prefix\":1}}]}", "selector_type"),
      ("{\"people\":[{\"note\":{\"is_null\":\"true\"}}]}", "selector_type"),
    ] {
    assert_eq(
      error_code(() => ignore(plan.subset_where(dataset(), selector))),
      code,
    )
  }
  assert_eq(
    plan.subset_where(dataset(), "{\"people\":[{\"note\":{\"eq\":null}}]}"),
    plan.subset(dataset(), "{\"people\":[{\"id\":42}]}"),
  )
  let bad = substitute(
    dataset(),
    "\"person\":9007199254740993",
    "\"person\":999",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.subset_where(bad, "{\"people\":[{\"note\":{\"eq\":null}}]}"))
    }),
    "orphan_reference",
  )
}

///|
test "selection bounds predicates branches closure and input configuration" {
  let plan = @relmask.Plan::parse(merge_policy())
  let empty = "{\"t\":[]}"
  let alternatives = Array::make(65, "{\"id\":{\"eq\":1}}").join(",")
  assert_eq(
    error_code(() => {
      ignore(plan.subset_where(empty, "{\"t\":[" + alternatives + "]}"))
    }),
    "selector_branch_limit",
  )
  let too_many = Array::make(
    64, "{\"id\":{\"eq\":1,\"neq\":2,\"gte\":0,\"lt\":3,\"lte\":4}}",
  ).join(",")
  assert_eq(
    error_code(() => {
      ignore(plan.subset_where(empty, "{\"t\":[" + too_many + "]}"))
    }),
    "selector_predicate_limit",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.subset_where(empty, Array::make(1_000_001, " ").join("")))
    }),
    "selector_too_large",
  )
  let relational = @relmask.Plan::parse(policy())
  assert_eq(
    error_code(() => {
      ignore(
        relational.subset_where(
          dataset(),
          "{\"orders\":[{\"id\":{\"eq\":1}}]}",
          options="{\"max_rows\":1}",
        ),
      )
    }),
    "subset_row_limit",
  )
  assert_eq(
    error_code(() => {
      ignore(
        relational.subset_where(
          dataset(),
          "{\"orders\":[{\"id\":{\"eq\":1}}]}",
          options="{\"truncate\":true}",
        ),
      )
    }),
    "unknown_option",
  )
}

///|
test "generated integer filters equal explicit seed closure without changing order" {
  let plan = @relmask.Plan::parse(merge_policy())
  for n in 0..<=30 {
    let make = fn(i : Int32) {
      "{\"id\":" + (9007199254740992L + i.to_int64()).to_string() + "}"
    }
    let data = "{\"t\":[" + Array::makei(n, make).join(",") + "]}"
    let seeds : Array[String] = []
    for i in (n / 3)..<(2 * n / 3) {
      seeds.push(make(i))
    }
    let filter = "{\"t\":[{\"id\":{\"gte\":" +
      (9007199254740992L + (n / 3).to_int64()).to_string() +
      ",\"lt\":" +
      (9007199254740992L + (2 * n / 3).to_int64()).to_string() +
      "}}]}"
    let expected = plan.subset(data, "{\"t\":[" + seeds.join(",") + "]}")
    assert_eq(plan.subset_where(data, filter), expected)
    assert_eq(plan.subset_where(expected, filter), expected)
  }
}

///|
test "selection retains compound reference semantics cycles and UTF16 ordering" {
  let plan = @relmask.Plan::parse(compound_policy())
  assert_eq(
    plan.subset_where(
      compound_data(),
      "{\"events\":[{\"tenant\":{\"eq\":\"south\"},\"account\":{\"eq\":7}}]}",
    ),
    plan.subset(compound_data(), "{\"events\":[{\"id\":1}]}"),
  )
  assert_eq(
    plan.subset_where(
      compound_data(),
      "{\"events\":[{\"account\":{\"is_null\":true}},{\"tenant\":{\"is_null\":true}}]}",
    ),
    plan.subset(compound_data(), "{\"events\":[{\"id\":2},{\"id\":3}]}"),
  )
  let cycle = @relmask.Plan::parse(
    (
      #|{"tables":[{"name":"t","columns":[{"name":"id","type":"integer","rule":"keep"},{"name":"parent","type":"integer","rule":"keep"}],"primary":["id"],"references":[{"columns":["parent"],"table":"t","target":["id"]}]}]}
    ),
  )
  let data = "{\"t\":[{\"id\":1,\"parent\":2},{\"id\":2,\"parent\":1}]}"
  assert_eq(cycle.subset_where(data, "{\"t\":[{\"id\":{\"eq\":1}}]}"), data)
  let text = @relmask.Plan::parse(
    (
      #|{"tables":[{"name":"t","columns":[{"name":"id","type":"text","rule":"keep"}],"primary":["id"]}]}
    ),
  )
  assert_eq(
    text.subset_where(
      "{\"t\":[{\"id\":\"😀\"},{\"id\":\"\u{e000}\"}]}", "{\"t\":[{\"id\":{\"lt\":\"\u{e000}\"}}]}",
    ),
    "{\"t\":[{\"id\":\"😀\"}]}",
  )
}

///|
test "predicate selection does not serialize large primary keys into seed input" {
  let plan = @relmask.Plan::parse(
    (
      #|{"tables":[{"name":"t","columns":[{"name":"id","type":"text","rule":"keep"}],"primary":["id"]}]}
    ),
  )
  let prefix = "k" + Array::make(1024, "x").join("")
  let data = "{\"t\":[" +
    Array::makei(1024, i => "{\"id\":\"" + prefix + i.to_string() + "\"}").join(
      ",",
    ) +
    "]}"
  assert_true(data.length() > 1_000_000)
  assert_eq(
    error_code(() => ignore(plan.subset(data, data))),
    "seeds_too_large",
  )
  assert_eq(
    plan.subset_where(data, "{\"t\":[{\"id\":{\"prefix\":\"k\"}}]}"),
    data,
  )
}
