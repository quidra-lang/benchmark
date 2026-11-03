use std::collections::HashMap;
use crate::script_loader::reference;

pub fn reflect(words: &[String], replacements: &HashMap<String, Vec<String>>) -> Vec<String> {
    words.iter().flat_map(|word| replacements.get(word).cloned().unwrap_or_else(|| vec![word.clone()])).collect()
}

fn binding(bindings: &[Vec<String>], number: usize) -> &[String] {
    number.checked_sub(1).and_then(|index| bindings.get(index)).map(Vec::as_slice).unwrap_or(&[])
}

pub fn build_reply(template: &str, bindings: &[Vec<String>], replacements: &HashMap<String, Vec<String>>) -> String {
    let mut text = String::new();
    let mut index = 0;
    while index < template.len() {
        if let Some(number) = template.get(index..index + 3).and_then(reference) {
            text.push_str(&reflect(binding(bindings, number), replacements).join(" "));
            index += 3;
        } else {
            text.push(template.as_bytes()[index] as char);
            index += 1;
        }
    }
    let mut reply = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if reply.as_bytes().first().is_some_and(u8::is_ascii_lowercase) {
        reply.replace_range(..1, &reply[..1].to_ascii_uppercase());
    }
    reply
}

pub fn restate(arguments: &[String], bindings: &[Vec<String>]) -> Vec<String> {
    arguments.iter().flat_map(|word| {
        reference(word).map(|number| binding(bindings, number).to_vec()).unwrap_or_else(|| vec![word.clone()])
    }).collect()
}

pub fn wrap_reply(text: &str) -> Vec<String> {
    let mut words = text.split_whitespace();
    let Some(first) = words.next() else { return vec!["ELIZA:".to_owned()]; };
    let mut lines = vec![format!("ELIZA: {first}")];
    for word in words {
        let last = lines.last_mut().unwrap();
        if last.len() + word.len() + 1 <= 72 { last.push(' '); last.push_str(word); }
        else { lines.push(format!("       {word}")); }
    }
    lines
}
