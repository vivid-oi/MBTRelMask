///|
/// Completed batch and its authenticated, append-only integer mapping snapshot.
pub struct MappedDataset {
  priv checked : CheckedDataset
  priv state : String
}

///|
pub fn MappedDataset::dataset(self : MappedDataset) -> CheckedDataset {
  self.checked
}

///|
/// Contains keyed source tags and assigned IDs, not original cells. Treat as
/// sensitive state and serialize updates; forks are not automatically merged.
pub fn MappedDataset::state_json(self : MappedDataset) -> String {
  self.state
}

///|
/// Reuse integer IDs across batches with the same exact policy and secret.
/// State and data are returned only after every constraint and budget passes.
pub fn Plan::transform_with_state(
  self : Plan,
  source : String,
  secret : String,
  previous? : String,
  max_entries~ : Int32 = 100_000,
) -> MappedDataset raise MaskError {
  validate_secret(secret)
  if max_entries < 1 || max_entries > 100_000 {
    reject("state_limit_range", "state")
  }
  let rows = load(self, source)
  validate_rows(self, rows)
  let (parents, offsets) = domains(self)
  let starts : Map[Int32, Int64] = Map([])
  let originals : Map[Int32, Map[String, Bool]] = Map([])
  for ti, table in self.tables {
    for ci, column in table.columns {
      if column.rule is Reindex(start) {
        let root = root_of(parents, offsets[ti] + ci)
        starts[root] = start
        let values = originals.get_or_init(root, () => Map([]))
        for row in rows[ti] {
          if !(row[ci] is Null) {
            values[cell_key(row[ci], column, table.name)] = true
          }
        }
      }
    }
  }
  let state = decode_state(self, secret, previous, starts, max_entries)
  let mut count = 0
  for _, values in state {
    count += values.length()
  }
  let assigned : ReindexState = Map([])
  for root, values in originals {
    let stored = state.get_or_init(root, () => Map([]))
    let mapping : Map[String, Int64] = Map([])
    let tags : Map[String, String] = Map([])
    let seen : Map[String, String] = Map([])
    let fresh : Array[String] = []
    for original, _ in values {
      let tag = state_mac(secret, "relmask-state-key-1", [
        self.fingerprint,
        root.to_string(),
        original,
      ])
      if seen.get(tag) is Some(prior) && prior != original {
        reject("state_tag_collision", "state")
      }
      seen[tag] = original
      tags[original] = tag
      if !stored.contains(tag) {
        fresh.push(original)
      }
    }
    let scores : Map[String, String] = Map([])
    for original in fresh {
      scores[original] = pseudonym(
        secret,
        "reindex:" + root.to_string(),
        original,
      )
    }
    fresh.sort_by((a, b) => {
      let c = scores[a].compare(scores[b])
      if c == 0 {
        a.compare(b)
      } else {
        c
      }
    })
    for original in fresh {
      if count >= max_entries {
        reject("state_entry_limit", "state")
      }
      let rank = stored.length().to_int64()
      if starts[root] > 9223372036854775807L - rank {
        reject("reindex_overflow", "state")
      }
      stored[tags[original]] = starts[root] + rank
      count += 1
    }
    for original, tag in tags {
      mapping[original] = stored[tag]
    }
    assigned[root] = mapping
  }
  let checked = self.rewrite_rows(rows, secret, Some(assigned))
  { checked, state: encode_state(self, secret, state), }
}
