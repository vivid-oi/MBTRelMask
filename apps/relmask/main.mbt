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
    @stdio.stdout.write(
      "relmask check POLICY DATA\nrelmask mask POLICY DATA\nrelmask export POLICY DATA DEST\nrelmask export-subset POLICY DATA SEEDS DEST\nrelmask verify POLICY BUNDLE\nmask/export/export-subset read RELMASK_KEY (at least 32 UTF-8 bytes). Exports require a new destination.\n",
    )
    return
  }
  if !((args.length() == 4 && ["check", "mask", "verify"].contains(args[1])) ||
    (args.length() == 5 && args[1] == "export") ||
    (args.length() == 6 && args[1] == "export-subset")) {
    @stdio.stderr.write(
      "usage: relmask <check|mask|verify> POLICY INPUT, relmask export POLICY DATA DEST, or relmask export-subset POLICY DATA SEEDS DEST\n",
    )
    exit_process(2)
    return
  }
  let policy = @engine.Plan::parse(read_text(args[2], 4_000_000L))
  let input = read_text(
    args[3],
    if args[1] == "verify" {
      128_000_000L
    } else {
      64_000_000L
    },
  )
  if args[1] == "check" {
    @stdio.stdout.write(policy.validate(input) + "\n")
  } else if args[1] == "verify" {
    @stdio.stdout.write(policy.verify_bundle(input).report_json() + "\n")
  } else {
    let key = @env.get_env_var("RELMASK_KEY").unwrap_or("")
    let data = if args[1] == "export-subset" {
      policy.subset(input, read_text(args[4], 4_000_000L))
    } else {
      input
    }
    let output = policy.transform(data, key)
    if args[1] == "export" || args[1] == "export-subset" {
      publish(
        args[if args[1] == "export" { 4 } else { 5 }],
        output.bundle_json(),
      )
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
