use std::collections::BTreeMap;

fn decode(s: &str) -> String {
    let b = s.as_bytes();
    let (mut out, mut i) = (String::new(), 0);
    while i < b.len() {
        if b[i] == b'+' {
            out.push(' ');
            i += 1;
        } else if b[i] == b'%' {
            let value = u8::from_str_radix(&s[i + 1..i + 3], 16).unwrap();
            out.push(value as char);
            i += 3;
        } else {
            out.push(b[i] as char);
            i += 1;
        }
    }
    out
}

fn main() {
    for (k, query) in [
        "name=Alice+Smith&age=30&city=New%20York",
        "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
        "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
        "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips",
    ]
    .iter()
    .enumerate()
    {
        let mut values: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for item in query.split('&') {
            let (key, value) = item.split_once('=').unwrap_or((item, ""));
            values.entry(decode(key)).or_default().push(decode(value));
        }
        println!("query {}:", k + 1);
        for (key, items) in values {
            let quoted = items
                .iter()
                .map(|value| format!("\"{}\"", value))
                .collect::<Vec<_>>()
                .join(", ");
            println!("  {}: {}", key, quoted);
        }
    }
}
