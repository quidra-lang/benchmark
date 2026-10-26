use std::{fs, io};
use crate::day_rules::split_time;
use crate::resolver::Period;

pub fn local_text(time: i64) -> String { let (y, m, d, h, mi, s) = split_time(time); format!("{y:04}-{m:02}-{d:02}T{h:02}:{mi:02}:{s:02}") }
pub fn ut_text(time: i64) -> String { local_text(time) + "Z" }
pub fn offset_text(value: i64) -> String {
    let absolute = value.abs();
    let mut text = format!("{}{:02}:{:02}", if value < 0 { "-" } else { "+" }, absolute / 3600, absolute / 60 % 60);
    if absolute % 60 != 0 { text += &format!(":{:02}", absolute % 60); }
    text
}
pub fn duration_text(value: i64) -> String { let absolute = value.abs(); format!("{}{}:{:02}:{:02}", if value < 0 { "-" } else { "" }, absolute / 3600, absolute / 60 % 60, absolute % 60) }
pub fn clock_text(value: i64) -> String { let mut text = format!("{}:{:02}", value / 3600, value / 60 % 60); if value % 60 != 0 { text += &format!(":{:02}", value % 60); } text }
pub fn state_text(period: &Period) -> String { format!("{} {} {}", offset_text(period.offset), if period.dst { "DST" } else { "STD" }, period.abbreviation) }
pub fn change_text(time: i64, before: &Period, after: &Period) -> String { format!("{} {} -> {}", ut_text(time), state_text(before), state_text(after)) }
pub fn write_lines(path: &str, lines: &[String]) -> io::Result<()> { fs::write(path, if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }) }
pub fn write_blocks(path: &str, blocks: &[Vec<String>]) -> io::Result<()> {
    let mut lines = Vec::new();
    for (index, block) in blocks.iter().enumerate() { if index > 0 { lines.push(String::new()); } lines.extend(block.iter().cloned()); }
    write_lines(path, &lines)
}
