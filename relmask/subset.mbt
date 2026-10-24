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
  options? : String,
) -> String raise MaskError {
  let rows = load(self, source)
  validate_rows(self, rows)
  self.subset_rows(rows, Keys(seeds), options)
}

///|
priv enum RowSelection {
  Keys(String)
  Indexes(Array[Array[Int32]])
}

///|
fn Plan::subset_rows(
  self : Plan,
  rows : Rows,
  selection : RowSelection,
  options : String?,
) -> String raise MaskError {
  if options is Some(value) && value.length() > 1_000_000 {
    reject("subset_options_too_large", "subset.options")
  }
  let config = fields(
    parse_json(options.unwrap_or("{}"), "subset.options"),
    "subset.options",
  )
  only_keys(config, ["descendants", "max_rows"], "subset.options")
  let descendants = match config.get("descendants") {
    Some(v) => items(v, "subset.descendants")
    None => []
  }
  let limit = match config.get("max_rows") {
    Some(v) => {
      let n = integer(v, "subset.max_rows")
      if n < 1L || n > self.max_rows.to_int64() {
        reject("subset_limit_range", "subset.max_rows")
      }
      n.to_int()
    }
    None => self.max_rows
  }
  let incoming : Array[Array[(Int32, Int32)]] = self.tables.map(_ => [])
  let seen_edges : Map[String, Bool] = Map([])
  for selection in descendants {
    let (name, columns) = match selection {
      String(name) => (name, None)
      _ => {
        let edge = fields(selection, "subset.descendants")
        only_keys(edge, ["table", "columns"], "subset.descendants")
        (
          text(
            required(edge, "table", "subset.descendants"),
            "subset.descendants",
          ),
          Some(
            names(
              required(edge, "columns", "subset.descendants"),
              "subset.descendants",
            ),
          ),
        )
      }
    }
    guard table_index(self.tables, name) is Some(ci) else {
      reject("unknown_child_table", "subset.descendants")
    }
    let matches : Array[Int32] = []
    for fi, reference in self.tables[ci].references {
      if columns is None || columns == Some(reference.columns) {
        matches.push(fi)
      }
    }
    if matches.length() != 1 {
      reject("ambiguous_or_missing_child_reference", "subset.descendants")
    }
    let fi = matches[0]
    let edge_key = ci.to_string() + ":" + fi.to_string()
    if seen_edges.contains(edge_key) {
      reject("duplicate_child_reference", "subset.descendants")
    }
    seen_edges[edge_key] = true
    let reference = self.tables[ci].references[fi]
    incoming[table_index(self.tables, reference.target).unwrap()].push((ci, fi))
  }
  let seed_tables = match selection {
    Keys(seeds) => {
      if seeds.length() > 1_000_000 {
        reject("seeds_too_large", "seeds")
      }
      fields(parse_json(seeds, "seeds"), "seeds")
    }
    Indexes(_) => Map([])
  }
  only_keys(seed_tables, self.tables.map(t => t.name), "seeds")
  let selected : Array[Map[Int32, Bool]] = self.tables.map(_ => Map([]))
  let queue : Array[(Int32, Int32)] = []
  let enqueue = fn(ti : Int32, ri : Int32) raise MaskError {
    if !selected[ti].contains(ri) {
      if queue.length() >= limit {
        reject("subset_row_limit", "subset")
      }
      selected[ti][ri] = true
      queue.push((ti, ri))
    }
  }
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
      enqueue(ti, ri)
    }
  }
  if selection is Indexes(indexes) {
    for ti, indices in indexes {
      for ri in indices {
        enqueue(ti, ri)
      }
    }
  }
  // Build each needed unique-key index once. Iterative closure handles cycles
  // and long chains without recursion or a dependency order requirement.
  let indexes : Map[String, Map[String, Int32]] = Map([])
  let children : Map[String, Map[String, Array[Int32]]] = Map([])
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
        enqueue(pi, parent_row)
      }
    }
    for (ci, fi) in incoming[ti] {
      let child = self.tables[ci]
      let reference = child.references[fi]
      if tuple_key(rows[ti][ri], table, reference.target_columns) is Some(key) {
        let domain = ci.to_string() + ":" + fi.to_string()
        if !children.contains(domain) {
          let index : Map[String, Array[Int32]] = Map([])
          for child_row, value in rows[ci] {
            if tuple_key(value, child, reference.columns) is Some(child_key) {
              index.get_or_init(child_key, () => []).push(child_row)
            }
          }
          children[domain] = index
        }
        for child_row in children[domain].get(key).unwrap_or([]) {
          enqueue(ci, child_row)
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
