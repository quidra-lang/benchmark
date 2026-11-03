use crate::object_parser::{
    Object,
    Definition
};
#[derive(Clone)]
pub struct Resolution {
    pub kind: &'static str,
    pub definition: Option<(usize, usize)>,
    pub definer: String,
    pub size: i64,
    pub alignment: i64,
    pub strong: Vec<usize>,
    pub common: Vec<(i64, i64)>,
    pub referrers: Vec<usize>,
    pub live: bool,
    pub address: i64,
}
pub fn resolve(objects: &[Object], entries: &[(usize, usize)], script: bool) -> Resolution {
    let mut strong = Vec::new();
    let mut weak = Vec::new();
    let mut common = Vec::new();
    let mut references = Vec::new();
    let mut global_reference = false;
    for &(o, s) in entries {
        let symbol = &objects[o].symbols[s];
        match symbol.definition {
            Definition::Section(_, _) => if symbol.binding == "global" {
                strong.push((o, s));
            } else {
                weak.push((o, s));
            },
            Definition::Common(size, alignment) => common.push((o, s, size, alignment)),
            Definition::Undefined => {
                if !references.contains(&o) {
                    references.push(o);
                }
                global_reference |= symbol.binding == "global";
            }
        }
    }
    let mut result = Resolution {
        kind: "weakundef",
        definition: None,
        definer: "-".into(),
        size: 0,
        alignment: 1,
        strong: strong.iter().map(|v| v.0).collect(),
        common: common.iter().map(|v| (v.2, v.3)).collect(),
        referrers: references,
        live: false,
        address: 0
    };
    if script {
        result.kind = "script";
        result.definer = "*script*".into();
        result.live = true;
    }
    else if let Some(&(o, s)) = strong.first() {
        result.kind = "global";
        result.definition = Some((o, s));
        result.definer = objects[o].name.clone();
    }
    else if !common.is_empty() {
        result.kind = "common";
        result.size = common.iter().map(|v| v.2).max().unwrap();
        result.alignment = common.iter().map(|v| v.3).max().unwrap();
        let chosen = common.iter().find(|v| v.2 == result.size).unwrap();
        result.definer = objects[chosen.0].name.clone();
    } else if let Some(&(o, s)) = weak.first() {
        result.kind = "weak";
        result.definition = Some((o, s));
        result.definer = objects[o].name.clone();
    }
    else if global_reference {
        result.kind = "undefined";
    }
    result
}
