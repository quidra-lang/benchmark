use std::collections::{BTreeMap, HashSet};
use std::io::{self, Read};

type Outcome<T> = Result<T, String>;

fn check(condition: bool, reason: &str) -> Outcome<()> {
    if condition { Ok(()) } else { Err(reason.to_string()) }
}

fn floor_divide(value: i32, divisor: i32) -> i32 {
    let quotient = value / divisor;
    if value < 0 && value % divisor != 0 { quotient - 1 } else { quotient }
}

fn within_limits(values: &[i32]) -> bool {
    values.iter().all(|&x| (-1000..=1000).contains(&x))
}

#[derive(Clone, Copy, Eq, PartialEq, Hash)]
struct Point {
    x: i32,
    y: i32,
}

impl Point {
    fn new(x: i32, y: i32) -> Self { Self { x, y } }
}

const FOUR: [Point; 4] = [
    Point { x: 0, y: -1 }, Point { x: -1, y: 0 },
    Point { x: 1, y: 0 }, Point { x: 0, y: 1 },
];

const EIGHT: [Point; 8] = [
    Point { x: -1, y: -1 }, Point { x: 0, y: -1 },
    Point { x: 1, y: -1 }, Point { x: -1, y: 0 },
    Point { x: 1, y: 0 }, Point { x: -1, y: 1 },
    Point { x: 0, y: 1 }, Point { x: 1, y: 1 },
];

#[derive(Clone)]
struct Image {
    width: i32,
    height: i32,
    maxval: i32,
    pixels: Vec<i32>,
}

impl Image {
    fn at(&self, x: i32, y: i32) -> i32 {
        self.pixels[(y * self.width + x) as usize]
    }

    fn contains(&self, x: i32, y: i32) -> bool {
        x >= 0 && y >= 0 && x < self.width && y < self.height
    }

    fn clamped(&self, value: i32) -> i32 {
        value.clamp(0, self.maxval)
    }

    fn with_pixels(&self, pixels: Vec<i32>) -> Self {
        Self { width: self.width, height: self.height, maxval: self.maxval, pixels }
    }

    fn map(&self, change: impl Fn(i32) -> i32) -> Self {
        self.with_pixels(self.pixels.iter().map(|&pixel| change(pixel)).collect())
    }

    fn neighborhood(&self, x: i32, y: i32) -> [i32; 9] {
        let mut result = [0; 9];
        let mut index = 0;
        for dy in -1..=1 {
            for dx in -1..=1 {
                result[index] = self.at(
                    (x + dx).clamp(0, self.width - 1),
                    (y + dy).clamp(0, self.height - 1),
                );
                index += 1;
            }
        }
        result
    }

    fn summary(&self) -> String {
        let checksum: i64 = self.pixels.iter().enumerate()
            .map(|(index, &value)| (index as i64 + 1) * value as i64)
            .sum();
        format!("{}x{} maxval {} checksum {}", self.width, self.height, self.maxval, checksum)
    }
}

fn transformed(
    image: &Image, width: i32, height: i32,
    pixel: impl Fn(i32, i32) -> i32,
) -> Image {
    let mut pixels = Vec::with_capacity((width * height) as usize);
    for y in 0..height {
        for x in 0..width { pixels.push(pixel(x, y)); }
    }
    Image { width, height, maxval: image.maxval, pixels }
}

fn cropped(image: &Image, x: i32, y: i32, width: i32, height: i32) -> Image {
    transformed(image, width, height, |i, j| image.at(x + i, y + j))
}

fn translated(
    image: &Image, width: i32, height: i32,
    dx: i32, dy: i32, fill: i32,
) -> Image {
    transformed(image, width, height, |x, y| {
        if image.contains(x - dx, y - dy) { image.at(x - dx, y - dy) } else { fill }
    })
}

fn convolved(image: &Image, kernel: &[i32; 9], divisor: i32) -> Image {
    transformed(image, image.width, image.height, |x, y| {
        let q = image.neighborhood(x, y);
        let total: i32 = q.iter().zip(kernel).map(|(&pixel, &weight)| pixel * weight).sum();
        image.clamped(floor_divide(total, divisor))
    })
}

