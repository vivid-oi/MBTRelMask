///|
priv struct CsvCell {
  value : String
  quoted : Bool
}

///|
fn csv_records(
  source : String,
  width : Int32,
  max_rows : Int32,
  location : String,
) -> Array[Array[CsvCell]] raise MaskError {
  let chars = source.to_array()
  let mut cursor = if chars.get(0) == Some('\u{feff}') { 1 } else { 0 }
  let records : Array[Array[CsvCell]] = []
  while cursor < chars.length() {
    let record : Array[CsvCell] = []
    for ;; {
      let loc = location +
        ".row[" +
        records.length().to_string() +
        "].field[" +
        record.length().to_string() +
        "]"
      let value = StringBuilder()
      let quoted = cursor < chars.length() && chars[cursor] == '"'
      if quoted {
        cursor += 1
        let mut closed = false
        while cursor < chars.length() {
          let ch = chars[cursor]
          cursor += 1
          if ch == '"' {
            if cursor < chars.length() && chars[cursor] == '"' {
              value.write_char('"')
              cursor += 1
            } else {
              closed = true
              break
            }
          } else {
            value.write_char(ch)
          }
        }
        if !closed {
          reject("csv_unclosed_quote", loc)
        }
        if cursor < chars.length() && ![',', '\r', '\n'].contains(chars[cursor]) {
          reject("csv_after_quote", loc)
        }
      } else {
        while cursor < chars.length() &&
              ![',', '\r', '\n'].contains(chars[cursor]) {
          if chars[cursor] == '"' {
            reject("csv_unexpected_quote", loc)
          }
          value.write_char(chars[cursor])
          cursor += 1
        }
      }
      record.push({ value: value.to_string(), quoted, })
      if record.length() > width {
        reject("csv_width", loc)
      }
      if cursor == chars.length() {
        break
      }
      match chars[cursor] {
        ',' => {
          cursor += 1
          continue
        }
        '\n' => {
          cursor += 1
          break
        }
        '\r' => {
          if cursor + 1 >= chars.length() || chars[cursor + 1] != '\n' {
            reject("csv_bare_cr", loc)
          }
          cursor += 2
          break
        }
        _ => {
          reject("csv_separator", loc)
          break
        }
      }
    }
    records.push(record)
    if records.length() > max_rows + 1 {
      reject("row_limit", location)
    }
  }
  if records.is_empty() {
    reject("csv_missing_header", location)
  }
  records
}

///|
fn csv_quote(value : String) -> String {
  let builder = StringBuilder()
  builder.write_char('"')
  for ch in value.to_array() {
    builder.write_char(ch)
    if ch == '"' {
      builder.write_char('"')
    }
  }
  builder.write_char('"')
  builder.to_string()
}
