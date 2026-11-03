use std::{fs, io};
use crate::canvas::Image;

pub fn write_text(name: &str, lines: &[String]) -> io::Result<()> { fs::write(format!("output/{name}"), if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }) }
pub fn write_ppm(image: &Image) -> io::Result<()> {
    let mut lines = vec!["P3".into(), format!("{} {}", image[0].len(), image.len()), "255".into()];
    lines.extend(image.iter().map(|row| row.iter().map(|c| format!("{} {} {}", c[0], c[1], c[2])).collect::<Vec<_>>().join(" ")));
    write_text("image.ppm", &lines)
}
pub fn write_preview(image: &Image) -> io::Result<()> {
    let mut lines = Vec::new();
    for top in (0..image.len()).step_by(4) {
        let mut text = String::new();
        for left in (0..image[0].len()).step_by(2) {
            let mut total = 0;
            for row in &image[top..top + 4] { for c in &row[left..left + 2] { total += 299 * c[0] + 587 * c[1] + 114 * c[2]; } }
            text.push(b"@%#*+=-:,."[(total / 8000 * 10 / 256) as usize] as char);
        }
        lines.push(text);
    }
    write_text("preview.txt", &lines)
}
