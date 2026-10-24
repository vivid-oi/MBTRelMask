///|
fn audit_shape(
  plan : Plan,
  root : Map[String, Json],
  findings : Findings,
) -> Rows raise MaskError {
  for name, _ in root {
    if table_index(plan.tables, name) is None {
      findings.add("unknown_option", "data")
    }
  }
  let result : Rows = []
  let mut count = 0
  for table in plan.tables {
    let rows : Array[Array[Json]] = []
    result.push(rows)
    guard root.get(table.name) is Some(value) else {
      findings.add("missing_" + table.name, "data")
      continue
    }
    guard value is Array(values) else {
      findings.add("expected_array", table.name)
      continue
    }
    for ri, value in values {
      count += 1
      if count > plan.max_rows {
        reject("row_limit", table.name)
      }
      let loc = table.name + "[" + ri.to_string() + "]"
      guard value is Object(obj) else {
        findings.add("expected_object", loc)
        continue
      }
      for name, _ in obj {
        if column_index(table, name) is None {
          findings.add("unknown_option", loc)
        }
      }
      let cells : Array[Json] = []
      for column in table.columns {
        match obj.get(column.name) {
          None => {
            findings.add("missing_" + column.name, loc)
            cells.push(Json::null())
          }
          Some(cell) => {
            check_cell(cell, column, loc + "." + column.name) catch {
              Invalid(code~, location~) => findings.add(code, location)
            }
            cells.push(cell)
          }
        }
      }
      rows.push(cells)
    }
  }
  result
}
