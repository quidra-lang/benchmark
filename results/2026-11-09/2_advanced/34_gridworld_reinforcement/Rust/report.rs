use crate::environment::World;
use std::fs;

pub fn fixed(value: i64) -> String {
    let magnitude = value.abs();
    format!("{}{}.{:04}", if value < 0 { "-" } else { "" }, magnitude / 10000, magnitude % 10000)
}

pub fn average(total: i64, count: usize) -> String {
    fixed((10000 * total).div_euclid(count as i64))
}

pub fn cell(world: &World, index: usize) -> String {
    format!("{},{}", index / world.width, index % world.width)
}

pub fn cells(world: &World, path: &[usize]) -> String {
    path.iter().map(|&x| cell(world, x)).collect::<Vec<_>>().join(" ")
}

pub fn grid(world: &World, separated: bool, content: impl Fn(usize) -> String) -> Vec<String> {
    (0..world.height).map(|row| {
        (0..world.width).map(|column| {
            let index = row * world.width + column;
            if b"#GP".contains(&world.cells[index]) { (world.cells[index] as char).to_string() } else { content(index) }
        }).collect::<Vec<_>>().join(if separated { " " } else { "" })
    }).collect()
}

pub fn q_rows(world: &World, name: &str, q: &[[i64; 4]], visits: Option<&[[i64; 4]]>) -> Vec<String> {
    let mut lines = Vec::new();
    for &x in &world.states {
        for action in 0..4 {
            let count = visits.map_or_else(|| "-".into(), |v| v[x][action].to_string());
            lines.push(format!("{},{},{},{},{},{}", name, x / world.width, x % world.width, b"NESW"[action] as char, fixed(q[x][action]), count));
        }
    }
    lines
}

pub fn write(name: &str, lines: &[String]) {
    fs::write(format!("output/{name}"), format!("{}\n", lines.join("\n"))).unwrap();
}
