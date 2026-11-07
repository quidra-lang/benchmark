use std::{fs, io};
use crate::{Difference, OutputKey, Profile, Value, key_parts, ordered_keys};
use crate::schema::Kind;

pub const MASK: &str = "********";
pub fn string_notation(text: &str) -> String {
    let mut result = String::from("\"");
    for c in text.chars() {
        match c { '\\' => result.push_str("\\\\"), '"' => result.push_str("\\\""), '\n' => result.push_str("\\n"), '\t' => result.push_str("\\t"), _ => result.push(c) }
    }
    result.push('"'); result
}
pub fn value_notation(kind: Kind, item: Kind, value: &Value) -> String {
    match value {
        Value::List(items) => format!("[{}]", items.iter().map(|v| value_notation(item, Kind::String, v)).collect::<Vec<_>>().join(", ")),
        Value::Text(text) if kind == Kind::String => string_notation(text),
        Value::Text(text) => text.clone(), Value::Integer(n) => n.to_string(), Value::Boolean(b) => b.to_string(),
    }
}
pub fn shown(output: &OutputKey) -> &str { if output.secret { MASK } else { &output.notation } }

fn normalized(profile: &Profile) -> Vec<String> {
    let mut lines = vec![format!("profile {}", profile.name)];
    let mut current = String::new();
    for key in ordered_keys(&profile.outputs) {
        let (section, name) = key_parts(&key);
        if section != current { lines.push(format!("[{section}]")); current = section.into(); }
        lines.push(format!("{name} = {}", shown(&profile.outputs[&key])));
    }
    lines
}
fn diagnostics(profile: &Profile) -> Vec<String> {
    let mut lines = vec![format!("profile {} errors {} warnings {}", profile.name, profile.errors, profile.warnings)];
    lines.extend(profile.diagnostics.iter().map(|d| format!("{} {} {}", d.origin.text(), d.code, d.message)));
    lines
}
fn report(profile: &Profile) -> Vec<String> {
    let mut lines = vec![format!("profile {}", profile.name), "includes".into()];
    lines.extend(profile.tree.iter().map(|(depth, text)| format!("{}{text}", "  ".repeat(depth + 1))));
    lines.push("overridden".into());
    if profile.overridden.is_empty() { lines.push("  (none)".into()); }
    for (key, history) in &profile.overridden {
        lines.push(format!("  {key}: {}", history.iter().map(|o| o.text()).collect::<Vec<_>>().join(" -> ")));
    }
    lines.push(format!("keys {} documents {} manifest {} defaults {}", profile.outputs.len(), profile.document_keys, profile.manifest_keys, profile.default_keys));
    lines.push(format!("dropped {}", profile.dropped));
    lines.push(format!("errors {} warnings {}", profile.errors, profile.warnings));
    lines
}
fn difference(diff: &Difference) -> Vec<String> {
    let mut lines = vec![format!("diff {} -> {}: {} added, {} removed, {} changed", diff.first, diff.second, diff.added, diff.removed, diff.changed)];
    for (key, before, after) in &diff.entries {
        lines.push(match (before, after) {
            (None, Some(value)) => format!("+ {key} = {value}"), (Some(value), None) => format!("- {key} = {value}"),
            (Some(a), Some(b)) => format!("~ {key}: {a} -> {b}"), _ => unreachable!(),
        });
    }
    lines
}
fn write(name: &str, blocks: Vec<Vec<String>>) -> io::Result<()> {
    let text = blocks.into_iter().map(|lines| lines.join("\n")).collect::<Vec<_>>().join("\n\n") + "\n";
    fs::write(format!("output/{name}.txt"), text)
}
pub fn write_outputs(profiles: &[Profile], diffs: &[Difference]) -> io::Result<()> {
    fs::create_dir_all("output")?;
    write("normalized", profiles.iter().map(normalized).collect())?;
    write("diagnostics", profiles.iter().map(diagnostics).collect())?;
    write("report", profiles.iter().map(report).collect())?;
    write("diff", diffs.iter().map(difference).collect())
}
