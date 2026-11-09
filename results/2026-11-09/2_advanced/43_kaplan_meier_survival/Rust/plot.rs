use crate::dataset::Subject;
use crate::estimators::{at, KmRow};

pub fn render(names: &[String], collections: &[Vec<Subject>], tables: &[Vec<KmRow>], width: usize, height: usize, time: i64) -> Vec<String> {
    let mut cells = vec![vec![b' '; width]; height];
    for (g, subjects) in collections.iter().take(names.len()).enumerate() {
        let maximum = subjects.iter().map(|s| s.time).max().unwrap();
        let mut previous = None;
        for column in 0..width {
            let t = column as i64 * (time / width as i64);
            if t > maximum { break; }
            let band = ((at(&tables[g], t).survival * height as f64).floor() as usize).min(height - 1);
            let mut occupied = vec![band];
            if let Some(previous) = previous { if previous > band + 1 { occupied.extend(band + 1..previous); } }
            for band in occupied {
                let cell = &mut cells[height - 1 - band][column];
                *cell = if *cell == b' ' { b'A' + g as u8 } else { b'*' };
            }
            previous = Some(band);
        }
    }
    let mut lines = vec![format!("km_plot width {width} height {height} time {time}"), format!("legend {}", names.iter().enumerate().map(|(i, name)| format!("{} {}", (b'A' + i as u8) as char, name)).collect::<Vec<_>>().join(" "))];
    let border = format!("   +{}+", "-".repeat(width));
    lines.push(border.clone());
    for (row, cells) in cells.iter().enumerate() { lines.push(format!("{:3}|{}|", 100 * (height - 1 - row) / height, String::from_utf8(cells.clone()).unwrap())); }
    lines.push(border);
    lines.push(format!("time 0 to {time} days, {} days per column", time / width as i64));
    lines
}
