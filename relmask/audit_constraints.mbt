///|
fn audit_key(
  table : TableSpec,
  rows : Array[Array[Json]],
  columns : Array[String],
  primary : Bool,
  nulls_equal : Bool,
  suffix : String,
  findings : Findings,
) -> Unit raise MaskError {
  let seen : Map[String, Bool] = Map([])
  for ri, row in rows {
    let loc = table.name + "[" + ri.to_string() + "]." + suffix
    match tuple_key(row, table, columns, nulls_equal~) {
      None => if primary { findings.add("null_primary_key", loc) }
      Some(key) => {
        if seen.contains(key) {
          findings.add("duplicate_key", loc)
        }
        seen[key] = true
      }
    }
  }
}

///|
fn audit_constraints(
  plan : Plan,
  rows : Rows,
  findings : Findings,
) -> Unit raise MaskError {
  for ti, table in plan.tables {
    audit_key(table, rows[ti], table.primary, true, false, "primary", findings)
    for ui, key in table.unique {
      audit_key(
        table,
        rows[ti],
        key.columns,
        false,
        key.nulls_equal,
        "unique[" + ui.to_string() + "]",
        findings,
      )
    }
    for fi, reference in table.references {
      let pi = table_index(plan.tables, reference.target).unwrap()
      let parents : Map[String, Bool] = Map([])
      for row in rows[pi] {
        if tuple_key(row, plan.tables[pi], reference.target_columns)
          is Some(key) {
          parents[key] = true
        }
      }
      for ri, row in rows[ti] {
        let loc = table.name +
          "[" +
          ri.to_string() +
          "].references[" +
          fi.to_string() +
          "]"
        if reference.full {
          let nulls = reference.columns
            .filter(name => row[column_index(table, name).unwrap()] is Null)
            .length()
          if nulls > 0 && nulls < reference.columns.length() {
            findings.add("partial_null_reference", loc)
            continue
          }
        }
        if tuple_key(row, table, reference.columns) is Some(key) &&
          !parents.contains(key) {
          findings.add("orphan_reference", loc)
        }
      }
    }
  }
}
