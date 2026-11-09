pub const MONTH_NAMES: [&str; 12] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
pub const WEEKDAY_NAMES: [&str; 7] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
pub const COMMON_MONTH_DAYS: [i64; 12] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
pub const DAY: i64 = 86400;
pub const NEG_INFINITY: i64 = -(1i64 << 62);
pub const POS_INFINITY: i64 = 1i64 << 62;
pub fn is_leap_year(year: i64) -> bool { year % 4 == 0 && year % 100 != 0 || year % 400 == 0 }
pub fn days_in_month(year: i64, month: usize) -> i64 { if month == 2 && is_leap_year(year) { 29 } else { COMMON_MONTH_DAYS[month - 1] } }
fn days_before_year(year: i64) -> i64 { let previous = year - 1; previous * 365 + previous.div_euclid(4) - previous.div_euclid(100) + previous.div_euclid(400) }
pub fn day_number(year: i64, month: usize, day: i64) -> i64 {
    let mut result = days_before_year(year) - days_before_year(1970) + day - 1;
    for earlier in 1..month { result += days_in_month(year, earlier); }
    result
}
pub fn weekday_of(number: i64) -> i64 { (number + 4).rem_euclid(7) }
pub fn date_of_day(number: i64) -> (i64, usize, i64) {
    let mut year = 1970 + number.div_euclid(366);
    while day_number(year, 1, 1) > number { year -= 1; }
    while day_number(year + 1, 1, 1) <= number { year += 1; }
    let mut month = 1;
    let mut day = number - day_number(year, 1, 1) + 1;
    while day > days_in_month(year, month) { day -= days_in_month(year, month); month += 1; }
    (year, month, day)
}
pub fn time_value(year: i64, month: usize, day: i64, hour: i64, minute: i64, second: i64) -> i64 { day_number(year, month, day) * DAY + hour * 3600 + minute * 60 + second }
pub fn split_time(time: i64) -> (i64, usize, i64, i64, i64, i64) {
    let (year, month, day) = date_of_day(time.div_euclid(DAY));
    let seconds = time.rem_euclid(DAY);
    (year, month, day, seconds / 3600, seconds / 60 % 60, seconds % 60)
}
#[derive(Clone)]
pub enum DaySpec { Day(i64), Last(i64), After(i64, i64), Before(i64, i64) }
impl DaySpec {
    pub fn value(&self, year: i64, month: usize) -> i64 {
        match *self {
            Self::Day(day) => day_number(year, month, day),
            Self::Last(weekday) => { let last = day_number(year, month, days_in_month(year, month)); last - (weekday_of(last) - weekday).rem_euclid(7) }
            Self::After(weekday, day) => { let base = day_number(year, month, day); base + (weekday - weekday_of(base)).rem_euclid(7) }
            Self::Before(weekday, day) => { let base = day_number(year, month, day); base - (weekday_of(base) - weekday).rem_euclid(7) }
        }
    }
}
