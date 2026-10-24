///|
/// Value-free differences matched by complete primary keys, ignoring row order.
pub struct DatasetDiff {
  priv encoded : String
  priv empty : Bool
}

///|
pub fn DatasetDiff::to_json(self : DatasetDiff) -> String {
  self.encoded
}

///|
pub fn DatasetDiff::is_empty(self : DatasetDiff) -> Bool {
  self.empty
}

///|
/// Validate both datasets and compare rows with equal primary keys. Added or
/// removed rows do not count as changed cells. No cell values or keys are emitted.
pub fn Plan::compare_datasets(
  self : Plan,
  before : String,
  after : String,
) -> DatasetDiff raise MaskError {
  let old = load(self, before)
  let new = load(self, after)
  validate_rows(self, old)
  validate_rows(self, new)
  let tables : Array[String] = []
  let mut empty = true
  for ti, table in self.tables {
    let old_keys = row_index(table, old[ti], table.primary)
    let new_keys = row_index(table, new[ti], table.primary)
    let mut added = 0
    let mut removed = 0
    let mut changed = 0
    let columns = table.columns.map(_ => 0)
    for key, oi in old_keys {
      match new_keys.get(key) {
        None => removed += 1
        Some(ni) => {
          let mut differs = false
          for ci in 0..<table.columns.length() {
            if old[ti][oi][ci].stringify() != new[ti][ni][ci].stringify() {
              columns[ci] += 1
              differs = true
            }
          }
          if differs {
            changed += 1
          }
        }
      }
    }
    for key, _ in new_keys {
      if !old_keys.contains(key) {
        added += 1
      }
    }
    if added != 0 || removed != 0 || changed != 0 {
      empty = false
    }
    let counts = table.columns.mapi((ci, column) => {
      "{\"name\":" +
      Json::string(column.name).stringify() +
      ",\"changed\":" +
      columns[ci].to_string() +
      "}"
    })
    tables.push(
      "{\"name\":" +
      Json::string(table.name).stringify() +
      ",\"added\":" +
      added.to_string() +
      ",\"removed\":" +
      removed.to_string() +
      ",\"changed\":" +
      changed.to_string() +
      ",\"columns\":[" +
      counts.join(",") +
      "]}",
    )
  }
  {
    encoded: "{\"format\":\"relmask-diff-1\",\"equal\":" +
    (if empty { "true" } else { "false" }) +
    ",\"tables\":[" +
    tables.join(",") +
    "]}",
    empty,
  }
}
