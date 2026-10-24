///|
test "Gregorian day shifts round trip across boundary calendars" {
  for year in [1, 4, 100, 400, 1600, 1900, 1999, 2000, 2024, 2100, 9999] {
    for month in 1..<=12 {
      for day in [1, month_days(year, month)] {
        let original = date_pad(year, 4) +
          "-" +
          date_pad(month, 2) +
          "-" +
          date_pad(day, 2)
        assert_eq(shift_date(original, 0, "test"), original)
        for delta in [-146097, -365, -1, 1, 365, 146097] {
          let shifted = Some(shift_date(original, delta, "test")) catch {
            Invalid(code~, ..) => {
              assert_eq(code, "date_range")
              None
            }
          }
          if shifted is Some(value) {
            assert_eq(shift_date(value, -delta, "test"), original)
          }
        }
      }
    }
  }
}