fn rank_filtered(image: &Image, rank: usize) -> Image {
    transformed(image, image.width, image.height, |x, y| {
        let mut values = image.neighborhood(x, y);
        values.sort_unstable();
        values[rank]
    })
}

fn sobel(image: &Image) -> Image {
    transformed(image, image.width, image.height, |x, y| {
        let q = image.neighborhood(x, y);
        let gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6];
        let gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2];
        image.clamped(gx.abs() + gy.abs())
    })
}

fn line_points(x0: i32, y0: i32, x1: i32, y1: i32) -> Vec<Point> {
    let dx = (x1 - x0).abs();
    let dy = -(y1 - y0).abs();
    let sx = if x0 < x1 { 1 } else { -1 };
    let sy = if y0 < y1 { 1 } else { -1 };
    let mut error = dx + dy;
    let (mut x, mut y) = (x0, y0);
    let mut points = Vec::new();
    loop {
        points.push(Point::new(x, y));
        if x == x1 && y == y1 { break; }
        let twice = 2 * error;
        if twice >= dy { error += dy; x += sx; }
        if twice <= dx { error += dx; y += sy; }
    }
    points
}

fn rectangle_points(
    image: &Image, left: i32, top: i32,
    width: i32, height: i32, fill: bool,
) -> Vec<Point> {
    let right = left + width - 1;
    let bottom = top + height - 1;
    let first_x = left.max(0);
    let last_x = right.min(image.width - 1);
    let first_y = top.max(0);
    let last_y = bottom.min(image.height - 1);
    let mut points = Vec::new();
    if first_x <= last_x && first_y <= last_y {
        for y in first_y..=last_y {
            for x in first_x..=last_x {
                if fill || x == left || x == right || y == top || y == bottom {
                    points.push(Point::new(x, y));
                }
            }
        }
    }
    points
}

fn circle_points(cx: i32, cy: i32, radius: i32) -> Vec<Point> {
    let (mut a, mut b, mut error) = (radius, 0, 1 - radius);
    let mut points = Vec::new();
    while a >= b {
        points.extend_from_slice(&[
            Point::new(cx + a, cy + b), Point::new(cx + b, cy + a),
            Point::new(cx - b, cy + a), Point::new(cx - a, cy + b),
            Point::new(cx - a, cy - b), Point::new(cx - b, cy - a),
            Point::new(cx + b, cy - a), Point::new(cx + a, cy - b),
        ]);
        b += 1;
        if error < 0 { error += 2 * b + 1; }
        else { a -= 1; error += 2 * (b - a) + 1; }
    }
    points
}

fn disc_points(image: &Image, outline: &[Point]) -> Vec<Point> {
    let mut rows = BTreeMap::<i32, (i32, i32)>::new();
    for point in outline {
        let bounds = rows.entry(point.y).or_insert((point.x, point.x));
        bounds.0 = bounds.0.min(point.x);
        bounds.1 = bounds.1.max(point.x);
    }
    let mut points = Vec::new();
    for (y, (left, right)) in rows {
        if y < 0 || y >= image.height { continue; }
        let start = left.max(0);
        let end = right.min(image.width - 1);
        if start <= end {
            for x in start..=end { points.push(Point::new(x, y)); }
        }
    }
    points
}

fn flood_points(image: &Image, x: i32, y: i32) -> Vec<Point> {
    let target = image.at(x, y);
    let mut stack = vec![Point::new(x, y)];
    let mut seen = HashSet::from([(y * image.width + x) as usize]);
    let mut points = Vec::new();
    while let Some(p) = stack.pop() {
        points.push(p);
        for d in FOUR {
            let (nx, ny) = (p.x + d.x, p.y + d.y);
            if !image.contains(nx, ny) || image.at(nx, ny) != target { continue; }
            if seen.insert((ny * image.width + nx) as usize) {
                stack.push(Point::new(nx, ny));
            }
        }
    }
    points
}

fn equalized(image: &Image) -> Image {
    let mut counts = vec![0; (image.maxval + 1) as usize];
    for &pixel in &image.pixels { counts[pixel as usize] += 1; }
    let mut running = 0;
    let cdf: Vec<i32> = counts.into_iter().map(|v| { running += v; running }).collect();
    let first = cdf[*image.pixels.iter().min().unwrap() as usize];
    let size = image.pixels.len() as i32;
    if first == size { return image.clone(); }
    let span = size - first;
    image.map(|pixel| (2 * (cdf[pixel as usize] - first) * image.maxval + span) / (2 * span))
}

