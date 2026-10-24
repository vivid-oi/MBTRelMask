///|
test "merge reuses complete shared rows and retains relational references" {
  let plan = @relmask.Plan::parse(policy())
  let a = plan.subset(dataset(), "{\"orders\":[{\"id\":1}]}")
  let b = plan.subset(dataset(), "{\"orders\":[{\"id\":1},{\"id\":2}]}")
  let merged = plan.merge_datasets(a, b)
  assert_true(plan.compare_datasets(merged.to_json(), b).is_empty())
  assert_true(
    @json.parse(merged.report_json())
    is {
      "tables": Array(
        [
          { "left": 1, "right": 2, "reused": 1, "added": 1, "result": 2, .. },
          { "left": 1, "right": 2, "reused": 1, "added": 1, "result": 2, .. },
        ]
      ),
      ..
    },
  )
  assert_true(!merged.report_json().contains("9007199254740993"))
  assert_true(!merged.report_json().contains("example.test"))
  assert_eq(merged.to_json(), plan.merge_datasets(a, b).to_json())
  let checked = plan.transform(merged.to_json(), secret)
  assert_eq(
    plan.verify_bundle(checked.bundle_json()).to_json(),
    checked.to_json(),
  )
}

///|
test "merge never chooses one conflicting row or normalizes numeric spelling" {
  let plan = @relmask.Plan::parse(policy())
  for
    changed in [
      substitute(dataset(), "private", "sensitive-conflict"),
      substitute(dataset(), "1e400", "1E400"),
    ] {
    assert_eq(
      error_code(() => ignore(plan.merge_datasets(dataset(), changed))),
      "merge_row_conflict",
    )
    try plan.merge_datasets(dataset(), changed) catch {
      @relmask.Invalid(code~, location~) => {
        assert_true(!location.contains("sensitive-conflict"))
        assert_true(!location.contains("9007199254740993"))
        assert_eq(code, "merge_row_conflict")
        assert_true(location.contains(".right["))
      }
    } noraise {
      _ => fail("conflict accepted")
    }
  }
  assert_eq(
    plan.merge_datasets(dataset(), dataset()).to_json(),
    plan.merge_datasets(dataset(), "{\"people\":[],\"orders\":[]}").to_json(),
  )
}

///|
test "merge checks individual inputs and new cross-export unique conflicts" {
  let plan = @relmask.Plan::parse(policy())
  let a = "{\"people\":[{\"id\":1,\"email\":\"same\",\"note\":null}],\"orders\":[]}"
  let b = "{\"people\":[{\"id\":2,\"email\":\"same\",\"note\":null}],\"orders\":[]}"
  assert_eq(
    error_code(() => ignore(plan.merge_datasets(a, b))),
    "duplicate_key",
  )
  let orphan = "{\"people\":[],\"orders\":[{\"id\":1,\"person\":1,\"amount\":1}]}"
  assert_eq(
    error_code(() => ignore(plan.merge_datasets(a, orphan))),
    "orphan_reference",
  )
  assert_eq(
    error_code(() => ignore(plan.merge_datasets(a, "{}"))),
    "missing_people",
  )
  assert_eq(
    error_code(() => {
      ignore(
        plan.merge_datasets(a, "{\"people\":[],\"people\":[],\"orders\":[]}"),
      )
    }),
    "invalid_json",
  )
  ignore(plan.merge_datasets(a, a))
}

///|
fn merge_policy(limits~ : String = "") -> String {
  "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"}],\"primary\":[\"id\"]}]" +
  limits +
  "}"
}

///|
test "merge budgets apply to union rows and complete encoded output" {
  let plan = @relmask.Plan::parse(merge_policy(limits=",\"max_rows\":2"))
  let a = "{\"t\":[{\"id\":1},{\"id\":2}]}"
  let b = "{\"t\":[{\"id\":2},{\"id\":3}]}"
  assert_eq(
    error_code(() => ignore(plan.merge_datasets(a, b))),
    "merge_row_limit",
  )
  assert_eq(plan.merge_datasets(a, a).to_json(), a)
  let small = @relmask.Plan::parse(
    merge_policy(limits=",\"max_input_units\":20"),
  )
  assert_eq(
    error_code(() => {
      ignore(
        small.merge_datasets("{\"t\":[{\"id\":1}]}", "{\"t\":[{\"id\":2}]}"),
      )
    }),
    "output_too_large",
  )
  assert_eq(
    small.merge_datasets("{\"t\":[]}", "{\"t\":[{\"id\":1}]}").to_json(),
    "{\"t\":[{\"id\":1}]}",
  )
}

///|
test "merge matches complete compound keys and exact integer identities" {
  let plan = @relmask.Plan::parse(compound_policy())
  let a = plan.subset(
    compound_data(),
    "{\"accounts\":[{\"tenant\":\"north\",\"account\":7}]}",
  )
  let b = plan.subset(
    compound_data(),
    "{\"accounts\":[{\"tenant\":\"south\",\"account\":7}]}",
  )
  assert_true(
    @json.parse(plan.merge_datasets(a, b).to_json())
    is { "accounts": Array([_, _]), .. },
  )
  let plain = @relmask.Plan::parse(merge_policy())
  let result = plain
    .merge_datasets(
      "{\"t\":[{\"id\":-9223372036854775808},{\"id\":9007199254740992}]}", "{\"t\":[{\"id\":9007199254740993},{\"id\":9223372036854775807}]}",
    )
    .to_json()
  assert_true(
    @json.parse(result, preserve_number_repr=true)
    is { "t": Array([_, _, _, _]), .. },
  )
  assert_true(result.contains("9007199254740993"))
  assert_eq(
    error_code(() => {
      ignore(
        plain.merge_datasets("{\"t\":[{\"id\":-0}]}", "{\"t\":[{\"id\":0}]}"),
      )
    }),
    "merge_row_conflict",
  )
}

///|
test "generated overlapping unions are idempotent associative and lossless" {
  let plan = @relmask.Plan::parse(merge_policy())
  let make = fn(start : Int32, count : Int32) {
    "{\"t\":[" +
    Array::makei(count, i => {
      "{\"id\":" +
      (9007199254740992L + (start + i).to_int64()).to_string() +
      "}"
    }).join(",") +
    "]}"
  }
  for n in 0..<=30 {
    let a = make(0, n)
    let b = make(n / 2, n)
    let c = make(n, n)
    let ab = plan.merge_datasets(a, b)
    let ba = plan.merge_datasets(b, a)
    assert_true(plan.compare_datasets(ab.to_json(), ba.to_json()).is_empty())
    assert_eq(
      plan.merge_datasets(ab.to_json(), ab.to_json()).to_json(),
      ab.to_json(),
    )
    assert_eq(
      plan.merge_datasets(ab.to_json(), c).to_json(),
      plan.merge_datasets(a, plan.merge_datasets(b, c).to_json()).to_json(),
    )
    assert_true(
      @json.parse(ab.report_json())
      is { "tables": Array([{ "result": count, .. }]), .. } &&
      count.stringify() == (n + n / 2).to_string(),
    )
    ignore(plan.validate(ab.to_json()))
  }
}
