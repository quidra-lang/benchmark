use std::collections::BTreeMap;
use crate::Message;

pub struct Container {
    pub id: String,
    pub message: Option<usize>,
    pub parent: Option<usize>,
    pub children: Vec<usize>,
    pub subject: Option<String>,
}
impl Container {
    fn new(id: String) -> Self { Self { id, message: None, parent: None, children: Vec::new(), subject: None } }
}
pub struct Threads { pub containers: Vec<Container>, pub roots: Vec<usize> }
fn container_of(id: &str, table: &mut BTreeMap<String, usize>, containers: &mut Vec<Container>) -> usize {
    if let Some(&number) = table.get(id) { return number; }
    let number = containers.len();
    containers.push(Container::new(id.to_owned())); table.insert(id.to_owned(), number); number
}
fn ancestor(containers: &[Container], candidate: usize, mut node: usize) -> bool {
    loop { if candidate == node { return true; } match containers[node].parent { Some(parent) => node = parent, None => return false } }
}
fn adopt(containers: &mut [Container], parent: usize, child: usize) { containers[child].parent = Some(parent); containers[parent].children.push(child); }
fn prune(containers: &mut [Container], nodes: Vec<usize>, at_root: bool) -> Vec<usize> {
    let mut result = Vec::new();
    for node in nodes {
        let children = std::mem::take(&mut containers[node].children);
        containers[node].children = prune(containers, children, false);
        if containers[node].message.is_some() || at_root && containers[node].children.len() >= 2 { result.push(node); }
        else {
            let parent = if at_root { None } else { containers[node].parent };
            let children = containers[node].children.clone();
            for child in children { containers[child].parent = parent; result.push(child); }
        }
    }
    result
}
type Key = (u8, i64, String, usize);
fn key(containers: &[Container], messages: &[Message], node: usize) -> Key {
    if let Some(message) = containers[node].message { return messages[message].sort_key(); }
    containers[node].children.iter().map(|&child| key(containers, messages, child)).min().unwrap()
}
fn sort_set(containers: &mut [Container], messages: &[Message], nodes: &mut [usize]) {
    for &node in nodes.iter() {
        let mut children = std::mem::take(&mut containers[node].children);
        sort_set(containers, messages, &mut children);
        containers[node].children = children;
    }
    nodes.sort_by_cached_key(|&node| key(containers, messages, node));
}
pub fn root_subject<'a>(containers: &[Container], messages: &'a [Message], root: usize) -> &'a str {
    let message = containers[root].message.unwrap_or_else(|| containers[containers[root].children[0]].message.unwrap());
    &messages[message].base_subject
}
pub fn build_threads(messages: &[Message]) -> Threads {
    let mut table = BTreeMap::new();
    let mut containers = Vec::new();
    for (index, message) in messages.iter().enumerate() {
        let node = if message.id.is_empty() { let node = containers.len(); containers.push(Container::new(String::new())); node }
            else { container_of(&message.id, &mut table, &mut containers) };
        containers[node].message = Some(index);
        let references: Vec<_> = message.references.iter().map(|id| container_of(id, &mut table, &mut containers)).collect();
        for pair in references.windows(2) {
            if containers[pair[1]].parent.is_none() && !ancestor(&containers, pair[1], pair[0]) { adopt(&mut containers, pair[0], pair[1]); }
        }
        if let Some(parent) = containers[node].parent.take() { containers[parent].children.retain(|&child| child != node); }
        if let Some(&last) = references.last() { if !ancestor(&containers, node, last) { adopt(&mut containers, last, node); } }
    }
    let roots = containers.iter().enumerate().filter(|(_, node)| node.parent.is_none()).map(|(index, _)| index).collect();
    let mut roots = prune(&mut containers, roots, true);
    sort_set(&mut containers, messages, &mut roots);
    let mut groups: BTreeMap<String, Vec<usize>> = BTreeMap::new();
    for &root in &roots {
        let subject = root_subject(&containers, messages, root);
        if !subject.is_empty() { groups.entry(subject.to_owned()).or_default().push(root); }
    }
    let mut merged: Vec<_> = roots.iter().copied().filter(|&root| {
        let subject = root_subject(&containers, messages, root);
        subject.is_empty() || groups[subject].len() == 1
    }).collect();
    for (subject, group) in groups {
        if group.len() < 2 { continue; }
        let missing = group.iter().copied().find(|&node| containers[node].message.is_none());
        let originals: Vec<_> = group.iter().copied().filter(|&node| containers[node].message.is_some_and(|index| !messages[index].reply)).collect();
        let target = if let Some(missing) = missing { missing } else if originals.len() == 1 { originals[0] }
            else { let target = containers.len(); let mut container = Container::new(String::new()); container.subject = Some(subject); containers.push(container); target };
        for node in group {
            if node == target { continue; }
            if containers[node].message.is_some() { adopt(&mut containers, target, node); }
            else { for child in containers[node].children.clone() { adopt(&mut containers, target, child); } }
        }
        merged.push(target);
    }
    sort_set(&mut containers, messages, &mut merged);
    Threads { containers, roots: merged }
}
