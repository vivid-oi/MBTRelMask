///|
test "aggregate subsets include allowed children only and refuse truncation" {
  let plan = @relmask.Plan::parse(policy())
  let seed = "{\"people\":[{\"id\":42}]}"
  let options = "{\"descendants\":[\"orders\"],\"max_rows\":2}"
  let result = plan.subset(dataset(), seed, options~)
  assert_true(
    @json.parse(result) is { "people": Array([_]), "orders": Array([_]), .. },
  )
  assert_true(result.contains("1e400"))
  assert_eq(plan.subset(result, seed, options~), result)
  assert_eq(
    error_code(() => {
      ignore(
        plan.subset(
          dataset(),
          seed,
          options="{\"descendants\":[\"orders\"],\"max_rows\":1}",
        ),
      )
    }),
    "subset_row_limit",
  )
  assert_eq(
    error_code(() => {
      ignore(
        plan.subset(dataset(), seed, options="{\"descendants\":[\"unknown\"]}"),
      )
    }),
    "unknown_child_table",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.subset(dataset(), seed, options="{\"max_rows\":0}"))
    }),
    "subset_limit_range",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.subset(dataset(), seed, options="{\"truncate\":true}"))
    }),
    "unknown_option",
  )
  assert_eq(plan.subset(dataset(), seed, options~), result)
  assert_eq(
    error_code(() => {
      ignore(
        plan.subset(
          dataset(),
          seed,
          options="{\"descendants\":[\"orders\",\"orders\"]}",
        ),
      )
    }),
    "duplicate_child_reference",
  )
  let ambiguous = @relmask.Plan::parse(
    substitute(
      policy(),
      "\"references\":[",
      "\"references\":[{\"columns\":[\"person\"],\"table\":\"people\",\"target\":[\"id\"]},",
    ),
  )
  assert_eq(
    error_code(() => {
      ignore(
        ambiguous.subset(
          dataset(),
          seed,
          options="{\"descendants\":[\"orders\"]}",
        ),
      )
    }),
    "ambiguous_or_missing_child_reference",
  )
}

///|
test "aggregate reverse joins match complete tuples and exclude null references" {
  let plan = @relmask.Plan::parse(compound_policy())
  let seed = "{\"accounts\":[{\"tenant\":\"south\",\"account\":7}]}"
  let out = plan.subset(
    compound_data(),
    seed,
    options="{\"descendants\":[\"events\"]}",
  )
  assert_true(
    @json.parse(out)
    is {
      "accounts": Array([_]),
      "events": Array([{ "id": Number(1.0, ..), .. }]),
      ..
    },
  )
  ignore(plan.validate(out))
  assert_eq(
    plan.subset(compound_data(), seed, options="{}"),
    plan.subset(compound_data(), seed),
  )
}
