use std::fs;
pub fn real(value: f64, digits: usize) -> String {
    let scale = 10.0f64.powi(digits as i32);
    let rounded = (value.abs()*scale+0.5).floor()/scale;
    let text = format!("{:.*}",digits,rounded);
    if value < 0.0 && rounded != 0.0 {
        format!("-{}",text)
    } else {
        text
    }
}
pub fn signed(value: i64) -> String {
    if value > 0 {
        format!("+{}",value)
    } else {
        value.to_string()
    }
}
pub fn chart(grid: &[Vec<u8>]) -> Vec<String> {
    let border = format!("+{}+","-".repeat(grid[0].len()));
    let mut lines = vec![border.clone()];
    for row in grid {
        lines.push(format!("|{}|",String::from_utf8(row.clone()).unwrap()));
    }
    lines.push(border);
    lines
}
pub fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}",name),lines.join("\n")+"\n").unwrap();
}
