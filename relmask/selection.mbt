///|
priv enum SelectOp {
  Eq(Json)
  Neq(Json)
  Gt(Json)
  Gte(Json)
  Lt(Json)
  Lte(Json)
  Prefix(String)
  IsNull(Bool)
}

///|
priv struct SelectCondition {
  column : Int32
  kind : Kind
  op : SelectOp
}

///|
fn selector_value(
  value : Json,
  kind : Kind,
  location : String,
) -> Unit raise MaskError {
  match (kind, value) {
    (_, Null) => ()
    (Text, String(_))
    | (Boolean, True | False)
    | (Decimal, Number(_, repr=Some(_))) => ()
    (Integer, _) => ignore(integer(value, location))
    _ => reject("selector_type", location)
  }
}

///|
fn selector_equal(a : Json, b : Json, kind : Kind) -> Bool raise MaskError {
  if a is Null || b is Null {
    return a is Null && b is Null
  }
  if kind is Integer {
    return integer(a, "selector") == integer(b, "selector")
  }
  if kind is Decimal {
    return decimal_compare(a, b) == 0
  }
  a.stringify() == b.stringify()
}

///|
fn selector_compare(a : Json, b : Json, kind : Kind) -> Int32 raise MaskError {
  if kind is Decimal {
    return decimal_compare(a, b)
  }
  if kind is Integer {
    let a = integer(a, "selector")
    let b = integer(b, "selector")
    return if a < b { -1 } else if a > b { 1 } else { 0 }
  }
  guard a is String(a) && b is String(b) else {
    abort("validated text comparison")
  }
  a.lexical_compare(b)
}

///|
fn selector_matches(
  row : Array[Json],
  condition : SelectCondition,
) -> Bool raise MaskError {
  let value = row[condition.column]
  match condition.op {
    IsNull(expected) => (value is Null) == expected
    Eq(other) => selector_equal(value, other, condition.kind)
    Neq(other) => !selector_equal(value, other, condition.kind)
    Prefix(prefix) =>
      match value {
        String(s) => s.has_prefix(prefix)
        _ => false
      }
    Gt(other) =>
      !(value is Null) && selector_compare(value, other, condition.kind) > 0
    Gte(other) =>
      !(value is Null) && selector_compare(value, other, condition.kind) >= 0
    Lt(other) =>
      !(value is Null) && selector_compare(value, other, condition.kind) < 0
    Lte(other) =>
      !(value is Null) && selector_compare(value, other, condition.kind) <= 0
  }
}

///|
fn Plan::read_selector(
  self : Plan,
  source : String,
) -> Array[Array[Array[SelectCondition]]] raise MaskError {
  if source.length() > 1_000_000 {
    reject("selector_too_large", "selector")
  }
  let root = fields(parse_json(source, "selector"), "selector")
  if root.is_empty() {
    reject("empty_selector", "selector")
  }
  only_keys(root, self.tables.map(t => t.name), "selector")
  let result = self.tables.map(_ => [])
  let mut predicates = 0
  let mut branches = 0
  for ti, table in self.tables {
    if root.get(table.name) is Some(value) {
      let location = "selector." + table.name
      let alternatives = items(value, location)
      if alternatives.is_empty() {
        reject("empty_selector", location)
      }
      for bi, alternative in alternatives {
        branches += 1
        if branches > 64 {
          reject("selector_branch_limit", "selector")
        }
        let location = location + "[" + bi.to_string() + "]"
        let branch_fields = fields(alternative, location)
        if branch_fields.is_empty() {
          reject("empty_selector", location)
        }
        only_keys(branch_fields, table.columns.map(c => c.name), location)
        let conditions = []
        for ci, column in table.columns {
          if branch_fields.get(column.name) is Some(value) {
            let location = location + "." + column.name
            let operators = fields(value, location)
            if operators.is_empty() {
              reject("empty_selector", location)
            }
            only_keys(
              operators,
              ["eq", "neq", "gt", "gte", "lt", "lte", "prefix", "is_null"],
              location,
            )
            // Fixed operator order makes configuration object order irrelevant.
            for
              operator in [
                "eq", "neq", "gt", "gte", "lt", "lte", "prefix", "is_null",
              ] {
              if operators.get(operator) is Some(value) {
                predicates += 1
                if predicates > 256 {
                  reject("selector_predicate_limit", "selector")
                }
                let location = location + "." + operator
                let op = if operator == "is_null" {
                  match value {
                    True => IsNull(true)
                    False => IsNull(false)
                    _ => {
                      reject("selector_type", location)
                      abort("unreachable")
                    }
                  }
                } else {
                  selector_value(value, column.kind, location)
                  match operator {
                    "eq" => Eq(value)
                    "neq" => Neq(value)
                    "prefix" => {
                      guard column.kind is Text && value is String(prefix) else {
                        reject("selector_type", location)
                        abort("unreachable")
                      }
                      Prefix(prefix)
                    }
                    _ => {
                      if value is Null ||
                        !(column.kind is Text ||
                        column.kind is Integer ||
                        column.kind is Decimal) {
                        reject("selector_order_type", location)
                      }
                      match operator {
                        "gt" => Gt(value)
                        "gte" => Gte(value)
                        "lt" => Lt(value)
                        _ => Lte(value)
                      }
                    }
                  }
                }
                conditions.push({ column: ci, kind: column.kind, op, })
              }
            }
          }
        }
        result[ti].push(conditions)
      }
    }
  }
  result
}

///|
/// Select original rows by typed predicates and include their relational closure.
/// Tables map to OR branches; fields and operators within a branch are ANDed.
/// The result retains original values; transform it before sharing.
pub fn Plan::subset_where(
  self : Plan,
  source : String,
  selector : String,
  options? : String,
) -> String raise MaskError {
  let rows = load(self, source)
  validate_rows(self, rows)
  let predicates = self.read_selector(selector)
  let selected = self.tables.map(_ => [])
  for ti, table in rows {
    for ri, row in table {
      if predicates[ti].any(branch => branch.all(c => selector_matches(row, c))) {
        selected[ti].push(ri)
      }
    }
  }
  self.subset_rows(rows, Indexes(selected), options)
}
