///|
let secret = "test-key-32-bytes-for-relmask-suite"

///|
fn policy() -> String {
  (
    #|{"tables":[
    #|{"name":"people","columns":[
    #|{"name":"id","type":"integer","rule":{"reindex":100}},
    #|{"name":"email","type":"text","max_length":60,"rule":{"token":{"domain":"email","suffix":"@example.test"}}},
    #|{"name":"note","type":"text","nullable":true,"rule":"null"}],
    #|"primary":["id"],"unique":[["email"]]},
    #|{"name":"orders","columns":[
    #|{"name":"id","type":"integer","rule":"keep"},
    #|{"name":"person","type":"integer","nullable":true,"rule":{"reindex":100}},
    #|{"name":"amount","type":"decimal","rule":"keep"}],
    #|"primary":["id"],"references":[{"columns":["person"],"table":"people","target":["id"]}]}]}
  )
}

///|
fn dataset() -> String {
  (
    #|{"people":[{"id":9007199254740993,"email":"甲@example.test","note":"private"},{"id":42,"email":"b@example.test","note":null}],
    #|"orders":[{"id":1,"person":9007199254740993,"amount":12.345678901234567890},{"id":2,"person":42,"amount":1e400},{"id":3,"person":null,"amount":-0.000}]}
  )
}

///|
fn error_code(f : () -> Unit raise @relmask.MaskError) -> String {
  try {
    f()
    "unexpected success"
  } catch {
    @relmask.Invalid(code~, ..) => code
  }
}

///|
test "existing rows are rewritten together while decimals remain exact" {
  let plan = @relmask.Plan::parse(policy())
  let output = plan.transform(dataset(), secret)
  let json = @json.parse(output.to_json(), preserve_number_repr=true)
  guard json is { "people": Array(people), "orders": Array(orders), .. } else {
    fail("bad output")
  }
  guard people[0] is { "id": a, "email": String(email), "note": Null, .. } else {
    fail("bad person")
  }
  guard orders[0] is { "person": b, .. } else { fail("bad order") }
  assert_eq(a.stringify(), b.stringify())
  assert_true(email.has_suffix("@example.test"))
  assert_true(!output.to_json().contains("甲"))
  assert_true(!output.to_json().contains("private"))
  assert_true(output.to_json().contains("12.345678901234567890"))
  assert_true(output.to_json().contains("1e400"))
  assert_true(output.to_json().contains("-0.000"))
  ignore(plan.validate(output.to_json()))
  assert_true(!output.report_json().contains("example.test"))
  assert_true(!output.report_json().contains(secret))
  assert_eq(plan.transform(dataset(), secret).to_json(), output.to_json())
}

///|
test "unknown data, duplicate fields, orphan and missing field are rejected" {
  let plan = @relmask.Plan::parse(policy())
  for input in ["{\"people\":[],\"people\":[],\"orders\":[]}", "{", "[]"] {
    assert_eq(
      error_code(() => ignore(plan.transform(input, secret))),
      if input != "[]" {
        "invalid_json"
      } else {
        "expected_object"
      },
    )
  }
  assert_eq(
    error_code(() => {
      ignore(plan.validate("{\"people\":[],\"orders\":[],\"extra\":[]}"))
    }),
    "unknown_option",
  )
  assert_eq(
    error_code(() => {
      ignore(
        plan.validate(
          "{\"people\":[],\"orders\":[{\"id\":1,\"person\":8,\"amount\":0}]}",
        ),
      )
    }),
    "orphan_reference",
  )
  assert_eq(
    error_code(() => {
      ignore(
        plan.validate("{\"people\":[],\"orders\":[{\"id\":1,\"amount\":0}]}"),
      )
    }),
    "missing_person",
  )
  ignore(plan.validate(dataset())) // A failure must not mutate the plan.
}

///|
test "keep round trip preserves extreme integers, text and decimal lexemes" {
  let source =
    #|{"tables":[{"name":"t","columns":[{"name":"id","type":"integer","rule":"keep"},{"name":"s","type":"text","rule":"keep"},{"name":"n","type":"decimal","rule":"keep"}],"primary":["id"]}]}
  let plan = @relmask.Plan::parse(source)
  let raw = "{\"t\":[{\"id\":9223372036854775807,\"s\":\"雪\\n\\\"\",\"n\":0.100000000000000000001},{\"id\":-9223372036854775808,\"s\":\"\",\"n\":-1E-999}]}"
  let out = plan.transform(raw, secret).to_json()
  assert_eq(out, raw)
  assert_eq(plan.transform(out, secret).to_json(), out)
}

///|
test "key duplicates are found using exact Int64 rather than Double" {
  let plan = @relmask.Plan::parse(policy())
  let raw = "{\"people\":[{\"id\":1,\"email\":\"a\",\"note\":null},{\"id\":1,\"email\":\"b\",\"note\":null}],\"orders\":[]}"
  assert_eq(error_code(() => ignore(plan.validate(raw))), "duplicate_key")
  let precise = raw
    .replace(
      old="\"id\":1,\"email\":\"a\"",
      new="\"id\":9007199254740992,\"email\":\"a\"",
    )
    .replace(
      old="\"id\":1,\"email\":\"b\"",
      new="\"id\":9007199254740993,\"email\":\"b\"",
    )
  ignore(plan.validate(precise))
}

