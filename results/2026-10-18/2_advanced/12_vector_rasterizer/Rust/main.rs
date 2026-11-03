mod canvas;
mod primitives;
mod clipping;
mod fill;
mod ppm_writer;

use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};
use canvas::{Color, Image, Layer, Rgb, round_ratio};
use clipping::Rect;
use primitives::{Pixels, Point};

const PEN_COMMANDS: &[&str] = &["LINE", "RECT", "CIRCLE", "ELLIPSE", "POLYLINE", "POLYGON", "PATH"];
const BRUSH_COMMANDS: &[&str] = &["FILLRECT", "FILLCIRCLE", "FILLELLIPSE", "FILLPOLYGON", "FILLPATH", "FLOOD", "TEXT"];
const STATE_COMMANDS: &[&str] = &["TRANSLATE", "SCALE", "ROTATE", "SAVE", "RESTORE", "CLIP", "NOCLIP", "USE"];
const ERROR_NAMES: &[&str] = &["unknown_command", "bad_arguments", "unknown_style", "unknown_symbol", "unknown_glyph", "bad_value", "stack_empty"];

struct Pen { width: i64, color: String, on: i64, off: i64 }
struct Brush { colors: Vec<String>, axis: Option<u8>, rule: String }
#[derive(Default)]
struct Styles { colors: BTreeMap<String, Color>, pens: BTreeMap<String, Pen>, brushes: BTreeMap<String, Brush> }
struct Font { width: i64, height: i64, glyphs: BTreeMap<u8, Vec<Point>> }
#[derive(Clone)]
struct Command { line: usize, keyword: String, arguments: Vec<String> }
enum Item { Command(Command), Repeat { count: i64, dx: i64, dy: i64, body: Vec<Item> } }
struct Block { name: String, opacity: i64, mode: String, end_line: usize, body: Vec<Item> }
#[derive(Default)]
struct Scene { width: usize, height: usize, background: String, layers: Vec<Block>, symbols: BTreeMap<String, Block> }
struct PathCommand { letter: u8, values: Vec<i64> }
struct Subpath { points: Vec<Point>, closed: bool }
struct Execution { sequence: usize, layer: usize, command: Command, kind: &'static str, error: &'static str, pixels: usize, bbox: Option<Rect> }

