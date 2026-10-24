///|
fn substitute(source : String, old : String, new : String) -> String {
  source.replace(old~, new~)
}

///|
fn compound_policy() -> String {
  (
    #|{"tables":[
    #|{"name":"accounts","columns":[
    #|{"name":"tenant","type":"text","rule":{"token":{"domain":"tenant"}}},
    #|{"name":"account","type":"integer","rule":{"reindex":1000}}],"primary":["tenant","account"]},
    #|{"name":"events","columns":[
    #|{"name":"id","type":"integer","rule":"keep"},
    #|{"name":"tenant","type":"text","nullable":true,"rule":{"token":{"domain":"tenant"}}},
    #|{"name":"account","type":"integer","nullable":true,"rule":{"reindex":1000}}],
    #|"primary":["id"],"references":[{"columns":["tenant","account"],"table":"accounts","target":["tenant","account"]}]}]}
  )
}

///|
fn compound_data() -> String {
  (
    #|{"accounts":[{"tenant":"north","account":7},{"tenant":"south","account":7},{"tenant":"north","account":8}],
    #|"events":[{"id":1,"tenant":"south","account":7},{"id":2,"tenant":null,"account":999},{"id":3,"tenant":"missing","account":null}]}
  )
}

///|
test "compound references preserve tenant partitions and partial nulls" {
  let plan = @relmask.Plan::parse(compound_policy())
  let result = plan.transform(compound_data(), secret).to_json()
  guard @json.parse(result)
    is { "accounts": Array(accounts), "events": Array(events), .. } else {
    fail("shape")
  }
  guard accounts[0] is { "tenant": t0, "account": a0, .. } &&
    accounts[1] is { "tenant": t1, "account": a1, .. } &&
    accounts[2] is { "tenant": t2, "account": a2, .. } &&
    events[0] is { "tenant": et, "account": ea, .. } else {
    fail("shape")
  }
  assert_eq(t0, t2)
  assert_true(t0 != t1)
  assert_eq(a0, a1)
  assert_true(a0 != a2)
  assert_eq(et, t1)
  assert_eq(ea, a1)
  assert_true(events[1] is { "tenant": Null, .. })
  assert_true(events[2] is { "account": Null, .. })
  ignore(plan.validate(result))
  // Change the child, leaving both scalar values present in the parent table.
  let orphan = substitute(
    compound_data(),
    "\"id\":1,\"tenant\":\"south\",\"account\":7",
    "\"id\":1,\"tenant\":\"south\",\"account\":8",
  )
  assert_eq(error_code(() => ignore(plan.validate(orphan))), "orphan_reference")
  assert_eq(plan.transform(compound_data(), secret).to_json(), result)
}

///|
test "compound mappings do not depend on parent row order" {
  let plan = @relmask.Plan::parse(compound_policy())
  let source = compound_data()
  let reordered = substitute(
    source, "{\"tenant\":\"north\",\"account\":7},{\"tenant\":\"south\",\"account\":7}",
    "{\"tenant\":\"south\",\"account\":7},{\"tenant\":\"north\",\"account\":7}",
  )
  let a = @json.parse(plan.transform(source, secret).to_json())
  let b = @json.parse(plan.transform(reordered, secret).to_json())
  guard a is { "accounts": Array(ap), "events": ae, .. } &&
    b is { "accounts": Array(bp), "events": be, .. } else {
    fail("shape")
  }
  assert_eq(ae, be)
  assert_eq(ap[0], bp[1])
  assert_eq(ap[1], bp[0])
}

///|
test "every compound position validates arity type and rule" {
  let p = compound_policy()
  assert_eq(
    error_code(() => {
      ignore(
        @relmask.Plan::parse(
          substitute(
            p, "\"columns\":[\"tenant\",\"account\"]", "\"columns\":[\"tenant\"]",
          ),
        ),
      )
    }),
    "reference_arity",
  )
  let p = substitute(
    p, "\"nullable\":true,\"rule\":{\"reindex\":1000}", "\"nullable\":true,\"rule\":{\"reindex\":2000}",
  )
  assert_eq(
    error_code(() => ignore(@relmask.Plan::parse(p))),
    "reference_rule_mismatch",
  )
  let p = substitute(
    compound_policy(),
    "\"type\":\"integer\",\"nullable\":true,\"rule\":{\"reindex\":1000}",
    "\"type\":\"boolean\",\"nullable\":true,\"rule\":\"keep\"",
  )
  assert_eq(
    error_code(() => ignore(@relmask.Plan::parse(p))),
    "reference_type_mismatch",
  )
}

///|
test "compound tuple encoding is unambiguous with delimiters and Unicode" {
  let p = substitute(
    compound_policy(),
    "\"type\":\"integer\",\"rule\":{\"reindex\":1000}",
    "\"type\":\"text\",\"rule\":\"keep\"",
  )
  let p = substitute(
    p, "\"type\":\"integer\",\"nullable\":true,\"rule\":{\"reindex\":1000}", "\"type\":\"text\",\"nullable\":true,\"rule\":\"keep\"",
  )
  let plan = @relmask.Plan::parse(p)
  let data = "{\"accounts\":[{\"tenant\":\"a|界\",\"account\":\"c\"},{\"tenant\":\"a\",\"account\":\"界|c\"}],\"events\":[{\"id\":1,\"tenant\":\"a|界\",\"account\":\"c\"}]}"
  let out = plan.transform(data, secret).to_json()
  ignore(plan.validate(out))
  let invalid = substitute(
    data, "\"id\":1,\"tenant\":\"a|界\",\"account\":\"c\"", "\"id\":1,\"tenant\":\"a\",\"account\":\"c\"",
  )
  assert_eq(
    error_code(() => ignore(plan.validate(invalid))),
    "orphan_reference",
  )
}
