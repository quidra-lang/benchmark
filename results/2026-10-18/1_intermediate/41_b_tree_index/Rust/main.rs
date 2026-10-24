use std::collections::BTreeMap;
use std::fmt::{self, Display};
use std::io::{self, BufRead, Write};

#[derive(Clone, PartialEq, Eq)]
struct Entry {
    key: i32,
    value: String,
}

impl Display for Entry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}={}", self.key, self.value)
    }
}

#[derive(Clone, Default, PartialEq, Eq)]
struct Node {
    entries: Vec<Entry>,
    children: Vec<usize>,
}

impl Node {
    fn notation(&self) -> String {
        format!("[{}]", self.entries.iter().map(|e| e.key.to_string()).collect::<Vec<_>>().join(" "))
    }

    fn position(&self, key: i32) -> usize {
        self.entries.iter().position(|entry| key <= entry.key).unwrap_or(self.entries.len())
    }
}

#[derive(Default)]
struct Trace {
    enabled: bool,
    lines: Vec<String>,
}

impl Trace {
    fn emit(&mut self, line: String) {
        if self.enabled {
            self.lines.push(line);
        }
    }
}

#[derive(Clone)]
struct Tree {
    degree: usize,
    root: usize,
    pages: BTreeMap<usize, Node>,
    splits: usize,
    merges: usize,
    borrows: usize,
}

impl Tree {
    fn new(degree: usize) -> Self {
        Self { degree, root: 0, pages: BTreeMap::from([(0, Node::default())]), splits: 0, merges: 0, borrows: 0 }
    }

    fn node(&self, page: usize) -> &Node {
        &self.pages[&page]
    }

    fn node_mut(&mut self, page: usize) -> &mut Node {
        self.pages.get_mut(&page).unwrap()
    }

    fn allocate(&mut self, node: Node) -> usize {
        let mut page = 0;
        while self.pages.contains_key(&page) {
            page += 1;
        }
        self.pages.insert(page, node);
        page
    }

    fn entries(&self) -> Vec<Entry> {
        fn visit(tree: &Tree, page: usize, result: &mut Vec<Entry>) {
            let node = tree.node(page);
            for j in 0..=node.entries.len() {
                if !node.children.is_empty() {
                    visit(tree, node.children[j], result);
                }
                if let Some(entry) = node.entries.get(j) {
                    result.push(entry.clone());
                }
            }
        }
        let mut result = Vec::new();
        visit(self, self.root, &mut result);
        result
    }

    fn search(&self, key: i32) -> (Option<(usize, usize)>, Vec<String>) {
        let mut page = self.root;
        let mut path = Vec::new();
        loop {
            let node = self.node(page);
            path.push(node.notation());
            let position = node.position(key);
            if node.entries.get(position).is_some_and(|entry| entry.key == key) {
                return (Some((page, position)), path);
            }
            if node.children.is_empty() {
                return (None, path);
            }
            page = node.children[position];
        }
    }

