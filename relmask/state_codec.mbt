///|
type ReindexState = Map[Int32, Map[String, Int64]]

///|
fn state_mac(
  secret : String,
  domain : String,
  values : Array[String],
) -> String {
  let framed = Json::array([Json::string(domain)] + values.map(Json::string)).stringify()
  hex(hmac(@utf8.encode(secret[:]), @utf8.encode(framed[:])))
}

///|
fn encode_state(plan : Plan, secret : String, state : ReindexState) -> String {
  let roots = state.keys().to_array()
  roots.sort()
  let domains : Array[String] = []
  for root in roots {
    let tags = state[root].keys().to_array()
    tags.sort()
    let entries = tags.map(tag => {
      "[" +
      Json::string(tag).stringify() +
      "," +
      state[root][tag].to_string() +
      "]"
    })
    domains.push(
      "{\"root\":" +
      root.to_string() +
      ",\"entries\":[" +
      entries.join(",") +
      "]}",
    )
  }
  let body = "{\"format\":\"relmask-state-1\",\"policy\":" +
    Json::string(plan.fingerprint).stringify() +
    ",\"domains\":[" +
    domains.join(",") +
    "]}"
  "{\"body\":" +
  Json::string(body).stringify() +
  ",\"hmac\":" +
  Json::string(state_mac(secret, "relmask-state-auth-1", [body])).stringify() +
  "}"
}

///|
fn decode_state(
  plan : Plan,
  secret : String,
  encoded : String?,
  starts : Map[Int32, Int64],
  limit : Int32,
) -> ReindexState raise MaskError {
  guard encoded is Some(source) else { return Map([]) }
  if source.length() > limit * 160 + 100_000 {
    reject("state_too_large", "state")
  }
  let envelope = fields(parse_json(source, "state"), "state")
  only_keys(envelope, ["body", "hmac"], "state")
  let body = text(required(envelope, "body", "state"), "state.body")
  let mac = text(required(envelope, "hmac", "state"), "state.hmac")
  if mac != state_mac(secret, "relmask-state-auth-1", [body]) {
    reject("state_authentication", "state.hmac")
  }
  let obj = fields(parse_json(body, "state.body"), "state.body")
  only_keys(obj, ["format", "policy", "domains"], "state.body")
  if text(required(obj, "format", "state"), "state") != "relmask-state-1" {
    reject("state_version", "state")
  }
  if text(required(obj, "policy", "state"), "state") != plan.fingerprint {
    reject("state_policy_mismatch", "state")
  }
  let result : ReindexState = Map([])
  let mut total = 0
  for domain in items(required(obj, "domains", "state"), "state.domains") {
    let d = fields(domain, "state.domain")
    only_keys(d, ["root", "entries"], "state.domain")
    let n = integer(required(d, "root", "state"), "state.root")
    if n < 0L || n >= 32768L {
      reject("state_domain", "state.root")
    }
    let root = n.to_int()
    if !starts.contains(root) || result.contains(root) {
      reject("state_domain", "state.root")
    }
    let entries : Map[String, Int64] = Map([])
    let values : Array[Int64] = []
    for entry in items(required(d, "entries", "state"), "state.entries") {
      total += 1
      if total > limit {
        reject("state_entry_limit", "state")
      }
      let pair = items(entry, "state.entry")
      if pair.length() != 2 {
        reject("state_entry", "state")
      }
      let tag = text(pair[0], "state.tag")
      if tag.length() != 64 ||
        !tag
        .to_array()
        .all(ch => (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) ||
        entries.contains(tag) {
        reject("state_tag", "state")
      }
      let value = integer(pair[1], "state.value")
      entries[tag] = value
      values.push(value)
    }
    values.sort()
    for rank, value in values {
      if starts[root] > 9223372036854775807L - rank.to_int64() ||
        value != starts[root] + rank.to_int64() {
        reject("state_sequence", "state")
      }
    }
    result[root] = entries
  }
  result
}
