///|
fn date_digits(
  source : String,
  from : Int32,
  count : Int32,
  loc : String,
) -> Int32 raise MaskError {
  let mut value = 0
  for i in from..<(from + count) {
    let ch = source[i].to_int()
    if ch < 48 || ch > 57 {
      reject("date_format", loc)
    }
    value = value * 10 + ch - 48
  }
  value
}

///|
fn days_before_year(year : Int32) -> Int32 {
  let y = year - 1
  y * 365 + y / 4 - y / 100 + y / 400
}

///|
fn month_days(year : Int32, month : Int32) -> Int32 {
  if month == 2 && year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) {
    29
  } else {
    [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
  }
}

///|
fn date_pad(value : Int32, width : Int32) -> String {
  let text = value.to_string()
  Array::make(width - text.length(), "0").join("") + text
}

///|
fn shift_date(
  source : String,
  days : Int32,
  loc : String,
) -> String raise MaskError {
  if source.length() < 10 || source[4] != 45 || source[7] != 45 {
    reject("date_format", loc)
  }
  let year = date_digits(source, 0, 4, loc)
  let month = date_digits(source, 5, 2, loc)
  let day = date_digits(source, 8, 2, loc)
  if year < 1 || month < 1 || month > 12 {
    reject("date_invalid", loc)
  }
  if day < 1 || day > month_days(year, month) {
    reject("date_invalid", loc)
  }
  if source.length() != 10 {
    if source.length() < 19 ||
      (source[10] != 84 && source[10] != 32) ||
      source[13] != 58 ||
      source[16] != 58 {
      reject("date_format", loc)
    }
    if date_digits(source, 11, 2, loc) > 23 ||
      date_digits(source, 14, 2, loc) > 59 ||
      date_digits(source, 17, 2, loc) > 59 {
      reject("date_invalid", loc)
    }
    let mut end = 19
    if end < source.length() && source[end] == 46 {
      end += 1
      let start = end
      while end < source.length() && source[end] >= 48 && source[end] <= 57 {
        end += 1
      }
      if end - start < 1 || end - start > 9 {
        reject("date_format", loc)
      }
    }
    if end < source.length() && source[end] == 90 {
      end += 1
    }
    if end != source.length() {
      reject("date_format", loc)
    }
  }
  let mut ordinal = days_before_year(year) + day - 1
  for m in 1..<month {
    ordinal += month_days(year, m)
  }
  ordinal += days
  if ordinal < 0 || ordinal >= days_before_year(10000) {
    reject("date_range", loc)
  }
  let mut lo = 1
  let mut hi = 10000
  while lo + 1 < hi {
    let mid = (lo + hi) / 2
    if days_before_year(mid) <= ordinal {
      lo = mid
    } else {
      hi = mid
    }
  }
  let mut rest = ordinal - days_before_year(lo)
  let mut m = 1
  while rest >= month_days(lo, m) {
    rest -= month_days(lo, m)
    m += 1
  }
  date_pad(lo, 4) +
  "-" +
  date_pad(m, 2) +
  "-" +
  date_pad(rest + 1, 2) +
  source[10:].to_owned()
}