    fn violation(&self) -> Option<String> {
        fn visit(tree: &Tree, page: usize, location: String, depth: usize, low: Option<i32>, high: Option<i32>, reference: &mut Option<usize>) -> Option<String> {
            let node = tree.node(page);
            let count = node.entries.len();
            let minimum = if page == tree.root { usize::from(!node.children.is_empty()) } else { tree.degree - 1 };
            let maximum = 2 * tree.degree - 1;
            let details = format!("at={location} node={}", node.notation());
            if count < minimum || count > maximum {
                return Some(format!("COUNT {details} keys={count} allowed={minimum}..{maximum}"));
            }
            for pair in node.entries.windows(2) {
                if pair[0].key >= pair[1].key {
                    return Some(format!("ORDER {details} {}>={}", pair[0].key, pair[1].key));
                }
            }
            for entry in &node.entries {
                if low.is_some_and(|bound| entry.key <= bound) || high.is_some_and(|bound| entry.key >= bound) {
                    return Some(format!("RANGE {details} key={} low={} high={}", entry.key,
                        low.map_or_else(|| "-inf".into(), |n| n.to_string()), high.map_or_else(|| "+inf".into(), |n| n.to_string())));
                }
            }
            if node.children.is_empty() {
                if let Some(expected) = *reference {
                    if depth != expected {
                        return Some(format!("DEPTH {details} depth={depth} expected={expected}"));
                    }
                } else {
                    *reference = Some(depth);
                }
            }
            for (j, &child) in node.children.iter().enumerate() {
                let lower = if j == 0 { low } else { Some(node.entries[j - 1].key) };
                let upper = if j == count { high } else { Some(node.entries[j].key) };
                if let Some(error) = visit(tree, child, format!("{location}.{j}"), depth + 1, lower, upper, reference) {
                    return Some(error);
                }
            }
            None
        }
        visit(self, self.root, "root".into(), 0, None, None, &mut None)
    }