fn read_lines(name: &str) -> io::Result<Vec<String>> { Ok(fs::read_to_string(format!("input/{name}"))?.lines().map(str::to_owned).collect()) }
fn is_integer(word: &str) -> bool { let digits = word.strip_prefix('-').unwrap_or(word); !digits.is_empty() && digits.bytes().all(|c| c.is_ascii_digit()) }
fn all_integers(words: &[String]) -> bool { words.iter().all(|word| is_integer(word)) }
fn integers(words: &[String]) -> Vec<i64> { words.iter().map(|word| word.parse().unwrap()).collect() }
fn intersect(a: Rect, b: Rect) -> Rect { [a[0].max(b[0]), a[1].max(b[1]), a[2].min(b[2]), a[3].min(b[3])] }
fn is_empty(r: Rect) -> bool { r[0] > r[2] || r[1] > r[3] }
fn contains(r: Rect, (x, y): Point) -> bool { r[0] <= x && x <= r[2] && r[1] <= y && y <= r[3] }
fn rect_pixels([x0, y0, x1, y1]: Rect) -> Pixels { (y0..=y1).flat_map(|y| (x0..=x1).map(move |x| (x, y))).collect() }
fn bounding_box(pixels: &Pixels) -> Option<Rect> {
    let &(x, y) = pixels.iter().next()?;
    Some(pixels.iter().fold([x, y, x, y], |b, &(x, y)| [b[0].min(x), b[1].min(y), b[2].max(x), b[3].max(y)]))
}
fn values_text(values: &[i64]) -> String { values.iter().map(i64::to_string).collect::<Vec<_>>().join(" ") }
fn box_text(bbox: Option<Rect>) -> String { bbox.map_or_else(|| "none".into(), |b| values_text(&b)) }
fn segments(points: &[Point], closed: bool) -> Vec<(Point, Point)> {
    let mut lines: Vec<_> = points.windows(2).map(|pair| (pair[0], pair[1])).collect();
    if closed { lines.push((*points.last().unwrap(), points[0])); } lines
}
fn read_styles(lines: Vec<String>) -> Styles {
    let mut styles = Styles::default();
    for line in lines {
        if line.is_empty() || line.starts_with('#') { continue; }
        let words: Vec<_> = line.split(' ').map(str::to_owned).collect();
        let name = words[1].clone();
        let v = &words[2..];
        match words[0].as_str() {
            "color" => { styles.colors.insert(name, integers(v).try_into().unwrap()); }
            "pen" => { styles.pens.insert(name, Pen { width: v[0].parse().unwrap(), color: v[1].clone(), on: v[2].parse().unwrap(), off: v[3].parse().unwrap() }); }
            "brush" => { styles.brushes.insert(name, Brush { colors: vec![v[0].clone()], axis: None, rule: v[1].clone() }); }
            _ => { styles.brushes.insert(name, Brush { colors: v[..2].to_vec(), axis: Some(v[2].as_bytes()[0]), rule: v[3].clone() }); }
        }
    }
    styles
}
fn read_font(lines: Vec<String>) -> Font {
    let header: Vec<_> = lines[0].split(' ').collect();
    let mut font = Font { width: header[1].parse().unwrap(), height: header[2].parse().unwrap(), glyphs: BTreeMap::new() };
    let mut index = 1;
    while index < lines.len() {
        let character = lines[index].as_bytes()[6];
        let mut dots = Vec::new();
        for row in 0..font.height { for column in 0..font.width { if lines[index + 1 + row as usize].as_bytes()[column as usize] == b'#' { dots.push((column, row)); } } }
        font.glyphs.insert(character, dots); index += 1 + font.height as usize;
    }
    font
}
struct SceneParser { instructions: Vec<(usize, Vec<String>)>, index: usize }
impl SceneParser {
    fn new(lines: Vec<String>) -> Self {
        let instructions = lines.iter().enumerate().filter_map(|(i, line)| {
            let words: Vec<_> = line.split_whitespace().map(str::to_owned).collect();
            if words.is_empty() || words[0].starts_with('#') { None } else { Some((i + 1, words)) }
        }).collect();
        Self { instructions, index: 0 }
    }
    fn body(&mut self, end: &str) -> (Vec<Item>, usize) {
        let mut body = Vec::new();
        loop {
            let (line, words) = self.instructions[self.index].clone(); self.index += 1;
            if words[0] == end { return (body, line); }
            if words[0] == "REPEAT" {
                let (nested, _) = self.body("ENDREPEAT");
                body.push(Item::Repeat { count: words[1].parse().unwrap(), dx: words[2].parse().unwrap(), dy: words[3].parse().unwrap(), body: nested });
            } else { body.push(Item::Command(Command { line, keyword: words[0].clone(), arguments: words[1..].to_vec() })); }
        }
    }
    fn parse(mut self) -> Scene {
        let mut scene = Scene::default();
        while self.index < self.instructions.len() {
            let (_, words) = self.instructions[self.index].clone(); self.index += 1;
            if words[0] == "CANVAS" { scene.width = words[1].parse().unwrap(); scene.height = words[2].parse().unwrap(); scene.background = words[3].clone(); continue; }
            let (body, end_line) = self.body("END");
            let layer = words[0] == "LAYER";
            let block = Block { name: words[1].clone(), opacity: if layer { words[2].parse().unwrap() } else { 255 }, mode: if layer { words[3].clone() } else { "normal".into() }, end_line, body };
            if layer { scene.layers.push(block); } else { scene.symbols.insert(block.name.clone(), block); }
        }
        scene
    }
}
fn path_arity(letter: &str) -> Option<usize> {
    match letter { "M" | "m" | "L" | "l" => Some(2), "H" | "h" | "V" | "v" => Some(1), "Q" | "q" => Some(4), "C" | "c" => Some(6), "Z" | "z" => Some(0), _ => None }
}
fn parse_path(words: &[String]) -> Option<Vec<PathCommand>> {
    let mut commands: Vec<PathCommand> = Vec::new();
    let mut index = 0;
    while index < words.len() {
        let count = path_arity(&words[index])?;
        if index + 1 + count > words.len() || !all_integers(&words[index + 1..index + 1 + count]) { return None; }
        let letter = words[index].as_bytes()[0];
        if (commands.is_empty() || matches!(commands.last().unwrap().letter, b'Z' | b'z')) && !matches!(letter, b'M' | b'm') { return None; }
        commands.push(PathCommand { letter, values: integers(&words[index + 1..index + 1 + count]) }); index += 1 + count;
    }
    if commands.is_empty() { None } else { Some(commands) }
}
fn valid_form(keyword: &str, a: &[String]) -> bool {
    let fixed = match keyword {
        "LINE" | "RECT" | "FILLRECT" | "ELLIPSE" | "FILLELLIPSE" => Some((5, 1)),
        "CIRCLE" | "FILLCIRCLE" => Some((4, 1)), "FLOOD" | "USE" => Some((3, 1)),
        "ERASE" | "CLIP" => Some((4, 0)), "TRANSLATE" | "SCALE" => Some((2, 0)),
        "ROTATE" => Some((1, 0)), "SAVE" | "RESTORE" | "NOCLIP" => Some((0, 0)), _ => None,
    };
    if let Some((count, first)) = fixed { return a.len() == count && all_integers(&a[first..]); }
    if keyword == "TEXT" { return a.len() == 5 && all_integers(&a[1..3]); }
    if ["POLYLINE", "POLYGON", "FILLPOLYGON"].contains(&keyword) { return a.len() >= 2 && all_integers(&a[1..]) && a.len() as i64 == 2 + 2 * a[1].parse::<i64>().unwrap(); }
    a.len() >= 2 && is_integer(&a[1]) && parse_path(&a[2..]).is_some()
}

