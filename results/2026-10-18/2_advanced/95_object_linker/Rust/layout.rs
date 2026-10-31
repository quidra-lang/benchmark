use crate::object_parser::nobits;
#[derive(Clone)]
pub enum Kind {
    Input(usize, usize),
    Merged {
        sections: usize,
        strings: usize,
        unique: usize,
        saved: i64,
        positions: Vec<(usize, usize, i64, i64)>
    },
    Common(String),
    Veneer(String),
}
#[derive(Clone)]
pub struct Component {
    pub kind: Kind,
    pub size: i64,
    pub alignment: i64,
    pub address: i64,
    pub data: Vec<u8>
}
#[derive(Clone)]
pub struct OutputSection {
    pub name: String,
    pub components: Vec<Component>,
    pub address: i64,
    pub size: i64,
    pub alignment: i64
}
pub struct Segment {
    pub name: String,
    pub base: i64,
    pub length: i64,
    pub fill: u8,
    pub outputs: Vec<usize>,
    pub memsz: i64,
    pub filesz: i64,
    pub paddr: i64,
    pub used: i64,
    pub image: Vec<u8>
}
pub fn align(x: i64, n: i64) -> i64 {
    x + (n - x.rem_euclid(n)).rem_euclid(n)
}
pub fn output(name: &str, outputs: &[OutputSection]) -> Option<usize> {
    outputs.iter().position(|o| crate::object_parser::belongs(name, &o.name))
}
pub fn assign(segment: &mut Segment, outputs: &mut [OutputSection]) {
    let mut cursor = segment.base;
    segment.filesz = 0;
    for &index in &segment.outputs {
        let output = &mut outputs[index];
        output.alignment = output.components.iter().map(|c| c.alignment).max().unwrap_or(1);
        cursor = align(cursor, output.alignment);
        output.address = cursor;
        for component in &mut output.components {
            cursor = align(cursor, component.alignment);
            component.address = cursor;
            cursor += component.size;
        }
        output.size = cursor - output.address;
        if !nobits(&output.name) {
            segment.filesz = cursor - segment.base;
        }
    }
    segment.memsz = cursor - segment.base;
    segment.paddr = segment.base;
    segment.used = segment.memsz;
}
