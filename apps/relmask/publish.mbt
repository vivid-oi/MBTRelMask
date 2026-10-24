///|
async fn publish(destination : String, content : String) -> Unit {
  if @utf8.encode(content[:]).length() > 128_000_000 {
    fail("bundle exceeds CLI byte budget")
  }
  guard @env.rand(16) is Some(random) else {
    fail("random temporary name unavailable")
  }
  let digits = "0123456789abcdef".to_array()
  let suffix = StringBuilder()
  for b in random {
    suffix.write_char(digits[b.to_int() >> 4])
    suffix.write_char(digits[b.to_int() & 15])
  }
  let temporary = destination + "." + suffix.to_string() + ".pending"
  // Keep creation, sync and no-replace publication in a cancellation shield.
  // Process termination can still leave a private .pending file, never a partial DEST.
  @async.protect_from_cancel(() => {
    let file = @fs.create(temporary[:], allow_existing=false, permission=0o600)
    let mut published = false
    defer (if !published {
      @fs.remove(temporary[:]) catch {
        _ =>
          @stdio.stderr.write(
            "cleanup_failed: remove temporary file " + temporary + "\n",
          )
      }
    })
    {
      defer file.close()
      file.write(content)
      file.sync()
    }
    @fs.rename(temporary[:], destination[:], replace=false)
    published = true
  })
}
