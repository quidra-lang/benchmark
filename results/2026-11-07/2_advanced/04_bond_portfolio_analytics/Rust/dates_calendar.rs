use std::collections::HashSet;

pub const BUSINESS_DAY_RULES: [&str; 4] = ["FOLLOWING", "MODIFIED_FOLLOWING", "PRECEDING", "UNADJUSTED"];
pub fn is_leap(year: i32) -> bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }
pub fn month_length(year: i32, month: i32) -> i32 { if month == 2 && is_leap(year) { 29 } else { [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][(month - 1) as usize] } }
pub fn valid_date(text: &str) -> bool {
    let year: i32 = text[..4].parse().unwrap(); let month: i32 = text[5..7].parse().unwrap(); let day: i32 = text[8..].parse().unwrap();
    (2001..=2099).contains(&year) && (1..=12).contains(&month) && (1..=month_length(year, month)).contains(&day)
}
pub fn day_number(year: i32, month: i32, day: i32) -> i32 {
    let mut number = day - 1;
    for earlier in 2000..year { number += if is_leap(earlier) { 366 } else { 365 }; }
    for earlier in 1..month { number += month_length(year, earlier); }
    number
}
pub fn parse_date(text: &str) -> i32 { day_number(text[..4].parse().unwrap(), text[5..7].parse().unwrap(), text[8..].parse().unwrap()) }
pub fn civil_date(mut number: i32) -> (i32, i32, i32) {
    let mut year = 2000;
    loop { let length = if is_leap(year) { 366 } else { 365 }; if number < length { break; } number -= length; year += 1; }
    let mut month = 1;
    while number >= month_length(year, month) { number -= month_length(year, month); month += 1; }
    (year, month, number + 1)
}
pub fn format_date(number: i32) -> String { let (year, month, day) = civil_date(number); format!("{year:04}-{month:02}-{day:02}") }
pub struct Calendar { holidays: HashSet<i32> }
impl Calendar {
    pub fn new(holidays: impl IntoIterator<Item = i32>) -> Self { Self { holidays: holidays.into_iter().collect() } }
    pub fn business(&self, day: i32) -> bool { (day + 5).rem_euclid(7) < 5 && !self.holidays.contains(&day) }
    pub fn following(&self, mut day: i32) -> i32 { while !self.business(day) { day += 1; } day }
    pub fn preceding(&self, mut day: i32) -> i32 { while !self.business(day) { day -= 1; } day }
    pub fn adjust(&self, day: i32, rule: &str) -> i32 {
        match rule {
            "FOLLOWING" => self.following(day), "PRECEDING" => self.preceding(day),
            "MODIFIED_FOLLOWING" => { let next = self.following(day); if civil_date(next).1 != civil_date(day).1 { self.preceding(day) } else { next } }
            _ => day,
        }
    }
    pub fn move_days(&self, mut day: i32, count: i32) -> i32 {
        let direction = if count < 0 { -1 } else { 1 }; let mut remaining = if count < 0 { -count } else { count };
        while remaining > 0 { day += direction; if self.business(day) { remaining -= 1; } }
        day
    }
}
