///|
#cfg(target="native")
extern "C" fn exit_process(code : Int32) -> Unit = "exit"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn exit_process(code : Int32) -> Unit = "moonbitlang/async" "runtime/exit"

///|
async fn read_text(path : String, maximum : Int64) -> String {
  let file = @fs.open(path[:], mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular {
    fail("not a regular input file")
  }
  if file.size() > maximum {
    fail("input exceeds CLI byte budget")
  }
  // Read with a hard cap even when the file grows after the metadata check.
  let buffer = @buffer.Buffer()
  let mut total = 0L
  while file.read_some(max_len=65536) is Some(bytes) {
    total += bytes.length().to_int64()
    if total > maximum {
      fail("input exceeds CLI byte budget")
    }
    buffer.write_bytes(bytes[:])
  }
  let bytes = buffer.to_bytes()
  @utf8.decode(bytes[:])
}

///|
async fn execute() -> Unit {
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "help") {
    @stdio.stdout.write("relmask unpack-sql POLICY BUNDLE DEST [SCHEMA]\n")
    @stdio.stdout.write("relmask diagnose POLICY DATA\n")
    @stdio.stdout.write(
      "relmask compare POLICY BEFORE_BUNDLE AFTER_BUNDLE (exit 3 if different)\n",
    )
    @stdio.stdout.write(
      "relmask export-state POLICY DATA STATE_OR_DASH DESTDIR\n",
    )
    @stdio.stdout.write(
      "relmask export-aggregate POLICY DATA SEEDS OPTIONS DEST\n",
    )
    @stdio.stdout.write(
      "relmask check POLICY DATA\nrelmask mask POLICY DATA\nrelmask export POLICY DATA DEST\nrelmask export-subset POLICY DATA SEEDS DEST\nrelmask export-csv POLICY DIRECTORY DEST\nrelmask unpack-csv POLICY BUNDLE DESTDIR\nrelmask verify POLICY BUNDLE\nmask and export commands read RELMASK_KEY (at least 32 UTF-8 bytes). All exports require a new destination.\n",
    )
    return
  }
  if !((
      args.length() == 4 &&
      ["check", "mask", "verify", "diagnose"].contains(args[1])
    ) ||
    (
      args.length() == 5 &&
      ["export", "export-csv", "unpack-csv", "compare", "unpack-sql"].contains(
        args[1],
      )
    ) ||
    (
      args.length() == 6 &&
      ["export-subset", "export-state", "unpack-sql"].contains(args[1])
    ) ||
    (args.length() == 7 && args[1] == "export-aggregate")) {
    @stdio.stderr.write(
      "invalid arguments: run relmask --help for command forms\n",
    )
    exit_process(2)
    return
  }
  let policy = @engine.Plan::parse(read_text(args[2], 4_000_000L))
  if args[1] == "export-csv" {
    let data = policy.import_csv(read_csv_directory(args[3]))
    let output = policy.transform(
      data,
      @env.get_env_var("RELMASK_KEY").unwrap_or(""),
    )
    publish(args[4], output.bundle_json())
    @stdio.stderr.write(output.report_json() + "\n")
    return
  }
  let input = read_text(
    args[3],
    if ["verify", "unpack-csv", "compare", "unpack-sql"].contains(args[1]) {
      128_000_000L
    } else {
      64_000_000L
    },
  )
  if args[1] == "diagnose" {
    let result = policy.diagnose(input)
    @stdio.stdout.write(result.to_json() + "\n")
    if !result.is_valid() {
      exit_process(1)
    }
  } else if args[1] == "compare" {
    let a = policy.verify_bundle(input)
    let b = policy.verify_bundle(read_text(args[4], 128_000_000L))
    let difference = policy.compare_datasets(a.to_json(), b.to_json())
    @stdio.stdout.write(difference.to_json() + "\n")
    if !difference.is_empty() {
      exit_process(3)
    }
  } else if args[1] == "unpack-sql" {
    let data = policy.verify_bundle(input)
    let schema = if args.length() == 6 { args[5] } else { "relmask_fixture" }
    publish(args[4], policy.export_sql(data.to_json(), schema~))
    @stdio.stderr.write(data.report_json() + "\n")
  } else if args[1] == "check" {
    @stdio.stdout.write(policy.validate(input) + "\n")
  } else if args[1] == "export-state" {
    let key = @env.get_env_var("RELMASK_KEY").unwrap_or("")
    let batch = if args[4] == "-" {
      policy.transform_with_state(input, key)
    } else {
      policy.transform_with_state(
        input,
        key,
        previous=read_text(args[4], 32_000_000L),
      )
    }
    publish_directory(args[5], [
      ("bundle.json", batch.dataset().bundle_json()),
      ("state.json", batch.state_json()),
    ])
    @stdio.stderr.write(batch.dataset().report_json() + "\n")
  } else if args[1] == "unpack-csv" {
    let checked = policy.verify_bundle(input)
    publish_csv_directory(
      args[4],
      policy.export_csv(checked.to_json()),
      checked.report_json(),
    )
    @stdio.stderr.write(checked.report_json() + "\n")
  } else if args[1] == "verify" {
    @stdio.stdout.write(policy.verify_bundle(input).report_json() + "\n")
  } else {
    let key = @env.get_env_var("RELMASK_KEY").unwrap_or("")
    let data = if args[1] == "export-subset" || args[1] == "export-aggregate" {
      if args[1] == "export-aggregate" {
        policy.subset(
          input,
          read_text(args[4], 4_000_000L),
          options=read_text(args[5], 1_000_000L),
        )
      } else {
        policy.subset(input, read_text(args[4], 4_000_000L))
      }
    } else {
      input
    }
    let output = policy.transform(data, key)
    if ["export", "export-subset", "export-aggregate"].contains(args[1]) {
      publish(args[args.length() - 1], output.bundle_json())
    } else {
      @stdio.stdout.write(output.to_json() + "\n")
    }
    @stdio.stderr.write(output.report_json() + "\n")
  }
}

///|
async fn main {
  execute() catch {
    @engine.Invalid(code~, location~) => {
      @stdio.stderr.write(code + " at " + location + "\n")
      exit_process(1)
    }
    _ => {
      @stdio.stderr.write(
        "input_output_error: check paths, permissions, UTF-8 and byte budgets; export requires a new destination\n",
      )
      exit_process(1)
    }
  }
}
