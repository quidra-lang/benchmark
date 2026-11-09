use std::collections::BTreeSet;
use crate::key_parts;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Kind { String, Int, Bool, Enum, Size, Duration, Host, Path, Url, Date, List }

impl Kind {
    fn parse(text: &str) -> Self {
        match text {
            "string" => Self::String, "int" => Self::Int, "bool" => Self::Bool,
            "enum" => Self::Enum, "size" => Self::Size, "duration" => Self::Duration,
            "host" => Self::Host, "path" => Self::Path, "url" => Self::Url,
            "date" => Self::Date, "list" => Self::List, _ => unreachable!(),
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            Self::String => "string", Self::Int => "int", Self::Bool => "bool",
            Self::Enum => "enum", Self::Size => "size", Self::Duration => "duration",
            Self::Host => "host", Self::Path => "path", Self::Url => "url", Self::Date => "date", Self::List => "list",
        }
    }
}

pub struct Spec {
    pub line: usize,
    pub pattern: String,
    pub section: String,
    pub key: String,
    pub wildcard: bool,
    pub kind: Kind,
    pub item: Kind,
    pub required: bool,
    pub secret: bool,
    pub unique: bool,
    pub fixed: bool,
    pub default: Option<String>,
    pub range: Option<(String, String)>,
    pub values: Vec<String>,
    pub aliases: Vec<String>,
    pub when: Option<String>,
    pub le: Option<String>,
}

impl Spec {
    pub fn matches(&self, section: &str) -> bool {
        let pattern: Vec<&str> = self.section.split('.').collect();
        let parts: Vec<&str> = section.split('.').collect();
        pattern.len() == parts.len() && pattern.iter().zip(parts).all(|(p, s)| *p == "*" || *p == s)
    }
}

pub struct Schema { pub specs: Vec<Spec> }

impl Schema {
    pub fn parse(source: &str) -> Self {
        let mut specs = Vec::new();
        for (index, line) in source.lines().enumerate() {
            if line.trim_matches(' ').is_empty() || line.starts_with('#') { continue; }
            let words: Vec<&str> = line.split(' ').collect();
            let (section, key) = key_parts(words[0]);
            let mut spec = Spec {
                line: index + 1, pattern: words[0].into(), section: section.into(), key: key.into(),
                wildcard: section.split('.').any(|s| s == "*"), kind: Kind::parse(words[1]), item: Kind::String,
                required: false, secret: false, unique: false, fixed: false, default: None, range: None,
                values: Vec::new(), aliases: Vec::new(), when: None, le: None,
            };
            for attribute in &words[2..] {
                let (name, argument) = attribute.split_once('=').unwrap_or((attribute, ""));
                match name {
                    "required" => spec.required = true, "secret" => spec.secret = true,
                    "unique" => spec.unique = true, "fixed" => spec.fixed = true,
                    "default" => spec.default = Some(argument.into()),
                    "range" => { let (lo, hi) = argument.split_once("..").unwrap(); spec.range = Some((lo.into(), hi.into())); }
                    "values" => spec.values = argument.split(',').map(str::to_owned).collect(),
                    "alias" => spec.aliases = argument.split(',').map(str::to_owned).collect(),
                    "item" => spec.item = Kind::parse(argument), "when" => spec.when = Some(argument.into()),
                    "le" => spec.le = Some(argument.into()), _ => unreachable!(),
                }
            }
            specs.push(spec);
        }
        Self { specs }
    }
    pub fn spec_for(&self, key: &str) -> Option<usize> {
        if let Some(index) = self.specs.iter().position(|s| !s.wildcard && s.pattern == key) { return Some(index); }
        let (section, name) = key_parts(key);
        self.specs.iter().position(|s| s.wildcard && s.key == name && s.matches(section))
    }
    pub fn target_keys(&self, index: usize, sections: &BTreeSet<String>) -> Vec<String> {
        let spec = &self.specs[index];
        if !spec.wildcard { return vec![spec.pattern.clone()]; }
        sections.iter().filter(|s| spec.matches(s)).map(|s| format!("{s}.{}", spec.key))
            .filter(|key| self.spec_for(key) == Some(index)).collect()
    }
}
