///|
test "stateful batches keep existing IDs and preserve ordinary transform output" {
  let plan = @relmask.Plan::parse(policy())
  let small = plan.subset(dataset(), "{\"orders\":[{\"id\":2}]}")
  let first = plan.transform_with_state(small, secret)
  assert_eq(first.dataset().to_json(), plan.transform(small, secret).to_json())
  let second = plan.transform_with_state(
    dataset(),
    secret,
    previous=first.state_json(),
  )
  guard @json.parse(first.dataset().to_json())
    is { "people": Array([{ "id": old, .. }]), .. } &&
    @json.parse(second.dataset().to_json())
    is {
      "people": Array([_, { "id": new, .. }]),
      "orders": Array([_, { "person": parent, .. }, _]),
      ..
    } else {
    fail("shape")
  }
  assert_eq(old, new)
  assert_eq(new, parent)
  let replay = plan.transform_with_state(
    small,
    secret,
    previous=second.state_json(),
  )
  assert_eq(replay.state_json(), second.state_json())
  assert_eq(replay.dataset().to_json(), first.dataset().to_json())
  ignore(plan.verify_bundle(second.dataset().bundle_json()))
  assert_true(!second.state_json().contains("b@example.test"))
  assert_true(!second.state_json().contains(secret))
  assert_eq(
    error_code(() => {
      ignore(
        plan.transform_with_state(
          dataset(),
          secret,
          previous=first.state_json(),
          max_entries=1,
        ),
      )
    }),
    "state_entry_limit",
  )
  assert_eq(
    error_code(() => {
      ignore(
        plan.transform_with_state(
          small,
          "another-valid-key-32-bytes-long-enough",
          previous=first.state_json(),
        ),
      )
    }),
    "state_authentication",
  )
  assert_eq(
    error_code(() => {
      ignore(
        plan.transform_with_state(
          small,
          secret,
          previous=substitute(
            first.state_json(),
            "relmask-state-1",
            "relmask-state-2",
          ),
        ),
      )
    }),
    "state_authentication",
  )
  let other = @relmask.Plan::parse(policy() + " ")
  assert_eq(
    error_code(() => {
      ignore(
        other.transform_with_state(small, secret, previous=first.state_json()),
      )
    }),
    "state_policy_mismatch",
  )
  assert_eq(
    plan
    .transform_with_state(dataset(), secret, previous=first.state_json())
    .state_json(),
    second.state_json(),
  )
}

///|
test "state grows append only for generated batches and survives reload" {
  let plan = @relmask.Plan::parse(
    "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":{\"reindex\":100}}],\"primary\":[\"id\"]}]}",
  )
  let mut prior : String? = None
  for n in 1..<=30 {
    let source = "{\"t\":[" +
      Array::makei(n, i => "{\"id\":" + (i + 999).to_string() + "}").join(",") +
      "]}"
    let batch = match prior {
      None => plan.transform_with_state(source, secret)
      Some(previous) => plan.transform_with_state(source, secret, previous~)
    }
    guard @json.parse(batch.dataset().to_json()) is { "t": Array(rows), .. } else {
      fail("shape")
    }
    for i, row in rows {
      assert_eq(row.stringify(), "{\"id\":" + (100 + i).to_string() + "}")
    }
    assert_eq(
      plan
      .transform_with_state(source, secret, previous=batch.state_json())
      .state_json(),
      batch.state_json(),
    )
    prior = Some(batch.state_json())
  }
}

///|
test "state overflow rejects a new batch without corrupting previous snapshot" {
  let plan = @relmask.Plan::parse(
    "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":{\"reindex\":9223372036854775807}}],\"primary\":[\"id\"]}]}",
  )
  let first = plan.transform_with_state("{\"t\":[{\"id\":1}]}", secret)
  assert_eq(
    error_code(() => {
      ignore(
        plan.transform_with_state(
          "{\"t\":[{\"id\":2}]}",
          secret,
          previous=first.state_json(),
        ),
      )
    }),
    "reindex_overflow",
  )
  assert_eq(
    plan
    .transform_with_state(
      "{\"t\":[{\"id\":1}]}",
      secret,
      previous=first.state_json(),
    )
    .state_json(),
    first.state_json(),
  )
}
