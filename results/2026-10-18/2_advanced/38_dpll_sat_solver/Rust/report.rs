use std::collections::BTreeMap;
use std::fs;

pub fn items(values: &[(&str, String)]) -> String {
    values.iter().map(|(name, value)| format!("{name}={value}")).collect::<Vec<_>>().join(" ")
}

pub fn numbers(values: impl IntoIterator<Item = i64>) -> String {
    let values: Vec<_> = values.into_iter().map(|value| value.to_string()).collect();
    if values.is_empty() { "-".into() } else { values.join(",") }
}

pub fn frequencies(values: impl IntoIterator<Item = usize>) -> String {
    let mut counts = BTreeMap::new();
    for value in values { *counts.entry(value).or_insert(0) += 1; }
    if counts.is_empty() { "-".into() } else { counts.iter().map(|(value, count)| format!("{value}:{count}")).collect::<Vec<_>>().join(",") }
}

pub fn board(columns: &[usize]) -> Vec<String> {
    columns.iter().map(|&column| (1..=columns.len()).map(|c| if c == column { 'Q' } else { '.' }).collect()).collect()
}

pub fn paragraphs(name: &str, paragraphs: &[Vec<String>]) {
    let text = paragraphs.iter().map(|paragraph| paragraph.join("\n")).collect::<Vec<_>>().join("\n\n");
    fs::write(format!("output/{name}"), if text.is_empty() { text } else { format!("{text}\n") }).unwrap();
}

pub fn lines(name: &str, lines: &[String]) {
    fs::write(format!("output/{name}"), format!("{}\n", lines.join("\n"))).unwrap();
}