fn components(image: &Image, threshold: i32) -> Vec<Vec<Point>> {
    let mut visited = vec![false; image.pixels.len()];
    let mut groups = Vec::new();
    for start in 0..image.pixels.len() {
        if visited[start] || image.pixels[start] < threshold { continue; }
        visited[start] = true;
        let mut stack = vec![Point::new(start as i32 % image.width, start as i32 / image.width)];
        let mut group = Vec::new();
        while let Some(p) = stack.pop() {
            group.push(p);
            for d in EIGHT {
                let (nx, ny) = (p.x + d.x, p.y + d.y);
                if !image.contains(nx, ny) { continue; }
                let index = (ny * image.width + nx) as usize;
                if !visited[index] && image.pixels[index] >= threshold {
                    visited[index] = true;
                    stack.push(Point::new(nx, ny));
                }
            }
        }
        groups.push(group);
    }
    groups
}

fn component_text(image: &Image, threshold: i32, group: &[Point]) -> String {
    let mut left = group[0].x;
    let mut right = group[0].x;
    let mut top = group[0].y;
    let mut bottom = group[0].y;
    let (mut sum_x, mut sum_y, mut perimeter) = (0, 0, 0);
    for p in group {
        left = left.min(p.x);
        right = right.max(p.x);
        top = top.min(p.y);
        bottom = bottom.max(p.y);
        sum_x += p.x;
        sum_y += p.y;
        if FOUR.iter().any(|d| {
            !image.contains(p.x + d.x, p.y + d.y) ||
            image.at(p.x + d.x, p.y + d.y) < threshold
        }) { perimeter += 1; }
    }
    let area = group.len() as i32;
    format!("area {area} perimeter {perimeter} box {left} {top} {right} {bottom} \
             center {} {}", sum_x / area, sum_y / area)
}

fn distance_map(image: &Image, threshold: i32) -> Image {
    if image.pixels.iter().all(|&p| p >= threshold) {
        return image.with_pixels(vec![image.maxval; image.pixels.len()]);
    }
    let (w, h) = (image.width as usize, image.height as usize);
    let far = (w + h) as i32;
    let mut distances: Vec<i32> = image.pixels.iter()
        .map(|&p| if p < threshold { 0 } else { far }).collect();
    for y in 0..h {
        for x in 0..w {
            let i = y * w + x;
            if x > 0 { distances[i] = distances[i].min(distances[i - 1] + 1); }
            if y > 0 { distances[i] = distances[i].min(distances[i - w] + 1); }
        }
    }
    for y in (0..h).rev() {
        for x in (0..w).rev() {
            let i = y * w + x;
            if x + 1 < w { distances[i] = distances[i].min(distances[i + 1] + 1); }
            if y + 1 < h { distances[i] = distances[i].min(distances[i + w] + 1); }
        }
    }
    image.with_pixels(distances.into_iter().map(|v| v.min(image.maxval)).collect())
}

fn statistics(values: &[i32], maxval: i32) -> String {
    let mut sorted = values.to_vec();
    sorted.sort_unstable();
    let mut counts = vec![0; (maxval + 1) as usize];
    let mut total: i64 = 0;
    for &value in values {
        counts[value as usize] += 1;
        total += value as i64;
    }
    let mut mode = 0usize;
    for i in 1..counts.len() {
        if counts[i] > counts[mode] { mode = i; }
    }
    format!("min {} max {} mean {} median {} mode {}",
            sorted[0], sorted[sorted.len() - 1], total / values.len() as i64,
            sorted[(sorted.len() - 1) / 2], mode)
}

fn dithered(image: &Image) -> Image {
    let mut errors = image.pixels.clone();
    let mut pixels = vec![0; errors.len()];
    let offsets = [(1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)];
    for y in 0..image.height {
        for x in 0..image.width {
            let i = (y * image.width + x) as usize;
            let old = errors[i];
            let value = if 2 * old >= image.maxval { image.maxval } else { 0 };
            pixels[i] = value;
            let error = old - value;
            for &(dx, dy, weight) in &offsets {
                let nx = x + dx;
                let ny = y + dy;
                if image.contains(nx, ny) {
                    errors[(ny * image.width + nx) as usize] += floor_divide(error * weight, 16);
                }
            }
        }
    }
    image.with_pixels(pixels)
}

