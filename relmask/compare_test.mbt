///|
test "dataset comparison ignores row and object order but detects cell changes" {
  let plan = @relmask.Plan::parse(policy())
  guard @json.parse(dataset(), preserve_number_repr=true) is Object(tables) &&
    tables.get("people") is Some(Array(people)) else {
    fail("shape")
  }
  tables["people"] = Json::array([people[1], people[0]])
  assert_true(
    plan
    .compare_datasets(dataset(), Json::object(tables).stringify())
    .is_empty(),
  )
  let changed = substitute(dataset(), "private", "changed-sensitive-value")
  let diff = plan.compare_datasets(dataset(), changed)
  assert_true(!diff.is_empty())
  assert_true(
    @json.parse(diff.to_json())
    is { "tables": Array([{ "changed": Number(1.0, ..), .. }, _]), .. },
  )
  assert_true(!diff.to_json().contains("changed-sensitive-value"))
  assert_true(!diff.to_json().contains("9007199254740993"))
  assert_eq(diff.to_json(), plan.compare_datasets(dataset(), changed).to_json())
}

///|
test "comparison reports added removed and changed separately" {
  let plan = @relmask.Plan::parse(policy())
  let small = plan.subset(dataset(), "{\"orders\":[{\"id\":2}]}")
  assert_true(
    @json.parse(plan.compare_datasets(dataset(), small).to_json())
    is {
      "tables": Array(
        [
          { "removed": Number(1.0, ..), "changed": Number(0.0, ..), .. },
          { "removed": Number(2.0, ..), .. },
        ]
      ),
      ..
    },
  )
  assert_true(
    @json.parse(plan.compare_datasets(small, dataset()).to_json())
    is {
      "tables": Array(
        [{ "added": Number(1.0, ..), .. }, { "added": Number(2.0, ..), .. }]
      ),
      ..
    },
  )
  let decimal = plan.compare_datasets(
    dataset(),
    substitute(dataset(), "1e400", "1E400"),
  )
  assert_true(!decimal.is_empty())
  assert_true(
    @json.parse(decimal.to_json())
    is {
      "tables": Array(
        [
          _,
          {
            "changed": Number(1.0, ..),
            "columns": Array([_, _, { "changed": Number(1.0, ..), .. }]),
            ..
          },
        ]
      ),
      ..
    },
  )
}

///|
test "comparison matches compound keys and never repairs invalid input" {
  let plan = @relmask.Plan::parse(compound_policy())
  let changed = substitute(
    compound_data(),
    "\"id\":1,\"tenant\":\"south\"",
    "\"id\":1,\"tenant\":\"north\"",
  )
  assert_true(
    @json.parse(plan.compare_datasets(compound_data(), changed).to_json())
    is {
      "tables": Array(
        [{ "changed": Number(0.0, ..), .. }, { "changed": Number(1.0, ..), .. }]
      ),
      ..
    },
  )
  assert_eq(
    error_code(() => ignore(plan.compare_datasets(compound_data(), "{}"))),
    "missing_accounts",
  )
  let bad = substitute(
    compound_data(),
    "\"id\":1,\"tenant\":\"south\"",
    "\"id\":1,\"tenant\":\"absent\"",
  )
  assert_eq(
    error_code(() => ignore(plan.compare_datasets(compound_data(), bad))),
    "orphan_reference",
  )
  assert_true(
    plan.compare_datasets(compound_data(), compound_data()).is_empty(),
  )
}

///|
test "large integer primary keys are distinct and generated diffs have exact counts" {
  let plan = @relmask.Plan::parse(
    "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"}],\"primary\":[\"id\"]}]}",
  )
  for n in 0..<=30 {
    let rows = Array::makei(n, i => {
      "{\"id\":" + (9007199254740992L + i.to_int64()).to_string() + "}"
    })
    let before = "{\"t\":[" + rows.join(",") + "]}"
    rows.push("{\"id\":9223372036854775807}")
    let after = "{\"t\":[" + rows.join(",") + "]}"
    assert_true(
      @json.parse(plan.compare_datasets(before, after).to_json())
      is {
        "tables": Array(
          [
            {
              "added": Number(1.0, ..),
              "removed": Number(0.0, ..),
              "changed": Number(0.0, ..),
              ..
            },
          ]
        ),
        ..
      },
    )
    assert_true(
      @json.parse(plan.compare_datasets(after, before).to_json())
      is { "tables": Array([{ "removed": Number(1.0, ..), .. }]), .. },
    )
  }
  let a = "{\"t\":[{\"id\":9007199254740992}]}"
  let b = "{\"t\":[{\"id\":9007199254740993}]}"
  assert_true(
    @json.parse(plan.compare_datasets(a, b).to_json())
    is {
      "tables": Array(
        [{ "added": Number(1.0, ..), "removed": Number(1.0, ..), .. }]
      ),
      ..
    },
  )
}
