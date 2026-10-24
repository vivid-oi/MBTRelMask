///|
priv struct DecimalValue {
  sign : Int32
  order : DecimalOrder
  significant : String
}

///|
/// Input has already passed the JSON number grammar. Normalization is private:
/// selection never rewrites original number representations in the dataset.
fn decimal_value(raw : String) -> DecimalValue {
  let negative = raw[0] == 45
  let mut i = if negative { 1 } else { 0 }
  let coefficient = StringBuilder()
  let mut before = 0
  let mut fractional = false
  while i < raw.length() && raw[i] != 101 && raw[i] != 69 {
    if raw[i] == 46 {
      fractional = true
    } else {
      coefficient.write_char(raw[i].to_int().to_char().unwrap())
      if !fractional {
        before += 1
      }
    }
    i += 1
  }
  let digits = coefficient.to_string()
  let mut first = 0
  while first < digits.length() && digits[first] == 48 {
    first += 1
  }
  if first == digits.length() {
    return {
      sign: 0,
      order: { negative: false, digits: "0", },
      significant: "",
    }
  }
  let mut last = digits.length()
  while last > first && digits[last - 1] == 48 {
    last -= 1
  }
  let mut exponent_negative = false
  if i < raw.length() {
    i += 1
    exponent_negative = raw[i] == 45
    if raw[i] == 45 || raw[i] == 43 {
      i += 1
    }
    while i < raw.length() && raw[i] == 48 {
      i += 1
    }
  }
  let exponent = if i < raw.length() { raw[i:].to_owned() } else { "0" }
  let order = DecimalOrder::{
    negative: exponent_negative && exponent != "0",
    digits: exponent,
  }.add_offset(before - first)
  {
    sign: if negative {
      -1
    } else {
      1
    },
    order,
    significant: digits[first:last].to_owned(),
  }
}

///|
fn decimal_compare_repr(a : String, b : String) -> Int32 {
  let a = decimal_value(a)
  let b = decimal_value(b)
  if a.sign != b.sign {
    return if a.sign < b.sign { -1 } else { 1 }
  }
  if a.sign == 0 {
    return 0
  }
  let order = decimal_order_compare(a.order, b.order)
  let order = if order != 0 {
    order
  } else {
    a.significant.lexical_compare(b.significant)
  }
  if a.sign < 0 {
    -order
  } else {
    order
  }
}

///|
fn decimal_compare(a : Json, b : Json) -> Int32 {
  guard a is Number(_, repr=Some(a)) && b is Number(_, repr=Some(b)) else {
    abort("validated decimal representations")
  }
  decimal_compare_repr(a, b)
}
