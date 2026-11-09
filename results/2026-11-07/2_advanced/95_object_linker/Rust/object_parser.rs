use std::fs;
#[derive(Clone)]
pub struct Section {
    pub name: String,
    pub alignment: i64,
    pub size: i64,
    pub data: Vec<u8>,
    pub discard: Option<&'static str>,
    pub output: Option<usize>,
    pub live: bool,
    pub address: i64,
    pub strings: std::collections::BTreeMap<i64,
    i64>
}
#[derive(Clone)]
pub enum Definition {
    Section(usize, i64),
    Undefined,
    Common(i64, i64)
}
#[derive(Clone)]
pub struct Symbol {
    pub name: String,
    pub binding: String,
    pub definition: Definition
}
#[derive(Clone)]
pub struct Relocation {
    pub section: usize,
    pub offset: i64,
    pub kind: String,
    pub symbol: usize,
    pub addend: i64
}
#[derive(Clone)]
pub struct Object {
    pub name: String,
    pub sections: Vec<Section>,
    pub groups: Vec<(String, Vec<usize>)>,
    pub symbols: Vec<Symbol>,
    pub relocations: Vec<Relocation>
}
pub fn belongs(name: &str, output: &str) -> bool {
    name == output || name.starts_with(&(output.to_string() + "."))
}
pub fn nobits(name: &str) -> bool {
    belongs(name, ".bss")
}
pub fn strings(name: &str) -> bool {
    belongs(name, ".rodata.str")
}
pub fn lines(name: &str) -> Vec<String> {
    fs::read_to_string(format!("input/{}", name)).unwrap().lines().map(str::to_string).collect()
}
pub fn parse(name: String, lines: &[String]) -> Object {
    let mut object = Object {
        name,
        sections: Vec::new(),
        groups: Vec::new(),
        symbols: Vec::new(),
        relocations: Vec::new()
    };
    for line in lines {
        let fields: Vec<&str> = line.split(' ').collect();
        match fields[0] {
            "section" => object.sections.push(Section {
                name: fields[1].into(),
                alignment: fields[2].parse().unwrap(),
                size: fields[3].parse().unwrap(),
                data: Vec::new(),
                discard: None,
                output: None,
                live: false,
                address: 0,
                strings: std::collections::BTreeMap::new()
            }),
            "data" => {
                for i in (0..fields[1].len()).step_by(2) {
                    object.sections.last_mut().unwrap().data.push(u8::from_str_radix(&fields[1][i..i + 2], 16).unwrap());
                }
            },
            "comdat" => {
                let members = fields[2..].iter().map(|name| object.sections.iter().position(|s| s.name == *name).unwrap()).collect();
                object.groups.push((fields[1].into(), members));
            },
            "symbol" => {
                let definition = if fields[3] == "undef" {
                    Definition::Undefined
                } else if fields[3] == "common" {
                    Definition::Common(fields[4].parse().unwrap(), fields[5].parse().unwrap())
                } else {
                    Definition::Section(object.sections.iter().position(|s| s.name == fields[3]).unwrap(), fields[4].parse().unwrap())
                };
                object.symbols.push(Symbol {
                    name: fields[1].into(),
                    binding: fields[2].into(),
                    definition
                });
            },
            "reloc" => object.relocations.push(Relocation {
                section: object.sections.iter().position(|s| s.name == fields[1]).unwrap(),
                offset: fields[2].parse().unwrap(),
                kind: fields[3].into(),
                symbol: object.symbols.iter().position(|s| s.name == fields[4]).unwrap(),
                addend: fields[5].parse().unwrap()
            }),
            "end" => break,
            _ => unreachable!()
        }
    }
    object
}