fn pgm_header(words: &[&str], index: usize, maximum: i32, reason: &str) -> Outcome<i32> {
    check(index < words.len(), "truncated header")?;
    check(!words[index].is_empty() && words[index].bytes().all(|b| b.is_ascii_digit()),
          "bad number")?;
    let value: i32 = words[index].parse().unwrap();
    check(value >= 1 && value <= maximum, reason)?;
    Ok(value)
}

fn parse_pgm(lines: &[&str]) -> Outcome<Image> {
    let words: Vec<&str> = lines.iter()
        .flat_map(|line| line.split('#').next().unwrap_or("").split_whitespace())
        .collect();
    check(words.first() == Some(&"P2"), "bad magic")?;
    let width = pgm_header(&words, 1, 64, "bad size")?;
    let height = pgm_header(&words, 2, 64, "bad size")?;
    let maxval = pgm_header(&words, 3, 255, "bad maxval")?;
    let count = words.len().saturating_sub(4);
    let required = (width * height) as usize;
    let mut pixels = Vec::with_capacity(required);
    for i in 0..required {
        let x = i as i32 % width;
        let y = i as i32 / width;
        check(i < count, &format!("too few pixels ({count} of {required})"))?;
        let word = words[i + 4];
        check(!word.is_empty() && word.bytes().all(|b| b.is_ascii_digit()),
              &format!("bad pixel at {x},{y}"))?;
        let value: i32 = word.parse().unwrap();
        check(value <= maxval, &format!("pixel out of range at {x},{y}"))?;
        pixels.push(value);
    }
    check(count <= required, &format!("too many pixels ({count} of {required})"))?;
    Ok(Image { width, height, maxval, pixels })
}

fn command_pattern(name: &str) -> Option<&'static str> {
    match name {
        "NEW" => Some("iiii"),
        "OUTPUT" | "INVERT" | "FLIPH" | "FLIPV" | "BLUR" | "GAUSS" |
        "SHARPEN" | "SOBEL" | "MEDIAN" | "ERODE" | "DILATE" | "OPEN" |
        "CLOSE" | "GRADIENT" | "HISTOGRAM" | "EQUALIZE" | "STATS" |
        "DITHER" | "ASCIIART" | "SLOTS" | "INFO" | "UNDO" | "REDO" =>
            Some(""),
        "BRIGHTNESS" | "THRESHOLD" | "POSTERIZE" | "MAXVAL" | "ROTATE" |
        "LABEL" | "DISTANCE" => Some("i"),
        "CONTRAST" | "LEVELS" | "PAD" | "SCALE" | "TILE" => Some("ii"),
        "SHIFT" | "FLOOD" => Some("iii"),
        "CROP" | "REGION" | "CIRCLE" => Some("iiii"),
        "RECT" | "LINE" => Some("iiiii"),
        "CONVOLVE" => Some("iiiiiiiiii"),
        "STORE" | "RECALL" | "DROP" => Some("n"),
        "BLEND" => Some("nii"),
        "DIFF" => Some("n"),
        "PASTE" => Some("nii"),
        _ => None,
    }
}

fn integer_word(word: &str) -> bool {
    if word == "0" { return true; }
    let digits = word.strip_prefix('-').unwrap_or(word);
    !digits.is_empty() && digits.len() <= 7 && !digits.starts_with('0') &&
        digits.bytes().all(|b| b.is_ascii_digit())
}

fn name_word(word: &str) -> bool {
    !word.is_empty() && word.len() <= 8 &&
        word.bytes().all(|b| b.is_ascii_lowercase())
}

struct Command {
    name: String,
    args: Vec<i32>,
    slot: String,
    fill: bool,
}

