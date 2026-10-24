///|
fn read_rule(
  value : Json,
  kind : Kind,
  location : String,
) -> Rule raise MaskError {
  if value is String("keep") {
    return Keep
  }
  if value is String("null") {
    return Clear
  }
  let value = fields(value, location)
  if value.length() != 1 {
    reject("invalid_rule", location)
  }
  if value.get("replace") is Some(item) {
    guard kind is Text else { reject("text_rule_type", location) }
    return Replace(text(item, location))
  }
  if value.get("token") is Some(item) {
    guard kind is Text else { reject("text_rule_type", location) }
    let config = fields(item, location)
    only_keys(config, ["domain", "prefix", "suffix"], location)
    let domain = text(required(config, "domain", location), location)
    if domain.is_empty() {
      reject("empty_domain", location)
    }
    let prefix = match config.get("prefix") {
      Some(v) => text(v, location)
      None => ""
    }
    let suffix = match config.get("suffix") {
      Some(v) => text(v, location)
      None => ""
    }
    return Token(domain, prefix, suffix)
  }
  if value.get("reindex") is Some(item) {
    guard kind is Integer else { reject("integer_rule_type", location) }
    return Reindex(integer(item, location))
  }
  reject("unsupported_rule", location)
  abort("unreachable")
}

///|
fn read_column(value : Json, location : String) -> Column raise MaskError {
  let obj = fields(value, location)
  only_keys(obj, ["name", "type", "nullable", "max_length", "rule"], location)
  let name = text(required(obj, "name", location), location)
  if name.is_empty() {
    reject("empty_name", location)
  }
  let kind = match text(required(obj, "type", location), location) {
    "text" => Text
    "integer" => Integer
    "decimal" => Decimal
    "boolean" => Boolean
    _ => {
      reject("unsupported_type", location)
      abort("unreachable")
    }
  }
  let nullable = flag(obj, "nullable", false, location)
  let max_length = match obj.get("max_length") {
    None => None
    Some(item) => {
      let n = integer(item, location)
      if n < 0L || n > 1_000_000L {
        reject("length_range", location)
      }
      Some(n.to_int())
    }
  }
  if max_length is Some(_) && !(kind is Text) {
    reject("length_type", location)
  }
  let rule = read_rule(required(obj, "rule", location), kind, location)
  if rule is Clear && !nullable {
    reject("null_not_allowed", location)
  }
  { name, kind, nullable, max_length, rule, }
}

///|
fn column_index(table : TableSpec, name : String) -> Int32? {
  for i, column in table.columns {
    if column.name == name {
      return Some(i)
    }
  }
  None
}

///|
fn table_index(tables : Array[TableSpec], name : String) -> Int32? {
  for i, table in tables {
    if table.name == name {
      return Some(i)
    }
  }
  None
}

///|
fn check_names(
  table : TableSpec,
  columns : Array[String],
  location : String,
) -> Unit raise MaskError {
  if columns.is_empty() {
    reject("empty_key", location)
  }
  for column in columns {
    guard column_index(table, column) is Some(i) else {
      reject("unknown_column", location)
    }
    if table.columns[i].kind is Decimal {
      reject("decimal_key_unsupported", location)
    }
  }
}

///|
fn same_rule(a : Rule, b : Rule) -> Bool {
  match (a, b) {
    (Keep, Keep) => true
    (Token(x, xp, xs), Token(y, yp, ys)) => x == y && xp == yp && xs == ys
    (Reindex(x), Reindex(y)) => x == y
    _ => false
  }
}

///|
/// Parse a strict policy. Unknown options and unsupported constraints are errors.
pub fn Plan::parse(source : String) -> Plan raise MaskError {
  if source.length() > 1_000_000 {
    reject("policy_too_large", "policy")
  }
  let root = fields(parse_json(source, "policy"), "policy")
  only_keys(root, ["tables", "max_rows", "max_input_units"], "policy")
  let bound = fn(key, default) raise MaskError {
    match root.get(key) {
      None => default
      Some(x) => {
        let n = integer(x, "policy." + key)
        if n < 1L || n > 100_000_000L {
          reject("limit_range", "policy." + key)
        }
        n.to_int()
      }
    }
  }
  let max_rows = bound("max_rows", 100_000)
  let max_input_units = bound("max_input_units", 16_000_000)
  let tables : Array[TableSpec] = []
  for ti, input in items(required(root, "tables", "policy"), "tables") {
    let loc = "tables[" + ti.to_string() + "]"
    let obj = fields(input, loc)
    only_keys(obj, ["name", "columns", "primary", "unique", "references"], loc)
    let name = text(required(obj, "name", loc), loc)
    if name.is_empty() || table_index(tables, name) is Some(_) {
      reject("duplicate_or_empty_table", loc)
    }
    let columns : Array[Column] = []
    for ci, c in items(required(obj, "columns", loc), loc) {
      let column = read_column(c, loc + ".columns[" + ci.to_string() + "]")
      if columns.any(c => c.name == column.name) {
        reject("duplicate_column", loc)
      }
      columns.push(column)
    }
    if columns.is_empty() || columns.length() > 256 {
      reject("column_limit", loc)
    }
    let primary = names(required(obj, "primary", loc), loc)
    let unique = match obj.get("unique") {
      None => []
      Some(x) => items(x, loc).map(x => names(x, loc))
    }
    let references = match obj.get("references") {
      None => []
      Some(x) =>
        items(x, loc).map(x => {
          let refobj = fields(x, loc)
          only_keys(refobj, ["columns", "table", "target"], loc)
          let columns = names(required(refobj, "columns", loc), loc)
          let target_columns = names(required(refobj, "target", loc), loc)
          if columns.is_empty() || columns.length() != target_columns.length() {
            reject("reference_arity", loc)
          }
          {
            columns,
            target: text(required(refobj, "table", loc), loc),
            target_columns,
          }
        })
    }
    let table = { name, columns, primary, unique, references, }
    check_names(table, primary, loc)
    for u in unique {
      check_names(table, u, loc)
    }
    tables.push(table)
  }
  if tables.is_empty() || tables.length() > 128 {
    reject("table_limit", "tables")
  }
  let token_rules : Map[String, Rule] = Map([])
  for table in tables {
    for column in table.columns {
      if column.rule is Token(domain, _, _) {
        if token_rules.get(domain) is Some(prior) &&
          !same_rule(prior, column.rule) {
          reject("token_domain_rule_mismatch", table.name + "." + column.name)
        }
        token_rules[domain] = column.rule
      }
    }
  }
  for table in tables {
    for reference in table.references {
      let loc = table.name + ".references"
      check_names(table, reference.columns, loc)
      guard table_index(tables, reference.target) is Some(ti) else {
        reject("unknown_parent", loc)
      }
      let parent = tables[ti]
      check_names(parent, reference.target_columns, loc)
      if reference.target_columns != parent.primary &&
        !parent.unique.contains(reference.target_columns) {
        reject("reference_not_unique", loc)
      }
      for position, name in reference.columns {
        let a = table.columns[column_index(table, name).unwrap()]
        let b = parent.columns[column_index(
            parent,
            reference.target_columns[position],
          ).unwrap()]
        if !(match (a.kind, b.kind) {
            (Text, Text) | (Integer, Integer) | (Boolean, Boolean) => true
            _ => false
          }) {
          reject("reference_type_mismatch", loc)
        }
        if !same_rule(a.rule, b.rule) {
          reject("reference_rule_mismatch", loc)
        }
      }
    }
  }
  {
    tables,
    max_rows,
    max_input_units,
    fingerprint: hex(sha256(@utf8.encode(source[:]))),
  }
}
