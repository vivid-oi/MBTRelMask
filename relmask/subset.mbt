///|
fn row_index(
  table : TableSpec,
  rows : Array[Array[Json]],
  names : Array[String],
) -> Map[String, Int32] raise MaskError {
  let index : Map[String, Int32] = Map([])
  for ri, row in rows {
    if tuple_key(row, table, names) is Some(key) {
      index[key] = ri
    }
  }
  index
}

///|
/// Select primary-key seeds and their transitive parent dependencies. Seeds are
/// a JSON object mapping table names to arrays of complete primary-key objects.
/// The returned JSON still contains original values; call transform before sharing.
pub fn Plan::subset(
  self : Plan,
  source : String,
  seeds : String,
) -> String raise MaskError {
  let rows = load(self, source)
  validate_rows(self, rows)
  if seeds.length() > 1_000_000 {
    reject("seeds_too_large", "seeds")
  }
  let seed_tables = fields(parse_json(seeds, "seeds"), "seeds")
  only_keys(seed_tables, self.tables.map(t => t.name), "seeds")
  let selected : Array[Map[Int32, Bool]] = self.tables.map(_ => Map([]))
  let queue : Array[(Int32, Int32)] = []
  for name, values in seed_tables {
    let ti = table_index(self.tables, name).unwrap()
    let table = self.tables[ti]
    let index = row_index(table, rows[ti], table.primary)
    for si, value in items(values, "seeds." + name) {
      let loc = "seeds." + name + "[" + si.to_string() + "]"
      let key_fields = fields(value, loc)
      only_keys(key_fields, table.primary, loc)
      let key_row = table.columns.map(_ => Json::null())
      for column_name in table.primary {
        let ci = column_index(table, column_name).unwrap()
        let value = required(key_fields, column_name, loc)
        check_cell(value, table.columns[ci], loc + "." + column_name)
        key_row[ci] = value
      }
      guard tuple_key(key_row, table, table.primary) is Some(key) else {
        reject("null_seed_key", loc)
      }
      guard index.get(key) is Some(ri) else { reject("seed_not_found", loc) }
      if !selected[ti].contains(ri) {
        selected[ti][ri] = true
        queue.push((ti, ri))
      }
    }
  }
  // Build each needed unique-key index once. Iterative closure handles cycles
  // and long chains without recursion or a dependency order requirement.
  let indexes : Map[String, Map[String, Int32]] = Map([])
  let mut cursor = 0
  while cursor < queue.length() {
    let (ti, ri) = queue[cursor]
    cursor += 1
    let table = self.tables[ti]
    for reference in table.references {
      if tuple_key(rows[ti][ri], table, reference.columns) is Some(key) {
        let pi = table_index(self.tables, reference.target).unwrap()
        let domain = Json::array([
          Json::string(pi.to_string()),
          Json::array(reference.target_columns.map(Json::string)),
        ]).stringify()
        if !indexes.contains(domain) {
          indexes[domain] = row_index(
            self.tables[pi],
            rows[pi],
            reference.target_columns,
          )
        }
        // The full source was validated before selection, so every non-null
        // reference has exactly one matching row in its declared unique key.
        let parent_row = indexes[domain][key]
        if !selected[pi].contains(parent_row) {
          selected[pi][parent_row] = true
          queue.push((pi, parent_row))
        }
      }
    }
  }
  let result : Rows = rows.mapi((ti, table_rows) => {
    let kept : Array[Array[Json]] = []
    for ri, row in table_rows {
      if selected[ti].contains(ri) {
        kept.push(row)
      }
    }
    kept
  })
  validate_rows(self, result)
  let encoded = encode_rows(self, result)
  if encoded.length() > self.max_input_units {
    reject("output_too_large", "data")
  }
  encoded
}
