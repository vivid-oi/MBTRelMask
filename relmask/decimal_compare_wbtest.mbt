///|
test "decimal exponent offsets carry borrow cancel and cross zero" {
  for n in -100..<=100 {
    for offset in -20..<=20 {
      let order : DecimalOrder = {
        negative: n < 0,
        digits: (if n < 0 { -n } else { n }).to_string(),
      }
      let result = order.add_offset(offset)
      let expected = n + offset
      assert_eq(result.negative, expected < 0)
      assert_eq(
        result.digits,
        (if expected < 0 { -expected } else { expected }).to_string(),
      )
    }
  }
}

///|
test "decimal ordering agrees across scales without binary floating point" {
  for n in 1..<=200 {
    for exponent in -4..<=4 {
      let a = n.to_string() + "e" + exponent.to_string()
      let b = (n * 100).to_string() + "e" + (exponent - 2).to_string()
      let larger = (n * 100 + 1).to_string() + "e" + (exponent - 2).to_string()
      assert_eq(decimal_compare_repr(a, b), 0)
      assert_true(decimal_compare_repr(a, larger) < 0)
      assert_true(decimal_compare_repr("-" + a, "-" + larger) > 0)
      assert_eq(
        decimal_compare_repr(a, larger),
        -decimal_compare_repr(larger, a),
      )
    }
  }
}

///|
test "decimal total order includes underflow overflow zeros and close neighbors" {
  let values = [
    "-1e99999999999999999999999", "-1e400", "-9007199254740993.1", "-1.00000000000000000001",
    "-1", "-0.01", "-1e-99999999999999999999999", "-0", "0e99999999999999999999999",
    "1e-99999999999999999999999", "0.00000000000000000001", "0.1", "1", "1.00000000000000000001",
    "9007199254740993.1", "1e400", "1e99999999999999999999999",
  ]
  for i, a in values {
    for j, b in values {
      let order = decimal_compare_repr(a, b)
      if i == j || (i == 7 && j == 8) || (i == 8 && j == 7) {
        assert_eq(order, 0)
      } else if i < j {
        assert_true(order < 0)
      } else {
        assert_true(order > 0)
      }
    }
  }
}

///|
test "decimal exponents remain digit strings even at thousands of digits" {
  let nines = Array::make(1000, "9").join("")
  let power = "1" + Array::make(1000, "0").join("")
  let minus_two = Array::make(999, "9").join("") + "8"
  assert_eq(decimal_compare_repr("10e" + nines, "1e" + power), 0)
  assert_eq(decimal_compare_repr("0.01e" + power, "1e" + minus_two), 0)
  assert_eq(decimal_compare_repr("1e-0000", "1.000"), 0)
  assert_eq(decimal_compare_repr("-0.000e-" + power, "0"), 0)
  assert_true(decimal_compare_repr("1e-" + power, "1e-" + nines) < 0)
}
