///|
type Rows = Array[Array[Array[Json]]]

///|
fn cell_key(
  value : Json,
  column : Column,
  location : String,
) -> String raise MaskError {
  match column.kind {
    Integer => "i" + integer(value, location).to_string()
    _ => value.stringify()
  }
}

///|
fn check_cell(
  value : Json,
  column : Column,
  location : String,
) -> Unit raise MaskError {
  if value is Null {
    if !column.nullable {
      reject("null_not_allowed", location)
    }
    return
  }
  match (column.kind, value) {
    (Text, String(s)) =>
      if column.max_length is Some(n) && s.to_array().length() > n {
        reject("text_too_long", location)
      }
    (Integer, _) => ignore(integer(value, location))
    (Decimal, Number(_, repr=Some(_))) => ()
    (Boolean, True | False) => ()
    _ => reject("type_mismatch", location)
  }
}

///|
fn load(plan : Plan, source : String) -> Rows raise MaskError {
  if source.length() > plan.max_input_units {
    reject("input_too_large", "data")
  }
  let root = fields(parse_json(source, "data"), "data")
  only_keys(root, plan.tables.map(t => t.name), "data")
  let result : Rows = []
  let mut count = 0
  for table in plan.tables {
    let rows : Array[Array[Json]] = []
    for ri, row in items(required(root, table.name, "data"), table.name) {
      count += 1
      if count > plan.max_rows {
        reject("row_limit", table.name)
      }
      let loc = table.name + "[" + ri.to_string() + "]"
      let obj = fields(row, loc)
      only_keys(obj, table.columns.map(c => c.name), loc)
      let cells : Array[Json] = []
      for column in table.columns {
        let cell = required(obj, column.name, loc)
        check_cell(cell, column, loc + "." + column.name)
        cells.push(cell)
      }
      rows.push(cells)
    }
    result.push(rows)
  }
  result
}

///|
fn tuple_key(
  row : Array[Json],
  table : TableSpec,
  names : Array[String],
) -> String? raise MaskError {
  let parts : Array[Json] = []
  for name in names {
    let ci = column_index(table, name).unwrap()
    if row[ci] is Null {
      return None
    }
    parts.push(
      Json::string(
        cell_key(row[ci], table.columns[ci], table.name + "." + name),
      ),
    )
  }
  Some(Json::array(parts).stringify())
}

///|
fn key_set(
  table : TableSpec,
  rows : Array[Array[Json]],
  names : Array[String],
  primary : Bool,
) -> Map[String, Bool] raise MaskError {
  let keys : Map[String, Bool] = Map([])
  for ri, row in rows {
    let loc = table.name + "[" + ri.to_string() + "]"
    match tuple_key(row, table, names) {
      None => if primary { reject("null_primary_key", loc) }
      Some(key) => {
        if keys.contains(key) {
          reject("duplicate_key", loc)
        }
        keys[key] = true
      }
    }
  }
  keys
}

///|
fn validate_rows(plan : Plan, rows : Rows) -> Unit raise MaskError {
  for ti, table in plan.tables {
    ignore(key_set(table, rows[ti], table.primary, true))
    for key in table.unique {
      ignore(key_set(table, rows[ti], key, false))
    }
    for reference in table.references {
      let pi = table_index(plan.tables, reference.target).unwrap()
      let parent = key_set(
        plan.tables[pi],
        rows[pi],
        reference.target_columns,
        false,
      )
      for ri, row in rows[ti] {
        if tuple_key(row, table, reference.columns) is Some(key) &&
          !parent.contains(key) {
          reject(
            "orphan_reference",
            table.name + "[" + ri.to_string() + "].references",
          )
        }
      }
    }
  }
}

///|
fn encode_rows(plan : Plan, rows : Rows) -> String {
  let tables : Array[String] = []
  for ti, table in plan.tables {
    let encoded : Array[String] = []
    for row in rows[ti] {
      let cells : Array[String] = []
      for ci, column in table.columns {
        cells.push(
          Json::string(column.name).stringify() + ":" + row[ci].stringify(),
        )
      }
      encoded.push("{" + cells.join(",") + "}")
    }
    tables.push(
      Json::string(table.name).stringify() + ":[" + encoded.join(",") + "]",
    )
  }
  "{" + tables.join(",") + "}"
}

///|
fn report(plan : Plan, rows : Rows, changed : Int32) -> String {
  let tables = plan.tables.mapi((ti, table) => {
    "{\"name\":" +
    Json::string(table.name).stringify() +
    ",\"rows\":" +
    rows[ti].length().to_string() +
    "}"
  })
  "{\"algorithm\":\"relmask-1\",\"constraints\":\"passed\",\"changed_cells\":" +
  changed.to_string() +
  ",\"tables\":[" +
  tables.join(",") +
  "]}"
}

///|
/// Validate an existing dataset without changing it. Nullable UNIQUE uses
/// NULLS DISTINCT semantics; nullable foreign keys use MATCH SIMPLE semantics.
pub fn Plan::validate(self : Plan, source : String) -> String raise MaskError {
  let rows = load(self, source)
  validate_rows(self, rows)
  report(self, rows, 0)
}
