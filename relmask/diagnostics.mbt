///|
/// Bounded, value-free validation findings. Shape errors suppress constraint
/// checking; inspect constraints_checked in the report before interpreting it.
pub struct Diagnostics {
  priv encoded : String
  priv valid : Bool
}

///|
pub fn Diagnostics::to_json(self : Diagnostics) -> String {
  self.encoded
}

///|
pub fn Diagnostics::is_valid(self : Diagnostics) -> Bool {
  self.valid
}

///|
priv struct Findings {
  issues : Array[String]
  limit : Int32
  mut truncated : Bool
}

///|
fn Findings::add(self : Findings, code : String, location : String) -> Unit {
  if self.issues.length() < self.limit {
    self.issues.push(
      "{\"code\":" +
      Json::string(code).stringify() +
      ",\"location\":" +
      Json::string(location).stringify() +
      "}",
    )
  } else {
    self.truncated = true
  }
}

///|
fn Findings::report(self : Findings, constraints_checked : Bool) -> Diagnostics {
  let valid = self.issues.is_empty()
  {
    encoded: "{\"valid\":" +
    valid.to_string() +
    ",\"constraints_checked\":" +
    constraints_checked.to_string() +
    ",\"truncated\":" +
    self.truncated.to_string() +
    ",\"issues\":[" +
    self.issues.join(",") +
    "]}",
    valid,
  }
}

///|
/// Diagnose multiple shape or relational errors without emitting cell values.
/// Invalid JSON and resource-limit failures still raise; no partial report.
pub fn Plan::diagnose(
  self : Plan,
  source : String,
  max_issues~ : Int32 = 100,
) -> Diagnostics raise MaskError {
  if max_issues < 1 || max_issues > 1000 {
    reject("diagnose_limit_range", "diagnose")
  }
  if source.length() > self.max_input_units {
    reject("input_too_large", "data")
  }
  let findings : Findings = { issues: [], limit: max_issues, truncated: false, }
  let parsed = parse_json(source, "data")
  guard parsed is Object(root) else {
    findings.add("expected_object", "data")
    return findings.report(false)
  }
  let rows = audit_shape(self, root, findings)
  if !findings.issues.is_empty() {
    return findings.report(false)
  }
  audit_constraints(self, rows, findings)
  findings.report(true)
}
