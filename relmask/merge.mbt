///|
/// Validated union of two exports from the same logical primary-key namespace.
/// Values are still original; transform the result before sharing.
pub struct MergedDataset {
  priv encoded : String
  priv report : String
}

///|
pub fn MergedDataset::to_json(self : MergedDataset) -> String {
  self.encoded
}

///|
/// Per-table input, reused and result counts; contains no keys or cell values.
pub fn MergedDataset::report_json(self : MergedDataset) -> String {
  self.report
}

///|
/// Merge two independently valid datasets. Equal primary keys must have exactly
/// equal cells, including numeric representations; conflicting rows are refused.
/// Left row order is retained, followed by previously unseen right rows.
pub fn Plan::merge_datasets(
  self : Plan,
  left : String,
  right : String,
) -> MergedDataset raise MaskError {
  let result = load(self, left)
  let other = load(self, right)
  validate_rows(self, result)
  validate_rows(self, other)
  let reports : Array[String] = []
  let mut total = result.fold(init=0, (count, rows) => count + rows.length())
  for ti, table in self.tables {
    let index = row_index(table, result[ti], table.primary)
    let before = result[ti].length()
    let mut reused = 0
    for ri, row in other[ti] {
      let key = tuple_key(row, table, table.primary).unwrap()
      match index.get(key) {
        Some(prior) => {
          if row.map(x => x.stringify()) !=
            result[ti][prior].map(x => x.stringify()) {
            reject(
              "merge_row_conflict",
              "merge." + table.name + ".right[" + ri.to_string() + "]",
            )
          }
          reused += 1
        }
        None => {
          if total >= self.max_rows {
            reject("merge_row_limit", "merge")
          }
          index[key] = result[ti].length()
          result[ti].push(row)
          total += 1
        }
      }
    }
    reports.push(
      "{\"name\":" +
      Json::string(table.name).stringify() +
      ",\"left\":" +
      before.to_string() +
      ",\"right\":" +
      other[ti].length().to_string() +
      ",\"reused\":" +
      reused.to_string() +
      ",\"added\":" +
      (other[ti].length() - reused).to_string() +
      ",\"result\":" +
      result[ti].length().to_string() +
      "}",
    )
  }
  // A union can introduce UNIQUE conflicts even when each input is valid.
  validate_rows(self, result)
  let encoded = encode_rows(self, result)
  if encoded.length() > self.max_input_units {
    reject("output_too_large", "merge")
  }
  {
    encoded,
    report: "{\"format\":\"relmask-merge-1\",\"tables\":[" +
    reports.join(",") +
    "]}",
  }
}
