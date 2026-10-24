///|
test "SQL export quotes identifiers encodes text and preserves numeric precision" {
  let plan = @relmask.Plan::parse(policy())
  let data = substitute(dataset(), "-0.000", "0.000")
  let sql = plan.export_sql(data, schema="odd\"schema")
  assert_true(sql.has_prefix("BEGIN;\n"))
  assert_true(sql.has_suffix("COMMIT;\n"))
  assert_true(sql.contains("CREATE SCHEMA \"odd\"\"schema\";"))
  assert_true(sql.contains("'9007199254740993'::bigint"))
  assert_true(sql.contains("'12.345678901234567890'::numeric"))
  assert_true(sql.contains("'1e400'::numeric"))
  assert_true(sql.contains("DEFERRABLE INITIALLY DEFERRED"))
  assert_true(!sql.contains("b@example.test"))
  assert_eq(sql, plan.export_sql(data, schema="odd\"schema"))
}

///|
test "SQL refuses NUL negative zero numeric range and unsafe identifier loss" {
  let plan = @relmask.Plan::parse(policy())
  assert_eq(
    error_code(() => ignore(plan.export_sql(dataset()))),
    "sql_negative_zero",
  )
  let data = substitute(dataset(), "-0.000", "0.000")
  let nul = substitute(data, "private", "\\u0000")
  assert_eq(error_code(() => ignore(plan.export_sql(nul))), "sql_text_nul")
  assert_eq(
    error_code(() => {
      ignore(plan.export_sql(substitute(data, "1e400", "1e131072")))
    }),
    "sql_numeric_range",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.export_sql(substitute(data, "1e400", "1e-16384")))
    }),
    "sql_numeric_range",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.export_sql(data, schema=Array::make(64, "x").join("")))
    }),
    "sql_identifier",
  )
  assert_eq(
    error_code(() => ignore(plan.export_sql(data, schema="pg_custom"))),
    "sql_schema_reserved",
  )
  assert_eq(
    error_code(() => ignore(plan.export_sql(data, max_output_units=1))),
    "sql_output_limit",
  )
  ignore(plan.export_sql(data))
}

///|
test "SQL serializes nullable unique modes and FULL references without downgrade" {
  let plan = @relmask.Plan::parse(
    nullable_policy(
      "{\"columns\":[\"tenant\",\"alias\"],\"nulls\":\"not_distinct\"}",
    ),
  )
  let sql = plan.export_sql(
    "{\"t\":[{\"id\":1,\"tenant\":\"a\",\"alias\":null}]}",
  )
  assert_true(sql.contains("UNIQUE NULLS NOT DISTINCT (\"tenant\",\"alias\")"))
  let full = @relmask.Plan::parse(
    substitute(
      compound_policy(),
      "\"target\":[\"tenant\",\"account\"]",
      "\"target\":[\"tenant\",\"account\"],\"match\":\"full\"",
    ),
  )
  assert_true(
    full.export_sql("{\"accounts\":[],\"events\":[]}").contains("MATCH FULL"),
  )
}

///|
test "SQL accepts numeric endpoints and measures identifiers in UTF8 bytes" {
  let plan = @relmask.Plan::parse(policy())
  let data = substitute(dataset(), "-0.000", "0.000")
  for number in ["1e131071", "1e-16383"] {
    assert_true(
      plan
      .export_sql(substitute(data, "1e400", number))
      .contains("'" + number + "'::numeric"),
    )
  }
  ignore(plan.export_sql(data, schema=Array::make(21, "界").join("")))
  assert_eq(
    error_code(() => {
      ignore(plan.export_sql(data, schema=Array::make(22, "界").join("")))
    }),
    "sql_identifier",
  )
  assert_eq(
    error_code(() => {
      ignore(plan.export_sql(substitute(data, "1e400", "1e999999999")))
    }),
    "sql_numeric_range",
  )
}
