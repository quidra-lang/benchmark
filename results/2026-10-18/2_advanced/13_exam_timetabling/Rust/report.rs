use std::{fs, io, path::Path};

pub fn fixed_width_line(label: &str, cells: &[String], label_width: usize, cell_width: usize) -> String {
    let mut line = format!("{label:<label_width$}");
    for cell in cells {
        line.push_str(&format!("{cell:>cell_width$}"));
    }
    line
}

pub fn rounded_percent(part: usize, whole: usize) -> usize {
    (200 * part + whole) / (2 * whole)
}

pub fn write_files(directory: &str, files: Vec<(&str, Vec<String>)>) -> io::Result<()> {
    fs::create_dir_all(directory)?;
    for (name, lines) in files {
        fs::write(Path::new(directory).join(name), lines.join("\n") + "\n")?;
    }
    Ok(())
}
