use crate::dates_calendar::{civil_date, day_number, month_length};
pub fn coupon_schedule(issue: i32, maturity: i32, frequency: i32, eom: bool, long: bool) -> Vec<i32> {
    let (year, month, day) = civil_date(maturity); let eom = eom && day == month_length(year, month);
    let mut dates = Vec::new(); let mut boundary = maturity;
    while boundary > issue {
        dates.push(boundary);
        let index = year * 12 + month - 1 - (12 / frequency) * dates.len() as i32;
        let y = index / 12; let m = index % 12 + 1;
        boundary = day_number(y, m, if eom { month_length(y, m) } else { day.min(month_length(y, m)) });
    }
    if long && boundary != issue && dates.len() >= 2 { dates.pop(); }
    dates.push(issue); dates.reverse(); dates
}