#[derive(Clone)]
struct DrawingState { matrix: [i64; 6], clip: Rect, stack: Vec<([i64; 6], Rect)> }
impl DrawingState {
    fn new(screen: Rect) -> Self { Self { matrix: [1, 0, 0, 1, 0, 0], clip: screen, stack: Vec::new() } }
    fn transform(&self, (x, y): Point) -> Point { let [a, b, c, d, e, f] = self.matrix; (a * x + b * y + e, c * x + d * y + f) }
    fn device_rect(&self, v: &[i64]) -> Rect {
        let (x0, y0) = self.transform((v[0], v[1])); let (x1, y1) = self.transform((v[2], v[3]));
        [x0.min(x1), y0.min(y1), x0.max(x1), y0.max(y1)]
    }
    fn radii(&self, rx: i64, ry: i64) -> Point { let [a, b, c, d, _, _] = self.matrix; (a.abs() * rx + b.abs() * ry, c.abs() * rx + d.abs() * ry) }
    fn translate(&mut self, dx: i64, dy: i64) { let [a, b, c, d, e, f] = self.matrix; self.matrix = [a, b, c, d, e + a * dx + b * dy, f + c * dx + d * dy]; }
    fn scale(&mut self, sx: i64, sy: i64) { let [a, b, c, d, e, f] = self.matrix; self.matrix = [a * sx, b * sy, c * sx, d * sy, e, f]; }
    fn rotate(&mut self, k: i64) { for _ in 0..k.rem_euclid(4) { let [a, b, c, d, e, f] = self.matrix; self.matrix = [b, -a, d, -c, e, f]; } }
}