    fn status(&self) -> &'static str {
        if self.violation().is_none() { "OK" } else { "DAMAGED" }
    }

    fn height(&self) -> usize {
        let mut page = self.root;
        let mut depth = 0;
        while let Some(&child) = self.node(page).children.first() {
            page = child;
            depth += 1;
        }
        depth
    }

    fn load(degree: usize, tokens: &[&str]) -> Result<Self, usize> {
        struct Parser<'a> {
            tokens: &'a [&'a str],
            position: usize,
            tree: Tree,
        }
        impl Parser<'_> {
            fn entry(&mut self) -> Result<Entry, usize> {
                let token = self.tokens.get(self.position).ok_or(self.position + 1)?;
                let (key, value) = token.split_once('=').ok_or(self.position + 1)?;
                self.position += 1;
                Ok(Entry { key: key.parse().unwrap(), value: value.into() })
            }

            fn node(&mut self) -> Result<usize, usize> {
                if self.tokens.get(self.position) != Some(&"(") {
                    return Err(self.position + 1);
                }
                self.position += 1;
                let page = self.tree.allocate(Node::default());
                let mut node = Node::default();
                if self.tokens.get(self.position) == Some(&"(") {
                    node.children.push(self.node()?);
                    while self.tokens.get(self.position) != Some(&")") {
                        node.entries.push(self.entry()?);
                        node.children.push(self.node()?);
                    }
                } else {
                    while self.tokens.get(self.position) != Some(&")") {
                        node.entries.push(self.entry()?);
                    }
                }
                self.position += 1;
                self.tree.pages.insert(page, node);
                Ok(page)
            }
        }
        let mut parser = Parser { tokens, position: 0, tree: Self::new(degree) };
        parser.tree.pages.clear();
        parser.tree.root = parser.node()?;
        if parser.position != tokens.len() {
            return Err(parser.position + 1);
        }
        Ok(parser.tree)
    }

    fn changes(&self, before: &BTreeMap<usize, Node>) -> (usize, usize) {
        let writes = self.pages.iter().filter(|&(id, node)| before.get(id) != Some(node)).count();
        let frees = before.keys().filter(|id| !self.pages.contains_key(*id)).count();
        (writes, frees)
    }

    fn split(&mut self, parent: usize, position: usize, trace: &mut Trace) {
        let child = self.node(parent).children[position];
        let old_notation = self.node(child).notation();
        let degree = self.degree;
        let (middle, right) = {
            let node = self.node_mut(child);
            let entries = node.entries.split_off(degree);
            let children = if node.children.is_empty() { Vec::new() } else { node.children.split_off(degree) };
            (node.entries.pop().unwrap(), Node { entries, children })
        };
        let new_page = self.allocate(right);
        let middle_key = middle.key;
        let node = self.node_mut(parent);
        node.entries.insert(position, middle);
        node.children.insert(position + 1, new_page);
        self.splits += 1;
        trace.emit(format!("STEP split page={child} keys={old_notation} up={middle_key} new={new_page}"));
    }

    fn upsert(&mut self, entry: Entry, trace: &mut Trace) -> Option<String> {
        if let Some((page, position)) = self.search(entry.key).0 {
            return Some(std::mem::replace(&mut self.node_mut(page).entries[position].value, entry.value));
        }
        if self.node(self.root).entries.len() == 2 * self.degree - 1 {
            self.root = self.allocate(Node { entries: Vec::new(), children: vec![self.root] });
            trace.emit(format!("STEP grow page={}", self.root));
            self.split(self.root, 0, trace);
        }
        let mut page = self.root;
        while !self.node(page).children.is_empty() {
            let mut position = self.node(page).position(entry.key);
            let child = self.node(page).children[position];
            if self.node(child).entries.len() == 2 * self.degree - 1 {
                self.split(page, position, trace);
                if entry.key > self.node(page).entries[position].key {
                    position += 1;
                }
            }
            page = self.node(page).children[position];
        }
        let position = self.node(page).position(entry.key);
        self.node_mut(page).entries.insert(position, entry);
        trace.emit(format!("STEP place page={page} keys={}", self.node(page).notation()));
        None
    }

    fn extreme(&self, mut page: usize, last: bool) -> Entry {
        loop {
            let node = self.node(page);
            if node.children.is_empty() {
                return if last { node.entries.last().unwrap() } else { &node.entries[0] }.clone();
            }
            page = if last { *node.children.last().unwrap() } else { node.children[0] };
        }
    }

    fn merge(&mut self, parent: usize, position: usize, case: &str, trace: &mut Trace) -> usize {
        let left = self.node(parent).children[position];
        let right = self.node(parent).children[position + 1];
        let removed = self.pages.remove(&right).unwrap();
        let node = self.node_mut(parent);
        let middle = node.entries.remove(position);
        node.children.remove(position + 1);
        let node = self.node_mut(left);
        node.entries.push(middle);
        node.entries.extend(removed.entries);
        node.children.extend(removed.children);
        self.merges += 1;
        trace.emit(format!("STEP {case} page={parent} merge={left}+{right} keys={}", self.node(left).notation()));
        if parent == self.root && self.node(parent).entries.is_empty() {
            self.root = left;
            self.pages.remove(&parent);
            trace.emit(format!("STEP shrink page={left}"));
        }
        left
    }

    fn remove_at(&mut self, page: usize, key: i32, cases: &mut Vec<&'static str>, trace: &mut Trace) {
        let position = self.node(page).position(key);
        if self.node(page).entries.get(position).is_some_and(|entry| entry.key == key) {
            if self.node(page).children.is_empty() {
                cases.push("1");
                self.node_mut(page).entries.remove(position);
                trace.emit(format!("STEP 1 page={page} keys={}", self.node(page).notation()));
                return;
            }
            let left = self.node(page).children[position];
            let right = self.node(page).children[position + 1];
            if self.node(left).entries.len() >= self.degree {
                cases.push("2a");
                let predecessor = self.extreme(left, true);
                trace.emit(format!("STEP 2a page={page} pred={}", predecessor.key));
                self.remove_at(left, predecessor.key, cases, trace);
                self.node_mut(page).entries[position] = predecessor;
            } else if self.node(right).entries.len() >= self.degree {
                cases.push("2b");
                let successor = self.extreme(right, false);
                trace.emit(format!("STEP 2b page={page} succ={}", successor.key));
                self.remove_at(right, successor.key, cases, trace);
                self.node_mut(page).entries[position] = successor;
            } else {
                cases.push("2c");
                let child = self.merge(page, position, "2c", trace);
                self.remove_at(child, key, cases, trace);
            }
            return;
        }
        let mut child = self.node(page).children[position];
        if self.node(child).entries.len() == self.degree - 1 {
            let left = position.checked_sub(1).map(|j| self.node(page).children[j]);
            let right = self.node(page).children.get(position + 1).copied();
            if let Some(sibling) = left.filter(|&id| self.node(id).entries.len() >= self.degree) {
                cases.push("3a-left");
                let middle = self.node(page).entries[position - 1].clone();
                let replacement = self.node_mut(sibling).entries.pop().unwrap();
                let moved_child = self.node_mut(sibling).children.pop();
                self.node_mut(page).entries[position - 1] = replacement;
                self.node_mut(child).entries.insert(0, middle);
                if let Some(id) = moved_child {
                    self.node_mut(child).children.insert(0, id);
                }
                self.borrows += 1;
                trace.emit(format!("STEP 3a-left page={page} child={child} from={sibling} keys={}", self.node(child).notation()));
            } else if let Some(sibling) = right.filter(|&id| self.node(id).entries.len() >= self.degree) {
                cases.push("3a-right");
                let middle = self.node(page).entries[position].clone();
                let replacement = self.node_mut(sibling).entries.remove(0);
                let moved_child = if self.node(sibling).children.is_empty() { None } else { Some(self.node_mut(sibling).children.remove(0)) };
                self.node_mut(page).entries[position] = replacement;
                self.node_mut(child).entries.push(middle);
                if let Some(id) = moved_child {
                    self.node_mut(child).children.push(id);
                }
                self.borrows += 1;
                trace.emit(format!("STEP 3a-right page={page} child={child} from={sibling} keys={}", self.node(child).notation()));
            } else if left.is_some() {
                cases.push("3b-left");
                child = self.merge(page, position - 1, "3b-left", trace);
            } else {
                cases.push("3b-right");
                child = self.merge(page, position, "3b-right", trace);
            }
        }
        self.remove_at(child, key, cases, trace);
    }

    fn scan(&self, low: i32, high: i32) -> (Vec<Entry>, usize) {
        fn visit(tree: &Tree, page: usize, low: i32, high: i32, entries: &mut Vec<Entry>, visits: &mut usize) {
            *visits += 1;
            let node = tree.node(page);
            for j in 0..=node.entries.len() {
                if !node.children.is_empty() && (j == 0 || node.entries[j - 1].key < high)
                    && (j == node.entries.len() || node.entries[j].key > low) {
                    visit(tree, node.children[j], low, high, entries, visits);
                }
                if let Some(entry) = node.entries.get(j).filter(|e| low <= e.key && e.key <= high) {
                    entries.push(entry.clone());
                }
            }
        }
        let mut entries = Vec::new();
        let mut visits = 0;
        visit(self, self.root, low, high, &mut entries, &mut visits);
        (entries, visits)
    }

    fn dump(&self) -> String {
        fn visit(tree: &Tree, page: usize, tokens: &mut Vec<String>) {
            let node = tree.node(page);
            tokens.push("(".into());
            for j in 0..=node.entries.len() {
                if !node.children.is_empty() {
                    visit(tree, node.children[j], tokens);
                }
                if let Some(entry) = node.entries.get(j) {
                    tokens.push(entry.to_string());
                }
            }
            tokens.push(")".into());
        }
        let mut tokens = Vec::new();
        visit(self, self.root, &mut tokens);
        tokens.join(" ")
    }

    fn compact(&mut self) {
        let mut source = self.entries();
        let mut children = Vec::new();
        let mut built = Vec::new();
        let old_root;
        loop {
            let groups = (source.len() + 2 * self.degree) / (2 * self.degree);
            let keys = source.len() - (groups - 1);
            let (base, extra) = (keys / groups, keys % groups);
            let mut position = 0;
            let mut child_position = 0;
            let mut separators = Vec::new();
            let mut level = Vec::new();
            for j in 0..groups {
                let count = base + usize::from(j < extra);
                let mut node = Node { entries: source[position..position + count].to_vec(), children: Vec::new() };
                position += count;
                if !children.is_empty() {
                    node.children = children[child_position..child_position + count + 1].to_vec();
                    child_position += count + 1;
                }
                level.push(built.len());
                built.push(node);
                if j + 1 < groups {
                    separators.push(source[position].clone());
                    position += 1;
                }
            }
            if groups == 1 {
                old_root = level[0];
                break;
            }
            source = separators;
            children = level;
        }
        fn renumber(old: usize, built: &[Node], pages: &mut BTreeMap<usize, Node>) -> usize {
            let page = pages.len();
            pages.insert(page, Node::default());
            let children = built[old].children.iter().map(|&child| renumber(child, built, pages)).collect();
            pages.insert(page, Node { entries: built[old].entries.clone(), children });
            page
        }
        self.pages.clear();
        self.root = renumber(old_root, &built, &mut self.pages);
        self.splits = 0;
        self.merges = 0;
        self.borrows = 0;
    }
}