fn parse_command(words: &[&str]) -> Outcome<Command> {
    let name = words[0];
    let pattern = command_pattern(name)
        .ok_or_else(|| format!("unknown command {name}"))?;
    let mut given = words[1..].to_vec();
    let fill = (name == "RECT" || name == "CIRCLE") &&
        given.len() == pattern.len() + 1 && given.last() == Some(&"FILL");
    if fill { given.pop(); }
    check(given.len() == pattern.len(), "bad arguments")?;
    let mut args = Vec::new();
    let mut slot = String::new();
    for (kind, word) in pattern.bytes().zip(given) {
        if kind == b'i' {
            check(integer_word(word), "bad arguments")?;
            args.push(word.parse().unwrap());
        } else {
            check(name_word(word), "bad arguments")?;
            slot = word.to_string();
        }
    }
    Ok(Command { name: name.to_string(), args, slot, fill })
}

struct Editor {
    current: Option<Image>,
    undo: Vec<Image>,
    redo: Vec<Image>,
    slots: BTreeMap<String, Image>,
    output: Vec<String>,
}

impl Editor {
    fn new() -> Self {
        Self {
            current: None,
            undo: Vec::new(),
            redo: Vec::new(),
            slots: BTreeMap::new(),
            output: Vec::new(),
        }
    }

    fn emit(&mut self, line: String) { self.output.push(line); }

    fn replace(&mut self, image: Image, label: &str) {
        self.current = Some(image);
        self.undo.clear();
        self.redo.clear();
        self.emit(format!("{label} {}", self.current.as_ref().unwrap().summary()));
    }

    fn commit(&mut self, image: Image, painted: Option<usize>) {
        self.undo.push(self.current.replace(image).unwrap());
        self.redo.clear();
        let summary = self.current.as_ref().unwrap().summary();
        let suffix = painted.map(|count| format!(" painted {count}")).unwrap_or_default();
        self.emit(format!("ok {summary}{suffix}"));
    }

    fn paint(&mut self, image: &Image, points: Vec<Point>, value: i32) {
        let mut touched = HashSet::new();
        for point in points {
            if image.contains(point.x, point.y) {
                touched.insert((point.y * image.width + point.x) as usize);
            }
        }
        let mut pixels = image.pixels.clone();
        for &index in &touched { pixels[index] = value; }
        self.commit(image.with_pixels(pixels), Some(touched.len()));
    }

    fn crop_area(&self, image: &Image, args: &[i32]) -> Outcome<()> {
        check(args[0] >= 0 && args[1] >= 0 && args[2] >= 1 && args[3] >= 1,
              "bad value")?;
        check(args[0] + args[2] <= image.width && args[1] + args[3] <= image.height,
              "bad value")
    }

    fn matching_slot(&self, image: &Image, slot: &str) -> Outcome<&Image> {
        let other = &self.slots[slot];
        check(other.width == image.width && other.height == image.height, "size mismatch")?;
        check(other.maxval == image.maxval, "maxval mismatch")?;
        Ok(other)
    }

    fn execute(&mut self, words: &[&str]) {
        let result = (|| {
            let command = parse_command(words)?;
            let name = command.name.as_str();
            let imageless = matches!(
                name, "NEW" | "RECALL" | "DROP" | "SLOTS" | "INFO" | "UNDO" | "REDO"
            );
            check(imageless || self.current.is_some(), "no image")?;
            if matches!(name, "RECALL" | "DROP" | "BLEND" | "DIFF" | "PASTE") {
                check(self.slots.contains_key(&command.slot),
                      &format!("no slot {}", command.slot))?;
            }
            self.run(&command)
        })();
        if let Err(reason) = result { self.emit(format!("error: {reason}")); }
    }

    fn load(&mut self, lines: &[&str]) {
        match parse_pgm(lines) {
            Ok(image) => self.replace(image, "loaded"),
            Err(reason) => self.emit(format!("error: load: {reason}")),
        }
    }