struct Renderer<'a> { scene: &'a Scene, styles: &'a Styles, font: &'a Font, screen: Rect, state: DrawingState, layers: Vec<Layer>, executions: Vec<Execution> }
impl<'a> Renderer<'a> {
    fn new(scene: &'a Scene, styles: &'a Styles, font: &'a Font) -> Self {
        let screen = [0, 0, scene.width as i64 - 1, scene.height as i64 - 1];
        Self { scene, styles, font, screen, state: DrawingState::new(screen), layers: Vec::new(), executions: Vec::new() }
    }
    fn run(&mut self) {
        let scene = self.scene;
        for block in &scene.layers {
            self.layers.push(Layer::new(scene.width, scene.height, block.opacity, block.mode.clone())); self.state = DrawingState::new(self.screen); self.execute_body(&block.body);
        }
    }
    fn execute_body(&mut self, body: &[Item]) {
        for item in body {
            match item {
                Item::Repeat { count, dx, dy, body } => {
                    let saved = self.state.clone();
                    for k in 0..*count { self.state = saved.clone(); self.state.translate(k * dx, k * dy); self.execute_body(body); }
                    self.state = saved;
                }
                Item::Command(command) => self.execute_command(command),
            }
        }
    }
    fn execute_command(&mut self, command: &Command) {
        let error = self.check(command);
        let kind = if error.is_some() { "error" } else if STATE_COMMANDS.contains(&command.keyword.as_str()) { "state" } else { "drawing" };
        let index = self.executions.len();
        self.executions.push(Execution { sequence: index + 1, layer: self.layers.len(), command: command.clone(), kind, error: error.unwrap_or(""), pixels: 0, bbox: None });
        if error.is_some() { return; }
        if kind == "state" { self.apply_state(command); }
        else { let pixels = self.draw(command); self.executions[index].pixels = pixels.len(); self.executions[index].bbox = bounding_box(&pixels); }
    }
    fn check(&self, command: &Command) -> Option<&'static str> {
        let k = command.keyword.as_str(); let a = &command.arguments;
        if k != "ERASE" && !PEN_COMMANDS.contains(&k) && !BRUSH_COMMANDS.contains(&k) && !STATE_COMMANDS.contains(&k) { return Some("unknown_command"); }
        if !valid_form(k, a) { return Some("bad_arguments"); }
        if PEN_COMMANDS.contains(&k) && !self.styles.pens.contains_key(&a[0]) || BRUSH_COMMANDS.contains(&k) && !self.styles.brushes.contains_key(&a[0]) { return Some("unknown_style"); }
        if k == "USE" && !self.scene.symbols.get(&a[0]).is_some_and(|s| s.end_line < command.line) { return Some("unknown_symbol"); }
        if k == "TEXT" && a[4].bytes().any(|c| c != b'_' && !self.font.glyphs.contains_key(&c)) { return Some("unknown_glyph"); }
        if k == "RESTORE" && self.state.stack.is_empty() { return Some("stack_empty"); }
        let number = |i: usize| a[i].parse::<i64>().unwrap();
        let valid = match k {
            "CIRCLE" | "FILLCIRCLE" => number(3) >= 1,
            "ELLIPSE" | "FILLELLIPSE" => number(3) >= 1 && number(4) >= 1,
            "POLYLINE" => number(1) >= 2, "POLYGON" | "FILLPOLYGON" => number(1) >= 3,
            "PATH" | "FILLPATH" => (1..=32).contains(&number(1)),
            "FLOOD" => contains(self.state.clip, self.state.transform((number(1), number(2)))),
            "TEXT" => ["left", "center", "right"].contains(&a[3].as_str()),
            "SCALE" => number(0) != 0 && number(1) != 0,
            "CLIP" => !is_empty(intersect(self.state.device_rect(&integers(a)), self.state.clip)), _ => true,
        };
        if valid { None } else { Some("bad_value") }
    }
    fn apply_state(&mut self, command: &Command) {
        let a = &command.arguments;
        match command.keyword.as_str() {
            "TRANSLATE" => self.state.translate(a[0].parse().unwrap(), a[1].parse().unwrap()),
            "SCALE" => self.state.scale(a[0].parse().unwrap(), a[1].parse().unwrap()),
            "ROTATE" => self.state.rotate(a[0].parse().unwrap()),
            "SAVE" => self.state.stack.push((self.state.matrix, self.state.clip)),
            "RESTORE" => { let (matrix, clip) = self.state.stack.pop().unwrap(); self.state.matrix = matrix; self.state.clip = clip; }
            "CLIP" => self.state.clip = intersect(self.state.device_rect(&integers(a)), self.state.clip),
            "NOCLIP" => self.state.clip = self.screen,
            _ => {
                let scene = self.scene; let symbol = &scene.symbols[&a[0]];
                let saved = self.state.clone(); self.state.translate(a[1].parse().unwrap(), a[2].parse().unwrap()); self.execute_body(&symbol.body); self.state = saved;
            }
        }
    }
    fn draw(&mut self, command: &Command) -> Pixels {
        let k = command.keyword.as_str(); let a = &command.arguments;
        if k == "ERASE" {
            let pixels = rect_pixels(intersect(self.state.device_rect(&integers(a)), self.state.clip));
            let layer = self.layers.last_mut().unwrap();
            return pixels.into_iter().filter(|&(x, y)| layer.erase(x, y)).collect();
        }
        if PEN_COMMANDS.contains(&k) {
            let pen = &self.styles.pens[&a[0]];
            let pixels = self.pen_coverage(k, pen, &a[1..]);
            let color = self.styles.colors[&pen.color];
            let layer = self.layers.last_mut().unwrap();
            for &(x, y) in &pixels { layer.paint(x, y, color, command.line); }
            return pixels;
        }
        let brush = &self.styles.brushes[&a[0]];
        let pixels = self.brush_coverage(k, brush, &a[1..]);
        let first = self.styles.colors[&brush.colors[0]];
        let second = brush.colors.get(1).map(|name| self.styles.colors[name]);
        let axis = brush.axis;
        let Some(bbox) = bounding_box(&pixels) else { return pixels; };
        let layer = self.layers.last_mut().unwrap();
        for &(x, y) in &pixels {
            let mut color = first;
            if let Some(axis) = axis {
                let second = second.unwrap();
                let (offset, length) = if axis == b'x' { (x - bbox[0], bbox[2] - bbox[0]) } else { (y - bbox[1], bbox[3] - bbox[1]) };
                if length > 0 { for i in 0..4 { color[i] += round_ratio((second[i] - first[i]) * offset, length); } }
            }
            layer.paint(x, y, color, command.line);
        }
        pixels
    }
    fn vertices(&self, arguments: &[String]) -> Vec<Point> { integers(&arguments[1..]).chunks_exact(2).map(|p| self.state.transform((p[0], p[1]))).collect() }
    fn shape(&self, keyword: &str, v: &[i64]) -> (Point, Pixels) {
        let center = self.state.transform((v[0], v[1]));
        if ["CIRCLE", "FILLCIRCLE"].contains(&keyword) {
            let (rx, ry) = self.state.radii(v[2], v[2]);
            (center, if rx == ry { primitives::circle_points(rx) } else { primitives::ellipse_points(rx, ry) })
        } else { let (rx, ry) = self.state.radii(v[2], v[3]); (center, primitives::ellipse_points(rx, ry)) }
    }
    fn pen_coverage(&self, keyword: &str, pen: &Pen, a: &[String]) -> Pixels {
        if ["CIRCLE", "ELLIPSE"].contains(&keyword) {
            let ((cx, cy), points) = self.shape(keyword, &integers(a));
            return self.expand(points.into_iter().map(|(dx, dy)| (cx + dx, cy + dy)), pen.width);
        }
        let lines = match keyword {
            "LINE" => { let v = integers(a); vec![(self.state.transform((v[0], v[1])), self.state.transform((v[2], v[3])))] }
            "RECT" => { let [x0, y0, x1, y1] = self.state.device_rect(&integers(a)); segments(&[(x0, y0), (x1, y0), (x1, y1), (x0, y1)], true) }
            "POLYLINE" | "POLYGON" => segments(&self.vertices(a), keyword == "POLYGON"),
            _ => self.build_subpaths(parse_path(&a[1..]).unwrap(), a[0].parse().unwrap()).iter().flat_map(|path| segments(&path.points, path.closed)).collect(),
        };
        let mut points = Vec::new();
        for (start, end) in lines { if let Some((p, q)) = clipping::clip_segment(start, end, self.state.clip) { points.extend(primitives::bresenham(p, q)); } }
        self.expand(points.into_iter().enumerate().filter(|(i, _)| pen.off == 0 || (*i as i64) % (pen.on + pen.off) < pen.on).map(|(_, p)| p), pen.width)
    }
    fn expand(&self, points: impl IntoIterator<Item = Point>, width: i64) -> Pixels {
        points.into_iter().flat_map(|p| primitives::expand_square(p, width)).filter(|&p| contains(self.state.clip, p)).collect()
    }
    fn brush_coverage(&self, keyword: &str, brush: &Brush, a: &[String]) -> Pixels {
        match keyword {
            "FILLRECT" => rect_pixels(intersect(self.state.device_rect(&integers(a)), self.state.clip)),
            "FILLCIRCLE" | "FILLELLIPSE" => { let (center, points) = self.shape(keyword, &integers(a)); fill::fill_shape(center, &points, self.state.clip) }
            "FILLPOLYGON" => fill::fill_polygons(&[clipping::clip_polygon(self.vertices(a), self.state.clip)], &brush.rule, self.state.clip),
            "FILLPATH" => {
                let sequences: Vec<_> = self.build_subpaths(parse_path(&a[1..]).unwrap(), a[0].parse().unwrap()).into_iter().map(|path| clipping::clip_polygon(path.points, self.state.clip)).collect();
                fill::fill_polygons(&sequences, &brush.rule, self.state.clip)
            }
            "FLOOD" => fill::flood_fill(self.layers.last().unwrap(), self.state.transform((a[0].parse().unwrap(), a[1].parse().unwrap())), self.state.clip),
            _ => self.text_coverage(a[0].parse().unwrap(), a[1].parse().unwrap(), &a[2], &a[3]),
        }
    }
    fn text_coverage(&self, x: i64, y: i64, alignment: &str, text: &str) -> Pixels {
        let advance = self.font.width + 1;
        let extent = text.len() as i64 * advance - 1;
        let left = match alignment { "left" => x, "center" => x - extent / 2, _ => x - extent + 1 };
        let mut pixels = Pixels::new();
        for (i, character) in text.bytes().enumerate() {
            if character == b'_' { continue; }
            let origin = left + i as i64 * advance;
            for &(column, row) in &self.font.glyphs[&character] {
                let [x0, y0, x1, y1] = self.state.device_rect(&[origin + column, y + row, origin + column + 1, y + row + 1]);
                pixels.extend(rect_pixels(intersect([x0, y0, x1 - 1, y1 - 1], self.state.clip)));
            }
        }
        pixels
    }
    fn build_subpaths(&self, commands: Vec<PathCommand>, count: i64) -> Vec<Subpath> {
        let mut paths: Vec<Subpath> = Vec::new();
        let (mut current, mut start) = ((0, 0), (0, 0));
        for command in commands {
            let kind = command.letter.to_ascii_uppercase();
            if kind == b'Z' { paths.last_mut().unwrap().closed = true; current = start; continue; }
            let (ox, oy) = if command.letter.is_ascii_lowercase() { current } else { (0, 0) };
            let v = command.values;
            let points: Vec<Point> = match kind {
                b'H' => vec![(v[0] + ox, current.1)], b'V' => vec![(current.0, v[0] + oy)],
                _ => v.chunks_exact(2).map(|p| (p[0] + ox, p[1] + oy)).collect(),
            };
            let device: Vec<_> = points.iter().map(|&p| self.state.transform(p)).collect();
            match kind {
                b'M' => { paths.push(Subpath { points: vec![device[0]], closed: false }); start = points[0]; }
                b'L' | b'H' | b'V' => paths.last_mut().unwrap().points.push(device[0]),
                _ => {
                    let path = paths.last_mut().unwrap();
                    let controls: Vec<_> = std::iter::once(*path.points.last().unwrap()).chain(device).collect();
                    path.points.extend(primitives::bezier_points(&controls, count).into_iter().skip(1));
                }
            }
            current = *points.last().unwrap();
        }
        paths
    }
}