#[derive(Clone, Copy, Default)]
enum Cursor {
    #[default]
    Unset,
    Key(i32),
    Begin,
    End,
}

#[derive(Default)]
struct Workbench {
    index: Option<Tree>,
    saved: Option<Tree>,
    cursor: Cursor,
    trace: bool,
}

impl Workbench {
    fn process(&mut self, line: &str) -> Result<Vec<String>, String> {
        let words: Vec<_> = line.split(' ').collect();
        let command = words[0];
        if command == "TRACE" {
            self.trace = words[1] == "ON";
            return Ok(vec![format!("TRACE {}", words[1])]);
        }
        let first: i32 = words.get(1).map_or(0, |word| word.parse().unwrap());
        let ranged = matches!(command, "DELRANGE" | "RANGE" | "COUNT");
        let second: i32 = if ranged { words[2].parse().unwrap() } else { 0 };
        if matches!(command, "CREATE" | "LOAD") {
            if !(2..=5).contains(&first) {
                return Err(format!("BAD DEGREE {first}"));
            }
            let tree = if command == "CREATE" { Tree::new(first as usize) }
                else { Tree::load(first as usize, &words[2..]).map_err(|q| format!("SYNTAX {q}"))? };
            let result = if command == "CREATE" { format!("CREATE t={first}") }
                else { format!("LOAD t={first} nodes={} keys={} {}", tree.pages.len(), tree.entries().len(), tree.status()) };
            self.index = Some(tree);
            self.cursor = Cursor::Unset;
            return Ok(vec![result]);
        }
        let tree = self.index.as_mut().ok_or("NO INDEX")?;
        let needs_valid = matches!(command, "INSERT" | "BULKLOAD" | "DELETE" | "DELRANGE" | "RANGE" | "COUNT"
            | "MIN" | "MAX" | "FLOOR" | "CEIL" | "RANK" | "SELECT" | "SEEK" | "NEXT" | "PREV" | "HEIGHT" | "COMPACT");
        if needs_valid && tree.violation().is_some() {
            return Err("DAMAGED".into());
        }
        let entries = tree.entries();
        if ranged && first > second {
            return Err(format!("BAD RANGE {first} {second}"));
        }
        if command == "SELECT" && (first < 1 || first as usize > entries.len()) {
            return Err(format!("BAD POSITION {first}"));
        }
        if matches!(command, "NEXT" | "PREV") && matches!(self.cursor, Cursor::Unset) {
            return Err("NO CURSOR".into());
        }
        if command == "RESTORE" && self.saved.is_none() {
            return Err("NO SAVE".into());
        }
        let mut output = Vec::new();
        let mut trace = Trace { enabled: self.trace && matches!(command, "INSERT" | "DELETE"), lines: Vec::new() };
        match command {
            "INSERT" => {
                let before = tree.pages.clone();
                let splits = tree.splits;
                let old = tree.upsert(Entry { key: first, value: words[2].into() }, &mut trace);
                let writes = tree.changes(&before).0;
                output.extend(trace.lines);
                output.push(if let Some(value) = old { format!("INSERT {first} UPDATED old={value} writes={writes}") }
                    else { format!("INSERT {first} NEW splits={} height={} writes={writes}", tree.splits - splits, tree.height()) });
            }
            "BULKLOAD" => {
                let before = tree.pages.clone();
                let splits = tree.splits;
                let mut new = 0;
                let mut updated = 0;
                for pair in words[1..].chunks_exact(2) {
                    if tree.upsert(Entry { key: pair[0].parse().unwrap(), value: pair[1].into() }, &mut trace).is_some() {
                        updated += 1;
                    } else {
                        new += 1;
                    }
                }
                output.push(format!("BULKLOAD pairs={} new={new} updated={updated} splits={} height={} writes={}",
                    (words.len() - 1) / 2, tree.splits - splits, tree.height(), tree.changes(&before).0));
            }
            "DELETE" => {
                if let Some((page, position)) = tree.search(first).0 {
                    let value = tree.node(page).entries[position].value.clone();
                    let before = tree.pages.clone();
                    let mut cases = Vec::new();
                    tree.remove_at(tree.root, first, &mut cases, &mut trace);
                    let (writes, frees) = tree.changes(&before);
                    output.extend(trace.lines);
                    output.push(format!("DELETE {first} REMOVED value={value} cases={} height={} writes={writes} frees={frees}",
                        cases.join(","), tree.height()));
                } else {
                    output.push(format!("DELETE {first} NOT FOUND"));
                }
            }
            "DELRANGE" => {
                let before = tree.pages.clone();
                let (merges, borrows) = (tree.merges, tree.borrows);
                let mut removed = 0;
                for entry in entries.iter().filter(|entry| first <= entry.key && entry.key <= second) {
                    tree.remove_at(tree.root, entry.key, &mut Vec::new(), &mut trace);
                    removed += 1;
                }
                let (writes, frees) = tree.changes(&before);
                output.push(format!("DELRANGE {first} {second} removed={removed} merges={} borrows={} height={} writes={writes} frees={frees}",
                    tree.merges - merges, tree.borrows - borrows, tree.height()));
            }
            "GET" => {
                let (found, path) = tree.search(first);
                let result = found.map_or_else(|| "NOT FOUND".into(), |(page, position)| format!("FOUND value={}", tree.node(page).entries[position].value));
                output.push(format!("GET {first} {result} path={}", path.join(" -> ")));
            }
            "RANGE" | "COUNT" => {
                let (found, visits) = tree.scan(first, second);
                let mut result = format!("{command} {first} {second} count={} visited={visits}", found.len());
                if command == "RANGE" {
                    for entry in found {
                        result.push(' ');
                        result.push_str(&entry.to_string());
                    }
                }
                output.push(result);
            }
            "MIN" | "MAX" => {
                let entry = if command == "MIN" { entries.first() } else { entries.last() };
                output.push(format!("{command} {}", entry.map_or_else(|| "EMPTY".into(), ToString::to_string)));
            }
            "FLOOR" | "CEIL" => {
                let entry = if command == "FLOOR" { entries.iter().rev().find(|e| e.key <= first) }
                    else { entries.iter().find(|e| e.key >= first) };
                output.push(format!("{command} {first} {}", entry.map_or_else(|| "NONE".into(), ToString::to_string)));
            }
            "RANK" => output.push(format!("RANK {first} {}", entries.iter().filter(|e| e.key < first).count())),
            "SELECT" => output.push(format!("SELECT {first} {}", entries[first as usize - 1])),
            "SEEK" => {
                let entry = entries.iter().find(|e| e.key >= first);
                self.cursor = entry.map_or(Cursor::End, |e| Cursor::Key(e.key));
                output.push(format!("SEEK {first} {}", entry.map_or_else(|| "END".into(), ToString::to_string)));
            }
            "NEXT" | "PREV" => {
                let entry = match (command, self.cursor) {
                    ("NEXT", Cursor::Key(key)) => entries.iter().find(|e| e.key > key),
                    ("NEXT", Cursor::Begin) => entries.first(),
                    ("PREV", Cursor::Key(key)) => entries.iter().rev().find(|e| e.key < key),
                    ("PREV", Cursor::End) => entries.last(),
                    _ => None,
                };
                let boundary = if command == "NEXT" { Cursor::End } else { Cursor::Begin };
                self.cursor = entry.map_or(boundary, |e| Cursor::Key(e.key));
                output.push(format!("{command} {}", entry.map_or_else(|| if command == "NEXT" { "END".into() } else { "BEGIN".into() }, ToString::to_string)));
            }
            "PRINT" => {
                let mut level = vec![tree.root];
                let mut depth = 0;
                while !level.is_empty() {
                    output.push(format!("LEVEL {depth} {}", level.iter().map(|&page| tree.node(page).notation()).collect::<Vec<_>>().join(" ")));
                    level = level.iter().flat_map(|&page| tree.node(page).children.iter().copied()).collect();
                    depth += 1;
                }
            }
            "PAGES" => {
                for (page, node) in &tree.pages {
                    let children = if node.children.is_empty() { "-".into() }
                        else { node.children.iter().map(ToString::to_string).collect::<Vec<_>>().join(",") };
                    output.push(format!("PAGE {page} {} kids={children}", node.notation()));
                }
            }
            "DUMP" => output.push(format!("DUMP {} {}", tree.degree, tree.dump())),
            "HEIGHT" => output.push(format!("HEIGHT {}", tree.height())),
            "STATS" => {
                let nodes = tree.pages.len();
                let leaves = tree.pages.values().filter(|node| node.children.is_empty()).count();
                output.push(format!("STATS t={} nodes={nodes} leaves={leaves} keys={} fill={}% splits={} merges={} borrows={}",
                    tree.degree, entries.len(), 100 * entries.len() / ((2 * tree.degree - 1) * nodes), tree.splits, tree.merges, tree.borrows));
            }
            "VERIFY" => output.push(tree.violation().map_or_else(|| "VERIFY OK".into(), |error| format!("VERIFY FAIL {error}"))),
            "REBUILD" => {
                *tree = Tree::new(tree.degree);
                for entry in &entries {
                    tree.upsert(entry.clone(), &mut trace);
                }
                output.push(format!("REBUILD entries={} keys={} nodes={} splits={} height={}",
                    entries.len(), tree.entries().len(), tree.pages.len(), tree.splits, tree.height()));
            }
            "COMPACT" => {
                let nodes = tree.pages.len();
                tree.compact();
                output.push(format!("COMPACT nodes={nodes}->{} height={}", tree.pages.len(), tree.height()));
            }
            "SAVE" => {
                self.saved = Some(tree.clone());
                output.push(format!("SAVE nodes={} keys={} {}", tree.pages.len(), entries.len(), tree.status()));
            }
            "RESTORE" => {
                *tree = self.saved.as_ref().unwrap().clone();
                output.push(format!("RESTORE nodes={} keys={} {}", tree.pages.len(), tree.entries().len(), tree.status()));
            }
            _ => unreachable!(),
        }
        Ok(output)
    }
}

fn main() {
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap().unwrap().parse().unwrap();
    let mut workbench = Workbench::default();
    let mut output = io::BufWriter::new(io::stdout().lock());
    for line in lines.take(count) {
        match workbench.process(&line.unwrap()) {
            Ok(lines) => {
                for line in lines {
                    writeln!(output, "{line}").unwrap();
                }
            }
            Err(error) => writeln!(output, "ERROR {error}").unwrap(),
        }
    }
}
