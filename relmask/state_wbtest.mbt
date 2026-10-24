///|
test "authenticated malformed mapping entries still reject" {
  let plan = Plan::parse(
    "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":{\"reindex\":100}}],\"primary\":[\"id\"]}]}",
  )
  let secret = "test-key-32-bytes-for-relmask-suite"
  let tag = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  for
    (state, code) in [
      (Map([(0, Map([(tag, 101L)]))]), "state_sequence"),
      (Map([(999, Map([(tag, 100L)]))]), "state_domain"),
      (Map([(0, Map([("bad", 100L)]))]), "state_tag"),
      (
        Map([
          (
            0,
            Map([
              (tag, 100L),
              (
                "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                100L,
              ),
            ]),
          ),
        ]),
        "state_sequence",
      ),
    ] {
    let encoded = encode_state(plan, secret, state)
    let actual = try {
      ignore(plan.transform_with_state("{\"t\":[]}", secret, previous=encoded))
      "success"
    } catch {
      Invalid(code~, ..) => code
    }
    assert_eq(actual, code)
  }
}
