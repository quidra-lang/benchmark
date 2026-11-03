use std::{fs, io};

pub struct Image {
    pub name: String,
    pub width: usize,
    pub height: usize,
    pub maxval: usize,
    pub pixels: Vec<Vec<i64>>,
}

pub fn read_images(path: &str) -> io::Result<Vec<Image>> {
    let text = fs::read_to_string(path)?;
    let words: Vec<_> = text.lines().flat_map(|line| line.split('#').next().unwrap().split_ascii_whitespace()).collect();
    let mut images = Vec::new();
    let mut position = 0;
    while position < words.len() {
        let name = words[position + 1].to_owned();
        let width = words[position + 3].parse::<usize>().unwrap();
        let height = words[position + 4].parse::<usize>().unwrap();
        let maxval = words[position + 5].parse().unwrap();
        position += 6;
        let pixels = words[position..position + width * height].chunks(width)
            .map(|row| row.iter().map(|word| word.parse().unwrap()).collect()).collect();
        position += width * height;
        images.push(Image { name, width, height, maxval, pixels });
    }
    Ok(images)
}
