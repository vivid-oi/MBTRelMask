///|
/// A value-free diagnostic. Locations identify schema entries or row indexes.
pub(all) suberror MaskError {
  Invalid(code~ : String, location~ : String)
}

///|
pub fn MaskError::message(self : MaskError) -> String {
  let Invalid(code~, location~) = self
  code + " at " + location
}

///|
pub impl Show for MaskError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub extend MaskError with Show::{output, to_string}

///|
fn reject(code : String, location : String) -> Unit raise MaskError {
  raise Invalid(code~, location~)
}

///|
priv enum Kind {
  Text
  Integer
  Decimal
  Boolean
}

///|
priv enum Rule {
  Keep
  Clear
  Replace(String)
  Token(String, String, String)
  Reindex(Int64)
}

///|
priv struct Column {
  name : String
  kind : Kind
  nullable : Bool
  max_length : Int32?
  rule : Rule
}

///|
priv struct Reference {
  columns : Array[String]
  target : String
  target_columns : Array[String]
  full : Bool
}

///|
priv struct TableSpec {
  name : String
  columns : Array[Column]
  primary : Array[String]
  unique : Array[Array[String]]
  references : Array[Reference]
}

///|
/// Immutable, validated configuration. Construct with `Plan::parse`.
pub struct Plan {
  priv tables : Array[TableSpec]
  priv max_rows : Int32
  priv max_input_units : Int32
  priv fingerprint : String
}

///|
/// Completed transformation. Data is available only after all checks succeed.
/// Checked refers to declared relational constraints, not anonymity.
pub struct CheckedDataset {
  priv encoded : String
  priv report : String
  priv fingerprint : String
}

///|
/// Canonical JSON: table/column order follows the plan; row order is preserved.
pub fn CheckedDataset::to_json(self : CheckedDataset) -> String {
  self.encoded
}

///|
/// Counts only; never includes input cells, pseudonym maps, or the secret.
pub fn CheckedDataset::report_json(self : CheckedDataset) -> String {
  self.report
}

///|
fn parse_json(source : String, location : String) -> Json raise MaskError {
  @json.parse(
    source[:],
    reject_duplicate_keys=true,
    preserve_number_repr=true,
    max_nesting_depth=64,
  ) catch {
    _ => raise Invalid(code="invalid_json", location~)
  }
}

///|
fn fields(value : Json, location : String) -> Map[String, Json] raise MaskError {
  guard value is Object(result) else {
    reject("expected_object", location)
    abort("unreachable")
  }
  result
}

///|
fn only_keys(
  value : Map[String, Json],
  allowed : Array[String],
  location : String,
) -> Unit raise MaskError {
  for key, _ in value {
    if !allowed.contains(key) {
      reject("unknown_option", location)
    }
  }
}

///|
fn required(
  value : Map[String, Json],
  key : String,
  location : String,
) -> Json raise MaskError {
  match value.get(key) {
    Some(item) => item
    None => {
      reject("missing_" + key, location)
      abort("unreachable")
    }
  }
}

///|
fn text(value : Json, location : String) -> String raise MaskError {
  guard value is String(result) else {
    reject("expected_text", location)
    abort("unreachable")
  }
  result
}

///|
fn items(value : Json, location : String) -> Array[Json] raise MaskError {
  guard value is Array(result) else {
    reject("expected_array", location)
    abort("unreachable")
  }
  result
}

///|
fn integer(value : Json, location : String) -> Int64 raise MaskError {
  guard value is Number(_, repr=Some(raw)) else {
    reject("expected_integer", location)
    abort("unreachable")
  }
  // Integer keys deliberately require integer lexical form, never a Double cast.
  if raw.contains(".") || raw.contains("e") || raw.contains("E") {
    reject("expected_integer", location)
  }
  @string.parse_int64(raw[:]) catch {
    _ => raise Invalid(code="integer_range", location~)
  }
}

///|
fn flag(
  value : Map[String, Json],
  key : String,
  default : Bool,
  location : String,
) -> Bool raise MaskError {
  match value.get(key) {
    None => default
    Some(True) => true
    Some(False) => false
    _ => {
      reject("expected_boolean", location)
      abort("unreachable")
    }
  }
}

///|
fn names(value : Json, location : String) -> Array[String] raise MaskError {
  let result = items(value, location).map(x => text(x, location))
  let seen : Map[String, Bool] = Map([])
  for name in result {
    if name.is_empty() || seen.contains(name) {
      reject("duplicate_or_empty_name", location)
    }
    seen[name] = true
  }
  result
}
