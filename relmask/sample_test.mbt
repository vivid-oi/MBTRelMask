///|
fn sample_data(count : Int32) -> String {
  "{\"t\":[" +
  Array::makei(count, i => {
    "{\"id\":" + (9007199254740992L + i.to_int64()).to_string() + "}"
  }).join(",") +
  "]}"
}

///|
test "sampling is repeatable nested idempotent and independent of row ordering" {
  let plan = @relmask.Plan::parse(merge_policy())
  let data = sample_data(30)
  guard @json.parse(data, preserve_number_repr=true) is { "t": Array(rows), .. } else {
    fail("shape")
  }
  let reversed = Json::object({ "t": Json::array(rows.rev()) }).stringify()
  let mut previous : Map[String, Bool] = Map([])
  for count in 0..<=30 {
    let request = "{\"t\":" + count.to_string() + "}"
    let result = plan.sample(data, request, "public-test-seed")
    assert_eq(result, plan.sample(data, request, "public-test-seed"))
    assert_eq(result, plan.sample(result, request, "public-test-seed"))
    assert_true(
      plan
      .compare_datasets(
        result,
        plan.sample(reversed, request, "public-test-seed"),
      )
      .is_empty(),
    )
    guard @json.parse(result, preserve_number_repr=true)
      is { "t": Array(selected), .. } else {
      fail("sample shape")
    }
    assert_eq(selected.length(), count)
    let current : Map[String, Bool] = Map([])
    for row in selected {
      guard row is { "id": id, .. } else { fail("sample id") }
      current[id.stringify()] = true
    }
    for key, _ in previous {
      assert_true(current.contains(key))
    }
    previous = current
    if count == 30 {
      assert_eq(result, data)
    }
  }
  assert_true(
    plan.sample(data, "{\"t\":5}", "public-test-seed") !=
    plan.sample(data, "{\"t\":5}", "another-fixed-seed"),
  )
}

///|
test "sample ranks exclude nonkey values and retain original values" {
  let plan = @relmask.Plan::parse(
    (
      #|{"tables":[{"name":"t","columns":[{"name":"id","type":"integer","rule":"keep"},{"name":"note","type":"text","rule":"keep"}],"primary":["id"]}]}
    ),
  )
  let data = "{\"t\":[" +
    Array::makei(20, i => "{\"id\":" + i.to_string() + ",\"note\":\"original\"}").join(
      ",",
    ) +
    "]}"
  let changed = data.replace_all(old="original", new="changed")
  let a = plan.sample(data, "{\"t\":5}", "seed")
  let b = plan.sample(changed, "{\"t\":5}", "seed")
  assert_eq(a.replace_all(old="original", new="changed"), b)
  assert_true(a.contains("original"))
  let report = plan.compare_datasets(a, b).to_json()
  guard @json.parse(report)
    is {
      "tables": Array(
        [
          {
            "added": Number(0.0, ..),
            "removed": Number(0.0, ..),
            "changed": Number(5.0, ..),
            ..
          },
        ]
      ),
      ..
    } else {
    fail(report)
  }
}

///|
test "sample uses complete compound keys and exact integer keys" {
  let plan = @relmask.Plan::parse(compound_policy())
  let sample = plan.sample(compound_data(), "{\"accounts\":3}", "seed")
  assert_eq(
    sample,
    plan.subset(
      compound_data(),
      "{\"accounts\":[{\"tenant\":\"north\",\"account\":7},{\"tenant\":\"south\",\"account\":7},{\"tenant\":\"north\",\"account\":8}]}",
    ),
  )
  let event = plan.sample(compound_data(), "{\"events\":1}", "seed")
  guard @json.parse(event, preserve_number_repr=true)
    is { "events": Array([{ "id": id, .. }]), .. } else {
    fail("event shape")
  }
  assert_eq(
    event,
    plan.subset(
      compound_data(),
      "{\"events\":[{\"id\":" + id.stringify() + "}]}",
    ),
  )
  let integer = @relmask.Plan::parse(merge_policy())
  let extremes = "{\"t\":[{\"id\":-9223372036854775808},{\"id\":9007199254740992},{\"id\":9007199254740993},{\"id\":9223372036854775807}]}"
  assert_eq(integer.sample(extremes, "{\"t\":4}", "seed"), extremes)
  assert_true(
    @json.parse(integer.sample(extremes, "{\"t\":3}", "seed"))
    is { "t": Array([_, _, _]), .. },
  )
}