///|
test "policy coverage, output lengths, capacity, secret and limits fail closed" {
  let base = policy()
  assert_eq(
    error_code(() => {
      ignore(
        @relmask.Plan::parse(
          base.replace(old="\"reindex\":100", new="\"reindex\":99"),
        ),
      )
    }),
    "reference_rule_mismatch",
  )
  let small = @relmask.Plan::parse(
    base.replace(old="\"max_length\":60", new="\"max_length\":20"),
  )
  assert_eq(
    error_code(() => ignore(small.transform(dataset(), secret))),
    "text_too_long",
  )
  let overflow = @relmask.Plan::parse(
    base
    .replace(old="\"reindex\":100", new="\"reindex\":9223372036854775807")
    .replace(old="\"reindex\":100", new="\"reindex\":9223372036854775807"),
  )
  assert_eq(
    error_code(() => ignore(overflow.transform(dataset(), secret))),
    "reindex_overflow",
  )
  let plan = @relmask.Plan::parse(base)
  assert_eq(
    error_code(() => ignore(plan.transform(dataset(), "short"))),
    "secret_too_short",
  )
  let limited = @relmask.Plan::parse(
    base.replace(old="{\"tables\"", new="{\"max_rows\":1,\"tables\""),
  )
  assert_eq(error_code(() => ignore(limited.validate(dataset()))), "row_limit")
}

///|
test "row permutation does not change mappings for the same batch" {
  let plan = @relmask.Plan::parse(policy())
  let permuted = dataset().replace(
    old="{\"id\":9007199254740993,\"email\":\"甲@example.test\",\"note\":\"private\"},{\"id\":42,\"email\":\"b@example.test\",\"note\":null}",
    new="{\"id\":42,\"email\":\"b@example.test\",\"note\":null},{\"id\":9007199254740993,\"email\":\"甲@example.test\",\"note\":\"private\"}",
  )
  let a = @json.parse(plan.transform(dataset(), secret).to_json())
  let b = @json.parse(plan.transform(permuted, secret).to_json())
  guard a is { "people": Array(ap), "orders": ao, .. } else {
    fail("bad output")
  }
  guard b is { "people": Array(bp), "orders": bo, .. } else {
    fail("bad output")
  }
  assert_eq(ap[0], bp[1])
  assert_eq(ap[1], bp[0])
  assert_eq(ao, bo)
}

///|
test "all truncation prefixes reject and subsequent complete call succeeds" {
  let plan = @relmask.Plan::parse(policy())
  let raw = dataset()
  for i in 0..<raw.length() {
    assert_true(
      error_code(() => ignore(plan.validate(raw[:i].to_owned()))) !=
      "unexpected success",
    )
  }
  ignore(plan.transform(raw, secret))
}

///|
test "self references and cycles use one completed domain" {
  let schema =
    #|{"tables":[{"name":"nodes","columns":[{"name":"id","type":"integer","rule":{"reindex":100}},{"name":"next","type":"integer","nullable":true,"rule":{"reindex":100}}],"primary":["id"],"references":[{"columns":["next"],"table":"nodes","target":["id"]}]}]}
  let plan = @relmask.Plan::parse(schema)
  let result = @json.parse(
    plan
    .transform(
      "{\"nodes\":[{\"id\":1,\"next\":2},{\"id\":2,\"next\":1},{\"id\":3,\"next\":null}]}",
      secret,
    )
    .to_json(),
  )
  guard result is { "nodes": Array(rows), .. } else { fail("missing rows") }
  guard rows[0] is { "id": a, "next": b, .. } &&
    rows[1] is { "id": c, "next": d, .. } else {
    fail("missing edges")
  }
  assert_eq(a, d)
  assert_eq(b, c)
}

///|
test "constant replacements cannot silently destroy UNIQUE" {
  let schema =
    #|{"tables":[{"name":"t","columns":[{"name":"id","type":"integer","rule":"keep"},{"name":"name","type":"text","rule":{"replace":"same"}}],"primary":["id"],"unique":[["name"]]}]}
  let plan = @relmask.Plan::parse(schema)
  assert_eq(
    error_code(() => {
      ignore(
        plan.transform(
          "{\"t\":[{\"id\":1,\"name\":\"a\"},{\"id\":2,\"name\":\"b\"}]}", secret,
        ),
      )
    }),
    "duplicate_key",
  )
  ignore(plan.transform("{\"t\":[{\"id\":1,\"name\":\"a\"}]}", secret))
}

///|
test "generated relational batches preserve every edge and row cardinality" {
  let plan = @relmask.Plan::parse(policy())
  for count in 0..<25 {
    let people : Array[String] = []
    let orders : Array[String] = []
    for i in 0..<count {
      let id = (i * 19 + 7).to_string()
      people.push(
        "{\"id\":" +
        id +
        ",\"email\":\"person" +
        i.to_string() +
        "\",\"note\":null}",
      )
      orders.push(
        "{\"id\":" +
        i.to_string() +
        ",\"person\":" +
        id +
        ",\"amount\":0.10000000000000001}",
      )
    }
    let input = "{\"people\":[" +
      people.join(",") +
      "],\"orders\":[" +
      orders.join(",") +
      "]}"
    let output = plan.transform(input, secret).to_json()
    guard @json.parse(output) is { "people": Array(p), "orders": Array(o), .. } else {
      fail("missing dataset")
    }
    assert_eq(p.length(), count)
    assert_eq(o.length(), count)
    let seen : Map[String, Bool] = Map([])
    for i in 0..<count {
      guard p[i] is { "id": id, .. } && o[i] is { "person": ref_id, .. } else {
        fail("missing reference")
      }
      assert_eq(id, ref_id)
      assert_true(!seen.contains(id.stringify()))
      seen[id.stringify()] = true
    }
    ignore(plan.validate(output))
  }
}
