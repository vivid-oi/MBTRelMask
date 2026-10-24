///|
test "diagnostics collect constraint errors with bounded value-free output" {
  let plan = @relmask.Plan::parse(policy())
  let data = substitute(dataset(), "\"id\":9007199254740993", "\"id\":42")
  let report = plan.diagnose(data)
  assert_true(!report.is_valid())
  guard @json.parse(report.to_json())
    is { "constraints_checked": True, "issues": Array(issues), .. } else {
    fail("phase")
  }
  assert_true(
    issues.any(issue => issue is { "code": String("duplicate_key"), .. }),
  )
  assert_true(
    issues.any(issue => issue is { "code": String("orphan_reference"), .. }),
  )
  assert_true(!report.to_json().contains("example.test"))
  assert_true(!report.to_json().contains("9007199254740993"))
  assert_true(
    @json.parse(plan.diagnose(data, max_issues=1).to_json())
    is { "truncated": True, "issues": Array([_]), .. },
  )
  assert_true(plan.diagnose(dataset()).is_valid())
}

///|
test "shape findings are recoverable and never imply constraints were checked" {
  let plan = @relmask.Plan::parse(policy())
  let data = "{\"people\":[{\"id\":\"sensitive-wrong-type\",\"email\":7}],\"orders\":[]}"
  let report = plan.diagnose(data)
  assert_true(!report.to_json().contains("sensitive-wrong-type"))
  assert_true(
    @json.parse(report.to_json())
    is {
      "valid": False,
      "constraints_checked": False,
      "issues": Array(issues),
      ..
    } &&
    issues.length() == 3,
  )
  assert_true(
    @json.parse(plan.diagnose("[]").to_json())
    is { "constraints_checked": False, "valid": False, .. },
  )
  assert_eq(error_code(() => ignore(plan.diagnose("{"))), "invalid_json")
  assert_eq(
    error_code(() => ignore(plan.diagnose(dataset(), max_issues=0))),
    "diagnose_limit_range",
  )
  assert_true(plan.diagnose(dataset()).is_valid())
}

///|
test "generated duplicate audits agree with ordinary validation and retain exact keys" {
  let plan = @relmask.Plan::parse(
    "{\"tables\":[{\"name\":\"t\",\"columns\":[{\"name\":\"id\",\"type\":\"integer\",\"rule\":\"keep\"}],\"primary\":[\"id\"]}]}",
  )
  for n in 1..<=30 {
    let rows = Array::makei(n * 2, i => {
      "{\"id\":" + (9007199254740992L + (i % n).to_int64()).to_string() + "}"
    })
    let data = "{\"t\":[" + rows.join(",") + "]}"
    guard @json.parse(plan.diagnose(data).to_json())
      is { "constraints_checked": True, "issues": Array(issues), .. } else {
      fail("phase")
    }
    assert_eq(issues.length(), n)
    assert_eq(error_code(() => ignore(plan.validate(data))), "duplicate_key")
  }
}
