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
      "relmask check POLICY DATA\nrelmask mask POLICY DATA\nmask reads RELMASK_KEY (at least 32 UTF-8 bytes); writes complete JSON to stdout.\n",
    )
    return
  }
  if args.length() != 4 || (args[1] != "check" && args[1] != "mask") {
    @stdio.stderr.write("usage: relmask <check|mask> POLICY DATA\n")
    exit_process(2)
    return
  }
  let policy = @engine.Plan::parse(read_text(args[2], 4_000_000L))
  let input = read_text(args[3], 64_000_000L)
  if args[1] == "check" {
    @stdio.stdout.write(policy.validate(input) + "\n")
  } else {
    let key = @env.get_env_var("RELMASK_KEY").unwrap_or("")
    let output = policy.transform(input, key)
    @stdio.stdout.write(output.to_json() + "\n")
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
        "input_output_error: check paths, UTF-8 encoding and CLI byte budgets\n",
      )
      exit_process(1)
    }
  }
}
