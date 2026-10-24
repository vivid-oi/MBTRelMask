///|
test "SHA-256 empty, abc, multi-block and padding boundaries" {
  assert_eq(
    hex(sha256(b"")),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    hex(sha256(b"abc")),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    hex(sha256(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
  assert_eq(
    hex(sha256(Bytes::make(1_000_000, 0x61))),
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
  )
}

///|
test "RFC 4231 cases 1, 2 and 6 include long HMAC keys" {
  assert_eq(
    hex(hmac(Bytes::make(20, 0x0b), b"Hi There")),
    "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
  )
  assert_eq(
    hex(hmac(b"Jefe", b"what do ya want for nothing?")),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  )
  assert_eq(
    hex(
      hmac(
        Bytes::make(131, 0xaa),
        b"Test Using Larger Than Block-Size Key - Hash Key First",
      ),
    ),
    "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
  )
}
