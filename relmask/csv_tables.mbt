///|
fn csv_value(
  cell : CsvCell,
  column : Column,
  location : String,
) -> Json raise MaskError {
  let value = if cell.value == "\\N" && !cell.quoted {
    Json::null()
  } else {
    match column.kind {
      Text => Json::string(cell.value)
      Integer | Decimal | Boolean => {
        let parsed = parse_json(cell.value, location)
        if cell.value != parsed.stringify() {
          reject("csv_scalar_format", location)
        }
        match (column.kind, parsed) {
          (Integer | Decimal, Number(_, ..)) | (Boolean, True | False) => ()
          _ => reject("type_mismatch", location)
        }
        parsed
      }
    }
  }
  check_cell(value, column, location)
  value
}

///|
/// Import one header-bearing CSV string per declared table. Types come only from
/// the plan. Unquoted \N means null; quoted "\N" remains text. Validates the
/// complete relational dataset and returns canonical JSON with original values.
pub fn Plan::import_csv(
  self : Plan,
  tables : Map[String, String],
) -> String raise MaskError {
  for name, _ in tables {
    if table_index(self.tables, name) is None {
      reject("csv_unknown_table", "csv")
    }
  }
  let rows : Rows = []
  let mut units = 0L
  let mut count = 0
  for table in self.tables {
    let loc = "csv." + table.name
    guard tables.get(table.name) is Some(source) else {
      reject("csv_missing_table", loc)
    }
    units += source.length().to_int64()
    if units > self.max_input_units.to_int64() {
      reject("input_too_large", "csv")
    }
    let records = csv_records(
      source,
      table.columns.length(),
      self.max_rows - count,
      loc,
    )
    let header = records[0]
    if header.length() != table.columns.length() {
      reject("csv_width", loc)
    }
    let positions : Map[String, Int32] = Map([])
    for ci, cell in header {
      if positions.contains(cell.value) {
        reject("csv_duplicate_header", loc)
      }
      if column_index(table, cell.value) is None {
        reject("csv_unknown_column", loc)
      }
      positions[cell.value] = ci
    }
    let table_rows : Array[Array[Json]] = []
    for ri in 1..<records.length() {
      let record = records[ri]
      if record.length() != header.length() {
        reject("csv_width", loc + ".row[" + ri.to_string() + "]")
      }
      let row = table.columns.map(column => {
        csv_value(
          record[positions[column.name]],
          column,
          loc + ".row[" + ri.to_string() + "]." + column.name,
        )
      })
      table_rows.push(row)
    }
    count += table_rows.length()
    rows.push(table_rows)
  }
  validate_rows(self, rows)
  let encoded = encode_rows(self, rows)
  if encoded.length() > self.max_input_units {
    reject("output_too_large", "data")
  }
  encoded
}

///|
/// Export validated JSON to one CSV string per table in policy column order.
/// Text and headers are always quoted; null is unquoted \N. Numeric spelling is
/// preserved. This does not mask values; use transformed or verified data to share.
pub fn Plan::export_csv(
  self : Plan,
  source : String,
) -> Map[String, String] raise MaskError {
  let rows = load(self, source)
  validate_rows(self, rows)
  let result : Map[String, String] = Map([])
  let mut units = 0L
  for ti, table in self.tables {
    let records = [
      table.columns.map(column => csv_quote(column.name)).join(","),
    ]
    for row in rows[ti] {
      records.push(
        row
        .map(value => {
          match value {
            Null => "\\N"
            String(text) => csv_quote(text)
            _ => value.stringify()
          }
        })
        .join(","),
      )
    }
    let csv = records.join("\r\n") + "\r\n"
    units += csv.length().to_int64()
    if units > self.max_input_units.to_int64() {
      reject("csv_output_too_large", "csv")
    }
    result[table.name] = csv
  }
  result
}
