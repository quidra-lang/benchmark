use crate::measure::Point;
use std::fs;

pub struct Polygon {
    pub vertices: Vec<usize>,
    pub line: usize,
    pub group: String,
}

#[derive(Clone)]
pub struct Face {
    pub vertices: [usize; 3],
    pub polygon: Option<usize>,
    pub group: String,
}

pub struct Model {
    pub vertices: Vec<Point>,
    pub polygons: Vec<Polygon>,
    pub groups: Vec<String>,
    pub errors: Vec<(usize, &'static str)>,
    pub ignored: usize,
    pub lines: usize,
}

pub fn integer(text: &str) -> Option<i64> {
    let digits = text.strip_prefix('-').unwrap_or(text);
    if !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit()) { text.parse().ok() } else { None }
}

pub fn read() -> Model {
    let text = fs::read_to_string("input/model.obj").unwrap();
    let mut model = Model { vertices: vec![[0; 3]], polygons: Vec::new(), groups: Vec::new(), errors: Vec::new(), ignored: 0, lines: text.lines().count() };
    let mut group = String::from("default");
    for (index, line) in text.lines().enumerate() {
        if line.is_empty() || line.starts_with('#') { continue; }
        let words: Vec<_> = line.split(' ').collect();
        let arguments = &words[1..];
        let mut error = None;
        match words[0] {
            "v" => {
                if arguments.len() != 3 || arguments.iter().any(|value| integer(value).is_none()) { error = Some("bad_vertex"); }
                else { model.vertices.push(std::array::from_fn(|i| integer(arguments[i]).unwrap())); }
            }
            "f" => {
                if arguments.len() < 3 { error = Some("short_face"); }
                else {
                    let mut vertices = Vec::new();
                    let count = model.vertices.len() as i64 - 1;
                    for reference in arguments {
                        let part = reference.split('/').next().unwrap();
                        let value = integer(part);
                        if value.is_none() || value == Some(0) { error = Some("bad_index"); break; }
                        let value = value.unwrap();
                        let number = if value > 0 { value } else { count + 1 + value };
                        if number < 1 || number > count { error = Some("out_of_range"); break; }
                        vertices.push(number as usize);
                    }
                    if error.is_none() {
                        if !model.groups.contains(&group) { model.groups.push(group.clone()); }
                        model.polygons.push(Polygon { vertices, line: index + 1, group: group.clone() });
                    }
                }
            }
            "g" => group = arguments.first().unwrap_or(&"default").to_string(),
            "vt" | "vn" | "s" | "o" | "usemtl" | "mtllib" => model.ignored += 1,
            _ => error = Some("unknown_keyword"),
        }
        if let Some(error) = error { model.errors.push((index + 1, error)); }
    }
    model
}

pub fn write(vertices: &[Point], faces: &[Face]) {
    let mut lines = vec![format!("# vertices {} faces {}", vertices.len() - 1, faces.len())];
    lines.extend(vertices.iter().skip(1).map(|p| format!("v {} {} {}", p[0], p[1], p[2])));
    let mut group = None;
    for face in faces {
        if group != Some(&face.group) { lines.push(format!("g {}", face.group)); group = Some(&face.group); }
        lines.push(format!("f {} {} {}", face.vertices[0], face.vertices[1], face.vertices[2]));
    }
    fs::write("output/repaired.obj", format!("{}\n", lines.join("\n"))).unwrap();
}
