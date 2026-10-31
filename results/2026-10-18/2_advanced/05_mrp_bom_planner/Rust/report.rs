use std::{fs, io};
pub fn money(cents: i64) -> String { format!("{}.{:02}", cents / 100, cents % 100) }
pub fn percent(part: i64, whole: i64) -> i64 { (200 * part + whole) / (2 * whole) }
pub fn table_row(label: &str, values: &[i64], width: usize) -> String { let mut line = format!("{label:<10}"); for value in values { line.push_str(&format!("{value:>width$}")); } line }
pub fn write_report(name: &str, lines: &[String]) -> io::Result<()> { fs::create_dir_all("output")?; fs::write(format!("output/{name}"), if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }) }