    fn run(&mut self, command: &Command) -> Outcome<()> {
        let name = command.name.as_str();
        let a = &command.args;
        let slot = command.slot.as_str();
        let fill = command.fill;

        match name {
            "NEW" => {
                check((1..=64).contains(&a[0]) && (1..=64).contains(&a[1]), "bad value")?;
                check((1..=255).contains(&a[2]) && a[3] >= 0 && a[3] <= a[2],
                      "bad value")?;
                self.replace(Image {
                    width: a[0], height: a[1], maxval: a[2],
                    pixels: vec![a[3]; (a[0] * a[1]) as usize],
                }, "created");
                return Ok(());
            }
            "RECALL" => {
                self.replace(self.slots[slot].clone(), &format!("recalled {slot}"));
                return Ok(());
            }
            "DROP" => {
                self.slots.remove(slot);
                self.emit(format!("dropped {slot}"));
                return Ok(());
            }
            "SLOTS" => {
                if self.slots.is_empty() { self.emit("no slots".to_string()); }
                let lines: Vec<String> = self.slots.iter()
                    .map(|(name, image)| format!("{name} {}", image.summary())).collect();
                self.output.extend(lines);
                return Ok(());
            }
            "INFO" => {
                let summary = self.current.as_ref()
                    .map(Image::summary).unwrap_or_else(|| "none".to_string());
                self.emit(format!(
                    "image {summary} undo {} redo {} slots {}",
                    self.undo.len(), self.redo.len(), self.slots.len()
                ));
                return Ok(());
            }
            "UNDO" => {
                check(!self.undo.is_empty(), "nothing to undo")?;
                self.redo.push(self.current.take().unwrap());
                self.current = self.undo.pop();
                self.emit(format!("undo {}", self.current.as_ref().unwrap().summary()));
                return Ok(());
            }
            "REDO" => {
                check(!self.redo.is_empty(), "nothing to redo")?;
                self.undo.push(self.current.take().unwrap());
                self.current = self.redo.pop();
                self.emit(format!("redo {}", self.current.as_ref().unwrap().summary()));
                return Ok(());
            }
            _ => (),
        }

        let image = self.current.as_ref().unwrap().clone();
        let (w, h, m) = (image.width, image.height, image.maxval);

        match name {
            "OUTPUT" => {
                self.emit("P2".to_string());
                self.emit(format!("{w} {h}"));
                self.emit(m.to_string());
                for y in 0..h {
                    let row = (0..w).map(|x| image.at(x, y).to_string())
                        .collect::<Vec<_>>().join(" ");
                    self.emit(row);
                }
            }
            "INVERT" => self.commit(image.map(|p| m - p), None),
            "BRIGHTNESS" => {
                check((-255..=255).contains(&a[0]), "bad value")?;
                self.commit(image.map(|p| image.clamped(p + a[0])), None);
            }
            "CONTRAST" => {
                check((0..=100).contains(&a[0]) && (1..=100).contains(&a[1]), "bad value")?;
                let center = (m + 1) / 2;
                self.commit(image.map(|p| {
                    image.clamped(center + floor_divide((p - center) * a[0], a[1]))
                }), None);
            }
            "THRESHOLD" => {
                check((0..=m).contains(&a[0]), "bad value")?;
                self.commit(image.map(|p| if p >= a[0] { m } else { 0 }), None);
            }
            "LEVELS" => {
                check(a[0] >= 0 && a[0] < a[1] && a[1] <= m, "bad value")?;
                self.commit(image.map(|p| {
                    image.clamped(floor_divide((p - a[0]) * m, a[1] - a[0]))
                }), None);
            }
            "POSTERIZE" => {
                check((2..=m + 1).contains(&a[0]), "bad value")?;
                self.commit(image.map(|p| (p * a[0] / (m + 1)) * m / (a[0] - 1)), None);
            }
            "MAXVAL" => {
                check((1..=255).contains(&a[0]), "bad value")?;
                self.commit(Image {
                    width: w, height: h, maxval: a[0],
                    pixels: image.pixels.iter()
                        .map(|&p| (2 * p * a[0] + m) / (2 * m)).collect(),
                }, None);
            }
            "FLIPH" => self.commit(
                transformed(&image, w, h, |x, y| image.at(w - 1 - x, y)), None
            ),
            "FLIPV" => self.commit(
                transformed(&image, w, h, |x, y| image.at(x, h - 1 - y)), None
            ),
            "ROTATE" => {
                check([90, 180, 270].contains(&a[0]), "bad value")?;
                let result = match a[0] {
                    90 => transformed(&image, h, w, |x, y| image.at(y, h - 1 - x)),
                    180 => transformed(&image, w, h, |x, y| image.at(w - 1 - x, h - 1 - y)),
                    _ => transformed(&image, h, w, |x, y| image.at(w - 1 - y, x)),
                };
                self.commit(result, None);
            }
            "CROP" => {
                self.crop_area(&image, a)?;
                self.commit(cropped(&image, a[0], a[1], a[2], a[3]), None);
            }
            "PAD" => {
                check(a[0] >= 1 && a[1] >= 0 && a[1] <= m, "bad value")?;
                check(w + 2 * a[0] <= 64 && h + 2 * a[0] <= 64, "too large")?;
                self.commit(translated(&image, w + 2 * a[0], h + 2 * a[0],
                                       a[0], a[0], a[1]), None);
            }
            "SCALE" => {
                check((1..=16).contains(&a[0]) && (1..=16).contains(&a[1]), "bad value")?;
                let nw = w * a[0] / a[1];
                let nh = h * a[0] / a[1];
                check(nw >= 1 && nh >= 1, "too small")?;
                check(nw <= 64 && nh <= 64, "too large")?;
                self.commit(transformed(&image, nw, nh, |x, y| {
                    image.at((2 * x + 1) * a[1] / (2 * a[0]),
                             (2 * y + 1) * a[1] / (2 * a[0]))
                }), None);
            }
            "SHIFT" => {
                check(within_limits(&a[..2]) && a[2] >= 0 && a[2] <= m, "bad value")?;
                self.commit(translated(&image, w, h, a[0], a[1], a[2]), None);
            }
            "TILE" => {
                check(a[0] >= 1 && a[1] >= 1, "bad value")?;
                check(w * a[0] <= 64 && h * a[1] <= 64, "too large")?;
                self.commit(transformed(&image, w * a[0], h * a[1], |x, y| {
                    image.at(x % w, y % h)
                }), None);
            }
            "BLUR" | "GAUSS" | "SHARPEN" => {
                let (kernel, divisor) = match name {
                    "BLUR" => ([1, 1, 1, 1, 1, 1, 1, 1, 1], 9),
                    "GAUSS" => ([1, 2, 1, 2, 4, 2, 1, 2, 1], 16),
                    _ => ([0, -1, 0, -1, 5, -1, 0, -1, 0], 1),
                };
                self.commit(convolved(&image, &kernel, divisor), None);
            }
            "CONVOLVE" => {
                check(a[..9].iter().all(|&k| (-16..=16).contains(&k)) &&
                      (1..=256).contains(&a[9]), "bad value")?;
                let kernel: [i32; 9] = a[..9].try_into().unwrap();
                self.commit(convolved(&image, &kernel, a[9]), None);
            }
            "SOBEL" => self.commit(sobel(&image), None),
            "MEDIAN" => self.commit(rank_filtered(&image, 4), None),
            "ERODE" => self.commit(rank_filtered(&image, 0), None),
            "DILATE" => self.commit(rank_filtered(&image, 8), None),
            "OPEN" => self.commit(rank_filtered(&rank_filtered(&image, 0), 8), None),
            "CLOSE" => self.commit(rank_filtered(&rank_filtered(&image, 8), 0), None),
            "GRADIENT" => {
                let high = rank_filtered(&image, 8);
                let low = rank_filtered(&image, 0);
                let result = image.pixels.iter().enumerate()
                    .map(|(i, _)| high.pixels[i] - low.pixels[i]).collect();
                self.commit(image.with_pixels(result), None);
            }
            "LINE" => {
                check(within_limits(&a[..4]) && (0..=m).contains(&a[4]), "bad value")?;
                self.paint(&image, line_points(a[0], a[1], a[2], a[3]), a[4]);
            }
            "RECT" => {
                check(within_limits(&a[..2]) && (1..=1000).contains(&a[2]) &&
                      (1..=1000).contains(&a[3]) && (0..=m).contains(&a[4]),
                      "bad value")?;
                self.paint(&image, rectangle_points(&image, a[0], a[1], a[2], a[3], fill), a[4]);
            }
            "CIRCLE" => {
                check(within_limits(&a[..2]) && (0..=1000).contains(&a[2]) &&
                      (0..=m).contains(&a[3]), "bad value")?;
                let outline = circle_points(a[0], a[1], a[2]);
                let points = if fill { disc_points(&image, &outline) } else { outline };
                self.paint(&image, points, a[3]);
            }
            "FLOOD" => {
                check(image.contains(a[0], a[1]) && (0..=m).contains(&a[2]), "bad value")?;
                self.paint(&image, flood_points(&image, a[0], a[1]), a[2]);
            }
            "HISTOGRAM" => {
                let mut lows = [None; 16];
                let mut highs = [0; 16];
                let mut counts = [0; 16];
                for value in 0..=m {
                    let bin = (value * 16 / (m + 1)) as usize;
                    if lows[bin].is_none() { lows[bin] = Some(value); }
                    highs[bin] = value;
                }
                for &p in &image.pixels { counts[(p * 16 / (m + 1)) as usize] += 1; }
                let top = *counts.iter().max().unwrap();
                for bin in 0..16 {
                    if let Some(low) = lows[bin] {
                        self.emit(format!("{low:>3}-{hi:>3} {count:>4} |{bar}",
                            hi = highs[bin], count = counts[bin],
                            bar = "#".repeat((counts[bin] * 32 / top) as usize)));
                    }
                }
            }
            "EQUALIZE" => self.commit(equalized(&image), None),
            "LABEL" => {
                check((0..=m).contains(&a[0]), "bad value")?;
                let groups = components(&image, a[0]);
                self.emit(format!("labels {}", groups.len()));
                for (index, group) in groups.iter().enumerate() {
                    self.emit(format!("label {} {}", index + 1,
                                      component_text(&image, a[0], group)));
                }
            }
            "DISTANCE" => {
                check((0..=m).contains(&a[0]), "bad value")?;
                self.commit(distance_map(&image, a[0]), None);
            }
            "STATS" => self.emit(statistics(&image.pixels, m)),
            "REGION" => {
                self.crop_area(&image, a)?;
                self.emit(statistics(&cropped(&image, a[0], a[1], a[2], a[3]).pixels, m));
            }
            "DITHER" => self.commit(dithered(&image), None),
            "ASCIIART" => {
                let shades = b"@#*+=~-:,.";
                for y in 0..h {
                    let row: String = (0..w).map(|x| {
                        shades[(image.at(x, y) * 10 / (m + 1)) as usize] as char
                    }).collect();
                    self.emit(row);
                }
            }
            "STORE" => {
                self.slots.insert(slot.to_string(), image.clone());
                self.emit(format!("stored {slot} {}", image.summary()));
            }
            "BLEND" => {
                check(a[0] >= 0 && a[0] <= a[1] && (1..=100).contains(&a[1]),
                      "bad value")?;
                let saved = self.matching_slot(&image, slot)?;
                let pixels = image.pixels.iter().enumerate().map(|(i, &p)| {
                    (p * (a[1] - a[0]) + saved.pixels[i] * a[0]) / a[1]
                }).collect();
                self.commit(image.with_pixels(pixels), None);
            }
            "DIFF" => {
                let saved = self.matching_slot(&image, slot)?;
                let pixels = image.pixels.iter().enumerate().map(|(i, &p)| {
                    (p - saved.pixels[i]).abs()
                }).collect();
                self.commit(image.with_pixels(pixels), None);
            }
            "PASTE" => {
                check(within_limits(a), "bad value")?;
                let saved = &self.slots[slot];
                check(saved.maxval == m, "maxval mismatch")?;
                let mut pixels = image.pixels.clone();
                let mut painted = 0;
                for y in 0..saved.height {
                    for x in 0..saved.width {
                        if image.contains(a[0] + x, a[1] + y) {
                            pixels[((a[1] + y) * w + a[0] + x) as usize] = saved.at(x, y);
                            painted += 1;
                        }
                    }
                }
                self.commit(image.with_pixels(pixels), Some(painted));
            }
            _ => unreachable!("all commands are dispatched"),
        }
        Ok(())
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let lines: Vec<&str> = input.lines().collect();
    let command_count: usize = lines[0].parse().unwrap();
    let mut position = 1;
    let mut editor = Editor::new();
    for _ in 0..command_count {
        let words: Vec<&str> = lines[position].split_whitespace().collect();
        position += 1;
        if words[0] == "LOAD" {
            let count: usize = words[1].parse().unwrap();
            editor.load(&lines[position..position + count]);
            position += count;
        } else {
            editor.execute(&words);
        }
    }
    if !editor.output.is_empty() {
        println!("{}", editor.output.join("\n"));
    }
}
