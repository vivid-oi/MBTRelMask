///|
// SHA-256 compression and HMAC follow FIPS 180-4 and RFC 2104.
// Constants are the standard SHA-256 round constants. See THIRD_PARTY.md.
fn rotate(x : UInt32, n : Int32) -> UInt32 {
  (x >> n) | (x << (32 - n))
}

///|
fn sha256(input : Bytes) -> Bytes {
  let data = input.to_array()
  data.push(0x80)
  while data.length() % 64 != 56 {
    data.push(0)
  }
  let bits = input.length().to_uint64() * 8UL
  for i in 0..<8 {
    data.push((bits >> ((7 - i) * 8)).to_byte())
  }
  let h : Array[UInt32] = [
    0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU,
    0x1f83d9abU, 0x5be0cd19U,
  ]
  let k : Array[UInt32] = [
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U,
    0x923f82a4U, 0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
    0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U,
    0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U,
    0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
    0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
    0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU,
    0x5b9cca4fU, 0x682e6ff3U, 0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
  ]
  for block in 0..<(data.length() / 64) {
    let w = Array::make(64, 0U)
    for i in 0..<16 {
      let p = block * 64 + i * 4
      w[i] = (data[p].to_uint() << 24) |
        (data[p + 1].to_uint() << 16) |
        (data[p + 2].to_uint() << 8) |
        data[p + 3].to_uint()
    }
    for i in 16..<64 {
      let a = w[i - 15]
      let b = w[i - 2]
      w[i] = w[i - 16] +
        (rotate(a, 7) ^ rotate(a, 18) ^ (a >> 3)) +
        w[i - 7] +
        (rotate(b, 17) ^ rotate(b, 19) ^ (b >> 10))
    }
    let mut a = h[0]
    let mut b = h[1]
    let mut c = h[2]
    let mut d = h[3]
    let mut e = h[4]
    let mut f = h[5]
    let mut g = h[6]
    let mut z = h[7]
    for i in 0..<64 {
      let t1 = z +
        (rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)) +
        ((e & f) ^ (e.lnot() & g)) +
        k[i] +
        w[i]
      let t2 = (rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)) +
        ((a & b) ^ (a & c) ^ (b & c))
      z = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
    }
    h[0] += a
    h[1] += b
    h[2] += c
    h[3] += d
    h[4] += e
    h[5] += f
    h[6] += g
    h[7] += z
  }
  let out : Array[Byte] = []
  for word in h {
    for i in 0..<4 {
      out.push((word >> ((3 - i) * 8)).to_byte())
    }
  }
  Bytes::from_array(out[:])
}

///|
fn hmac(key : Bytes, message : Bytes) -> Bytes {
  let key = if key.length() > 64 { sha256(key) } else { key }
  let inner : Array[Byte] = []
  let outer : Array[Byte] = []
  for i in 0..<64 {
    let b = key.get(i).unwrap_or(0)
    inner.push(b ^ 0x36)
    outer.push(b ^ 0x5c)
  }
  sha256(
    Bytes::from_array(outer[:]) + sha256(Bytes::from_array(inner[:]) + message),
  )
}

///|
fn hex(bytes : Bytes) -> String {
  let digits = "0123456789abcdef".to_array()
  let out = StringBuilder()
  for b in bytes {
    out.write_char(digits[b.to_int() >> 4])
    out.write_char(digits[b.to_int() & 15])
  }
  out.to_string()
}

///|
fn pseudonym(secret : String, domain : String, value : String) -> String {
  // A length-framed JSON tuple separates domains and prevents concatenation ambiguity.
  let message = Json::array([
    Json::string("relmask-1"),
    Json::string(domain),
    Json::string(value),
  ]).stringify()
  hex(hmac(@utf8.encode(secret[:]), @utf8.encode(message[:])))[:32].to_owned()
}
