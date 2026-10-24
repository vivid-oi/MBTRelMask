///|
test "CSV round trip preserves null empty quoted markers Unicode and exact numbers" {
  let p = "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"},{\"name\":\"text\",\"type\":\"text\",\"nullable\":true,\"rule\":\"keep\"},{\"name\":\"n\",\"type\":\"decimal\",\"rule\":\"keep\"},{\"name\":\"ok\",\"type\":\"boolean\",\"rule\":\"keep\"}],\"primary\":[\"id\"]}]}"
  let plan = @relmask.Plan::parse(p)
  let data = "{\"t\":[{\"id\":9223372036854775807,\"text\":\"\\\\N\",\"n\":1e400,\"ok\":true},{\"id\":-9223372036854775808,\"text\":\"\",\"n\":-0.000,\"ok\":false},{\"id\":0,\"text\":null,\"n\":0.00000000000001,\"ok\":true},{\"id\":1,\"text\":\"界,\\\"词\\\"\\r\\nnext\",\"n\":2,\"ok\":false}]}"
  let files = plan.export_csv(data)
  assert_eq(plan.import_csv(files), data)
  assert_true(files["t"].contains("\"\\N\""))
  assert_true(files["t"].contains(",\\N,"))
  assert_eq(plan.export_csv(plan.import_csv(files))["t"], files["t"])
}

///|
test "CSV input headers may reorder without inferring text types" {
  let plan = @relmask.Plan::parse(policy())
  let files = {
    "people": "\u{feff}email,note,id\nb@example.test,\\N,42\n",
    "orders": "amount,person,id\n12.345678901234567890,42,1\n",
  }
  let data = plan.import_csv(files)
  assert_true(data.contains("12.345678901234567890"))
  assert_true(data.contains("\"note\":null"))
  ignore(plan.transform(data, secret))
  assert_eq(plan.import_csv(plan.export_csv(data)), data)
}

///|
test "CSV malformed syntax headers widths types and missing tables reject then recover" {
  let plan = @relmask.Plan::parse(policy())
  let good_people = "id,email,note\n42,b@example.test,\"\"\n"
  let orders = "id,person,amount\n1,42,0\n"
  for
    (people, code) in [
      ("", "csv_missing_header"),
      ("id,email,note\n42,\"unclosed,x", "csv_unclosed_quote"),
      ("id,email,note\n42,\"closed\"tail,x", "csv_after_quote"),
      ("id,email,note\n42,un\"expected,x", "csv_unexpected_quote"),
      ("id,email,note\r42,x,x", "csv_bare_cr"),
      ("id,id,note\n42,x,x", "csv_duplicate_header"),
      ("id,extra,note\n42,x,x", "csv_unknown_column"),
      ("id,email,note\n42,x", "csv_width"),
      ("id,email,note\n42,x,x,extra", "csv_width"),
      ("id,email,note\n42.0,x,x", "expected_integer"),
      ("id,email,note\n 42,x,x", "csv_scalar_format"),
    ] {
    assert_eq(
      error_code(() => {
        ignore(plan.import_csv({ "people": people, "orders": orders }))
      }),
      code,
    )
  }
  assert_eq(
    error_code(() => ignore(plan.import_csv({ "people": good_people }))),
    "csv_missing_table",
  )
  assert_eq(
    error_code(() => ignore(plan.import_csv({ "unknown": "x" }))),
    "csv_unknown_table",
  )
  let orphan = "id,person,amount\n1,999,0\n"
  assert_eq(
    error_code(() => {
      ignore(plan.import_csv({ "people": good_people, "orders": orphan }))
    }),
    "orphan_reference",
  )
  ignore(plan.import_csv({ "people": good_people, "orders": orders }))
}

///|
test "CSV null markers are explicit and budgets apply to whole batches" {
  let p = "{\"max_rows\":1,\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"},{\"name\":\"n\",\"type\":\"integer\",\"nullable\":true,\"rule\":\"keep\"}],\"primary\":[\"id\"]}]}"
  let plan = @relmask.Plan::parse(p)
  assert_eq(
    plan.import_csv({ "t": "id,n\n1,\\N" }),
    "{\"t\":[{\"id\":1,\"n\":null}]}",
  )
  assert_eq(
    error_code(() => ignore(plan.import_csv({ "t": "id,n\n1,null" }))),
    "type_mismatch",
  )
  assert_eq(
    error_code(() => ignore(plan.import_csv({ "t": "id,n\n1,\"\\N\"" }))),
    "invalid_json",
  )
  assert_eq(
    error_code(() => ignore(plan.import_csv({ "t": "id,n\n1,0\n2,0" }))),
    "row_limit",
  )
  assert_eq(plan.import_csv({ "t": "id,n" }), "{\"t\":[]}")
  let small = @relmask.Plan::parse(
    substitute(p, "\"max_rows\":1", "\"max_rows\":1,\"max_input_units\":8"),
  )
  assert_eq(
    error_code(() => ignore(small.import_csv({ "t": "id,n\n1,0\n" }))),
    "input_too_large",
  )
  assert_eq(
    error_code(() => ignore(small.export_csv("{\"t\":[]}"))),
    "csv_output_too_large",
  )
}

///|
test "CSV final empty fields and blank records are preserved rather than skipped" {
  let p = "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"text\",\"rule\":\"keep\"},{\"name\":\"v\",\"type\":\"text\",\"rule\":\"keep\"}],\"primary\":[\"id\"]}]}"
  let plan = @relmask.Plan::parse(p)
  assert_eq(
    plan.import_csv({ "t": "id,v\na," }),
    "{\"t\":[{\"id\":\"a\",\"v\":\"\"}]}",
  )
  assert_eq(
    error_code(() => ignore(plan.import_csv({ "t": "id,v\na,b\n\n" }))),
    "csv_width",
  )
  let single = @relmask.Plan::parse(
    "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"text\",\"rule\":\"keep\"}],\"primary\":[\"id\"]}]}",
  )
  assert_eq(single.import_csv({ "t": "id\n\n" }), "{\"t\":[{\"id\":\"\"}]}")
}

///|
test "CSV generated batches preserve delimiters quotes newlines markers and text digits" {
  let p = "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"},{\"name\":\"v\",\"type\":\"text\",\"nullable\":true,\"rule\":\"keep\"}],\"primary\":[\"id\"]}]}"
  let plan = @relmask.Plan::parse(p)
  let values = [
    "", "\\N", "界🙂", ",", "\"", "\r\n", "\n", "  x  ", "01", "true", "a\"b,c\nd",
  ]
  for n in 0..<=40 {
    let rows : Array[String] = []
    for i in 0..<n {
      let text = if i % 7 == 0 {
        "null"
      } else {
        Json::string(values[i % values.length()]).stringify()
      }
      rows.push("{\"id\":" + i.to_string() + ",\"v\":" + text + "}")
    }
    let source = "{\"t\":[" + rows.join(",") + "]}"
    assert_eq(plan.import_csv(plan.export_csv(source)), source)
  }
}
