///|
fn sql_utf8(value : String, location : String) -> Bytes raise MaskError {
  let bytes = @utf8.encode(value[:])
  let roundtrip = @utf8.decode(bytes[:]) catch {
    _ => {
      reject("sql_utf8", location)
      ""
    }
  }
  if roundtrip != value {
    reject("sql_utf8", location)
  }
  return bytes
}

///|
fn sql_identifier(value : String, location : String) -> String raise MaskError {
  let bytes = sql_utf8(value, location)
  if value.is_empty() ||
    bytes.length() > 63 ||
    value.to_array().any(ch => ch < ' ' || ch == '\u{7f}') {
    reject("sql_identifier", location)
  }
  let out = StringBuilder()
  out.write_char('"')
  for ch in value.to_array() {
    out.write_char(ch)
    if ch == '"' {
      out.write_char('"')
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
fn sql_number(
  raw : String,
  decimal : Bool,
  location : String,
) -> String raise MaskError {
  let chars = raw.to_array()
  let mut before = 0
  let mut after = 0
  let mut fraction = false
  let mut nonzero = false
  let mut pos = 0
  while pos < chars.length() && chars[pos] != 'e' && chars[pos] != 'E' {
    let ch = chars[pos]
    if ch == '.' {
      fraction = true
    } else if ch != '-' {
      if ch != '0' {
        nonzero = true
      }
      if fraction {
        after += 1
      } else {
        before += 1
      }
    }
    pos += 1
  }
  if chars.get(0) == Some('-') && !nonzero {
    reject("sql_negative_zero", location)
  }
  let mut exponent = 0
  if pos < chars.length() {
    pos += 1
    let negative = chars[pos] == '-'
    if chars[pos] == '-' || chars[pos] == '+' {
      pos += 1
    }
    while pos < chars.length() {
      // Inputs have already passed the JSON scalar grammar.
      exponent = exponent * 10 + (chars[pos].to_int() - 48)
      if exponent > 1_000_000 {
        reject("sql_numeric_range", location)
      }
      pos += 1
    }
    if negative {
      exponent = -exponent
    }
  }
  if decimal &&
    (
      before + after > 147455 ||
      before + exponent > 131072 ||
      after - exponent > 16383
    ) {
    reject("sql_numeric_range", location)
  }
  "'" + raw + "'::" + (if decimal { "numeric" } else { "bigint" })
}

///|
fn sql_cell(
  value : Json,
  column : Column,
  location : String,
) -> String raise MaskError {
  match value {
    Null => "NULL"
    String(text) => {
      if text.contains("\u{0000}") {
        reject("sql_text_nul", location)
      }
      let encoded = hex(sql_utf8(text, location))
      "pg_catalog.convert_from(pg_catalog.decode('" +
      encoded +
      "','hex'),'UTF8')"
    }
    True => "TRUE"
    False => "FALSE"
    Number(_, repr=Some(raw)) =>
      sql_number(raw, column.kind is Decimal, location)
    _ => {
      reject("sql_scalar", location)
      ""
    }
  }
}