fn ranked<K: Ord + Clone>(counts: &BTreeMap<K, usize>) -> Vec<(K, usize)> {
    let mut values: Vec<_> = counts.iter().map(|(color, &count)| (color.clone(), count)).collect();
    values.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0))); values
}
fn command_lines(executions: &[Execution]) -> Vec<String> {
    executions.iter().map(|e| {
        let head = format!("cmd {} line {} {}", e.sequence, e.command.line, e.command.keyword);
        match e.kind { "error" => format!("{head} error {}", e.error), "drawing" => format!("{head} pixels {} box {}", e.pixels, box_text(e.bbox)), _ => format!("{head} ok") }
    }).collect()
}
fn visible_counts(layers: &[Layer], width: usize, height: usize) -> Vec<usize> {
    let mut counts = vec![0; layers.len()];
    for y in 0..height { for x in 0..width {
        let mut covered = false;
        for (i, layer) in layers.iter().enumerate().rev() { let alpha = layer.alpha_at(x, y); if alpha > 0 && !covered { counts[i] += 1; } if alpha == 255 { covered = true; } }
    } }
    counts
}
fn layer_lines(scene: &Scene, layers: &[Layer], executions: &[Execution]) -> Vec<String> {
    let visible = visible_counts(layers, scene.width, scene.height);
    let mut lines = vec![format!("layers {}", layers.len())];
    for (i, layer) in layers.iter().enumerate() {
        let block = &scene.layers[i];
        let own: Vec<_> = executions.iter().filter(|e| e.layer == i + 1).collect();
        let mut counts = BTreeMap::new();
        let mut pixels = Pixels::new();
        for y in 0..layer.height { for x in 0..layer.width { if let Some(color) = layer.colors[y][x] { pixels.insert((x as i64, y as i64)); *counts.entry(color).or_insert(0) += 1; } } }
        lines.push(format!("layer {} {} opacity {} mode {} commands {} errors {} pixels {} box {} visible {} colors {}", i + 1, block.name, block.opacity, block.mode, own.len(), own.iter().filter(|e| e.kind == "error").count(), pixels.len(), box_text(bounding_box(&pixels)), visible[i], counts.len()));
        for (color, count) in ranked(&counts).into_iter().take(5) { lines.push(format!("color {} pixels {count}", values_text(&color))); }
    }
    lines
}
fn symbol_uses(scene: &Scene, executions: &[Execution]) -> BTreeMap<String, usize> {
    let mut uses: BTreeMap<_, _> = scene.symbols.keys().map(|name| (name.clone(), 0)).collect();
    for e in executions { if e.kind == "state" && e.command.keyword == "USE" { *uses.get_mut(&e.command.arguments[0]).unwrap() += 1; } }
    uses
}
fn unused_items(scene: &Scene, styles: &Styles, executions: &[Execution]) -> Vec<(&'static str, String)> {
    let mut pens = BTreeSet::new(); let mut brushes = BTreeSet::new();
    for e in executions {
        if e.kind != "drawing" { continue; }
        if PEN_COMMANDS.contains(&e.command.keyword.as_str()) { pens.insert(e.command.arguments[0].clone()); }
        else if BRUSH_COMMANDS.contains(&e.command.keyword.as_str()) { brushes.insert(e.command.arguments[0].clone()); }
    }
    let mut colors = BTreeSet::from([scene.background.clone()]);
    for name in &pens { colors.insert(styles.pens[name].color.clone()); }
    for name in &brushes { colors.extend(styles.brushes[name].colors.iter().cloned()); }
    let mut unused = Vec::new();
    unused.extend(styles.colors.keys().filter(|name| !colors.contains(*name)).map(|name| ("color", name.clone())));
    unused.extend(styles.pens.keys().filter(|name| !pens.contains(*name)).map(|name| ("pen", name.clone())));
    unused.extend(styles.brushes.keys().filter(|name| !brushes.contains(*name)).map(|name| ("brush", name.clone())));
    unused.extend(symbol_uses(scene, executions).into_iter().filter(|(_, count)| *count == 0).map(|(name, _)| ("symbol", name)));
    unused
}
fn summary_lines(scene: &Scene, styles: &Styles, executions: &[Execution], image: &Image) -> Vec<String> {
    let background = styles.colors[&scene.background];
    let mut kinds = [0; 3]; let mut errors = [0; 7];
    let (mut painted, mut erased) = (0, 0);
    let mut keywords: BTreeMap<String, [usize; 3]> = BTreeMap::new();
    for e in executions {
        kinds[match e.kind { "drawing" => 0, "state" => 1, _ => 2 }] += 1;
        let tally = keywords.entry(e.command.keyword.clone()).or_default(); tally[0] += 1;
        if e.kind == "error" { errors[ERROR_NAMES.iter().position(|&name| name == e.error).unwrap()] += 1; tally[1] += 1; }
        else if e.kind == "drawing" { tally[2] += e.pixels; if e.command.keyword == "ERASE" { erased += e.pixels; } else { painted += e.pixels; } }
    }
    let mut lines = vec![format!("canvas {} {}", scene.width, scene.height), format!("background {}", values_text(&background[..3])), format!("layers {}", scene.layers.len()), format!("symbols {}", scene.symbols.len()), format!("commands {}", executions.len()), format!("drawing {}", kinds[0]), format!("state {}", kinds[1]), format!("errors {}", kinds[2])];
    for (name, count) in ERROR_NAMES.iter().zip(errors) { lines.push(format!("error {name} {count}")); }
    lines.push(format!("painted {painted}")); lines.push(format!("erased {erased}"));
    let mut counts = BTreeMap::new();
    for color in image.iter().flatten() { *counts.entry(*color).or_insert(0) += 1; }
    lines.push(format!("colors {}", counts.len()));
    for (i, (color, count)) in ranked(&counts).into_iter().take(8).enumerate() { lines.push(format!("top {} {} pixels {count}", i + 1, values_text(&color))); }
    for (name, count) in symbol_uses(scene, executions) { lines.push(format!("symbol {name} uses {count}")); }
    for (keyword, [executed, errors, pixels]) in keywords { lines.push(format!("keyword {keyword} executed {executed} errors {errors} pixels {pixels}")); }
    let unused = unused_items(scene, styles, executions); lines.push(format!("unused {}", unused.len()));
    for (kind, name) in unused { lines.push(format!("unused {kind} {name}")); }
    lines
}
fn probe_lines(probes: Vec<String>, image: &Image, layers: &[Layer]) -> Vec<String> {
    let total: usize = probes[0].parse().unwrap();
    let mut lines = Vec::new();
    for (i, line) in probes.iter().skip(1).take(total).enumerate() {
        let words: Vec<_> = line.split(' ').map(str::to_owned).collect();
        let v = integers(&words[1..]);
        let number = i + 1;
        if words[0] == "point" {
            let (x, y) = (v[0] as usize, v[1] as usize);
            let stack: Vec<_> = layers.iter().enumerate().filter(|(_, layer)| layer.alpha_at(x, y) > 0).map(|(i, layer)| format!("{}:{}", i + 1, layer.lines[y][x])).collect();
            lines.push(format!("point {number} {x} {y} rgb {} layers {} stack {}", values_text(&image[y][x]), stack.len(), if stack.is_empty() { "none".into() } else { stack.join(" ") }));
        } else {
            let (x0, y0, x1, y1) = (v[0] as usize, v[1] as usize, v[2] as usize, v[3] as usize);
            let mut totals: Rgb = [0; 3]; let mut colors = BTreeSet::new(); let mut cover = vec![0; layers.len()];
            for y in y0..=y1 { for x in x0..=x1 {
                let color = image[y][x]; colors.insert(color);
                for c in 0..3 { totals[c] += color[c]; }
                for (i, layer) in layers.iter().enumerate() { if layer.alpha_at(x, y) > 0 { cover[i] += 1; } }
            } }
            let count = (x1 - x0 + 1) * (y1 - y0 + 1);
            let means = totals.map(|sum| sum / count as i64);
            lines.push(format!("area {number} {x0} {y0} {x1} {y1} pixels {count} mean {} colors {} cover {}", values_text(&means), colors.len(), cover.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")));
        }
    }
    lines
}

fn main() -> io::Result<()> {
    let styles = read_styles(read_lines("styles.txt")?);
    let font = read_font(read_lines("font.txt")?);
    let scene = SceneParser::new(read_lines("scene.txt")?).parse();
    let probes = read_lines("probes.txt")?;
    let mut renderer = Renderer::new(&scene, &styles, &font); renderer.run();
    let image = canvas::composite(&renderer.layers, styles.colors[&scene.background], scene.width, scene.height);
    fs::create_dir_all("output")?;
    ppm_writer::write_ppm(&image)?; ppm_writer::write_preview(&image)?;
    ppm_writer::write_text("commands.txt", &command_lines(&renderer.executions))?;
    ppm_writer::write_text("layers.txt", &layer_lines(&scene, &renderer.layers, &renderer.executions))?;
    ppm_writer::write_text("summary.txt", &summary_lines(&scene, &styles, &renderer.executions, &image))?;
    ppm_writer::write_text("probes.txt", &probe_lines(probes, &image, &renderer.layers))
}
