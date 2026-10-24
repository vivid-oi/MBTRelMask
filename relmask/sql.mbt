///|
/// Export validated data as a PostgreSQL 18 transaction creating a new schema.
/// Does not mask input values. SQL retains numeric values, not JSON lexeme style.
pub fn Plan::export_sql(
  self : Plan,
  source : String,
  schema~ : String = "relmask_fixture",
  max_output_units~ : Int32 = 64_000_000,
) -> String raise MaskError {
  if max_output_units < 1 || max_output_units > 128_000_000 {
    reject("sql_limit_range", "sql")
  }
  if schema.has_prefix("pg_") {
    reject("sql_schema_reserved", "sql.schema")
  }
  let schema_name = sql_identifier(schema, "sql.schema")
  let rows = load(self, source)
  validate_rows(self, rows)
  let statements : Array[String] = []
  let mut size = 0L
  let emit = fn(statement : String) raise MaskError {
    size += statement.length().to_int64() + 1L
    if size > max_output_units.to_int64() {
      reject("sql_output_limit", "sql")
    }
    statements.push(statement)
  }
  let names = fn(columns : Array[String]) raise MaskError {
    columns.map(name => sql_identifier(name, "sql.column")).join(",")
  }
  emit("BEGIN;")
  emit("SET LOCAL search_path = pg_catalog;")
  emit("SET LOCAL client_encoding = 'UTF8';")
  emit("CREATE SCHEMA " + schema_name + ";")
  for table in self.tables {
    let qualified = schema_name + "." + sql_identifier(table.name, "sql.table")
    let columns : Array[String] = []
    for column in table.columns {
      let name = sql_identifier(column.name, "sql.column")
      let kind = match column.kind {
        Text => "TEXT COLLATE pg_catalog.\"C\""
        Integer => "BIGINT"
        Decimal => "NUMERIC"
        Boolean => "BOOLEAN"
      }
      let length = match column.max_length {
        Some(n) =>
          " CHECK (pg_catalog.char_length(" +
          name +
          ") <= " +
          n.to_string() +
          ")"
        None => ""
      }
      columns.push(
        name +
        " " +
        kind +
        (if column.nullable { "" } else { " NOT NULL" }) +
        length,
      )
    }
    columns.push("PRIMARY KEY (" + names(table.primary) + ")")
    for unique in table.unique {
      columns.push(
        "UNIQUE " +
        (if unique.nulls_equal { "NULLS NOT DISTINCT " } else { "" }) +
        "(" +
        names(unique.columns) +
        ")",
      )
    }
    emit("CREATE TABLE " + qualified + " (" + columns.join(",") + ");")
  }
  for ti, table in self.tables {
    let qualified = schema_name + "." + sql_identifier(table.name, "sql.table")
    let header = "INSERT INTO " +
      qualified +
      " (" +
      names(table.columns.map(c => c.name)) +
      ") VALUES ("
    for ri, row in rows[ti] {
      let values = row.mapi((ci, value) => {
        sql_cell(
          value,
          table.columns[ci],
          table.name + "[" + ri.to_string() + "]." + table.columns[ci].name,
        )
      })
      emit(header + values.join(",") + ");")
    }
  }
  // Attach foreign keys after data: cycles and any policy table order work.
  for table in self.tables {
    for reference in table.references {
      emit(
        "ALTER TABLE " +
        schema_name +
        "." +
        sql_identifier(table.name, "sql.table") +
        " ADD FOREIGN KEY (" +
        names(reference.columns) +
        ") REFERENCES " +
        schema_name +
        "." +
        sql_identifier(reference.target, "sql.table") +
        " (" +
        names(reference.target_columns) +
        ") MATCH " +
        (if reference.full { "FULL" } else { "SIMPLE" }) +
        " DEFERRABLE INITIALLY DEFERRED;",
      )
    }
  }
  emit("COMMIT;")
  statements.join("\n") + "\n"
}
