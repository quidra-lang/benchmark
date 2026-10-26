use crate::day_rules::{COMMON_MONTH_DAYS, DAY, DaySpec, MONTH_NAMES, WEEKDAY_NAMES};

pub const MIN_YEAR: i64 = 1800;
pub const MAX_YEAR: i64 = 2099;
#[derive(Clone)]
pub struct Until { pub year_text: String, pub month_text: String, pub day_text: String, pub time: i64, pub time_type: u8, pub value: i64 }
pub fn line_content(raw: &str) -> &str { raw.split('#').next().unwrap().trim_end_matches(' ') }
pub fn split_fields(content: &str) -> Vec<String> { content.split(' ').filter(|field| !field.is_empty()).map(str::to_owned).collect() }
pub fn is_number(text: &str, low: usize, high: usize) -> bool { (low..=high).contains(&text.len()) && text.bytes().all(|byte| byte.is_ascii_digit()) }
fn hms_value(text: &str, max_parts: usize) -> Option<i64> {
    let parts: Vec<&str> = text.split(':').collect();
    if parts.len() > max_parts || !is_number(parts[0], 1, 2) { return None; }
    let mut value = parts[0].parse::<i64>().ok()? * 3600;
    for (&part, unit) in parts[1..].iter().zip([60, 1]) {
        if !is_number(part, 2, 2) { return None; }
        let number = part.parse::<i64>().ok()?;
        if number > 59 { return None; }
        value += number * unit;
    }
    Some(value)
}
pub fn parse_year(text: &str) -> Result<i64, String> {
    if is_number(text, 4, 4) { let value = text.parse().unwrap(); if (MIN_YEAR..=MAX_YEAR).contains(&value) { return Ok(value); } }
    Err("bad year".to_owned())
}
pub fn parse_to(text: &str, from: i64) -> Result<i64, String> {
    if text == "only" { return Ok(from); }
    if text == "max" { return Ok(MAX_YEAR); }
    if is_number(text, 4, 4) { let value = text.parse().unwrap(); if (from..=MAX_YEAR).contains(&value) { return Ok(value); } }
    Err("bad year".to_owned())
}
pub fn parse_month(text: &str) -> Result<usize, String> { MONTH_NAMES.iter().position(|&name| name == text).map(|i| i + 1).ok_or_else(|| "bad month".to_owned()) }
fn parse_weekday(text: &str) -> Result<i64, String> { WEEKDAY_NAMES.iter().position(|&name| name == text).map(|i| i as i64).ok_or_else(|| "bad day spec".to_owned()) }
fn parse_day(text: &str, month: usize) -> Result<i64, String> {
    if is_number(text, 1, 2) && !text.starts_with('0') { let value = text.parse().unwrap(); if value <= COMMON_MONTH_DAYS[month - 1] { return Ok(value); } }
    Err("bad day spec".to_owned())
}
pub fn parse_day_spec(text: &str, month: usize) -> Result<DaySpec, String> {
    if let Some(weekday) = text.strip_prefix("last") { return Ok(DaySpec::Last(parse_weekday(weekday)?)); }
    if let Some((weekday, day)) = text.split_once(">=") { return Ok(DaySpec::After(parse_weekday(weekday)?, parse_day(day, month)?)); }
    if let Some((weekday, day)) = text.split_once("<=") { return Ok(DaySpec::Before(parse_weekday(weekday)?, parse_day(day, month)?)); }
    Ok(DaySpec::Day(parse_day(text, month)?))
}
pub fn parse_time(text: &str) -> Result<(i64, u8), String> {
    let last = text.bytes().last().unwrap_or(b' ');
    let (clock, kind) = if b"wsu".contains(&last) { (&text[..text.len() - 1], last) } else { (text, b'w') };
    match hms_value(clock, 3) { Some(value) if value <= DAY => Ok((value, kind)), _ => Err("bad time".to_owned()) }
}
pub fn parse_save(text: &str) -> Result<i64, String> { match hms_value(text, 2) { Some(value) if value <= 7200 => Ok(value), _ => Err("bad save".to_owned()) } }
pub fn parse_letter(text: &str) -> Result<String, String> {
    if text == "-" { return Ok(String::new()); }
    if !text.is_empty() && text.len() <= 5 && text.bytes().all(|byte| byte.is_ascii_uppercase()) { Ok(text.to_owned()) } else { Err("bad letter".to_owned()) }
}
pub fn parse_stdoff(text: &str) -> Result<i64, String> {
    let (sign, clock) = if let Some(clock) = text.strip_prefix('-') { (-1, clock) } else { (1, text) };
    match hms_value(clock, 3) { Some(value) if value < 57600 => Ok(sign * value), _ => Err("bad offset".to_owned()) }
}
pub fn check_format(text: &str, uses_rule_set: bool) -> Result<(), String> {
    let placeholders = text.matches("%s").count();
    let slashes = text.matches('/').count();
    let valid = text.bytes().all(|byte| byte.is_ascii_alphanumeric() || b"+-/%".contains(&byte))
        && text.matches('%').count() == placeholders && placeholders <= 1 && slashes <= 1
        && !(placeholders > 0 && slashes > 0) && (uses_rule_set || placeholders == 0)
        && !(slashes == 1 && (text.starts_with('/') || text.ends_with('/')));
    if valid { Ok(()) } else { Err("bad format".to_owned()) }
}
pub fn parse_until(fields: &[String]) -> Result<Until, String> {
    let year = parse_year(&fields[0])?;
    let month_text = fields.get(1).map(String::as_str).unwrap_or("Jan");
    let month = parse_month(month_text)?;
    let day_text = fields.get(2).map(String::as_str).unwrap_or("1");
    let day = parse_day_spec(day_text, month)?;
    let (time, time_type) = if let Some(text) = fields.get(3) { parse_time(text)? } else { (0, b'w') };
    Ok(Until { year_text: fields[0].clone(), month_text: month_text.to_owned(), day_text: day_text.to_owned(), time, time_type, value: day.value(year, month) * DAY + time })
}
