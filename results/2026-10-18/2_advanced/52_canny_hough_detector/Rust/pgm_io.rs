use std::{fs, io};

pub struct Image {
    pub width: usize,
    pub height: usize,
    pub pixels: Vec<i64>,
}

pub struct Data {
    pub image: Image,
    pub trig: Vec<(i64, i64)>,
    pub params: Vec<Vec<i64>>,
}

pub fn read() -> io::Result<Data> {
    let content = fs::read_to_string("input/image.pgm")?;
    let mut words = content.split_whitespace();
    words.next();
    let width = words.next().unwrap().parse().unwrap();
    let height = words.next().unwrap().parse().unwrap();
    words.next();
    let pixels = words.map(|s| s.parse().unwrap()).collect();
    let trig = fs::read_to_string("input/trig.txt")?.lines().map(|l| {
        let v: Vec<i64> = l.split_whitespace().map(|s| s.parse().unwrap()).collect();
        (v[1], v[2])
    }).collect();
    let params = fs::read_to_string("input/params.txt")?.lines().map(|l| l.split_whitespace().skip(1).map(|s| s.parse().unwrap()).collect()).collect();
    Ok(Data { image: Image { width, height, pixels }, trig, params })
}

pub fn write(name: &str, image: &Image) -> io::Result<()> {
    let mut lines = vec!["P2".into(), format!("{} {}", image.width, image.height), "255".into()];
    lines.extend(image.pixels.chunks(image.width).map(|r| r.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")));
    fs::write(format!("output/{}", name), lines.join("\n") + "\n")
}
