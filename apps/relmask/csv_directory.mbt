///|
fn csv_filename(name : String) -> Bool {
  !name.is_empty() &&
  name != "." &&
  name != ".." &&
  name
  .to_array()
  .all(ch => {
    (ch >= 'a' && ch <= 'z') ||
    (ch >= 'A' && ch <= 'Z') ||
    (ch >= '0' && ch <= '9') ||
    ch == '.' ||
    ch == '_' ||
    ch == '-'
  })
}

///|
async fn read_csv_directory(directory : String) -> Map[String, String] {
  let manifest_path = directory + "/manifest.json"
  let source = read_text(manifest_path, 4_000_000L)
  let json = @json.parse(
    source,
    reject_duplicate_keys=true,
    max_nesting_depth=16,
  ) catch {
    _ => raise @engine.Invalid(code="csv_manifest_json", location="manifest")
  }
  guard json is Object(manifest) else {
    raise @engine.Invalid(code="csv_manifest_object", location="manifest")
  }
  if manifest.length() > 128 {
    raise @engine.Invalid(code="csv_manifest_limit", location="manifest")
  }
  let result : Map[String, String] = Map([])
  let mut total = 0L
  for table, value in manifest {
    guard value is String(filename) && csv_filename(filename) else {
      raise @engine.Invalid(code="csv_manifest_filename", location="manifest")
    }
    let content = read_text(directory + "/" + filename, 64_000_000L - total)
    total += @utf8.encode(content[:]).length().to_int64()
    if total > 64_000_000L {
      fail("CSV input exceeds CLI byte budget")
    }
    result[table] = content
  }
  result
}

///|
async fn publish_csv_directory(
  destination : String,
  tables : Map[String, String],
  report : String,
) -> Unit {
  let names = tables.keys().to_array()
  names.sort()
  let files : Array[(String, String)] = []
  let manifest : Array[String] = []
  let mut bytes = 0L
  for i, name in names {
    let filename = "table-" + i.to_string() + ".csv"
    let csv = tables[name]
    bytes += @utf8.encode(csv[:]).length().to_int64()
    if bytes > 64_000_000L {
      fail("CSV output exceeds CLI byte budget")
    }
    files.push((filename, csv))
    manifest.push(
      Json::string(name).stringify() + ":" + Json::string(filename).stringify(),
    )
  }
  files.push(("manifest.json", "{" + manifest.join(",") + "}"))
  files.push(("report.json", report))
  let temporary = destination + "." + random_suffix() + ".pending"
  @async.protect_from_cancel(() => {
    @fs.mkdir(temporary[:], permission=0o700, allow_exist=false)
    let mut published = false
    defer (if !published {
      try {
        for name in @fs.readdir(temporary[:]) {
          let path = temporary + "/" + name
          @fs.remove(path[:])
        }
        @fs.rmdir(temporary[:])
      } catch {
        _ =>
          @stdio.stderr.write(
            "cleanup_failed: remove temporary directory " + temporary + "\n",
          )
      }
    })
    for (name, content) in files {
      let path = temporary + "/" + name
      @fs.write_file(
        path[:],
        content,
        create_mode=CreateNew,
        permission=0o600,
        sync=Full,
      )
    }
    @fs.rename(temporary[:], destination[:], replace=false)
    published = true
  })
}
