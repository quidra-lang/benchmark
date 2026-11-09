use crate::dates_calendar::{civil_date, day_number, is_leap, month_length};
pub const DAY_COUNTS: [&str; 5] = ["30/360", "30E/360", "ACT/360", "ACT/365F", "ACT/ACT"];
pub fn year_fraction(convention: &str, mut start: i32, end: i32) -> (i64, i64) {
    let (mut y1, m1, mut d1) = civil_date(start); let (y2, m2, mut d2) = civil_date(end);
    match convention {
        "30/360" | "30E/360" => {
            if convention == "30/360" {
                let february = m1 == 2 && d1 == month_length(y1, 2);
                if february && m2 == 2 && d2 == month_length(y2, 2) { d2 = 30; }
                if february { d1 = 30; }
                if d2 == 31 && d1 >= 30 { d2 = 30; }
                if d1 == 31 { d1 = 30; }
            } else { d1 = d1.min(30); d2 = d2.min(30); }
            ((360 * (y2 - y1) + 30 * (m2 - m1) + d2 - d1) as i64, 360)
        }
        "ACT/360" => ((end - start) as i64, 360),
        "ACT/365F" => ((end - start) as i64, 365),
        _ => {
            let mut numerator = 0;
            while start < end { let boundary = end.min(day_number(y1 + 1, 1, 1)); numerator += (boundary - start) as i64 * if is_leap(y1) { 365 } else { 366 }; start = boundary; y1 += 1; }
            (numerator, 133590)
        }
    }
}
