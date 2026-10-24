///|
test "subset closes parent dependencies without unrelated child rows" {
  let plan = @relmask.Plan::parse(policy())
  let seeds = "{\"orders\":[{\"id\":1},{\"id\":1}]}"
  let selected = plan.subset(dataset(), seeds)
  guard @json.parse(selected, preserve_number_repr=true)
    is { "people": Array(people), "orders": Array(orders), .. } else {
    fail("shape")
  }
  assert_eq(people.length(), 1)
  assert_eq(orders.length(), 1)
  assert_true(selected.contains("9007199254740993"))
  assert_true(selected.contains("12.345678901234567890"))
  assert_eq(plan.subset(selected, seeds), selected)
  assert_eq(plan.subset(dataset(), "{\"orders\":[{\"id\":1}]}"), selected)
  let masked = plan.transform(selected, secret)
  ignore(plan.verify_bundle(masked.bundle_json()))
  let parent_only = plan.subset(dataset(), "{\"people\":[{\"id\":42}]}")
  assert_true(
    @json.parse(parent_only)
    is { "people": Array([_]), "orders": Array([]), .. },
  )
  assert_eq(plan.subset(dataset(), "{}"), "{\"people\":[],\"orders\":[]}")
}

///|
test "subset uses full compound tuples and skips partial null references" {
  let plan = @relmask.Plan::parse(compound_policy())
  let selected = plan.subset(compound_data(), "{\"events\":[{\"id\":1}]}")
  assert_eq(
    selected, "{\"accounts\":[{\"tenant\":\"south\",\"account\":7}],\"events\":[{\"id\":1,\"tenant\":\"south\",\"account\":7}]}",
  )
  let selected = plan.subset(
    compound_data(),
    "{\"events\":[{\"id\":2},{\"id\":3}]}",
  )
  assert_true(
    @json.parse(selected)
    is { "accounts": Array([]), "events": Array([_, _]), .. },
  )
  let selected = plan.subset(
    compound_data(),
    "{\"accounts\":[{\"account\":8,\"tenant\":\"north\"}]}",
  )
  assert_eq(
    selected, "{\"accounts\":[{\"tenant\":\"north\",\"account\":8}],\"events\":[]}",
  )
}

///|
test "subset rejects malformed seeds and validates the whole source first" {
  let plan = @relmask.Plan::parse(policy())
  for
    (seed, code) in [
      ("{", "invalid_json"),
      ("[]", "expected_object"),
      ("{\"missing\":[]}", "unknown_option"),
      ("{\"people\":[{}]}", "missing_id"),
      ("{\"people\":[{\"id\":999}]}", "seed_not_found"),
      ("{\"people\":[{\"id\":42,\"email\":\"private\"}]}", "unknown_option"),
      ("{\"people\":[{\"id\":42.0}]}", "expected_integer"),
    ] {
    assert_eq(error_code(() => ignore(plan.subset(dataset(), seed))), code)
  }
  let broken = substitute(dataset(), "\"person\":42", "\"person\":99")
  assert_eq(
    error_code(() => ignore(plan.subset(broken, "{}"))),
    "orphan_reference",
  )
  assert_true(plan.subset(dataset(), "{}").contains("people"))
}

///|
test "subset follows unique targets and terminates on cycles" {
  let p = "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"},{\"name\":\"code\",\"type\":\"text\",\"rule\":\"keep\"},{\"name\":\"parent\",\"type\":\"text\",\"nullable\":true,\"rule\":\"keep\"}],\"primary\":[\"id\"],\"unique\":[[\"code\"]],\"references\":[{\"columns\":[\"parent\"],\"table\":\"t\",\"target\":[\"code\"]}]}]}"
  let plan = @relmask.Plan::parse(p)
  let data = "{\"t\":[{\"id\":1,\"code\":\"a\",\"parent\":\"b\"},{\"id\":2,\"code\":\"b\",\"parent\":\"a\"},{\"id\":3,\"code\":\"c\",\"parent\":null}]}"
  assert_eq(
    plan.subset(data, "{\"t\":[{\"id\":1}]}"),
    "{\"t\":[{\"id\":1,\"code\":\"a\",\"parent\":\"b\"},{\"id\":2,\"code\":\"b\",\"parent\":\"a\"}]}",
  )
}

///|
test "subset closure is deterministic across seed permutations on generated chains" {
  let p = "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"},{\"name\":\"parent\",\"type\":\"integer\",\"nullable\":true,\"rule\":\"keep\"}],\"primary\":[\"id\"],\"references\":[{\"columns\":[\"parent\"],\"table\":\"t\",\"target\":[\"id\"]}]}]}"
  let plan = @relmask.Plan::parse(p)
  let rows : Array[String] = []
  for i in 0..<1000 {
    rows.push(
      "{\"id\":" +
      i.to_string() +
      ",\"parent\":" +
      (if i == 0 { "null" } else { (i - 1).to_string() }) +
      "}",
    )
  }
  let data = "{\"t\":[" + rows.join(",") + "]}"
  assert_eq(plan.subset(data, "{\"t\":[{\"id\":999}]}"), data)
  let a = plan.subset(data, "{\"t\":[{\"id\":1},{\"id\":99}]}")
  let b = plan.subset(data, "{\"t\":[{\"id\":99},{\"id\":1}]}")
  assert_eq(a, b)
  assert_true(
    @json.parse(a) is { "t": Array(rows), .. } && rows.length() == 100,
  )
}