///|
test "sampling closes cycles and enforces final closure budgets" {
  let plan = @relmask.Plan::parse(
    (
      #|{"tables":[{"name":"t","columns":[{"name":"id","type":"integer","rule":"keep"},{"name":"parent","type":"integer","rule":"keep"}],"primary":["id"],"references":[{"columns":["parent"],"table":"t","target":["id"]}]}]}
    ),
  )
  let data = "{\"t\":[{\"id\":1,\"parent\":2},{\"id\":2,\"parent\":1}]}"
  assert_eq(plan.sample(data, "{\"t\":1}", "seed"), data)
  assert_eq(
    error_code(() => {
      ignore(plan.sample(data, "{\"t\":1}", "seed", options="{\"max_rows\":1}"))
    }),
    "subset_row_limit",
  )
  let relational = @relmask.Plan::parse(policy())
  assert_eq(
    error_code(() => {
      ignore(
        relational.sample(
          dataset(),
          "{\"orders\":3}",
          "seed",
          options="{\"max_rows\":4}",
        ),
      )
    }),
    "subset_row_limit",
  )
  assert_eq(
    relational.sample(dataset(), "{\"orders\":0}", "seed"),
    "{\"people\":[],\"orders\":[]}",
  )
  assert_true(
    relational
    .compare_datasets(
      relational.sample(dataset(), "{\"orders\":3}", "seed"),
      dataset(),
    )
    .is_empty(),
  )
}

///|
test "sample rejects malformed counts requests seeds and invalid unselected data" {
  let plan = @relmask.Plan::parse(merge_policy())
  let data = sample_data(3)
  for
    (request, code) in [
      ("{", "invalid_json"),
      ("{\"t\":1,\"t\":2}", "invalid_json"),
      ("{}", "empty_sample_request"),
      ("[]", "expected_object"),
      ("{\"absent\":0}", "unknown_option"),
      ("{\"t\":-1}", "sample_count_range"),
      ("{\"t\":4}", "sample_population_too_small"),
      ("{\"t\":1.0}", "expected_integer"),
      ("{\"t\":\"1\"}", "expected_integer"),
      ("{\"t\":true}", "expected_integer"),
      ("{\"t\":9223372036854775808}", "integer_range"),
    ] {
    assert_eq(
      error_code(() => ignore(plan.sample(data, request, "seed"))),
      code,
    )
  }
  assert_eq(
    error_code(() => ignore(plan.sample(data, "{\"t\":1}", ""))),
    "sample_seed_range",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.sample(data, "{\"t\":1}", Array::make(4097, "s").join("")))
    }),
    "sample_seed_range",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.sample(data, Array::make(1_000_001, " ").join(""), "seed"))
    }),
    "sample_request_too_large",
  )
  let bad = "{\"t\":[{\"id\":1},{\"id\":1}]}"
  assert_eq(
    error_code(() => ignore(plan.sample(bad, "{\"t\":0}", "seed"))),
    "duplicate_key",
  )
  assert_eq(
    plan.sample(data, "{\"t\":1}", "seed"),
    plan.sample(data, "{\"t\":1}", "seed"),
  )
}

///|
test "multi-table sampling unions seed sets and respects Boolean primary keys" {
  let plan = @relmask.Plan::parse(policy())
  let sample = plan.sample(dataset(), "{\"people\":2,\"orders\":3}", "seed")
  assert_true(plan.compare_datasets(sample, dataset()).is_empty())
  assert_eq(
    sample,
    plan.sample(dataset(), "{\"orders\":3,\"people\":2}", "seed"),
  )
  let boolean = @relmask.Plan::parse(
    (
      #|{"tables":[{"name":"t","columns":[{"name":"id","type":"boolean","rule":"keep"}],"primary":["id"]}]}
    ),
  )
  assert_eq(
    boolean.sample(
      "{\"t\":[{\"id\":true},{\"id\":false}]}", "{\"t\":2}", "seed",
    ),
    "{\"t\":[{\"id\":true},{\"id\":false}]}",
  )
}
