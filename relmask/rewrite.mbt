///|
fn root_of(parent : Array[Int32], id : Int32) -> Int32 {
  let mut n = id
  while parent[n] != n {
    n = parent[n]
  }
  n
}

///|
fn domains(plan : Plan) -> (Array[Int32], Array[Int32]) {
  let offsets : Array[Int32] = []
  let mut total = 0
  for table in plan.tables {
    offsets.push(total)
    total += table.columns.length()
  }
  let parents = Array::makei(total, i => i)
  for ti, table in plan.tables {
    for reference in table.references {
      let pi = table_index(plan.tables, reference.target).unwrap()
      let ci = column_index(table, reference.columns[0]).unwrap()
      let pci = column_index(plan.tables[pi], reference.target_columns[0]).unwrap()
      let a = root_of(parents, offsets[ti] + ci)
      let b = root_of(parents, offsets[pi] + pci)
      parents[a] = if a < b { a } else { b }
      parents[b] = if a < b { a } else { b }
    }
  }
  (parents, offsets)
}

///|
/// Transform an existing dataset atomically in memory. The secret must contain
/// at least 32 UTF-8 bytes. Reindex mappings are stable only for the same batch.
pub fn Plan::transform(
  self : Plan,
  source : String,
  secret : String,
) -> CheckedDataset raise MaskError {
  if @utf8.encode(secret[:]).length() < 32 {
    reject("secret_too_short", "secret")
  }
  if secret.length() > 4096 {
    reject("secret_too_large", "secret")
  }
  let rows = load(self, source)
  validate_rows(self, rows)
  let (parents, offsets) = domains(self)
  // Union reference columns before enumerating values: cycles need no table order.
  let values : Map[Int32, Map[String, Bool]] = Map([])
  for ti, table in self.tables {
    for ci, column in table.columns {
      if column.rule is Reindex(_) {
        let root = root_of(parents, offsets[ti] + ci)
        let set = values.get_or_init(root, () => Map([]))
        for row in rows[ti] {
          if !(row[ci] is Null) {
            set[cell_key(row[ci], column, table.name)] = true
          }
        }
      }
    }
  }
  let indexes : Map[Int32, Map[String, Int32]] = Map([])
  for root, set in values {
    let sorted = set.keys().to_array()
    // Keyed ordering avoids depending on row order or on numeric key order.
    let scores : Map[String, String] = Map([])
    for value in sorted {
      scores[value] = pseudonym(secret, "reindex:" + root.to_string(), value)
    }
    sorted.sort_by((a, b) => {
      let order = scores[a].compare(scores[b])
      if order == 0 {
        a.compare(b)
      } else {
        order
      }
    })
    let index : Map[String, Int32] = Map([])
    for rank, value in sorted {
      index[value] = rank
    }
    indexes[root] = index
  }
  let seen_tokens : Map[String, Map[String, String]] = Map([])
  let mut changed = 0
  for ti, table in self.tables {
    for ri, row in rows[ti] {
      for ci, column in table.columns {
        let old = row[ci]
        if old is Null {
          continue
        }
        let loc = table.name + "[" + ri.to_string() + "]." + column.name
        let new = match column.rule {
          Keep => old
          Clear => Json::null()
          Replace(s) => Json::string(s)
          Token(domain, prefix, suffix) => {
            let original = text(old, loc)
            let token = prefix + pseudonym(secret, domain, original) + suffix
            let seen = seen_tokens.get_or_init(domain, () => Map([]))
            if seen.get(token) is Some(prior) && prior != original {
              reject("token_collision", loc)
            }
            seen[token] = original
            Json::string(token)
          }
          Reindex(start) => {
            let root = root_of(parents, offsets[ti] + ci)
            let rank = indexes[root][cell_key(old, column, loc)].to_int64()
            if start > 9223372036854775807L - rank {
              reject("reindex_overflow", loc)
            }
            Json::number(0.0, repr=(start + rank).to_string())
          }
        }
        check_cell(new, column, loc)
        if new.stringify() != old.stringify() {
          changed += 1
        }
        row[ci] = new
      }
    }
  }
  validate_rows(self, rows)
  { encoded: encode_rows(self, rows), report: report(self, rows, changed), }
}
