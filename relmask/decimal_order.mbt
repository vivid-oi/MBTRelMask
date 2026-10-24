///|
/// Signed decimal integer used only for an exponent plus a digit offset.
/// Keeping the exponent as digits avoids overflow and expanding powers of ten.
priv struct DecimalOrder {
  negative : Bool
  digits : String
}

///|
fn decimal_unsigned_compare(a : String, b : String) -> Int32 {
  if a.length() < b.length() {
    -1
  } else if a.length() > b.length() {
    1
  } else {
    a.lexical_compare(b)
  }
}

///|
fn decimal_order_compare(a : DecimalOrder, b : DecimalOrder) -> Int32 {
  if a.negative != b.negative {
    return if a.negative { -1 } else { 1 }
  }
  let order = decimal_unsigned_compare(a.digits, b.digits)
  if a.negative {
    -order
  } else {
    order
  }
}

///|
fn decimal_digit_string(reversed : Array[Int32]) -> String {
  let mut end = reversed.length()
  while end > 1 && reversed[end - 1] == 0 {
    end -= 1
  }
  let result = StringBuilder()
  while end > 0 {
    end -= 1
    result.write_char((48 + reversed[end]).to_char().unwrap())
  }
  result.to_string()
}

///|
fn decimal_add_digits(a : String, b : String) -> String {
  let result : Array[Int32] = []
  let mut i = a.length() - 1
  let mut j = b.length() - 1
  let mut carry = 0
  while i >= 0 || j >= 0 || carry != 0 {
    let x = if i >= 0 { a[i].to_int() - 48 } else { 0 }
    let y = if j >= 0 { b[j].to_int() - 48 } else { 0 }
    let sum = x + y + carry
    result.push(sum % 10)
    carry = sum / 10
    i -= 1
    j -= 1
  }
  decimal_digit_string(result)
}

///|
/// Inputs are canonical unsigned integers with a >= b.
fn decimal_subtract_digits(a : String, b : String) -> String {
  let result : Array[Int32] = []
  let mut i = a.length() - 1
  let mut j = b.length() - 1
  let mut borrow = 0
  while i >= 0 {
    let y = if j >= 0 { b[j].to_int() - 48 } else { 0 }
    let difference = a[i].to_int() - 48 - y - borrow
    result.push(if difference < 0 { difference + 10 } else { difference })
    borrow = if difference < 0 { 1 } else { 0 }
    i -= 1
    j -= 1
  }
  decimal_digit_string(result)
}

///|
fn DecimalOrder::add_offset(
  self : DecimalOrder,
  offset : Int32,
) -> DecimalOrder {
  if offset == 0 {
    return self
  }
  let negative = offset < 0
  let digits = (if negative { -offset } else { offset }).to_string()
  if self.negative == negative {
    return { negative, digits: decimal_add_digits(self.digits, digits), }
  }
  let order = decimal_unsigned_compare(self.digits, digits)
  if order == 0 {
    return { negative: false, digits: "0", }
  }
  if order > 0 {
    {
      negative: self.negative,
      digits: decimal_subtract_digits(self.digits, digits),
    }
  } else {
    { negative, digits: decimal_subtract_digits(digits, self.digits), }
  }
}
