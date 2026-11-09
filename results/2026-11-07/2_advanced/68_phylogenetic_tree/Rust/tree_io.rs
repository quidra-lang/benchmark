use std::collections::BTreeMap;
use std::fs;
use crate::tree_building::{Tree, Rooted};

pub fn real(value: f64, digits: usize) -> String {
    let s = format!("{:.*}", digits, value);
    if s.starts_with('-') && s[1..].bytes().all(|b| b == b'0' || b == b'.') { s[1..].to_owned() } else { s }
}
pub fn symbols(mask: u32, n: usize) -> String { (0..n).map(|i| if mask&(1<<i) != 0 { '*' } else { '.' }).collect() }

pub fn newick(tree: &Tree, outgroup: usize, names: &[String], lengths: bool, support: Option<&BTreeMap<u32, usize>>) -> String {
    let rooted = tree.root(outgroup, names);
    fn node(tree: &Tree, rooted: &Rooted, v: usize, names: &[String], lengths: bool, support: Option<&BTreeMap<u32, usize>>) -> String {
        let mut text = if v < tree.taxa_count { names[v].clone() } else {
            let children: Vec<_> = rooted.children[v].iter().map(|&child| node(tree, rooted, child, names, lengths, support)).collect();
            let mut text = format!("({})", children.join(","));
            if v != rooted.root { if let Some(support) = support { text.push_str(&support.get(&rooted.masks[v]).copied().unwrap_or(0).to_string()); } }
            text
        };
        if lengths && v != rooted.root { text.push_str(&format!(":{}", real(tree.adjacency[v][&rooted.parent[v].unwrap()], 5))); }
        text
    }
    format!("{};", node(tree, &rooted, rooted.root, names, lengths, support))
}

pub fn cladogram(tree: &Tree, outgroup: usize, names: &[String], support: &BTreeMap<u32, usize>) -> Vec<String> {
    let rooted = tree.root(outgroup, names); let mut lines = vec!["*".to_owned()];
    fn children(tree: &Tree, rooted: &Rooted, parent: usize, prefix: String, names: &[String], support: &BTreeMap<u32, usize>, lines: &mut Vec<String>) {
        for (i, &child) in rooted.children[parent].iter().enumerate() {
            let last = i+1 == rooted.children[parent].len();
            let label = if child < tree.taxa_count { names[child].clone() } else { format!("[{}]", support.get(&rooted.masks[child]).copied().unwrap_or(0)) };
            lines.push(format!("{}{}{}", prefix, if last { "`-- " } else { "|-- " }, label));
            children(tree, rooted, child, format!("{}{}", prefix, if last { "    " } else { "|   " }), names, support, lines);
        }
    }
    children(tree, &rooted, rooted.root, String::new(), names, support, &mut lines); lines
}
pub fn write(file: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap(); fs::write(format!("output/{}", file), lines.join("\n")+"\n").unwrap();
}
