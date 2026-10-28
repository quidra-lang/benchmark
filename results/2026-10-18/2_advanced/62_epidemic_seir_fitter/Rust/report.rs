pub fn real(value: f64, digits: usize) -> String {
    let s = format!("{:.*}", digits, value);
    if s.starts_with('-') && s[1..].bytes().all(|b| b == b'0' || b == b'.') { s[1..].to_owned() } else { s }
}

pub fn plot(cases: &[i64], fitted: &[f64]) -> Vec<String> {
    let days = cases.len();
    let maximum = *cases.iter().max().unwrap();
    let width = maximum.to_string().len();
    let mut grid = vec![vec![b'.'; 70]; 20];
    for x in 0..70 {
        let day = x*(days-1)/69;
        let observed = (20*cases[day]/maximum).min(19) as usize;
        let predicted = ((20.0*fitted[day]/maximum as f64).floor() as usize).min(19);
        grid[observed][x] = b'o';
        grid[predicted][x] = if predicted == observed { b'#' } else { b'*' };
    }
    let mut lines = vec![format!("plot observed o fitted * both # days 1 {} max {}", days, maximum)];
    for y in (0..20).rev() {
        lines.push(format!("{:>width$} |{}", maximum*y as i64/20, String::from_utf8(grid[y].clone()).unwrap(), width=width));
    }
    lines.push(format!("{} +{}", " ".repeat(width), (0..70).map(|x| if x%10 == 0 { '+' } else { '-' }).collect::<String>()));
    let mut field = vec![b' '; 70];
    for x in (0..70).step_by(10) {
        let day = (1+x*(days-1)/69).to_string();
        field[x..x+day.len()].copy_from_slice(day.as_bytes());
    }
    lines.push(format!("{}{}", " ".repeat(width+2), String::from_utf8(field).unwrap()).trim_end().to_owned());
    lines
}
