use crate::headers::{remove_comments, split_words};

const WEEKDAYS: [&str; 7] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
const MONTHS: [&str; 12] = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
fn leap(year: i64) -> bool { year % 4 == 0 && year % 100 != 0 || year % 400 == 0 }
fn month_days(year: i64, month: usize) -> i64 { if month == 2 && leap(year) { 29 } else { [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1] } }
fn year_days(year: i64) -> i64 { if leap(year) { 366 } else { 365 } }
fn digits(text: &str, lengths: &[usize]) -> bool { lengths.contains(&text.len()) && text.bytes().all(|byte| byte.is_ascii_digit()) }
pub fn parse_date(value: &str) -> Result<i64, &'static str> {
    let syntax = "bad Date syntax";
    let range = "Date out of range";
    let text = remove_comments(value).ok_or(syntax)?.replace(',', " , ");
    let mut tokens = split_words(&text);
    let mut weekday = None;
    if tokens.len() >= 3 && tokens[1] == "," {
        if let Some(day) = WEEKDAYS.iter().position(|word| tokens[0].eq_ignore_ascii_case(word)) { weekday = Some(day); tokens.drain(..2); }
    }
    if tokens.len() != 5 { return Err(syntax); }
    let (day_text, month_text, year_text, time, zone) = (tokens[0], tokens[1], tokens[2], tokens[3], tokens[4]);
    let month = MONTHS.iter().position(|word| month_text.eq_ignore_ascii_case(word)).ok_or(syntax)? + 1;
    let pieces: Vec<_> = time.split(':').collect();
    let numeric = zone.starts_with(['+', '-']) && digits(&zone[1..], &[4]);
    let named = match zone.to_ascii_lowercase().as_str() { "ut" | "gmt" | "z" => Some(0), "est" | "cdt" => Some(-300),
        "edt" => Some(-240), "cst" | "mdt" => Some(-360), "mst" | "pdt" => Some(-420), "pst" => Some(-480), _ => None };
    if !digits(day_text, &[1, 2]) || !digits(year_text, &[2, 4]) || ![2, 3].contains(&pieces.len()) || pieces.iter().any(|part| !digits(part, &[2])) || !(numeric || named.is_some()) { return Err(syntax); }
    let day: i64 = day_text.parse().unwrap();
    let mut year: i64 = year_text.parse().unwrap();
    if year_text.len() == 2 { year += if year < 50 { 2000 } else { 1900 }; }
    let hour: i64 = pieces[0].parse().unwrap();
    let minute: i64 = pieces[1].parse().unwrap();
    let second: i64 = if pieces.len() == 3 { pieces[2].parse().unwrap() } else { 0 };
    let offset = if numeric {
        let hours: i64 = zone[1..3].parse().unwrap();
        let minutes: i64 = zone[3..5].parse().unwrap();
        if hours > 23 || minutes > 59 { return Err(range); }
        (hours * 60 + minutes) * if zone.starts_with('-') { -1 } else { 1 }
    } else { named.unwrap() };
    if !(1970..=2099).contains(&year) || day < 1 || day > month_days(year, month) || hour > 23 || minute > 59 || second > 59 { return Err(range); }
    let days: i64 = (1970..year).map(year_days).sum::<i64>() + (1..month).map(|month| month_days(year, month)).sum::<i64>() + day - 1;
    let seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset * 60;
    if seconds < 0 { return Err(range); }
    if weekday.is_some_and(|weekday| ((days + 3) % 7) as usize != weekday) { return Err("Date weekday mismatch"); }
    Ok(seconds)
}
pub fn format_utc(seconds: i64) -> String {
    let (mut days, rest) = (seconds / 86400, seconds % 86400);
    let (mut year, mut month) = (1970, 1);
    while days >= year_days(year) { days -= year_days(year); year += 1; }
    while days >= month_days(year, month) { days -= month_days(year, month); month += 1; }
    format!("{year:04}-{month:02}-{:02} {:02}:{:02}:{:02}", days + 1, rest / 3600, rest % 3600 / 60, rest % 60)
}
