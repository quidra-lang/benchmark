use crate::Metric;

pub fn line(metric: &Metric, alignment: &str, last: bool, prefix: &str) -> String {
    let pieces: Vec<_> = metric.pieces.iter().map(|piece| piece.replace('~', " ")).collect();
    let text = pieces.join(" ");
    let content = if metric.slack <= 0 { text }
        else if alignment == "justify" && !last && pieces.len() > 1 {
            let gaps = pieces.len() - 1;
            let slack = metric.slack as usize;
            let mut result = pieces[0].clone();
            for (i, piece) in pieces.iter().skip(1).enumerate() {
                result.push_str(&" ".repeat(1 + slack / gaps + usize::from(i < slack % gaps)));
                result.push_str(piece);
            }
            result
        } else if alignment == "right" { format!("{}{}", " ".repeat(metric.slack as usize), text) }
        else if alignment == "center" { format!("{}{}", " ".repeat(metric.slack as usize / 2), text) }
        else { text };
    format!("{prefix}{content}")
}

pub fn table(rows: &[Vec<String>], columns: &str, caption: &str, number: &str) -> Vec<String> {
    let widths: Vec<_> = (0..columns.len()).map(|column| rows.iter().map(|row| row[column].len()).max().unwrap()).collect();
    let mut lines = Vec::new();
    if !caption.is_empty() { lines.push(format!("Table {number}. {caption}")); }
    for (index, row) in rows.iter().enumerate() {
        let cells: Vec<_> = row.iter().enumerate().map(|(column, text)| {
            let missing = widths[column] - text.len();
            let left = match columns.as_bytes()[column] { b'r' => missing, b'c' => missing / 2, _ => 0 };
            format!("{}{}{}", " ".repeat(left), text, " ".repeat(missing - left))
        }).collect();
        lines.push(cells.join(" | ").trim_end().into());
        if index == 0 { lines.push(widths.iter().map(|&width| "-".repeat(width)).collect::<Vec<_>>().join("-+-")); }
    }
    lines
}

pub fn running(fields: &[String; 3], replacements: &[(&str, String)], width: usize, even: bool) -> String {
    let mut fields: Vec<_> = fields.iter().map(|field| {
        let mut text = field.clone();
        for (key, value) in replacements { text = text.replace(key, value); }
        text
    }).collect();
    if even { fields.swap(0, 2); }
    let starts = [0, (width - fields[1].len()) / 2, width - fields[2].len()];
    let mut line = vec![b' '; width];
    for (field, start) in fields.iter().zip(starts) { line[start..start + field.len()].copy_from_slice(field.as_bytes()); }
    String::from_utf8(line).unwrap().trim_end().into()
}

pub fn pages(pages: &[(String, Vec<String>, String)]) -> Vec<String> {
    let mut lines = Vec::new();
    for (index, (header, body, footer)) in pages.iter().enumerate() {
        lines.extend([format!("--- page {} ---", index + 1), header.clone(), String::new()]);
        lines.extend(body.clone());
        lines.extend([String::new(), footer.clone()]);
    }
    lines
}
