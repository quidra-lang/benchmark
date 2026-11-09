use std::cell::RefCell;
use std::cmp::Reverse;
use std::collections::BTreeMap;
use std::fmt::Display;
use std::io::{self, BufRead, Write};
use std::rc::{Rc, Weak};

type NodeRef = Rc<RefCell<Node>>;
type Lines = Vec<Rc<str>>;

#[derive(Clone)]
enum Data {
    Directory(BTreeMap<String, NodeRef>),
    File(Lines),
    Link(String),
}
struct Node {
    inode: usize,
    modified: usize,
    parent: Weak<RefCell<Node>>,
    name: String,
    data: Data,
}
impl Node {
    fn tag(&self) -> char {
        match &self.data { Data::Directory(_) => 'd', Data::File(_) => 'f', Data::Link(_) => 'l' }
    }
    fn size(&self) -> u64 {
        match &self.data {
            Data::Directory(entries) => entries.len() as u64,
            Data::File(lines) => lines.iter().map(|line| line.len() as u64 + 1).sum(),
            Data::Link(target) => target.len() as u64,
        }
    }
    fn links(&self) -> u64 {
        match &self.data {
            Data::Directory(entries) => 2 + entries.values().filter(|node| is_directory(node)).count() as u64,
            _ => 1,
        }
    }
}
fn is_directory(node: &NodeRef) -> bool { matches!(&node.borrow().data, Data::Directory(_)) }
fn parent(node: &NodeRef) -> NodeRef { node.borrow().parent.upgrade().unwrap() }
fn children(node: &NodeRef) -> Vec<(String, NodeRef)> {
    match &node.borrow().data {
        Data::Directory(entries) => entries.iter().map(|(name, child)| (name.clone(), child.clone())).collect(),
        _ => Vec::new(),
    }
}
fn child(node: &NodeRef, name: &str) -> Option<NodeRef> {
    match &node.borrow().data { Data::Directory(entries) => entries.get(name).cloned(), _ => None }
}
fn last(path: &str) -> &str { path.rsplit('/').next().unwrap() }
fn join(path: &str, name: &str) -> String {
    if path == "/" { format!("/{name}") } else { format!("{path}/{name}") }
}
fn invalid_source(path: &str) -> bool { matches!(last(path), "" | "." | "..") }

#[derive(Clone, Copy)]
enum Failure { Missing, NotDirectory, TooManyLinks }
struct ResolutionError {
    failure: Failure,
    creation: Option<(NodeRef, String)>,
}
impl ResolutionError {
    fn new(failure: Failure) -> Self { Self { failure, creation: None } }
    fn reason(&self) -> &'static str {
        match self.failure {
            Failure::Missing => "No such file or directory",
            Failure::NotDirectory => "Not a directory",
            Failure::TooManyLinks => "Too many levels of symbolic links",
        }
    }
}
struct Output<'a> {
    terminal: &'a mut dyn Write,
    direct: bool,
    lines: Lines,
}
impl Output<'_> {
    fn emit(&mut self, line: impl Into<Rc<str>>) {
        let line = line.into();
        if self.direct { writeln!(self.terminal, "{line}").unwrap(); }
        else { self.lines.push(line); }
    }
    fn error(&mut self, message: impl Display) { writeln!(self.terminal, "{message}").unwrap(); }
}
struct Options<'a> {
    flags: [bool; 128],
    paths: &'a [&'a str],
}
impl Options<'_> {
    fn has(&self, option: u8) -> bool { self.flags[option as usize] }
}
fn options<'a>(arguments: &'a [&'a str]) -> Options<'a> {
    let mut flags = [false; 128];
    let mut position = 0;
    while position < arguments.len() && arguments[position].starts_with('-') {
        for flag in arguments[position][1..].bytes() { flags[flag as usize] = true; }
        position += 1;
    }
    Options { flags, paths: &arguments[position..] }
}

struct Shell {
    root: NodeRef,
    current: NodeRef,
    previous: Option<String>,
    clock: usize,
    next_inode: usize,
}
impl Shell {
    fn new() -> Self {
        let root = Rc::new_cyclic(|parent| RefCell::new(Node {
            inode: 1, modified: 0, parent: parent.clone(), name: String::new(), data: Data::Directory(BTreeMap::new()),
        }));
        Self { current: root.clone(), root, previous: None, clock: 0, next_inode: 2 }
    }
    fn absolute(&self, node: &NodeRef) -> String {
        let mut node = node.clone();
        let mut names = Vec::new();
        while !Rc::ptr_eq(&node, &self.root) {
            names.push(node.borrow().name.clone());
            node = parent(&node);
        }
        names.reverse();
        format!("/{}", names.join("/"))
    }
    fn descendant(&self, node: &NodeRef, ancestor: &NodeRef) -> bool {
        let mut node = node.clone();
        loop {
            if Rc::ptr_eq(&node, ancestor) { return true; }
            if Rc::ptr_eq(&node, &self.root) { return false; }
            node = parent(&node);
        }
    }
    fn add(&self, directory: &NodeRef, name: &str, node: NodeRef) {
        {
            let mut item = node.borrow_mut();
            item.name = name.to_owned();
            item.parent = Rc::downgrade(directory);
        }
        let mut directory = directory.borrow_mut();
        if let Data::Directory(entries) = &mut directory.data { entries.insert(name.to_owned(), node); }
        directory.modified = self.clock;
    }
    fn create(&mut self, directory: &NodeRef, name: &str, data: Data) -> NodeRef {
        let node = Rc::new(RefCell::new(Node {
            inode: self.next_inode, modified: self.clock, parent: Weak::new(), name: String::new(), data,
        }));
        self.next_inode += 1;
        self.add(directory, name, node.clone());
        node
    }
    fn detach(&self, node: &NodeRef) {
        let directory = parent(node);
        let name = node.borrow().name.clone();
        let mut directory = directory.borrow_mut();
        if let Data::Directory(entries) = &mut directory.data { entries.remove(&name); }
        directory.modified = self.clock;
    }
    fn write(&self, file: &NodeRef, lines: Lines, append: bool) {
        let mut file = file.borrow_mut();
        if let Data::File(content) = &mut file.data {
            if append { content.extend(lines); } else { *content = lines; }
        }
        file.modified = self.clock;
    }
    fn walk(&mut self, path: &str, base: &NodeRef, follow: bool, original: bool,
            parents: bool, expansions: &mut usize) -> Result<NodeRef, ResolutionError> {
        let mut node = if path.starts_with('/') { self.root.clone() } else { base.clone() };
        let mut parts = path.split('/').filter(|part| !part.is_empty()).peekable();
        while let Some(name) = parts.next() {
            if !is_directory(&node) { return Err(ResolutionError::new(Failure::NotDirectory)); }
            if name == "." { continue; }
            if name == ".." { node = parent(&node); continue; }
            let last = parts.peek().is_none();
            let mut next = match child(&node, name) {
                Some(next) => next,
                None if original && parents && !last => self.create(&node, name, Data::Directory(BTreeMap::new())),
                None => return Err(ResolutionError {
                    failure: Failure::Missing,
                    creation: (original && last).then(|| (node.clone(), name.to_owned())),
                }),
            };
            let target = match &next.borrow().data { Data::Link(target) => Some(target.clone()), _ => None };
            if let Some(target) = target.filter(|_| !last || follow) {
                *expansions += 1;
                if *expansions > 8 { return Err(ResolutionError::new(Failure::TooManyLinks)); }
                next = self.walk(&target, &node, true, false, false, expansions)?;
            }
            node = next;
        }
        Ok(node)
    }
    fn resolve(&mut self, path: &str, follow: bool, parents: bool) -> Result<NodeRef, ResolutionError> {
        let current = self.current.clone();
        self.walk(path, &current, follow, true, parents, &mut 0)
    }
    fn clone_node(&mut self, source: &NodeRef, directory: &NodeRef, name: &str) {
        let data = source.borrow().data.clone();
        match data {
            Data::Directory(entries) => {
                let copy = self.create(directory, name, Data::Directory(BTreeMap::new()));
                for (name, node) in entries { self.clone_node(&node, &copy, &name); }
            }
            data => { self.create(directory, name, data); }
        }
    }
    fn move_one(&mut self, source_path: &str, destination: &str, output: &mut Output<'_>) {
        if invalid_source(source_path) {
            output.error(format!("mv: cannot move '{source_path}' to '{destination}': Invalid argument"));
            return;
        }
        let source = match self.resolve(source_path, false, false) {
            Ok(source) => source,
            Err(error) => { output.error(format!("mv: cannot stat '{source_path}': {}", error.reason())); return; }
        };
        let destination_node = self.resolve(destination, true, false).ok().filter(is_directory);
        let (directory, name, target) = if let Some(directory) = destination_node {
            (directory, last(source_path).to_owned(), join(destination, last(source_path)))
        } else {
            match self.resolve(destination, false, false) {
                Ok(node) => {
                    let name = node.borrow().name.clone();
                    (parent(&node), name, destination.to_owned())
                }
                Err(error) => {
                    if let Some((directory, name)) = error.creation.as_ref() {
                        (directory.clone(), name.clone(), destination.to_owned())
                    } else {
                        output.error(format!("mv: cannot move '{source_path}' to '{destination}': {}", error.reason()));
                        return;
                    }
                }
            }
        };
        let existing = child(&directory, &name);
        let existing_directory = existing.as_ref().is_some_and(is_directory);
        if is_directory(&source) && self.descendant(&directory, &source) {
            output.error(format!("mv: cannot move '{source_path}' to a subdirectory of itself, '{target}'"));
        } else if existing.as_ref().is_some_and(|node| Rc::ptr_eq(node, &source)) {
            output.error(format!("mv: '{source_path}' and '{target}' are the same file"));
        } else if existing.is_some() && is_directory(&source) && !existing_directory {
            output.error(format!("mv: cannot overwrite non-directory '{target}' with directory '{source_path}'"));
        } else if !is_directory(&source) && existing_directory {
            output.error(format!("mv: cannot overwrite directory '{target}' with non-directory '{source_path}'"));
        } else if existing_directory && !children(existing.as_ref().unwrap()).is_empty() {
            output.error(format!("mv: cannot move '{source_path}' to '{target}': Directory not empty"));
        } else if existing.as_ref().is_some_and(|node| Rc::ptr_eq(node, &self.current)) {
            output.error(format!("mv: cannot move '{source_path}' to '{target}': Device or resource busy"));
        } else {
            if let Some(node) = existing { self.detach(&node); }
            self.detach(&source);
            self.add(&directory, &name, source);
        }
    }
    fn copy_one(&mut self, source_path: &str, destination: &str, recursive: bool, output: &mut Output<'_>) {
        if invalid_source(source_path) {
            output.error(format!("cp: cannot copy '{source_path}' to '{destination}': Invalid argument"));
            return;
        }
        let source = match self.resolve(source_path, true, false) {
            Ok(source) => source,
            Err(error) => { output.error(format!("cp: cannot stat '{source_path}': {}", error.reason())); return; }
        };
        if is_directory(&source) && !recursive {
            output.error(format!("cp: -r not specified; omitting directory '{source_path}'"));
            return;
        }
        let target = match self.resolve(destination, true, false) {
            Ok(node) if is_directory(&node) => join(destination, last(source_path)),
            Ok(_) => destination.to_owned(),
            Err(error) if error.creation.is_some() => destination.to_owned(),
            Err(error) => { output.error(format!("cp: cannot copy '{source_path}' to '{destination}': {}", error.reason())); return; }
        };
        match self.resolve(&target, !is_directory(&source), false) {
            Ok(_) if is_directory(&source) => output.error(format!("cp: cannot copy '{source_path}' to '{target}': File exists")),
            Ok(node) if Rc::ptr_eq(&node, &source) => output.error(format!("cp: '{source_path}' and '{target}' are the same file")),
            Ok(node) if is_directory(&node) => output.error(format!("cp: cannot overwrite directory '{target}' with non-directory '{source_path}'")),
            Ok(node) => {
                let Data::File(lines) = &source.borrow().data else { unreachable!() };
                self.write(&node, lines.clone(), false);
            }
            Err(error) => {
                if let Some((directory, name)) = error.creation.as_ref() {
                    if is_directory(&source) && self.descendant(directory, &source) {
                        output.error(format!("cp: cannot copy a directory, '{source_path}', into itself, '{target}'"));
                    } else { self.clone_node(&source, directory, name); }
                } else { output.error(format!("cp: cannot copy '{source_path}' to '{target}': {}", error.reason())); }
            }
        }
    }
    fn listing(&mut self, opts: &Options<'_>, output: &mut Output<'_>) {
        let paths = if opts.paths.is_empty() { &["."][..] } else { opts.paths };
        for &path in paths {
            let node = match self.resolve(path, !opts.has(b'l'), false) {
                Ok(node) => node,
                Err(error) => { output.error(format!("ls: cannot access '{path}': {}", error.reason())); continue; }
            };
            let mut entries = Vec::new();
            if is_directory(&node) {
                if paths.len() > 1 { output.emit(format!("{path}:")); }
                if opts.has(b'a') { entries.push((".".to_owned(), node.clone())); entries.push(("..".to_owned(), parent(&node))); }
                entries.extend(children(&node).into_iter().filter(|(name, _)| opts.has(b'a') || !name.starts_with('.')));
                if opts.has(b't') { entries.sort_by_key(|(_, node)| Reverse(node.borrow().modified)); }
                if opts.has(b'r') { entries.reverse(); }
            } else { entries.push((path.to_owned(), node)); }
            let mut widths = [1_usize; 3];
            for (_, node) in &entries {
                let node = node.borrow();
                for (i, value) in [node.links(), node.size(), node.modified as u64].iter().enumerate() {
                    widths[i] = widths[i].max(value.to_string().len());
                }
            }
            for (name, node) in entries {
                if !opts.has(b'l') { output.emit(name); continue; }
                let node = node.borrow();
                let kind = if node.tag() == 'f' { '-' } else { node.tag() };
                let suffix = match &node.data { Data::Link(target) => format!(" -> {target}"), _ => String::new() };
                output.emit(format!("{kind} {:>lw$} {:>sw$} {:>tw$} {name}{suffix}", node.links(), node.size(), node.modified,
                                    lw = widths[0], sw = widths[1], tw = widths[2]));
            }
        }
    }
    fn find(&mut self, arguments: &[&str], output: &mut Output<'_>) {
        let mut position = usize::from(arguments.first().is_some_and(|path| !path.starts_with('-')));
        let path = if position == 1 { arguments[0] } else { "." };
        let mut pattern = None;
        let mut kind = None;
        let mut limit = usize::MAX;
        while position < arguments.len() {
            match arguments[position] {
                "-name" => pattern = Some(arguments[position + 1]),
                "-type" => kind = arguments[position + 1].chars().next(),
                _ => limit = arguments[position + 1].parse().unwrap(),
            }
            position += 2;
        }
        match self.resolve(path, true, false) {
            Err(error) => output.error(format!("find: '{path}': {}", error.reason())),
            Ok(node) => walk_nodes(&node, path, 0, limit, &mut |node, display, depth| {
                let node = node.borrow();
                let name = if depth == 0 { if path == "/" { "/" } else { last(path) } } else { &node.name };
                if pattern.is_none_or(|pattern| glob_matches(pattern, name)) && kind.is_none_or(|kind| kind == node.tag()) {
                    output.emit(display);
                }
            }),
        }
    }
    fn disk_usage(&mut self, opts: &Options<'_>, output: &mut Output<'_>) {
        fn report(node: &NodeRef, path: &str, show: bool, opts: &Options<'_>, output: &mut Output<'_>) -> u64 {
            let mut usage = if is_directory(node) { 0 } else { node.borrow().size() };
            for (name, child) in children(node) {
                usage += report(&child, &join(path, &name), show && !opts.has(b's') && (is_directory(&child) || opts.has(b'a')), opts, output);
            }
            if show { output.emit(format!("{usage} {path}")); }
            usage
        }
        let paths = if opts.paths.is_empty() { &["."][..] } else { opts.paths };
        for &path in paths {
            match self.resolve(path, true, false) {
                Ok(node) => { report(&node, path, true, opts, output); }
                Err(error) => output.error(format!("du: cannot access '{path}': {}", error.reason())),
            }
        }
    }
    fn tree(&mut self, opts: &Options<'_>, output: &mut Output<'_>) {
        fn draw(node: &NodeRef, prefix: &str, all: bool, counts: &mut [usize; 2], output: &mut Output<'_>) {
            let entries: Vec<_> = children(node).into_iter().filter(|(name, _)| all || !name.starts_with('.')).collect();
            for (index, (name, child)) in entries.iter().enumerate() {
                let last = index + 1 == entries.len();
                let suffix = match &child.borrow().data { Data::Link(target) => format!(" -> {target}"), _ => String::new() };
                output.emit(format!("{prefix}{}{name}{suffix}", if last { "`-- " } else { "|-- " }));
                if is_directory(child) {
                    counts[0] += 1;
                    draw(child, &format!("{prefix}{}", if last { "    " } else { "|   " }), all, counts, output);
                } else { counts[1] += 1; }
            }
        }
        let path = opts.paths.first().copied().unwrap_or(".");
        match self.resolve(path, true, false) {
            Err(error) => output.error(format!("tree: {path}: {}", error.reason())),
            Ok(node) if !is_directory(&node) => output.error(format!("tree: {path}: Not a directory")),
            Ok(node) => {
                output.emit(path);
                let mut counts = [0; 2];
                draw(&node, "", opts.has(b'a'), &mut counts, output);
                output.emit(format!("{} {}, {} {}", counts[0], if counts[0] == 1 { "directory" } else { "directories" },
                                    counts[1], if counts[1] == 1 { "file" } else { "files" }));
            }
        }
    }
    fn read_inputs(&mut self, command: &str, paths: &[&str], input: &[Rc<str>], output: &mut Output<'_>,
                   mut consume: impl FnMut(&[Rc<str>], Option<&str>, &mut Output<'_>)) {
        if paths.is_empty() { consume(input, None, output); return; }
        for &path in paths {
            match self.resolve(path, true, false) {
                Err(error) => output.error(format!("{command}: {path}: {}", error.reason())),
                Ok(node) => {
                    let node = node.borrow();
                    match &node.data {
                        Data::File(lines) => consume(lines, Some(path), output),
                        Data::Directory(_) => output.error(format!("{command}: {path}: Is a directory")),
                        Data::Link(_) => unreachable!(),
                    }
                }
            }
        }
    }
    fn text_command(&mut self, command: &str, arguments: &[&str], input: &[Rc<str>], output: &mut Output<'_>) {
        let opts = options(arguments);
        if command == "grep" {
            let pattern = opts.paths[0];
            let paths = &opts.paths[1..];
            let named = paths.len() > 1 || opts.has(b'r');
            let consume = |lines: &[Rc<str>], name: Option<&str>, output: &mut Output<'_>| {
                let prefix = if named { format!("{}:", name.unwrap()) } else { String::new() };
                let mut selected = 0_u64;
                for (i, line) in lines.iter().enumerate() {
                    let matches = if opts.has(b'i') {
                        line.as_bytes().windows(pattern.len()).any(|part| part.eq_ignore_ascii_case(pattern.as_bytes()))
                    } else { line.contains(pattern) };
                    if matches == opts.has(b'v') { continue; }
                    selected += 1;
                    if !opts.has(b'c') {
                        if opts.has(b'n') { output.emit(format!("{prefix}{}:{line}", i + 1)); }
                        else if named { output.emit(format!("{prefix}{line}")); }
                        else { output.emit(line.clone()); }
                    }
                }
                if opts.has(b'c') { output.emit(format!("{prefix}{selected}")); }
            };
            if !opts.has(b'r') { self.read_inputs(command, paths, input, output, consume); }
            else {
                let paths = if paths.is_empty() { &["."][..] } else { paths };
                for &path in paths {
                    match self.resolve(path, true, false) {
                        Err(error) => output.error(format!("grep: {path}: {}", error.reason())),
                        Ok(node) => walk_nodes(&node, path, 0, usize::MAX, &mut |node, display, _| {
                            if let Data::File(lines) = &node.borrow().data { consume(lines, Some(display), output); }
                        }),
                    }
                }
            }
        } else if command == "sort" {
            let mut lines = Vec::new();
            self.read_inputs(command, opts.paths, input, output, |part, _, _| lines.extend_from_slice(part));
            lines.sort_by(|a, b| {
                if opts.has(b'n') { numeric_prefix(a).cmp(&numeric_prefix(b)).then_with(|| a.cmp(b)) }
                else { a.cmp(b) }
            });
            if opts.has(b'r') { lines.reverse(); }
            for line in lines { output.emit(line); }
        } else if command == "wc" {
            let mut totals = [0_u64; 3];
            let report = |counts: &[u64; 3], name: Option<&str>, output: &mut Output<'_>| {
                let all = !opts.has(b'l') && !opts.has(b'w') && !opts.has(b'c');
                let values: Vec<_> = counts.iter().zip(b"lwc").filter(|(_, flag)| all || opts.has(**flag)).map(|(n, _)| n.to_string()).collect();
                output.emit(format!("{}{}", values.join(" "), name.map_or(String::new(), |name| format!(" {name}"))));
            };
            self.read_inputs(command, opts.paths, input, output, |lines, name, output| {
                let mut counts = [lines.len() as u64, 0, 0];
                for line in lines {
                    counts[2] += line.len() as u64 + 1;
                    let mut inside = false;
                    for character in line.bytes() {
                        if character != b' ' && !inside { counts[1] += 1; }
                        inside = character != b' ';
                    }
                }
                for i in 0..3 { totals[i] += counts[i]; }
                report(&counts, name, output);
            });
            if opts.paths.len() > 1 { report(&totals, Some("total"), output); }
        } else if command == "head" || command == "tail" {
            let offset = if arguments.first() == Some(&"-n") { 2 } else { 0 };
            let count_text = if offset == 0 { "10" } else { arguments[1] };
            let special = count_text.starts_with('-') || count_text.starts_with('+');
            let count: usize = count_text[usize::from(special)..].parse().unwrap();
            self.read_inputs(command, &arguments[offset..], input, output, |lines, _, output| {
                let mut first = 0;
                let mut end = lines.len();
                if command == "head" { end = if special { end.saturating_sub(count) } else { end.min(count) }; }
                else { first = if special { count.saturating_sub(1).min(end) } else { end.saturating_sub(count) }; }
                for line in &lines[first..end] { output.emit(line.clone()); }
            });
        } else {
            self.read_inputs(command, opts.paths, input, output, |lines, _, output| {
                if command == "cat" { for line in lines { output.emit(line.clone()); } }
                else {
                    let mut first = 0;
                    while first < lines.len() {
                        let mut end = first + 1;
                        while end < lines.len() && lines[first] == lines[end] { end += 1; }
                        if opts.has(b'c') { output.emit(format!("{} {}", end - first, lines[first])); }
                        else { output.emit(lines[first].clone()); }
                        first = end;
                    }
                }
            });
        }
    }
    fn execute(&mut self, text: &str, input: &[Rc<str>], output: &mut Output<'_>) {
        let words: Vec<_> = text.split_whitespace().collect();
        let command = words[0];
        let arguments = &words[1..];
        let opts = options(arguments);
        match command {
            "pwd" => output.emit(self.absolute(&self.current)),
            "echo" => output.emit(&text[5..]),
            "cd" => {
                let back = arguments.first() == Some(&"-");
                let path = if back {
                    let Some(previous) = &self.previous else { output.error("cd: OLDPWD not set"); return; };
                    previous.clone()
                } else { arguments.first().copied().unwrap_or("/").to_owned() };
                match self.resolve(&path, true, false) {
                    Err(error) => output.error(format!("cd: {path}: {}", error.reason())),
                    Ok(node) if !is_directory(&node) => output.error(format!("cd: {path}: Not a directory")),
                    Ok(node) => {
                        self.previous = Some(self.absolute(&self.current));
                        self.current = node;
                        if back { output.emit(self.absolute(&self.current)); }
                    }
                }
            }
            "mkdir" => for &path in opts.paths {
                match self.resolve(path, false, opts.has(b'p')) {
                    Err(error) => {
                        if let Some((directory, name)) = error.creation.as_ref() {
                            self.create(directory, name, Data::Directory(BTreeMap::new()));
                        } else { output.error(format!("mkdir: cannot create directory '{path}': {}", error.reason())); }
                    }
                    Ok(_) => {
                        if !opts.has(b'p') || !self.resolve(path, true, false).is_ok_and(|node| is_directory(&node)) {
                            output.error(format!("mkdir: cannot create directory '{path}': File exists"));
                        }
                    }
                }
            },
            "touch" => for &path in arguments {
                match self.resolve(path, true, false) {
                    Ok(node) => node.borrow_mut().modified = self.clock,
                    Err(error) => {
                        if let Some((directory, name)) = error.creation.as_ref() { self.create(directory, name, Data::File(Vec::new())); }
                        else { output.error(format!("touch: cannot touch '{path}': {}", error.reason())); }
                    }
                }
            },
            "ls" => self.listing(&opts, output),
            "stat" => for &path in arguments {
                match self.resolve(path, false, false) {
                    Err(error) => output.error(format!("stat: cannot stat '{path}': {}", error.reason())),
                    Ok(node) => {
                        let node = node.borrow();
                        let kind = match &node.data {
                            Data::Directory(_) => "directory", Data::Link(_) => "symbolic link",
                            Data::File(lines) => if lines.is_empty() { "regular empty file" } else { "regular file" },
                        };
                        output.emit(format!("{path}: {kind}, size {}, inode {}, links {}, modified {}", node.size(), node.inode, node.links(), node.modified));
                    }
                }
            },
            "rm" | "rmdir" => for &path in opts.paths {
                let directory_only = command == "rmdir";
                let dot = matches!(last(path), "." | "..");
                if dot && !directory_only {
                    output.error(format!("rm: refusing to remove '.' or '..' directory: skipping '{path}'"));
                    continue;
                }
                let problem = if dot { Some("Invalid argument") }
                else {
                    match self.resolve(path, false, false) {
                        Err(error) if !directory_only && opts.has(b'f') && matches!(error.failure, Failure::Missing) => None,
                        Err(error) => Some(error.reason()),
                        Ok(node) if directory_only && !is_directory(&node) => Some("Not a directory"),
                        Ok(node) if !directory_only && is_directory(&node) && !opts.has(b'r') => Some("Is a directory"),
                        Ok(node) if self.descendant(&self.current, &node) => Some("Device or resource busy"),
                        Ok(node) if directory_only && !children(&node).is_empty() => Some("Directory not empty"),
                        Ok(node) => { self.detach(&node); None }
                    }
                };
                if let Some(reason) = problem {
                    if directory_only { output.error(format!("rmdir: failed to remove '{path}': {reason}")); }
                    else { output.error(format!("rm: cannot remove '{path}': {reason}")); }
                }
            },
            "mv" | "cp" => {
                let destination = opts.paths.last().unwrap();
                if opts.paths.len() > 2 && !self.resolve(destination, true, false).is_ok_and(|node| is_directory(&node)) {
                    output.error(format!("{command}: target '{destination}' is not a directory"));
                    return;
                }
                for &source in &opts.paths[..opts.paths.len() - 1] {
                    if command == "mv" { self.move_one(source, destination, output); }
                    else { self.copy_one(source, destination, opts.has(b'r'), output); }
                }
            }
            "ln" => {
                let path = arguments[2];
                match self.resolve(path, false, false) {
                    Ok(_) => output.error(format!("ln: failed to create symbolic link '{path}': File exists")),
                    Err(error) => {
                        if let Some((directory, name)) = error.creation.as_ref() { self.create(directory, name, Data::Link(arguments[1].to_owned())); }
                        else { output.error(format!("ln: failed to create symbolic link '{path}': {}", error.reason())); }
                    }
                }
            }
            "readlink" | "realpath" => {
                let path = arguments[0];
                match self.resolve(path, command == "realpath", false) {
                    Err(error) => output.error(format!("{command}: {path}: {}", error.reason())),
                    Ok(node) if command == "realpath" => output.emit(self.absolute(&node)),
                    Ok(node) => {
                        let node = node.borrow();
                        if let Data::Link(target) = &node.data { output.emit(target.as_str()); }
                        else { output.error(format!("readlink: {path}: Invalid argument")); }
                    }
                }
            }
            "find" => self.find(arguments, output),
            "du" => self.disk_usage(&opts, output),
            "tree" => self.tree(&opts, output),
            "cat" | "wc" | "head" | "tail" | "grep" | "sort" | "uniq" => self.text_command(command, arguments, input, output),
            _ => output.error(format!("{command}: command not found")),
        }
    }
    fn process(&mut self, line: &str, terminal: &mut dyn Write) {
        self.clock += 1;
        writeln!(terminal, "{}$ {line}", self.absolute(&self.current)).unwrap();
        let marker = line.find(" >> ").map(|index| (index, true, 4)).or_else(|| line.find(" > ").map(|index| (index, false, 3)));
        let mut pipeline = line;
        let mut redirect = None;
        if let Some((index, append, length)) = marker {
            pipeline = &line[..index];
            let path = &line[index + length..];
            match self.resolve(path, true, false) {
                Ok(node) if is_directory(&node) => { writeln!(terminal, "sh: {path}: Is a directory").unwrap(); return; }
                Ok(node) => {
                    if !append { self.write(&node, Vec::new(), false); }
                    redirect = Some(node);
                }
                Err(error) => {
                    if let Some((directory, name)) = error.creation.as_ref() { redirect = Some(self.create(directory, name, Data::File(Vec::new()))); }
                    else { writeln!(terminal, "sh: {path}: {}", error.reason()).unwrap(); return; }
                }
            }
        }
        let commands: Vec<_> = pipeline.split(" | ").collect();
        let mut input = Vec::new();
        for (i, command) in commands.iter().enumerate() {
            let mut output = Output { terminal: &mut *terminal, direct: i + 1 == commands.len() && redirect.is_none(), lines: Vec::new() };
            self.execute(command, &input, &mut output);
            input = output.lines;
        }
        if let Some(file) = redirect { if !input.is_empty() { self.write(&file, input, true); } }
    }
}

fn walk_nodes(node: &NodeRef, path: &str, depth: usize, limit: usize, visit: &mut impl FnMut(&NodeRef, &str, usize)) {
    visit(node, path, depth);
    if depth < limit {
        for (name, child) in children(node) { walk_nodes(&child, &join(path, &name), depth + 1, limit, visit); }
    }
}
fn glob_matches(pattern: &str, text: &str) -> bool {
    let mut previous = vec![false; text.len() + 1];
    previous[0] = true;
    for character in pattern.bytes() {
        let mut next = vec![false; previous.len()];
        next[0] = character == b'*' && previous[0];
        for (i, byte) in text.bytes().enumerate() {
            next[i + 1] = if character == b'*' { previous[i + 1] || next[i] }
                          else { previous[i] && (character == b'?' || character == byte) };
        }
        previous = next;
    }
    previous[text.len()]
}
fn numeric_prefix(text: &str) -> i64 {
    let negative = text.starts_with('-');
    let mut value = 0;
    for digit in text.bytes().skip(usize::from(negative)).take_while(u8::is_ascii_digit) { value = value * 10 + i64::from(digit - b'0'); }
    if negative { -value } else { value }
}
fn main() {
    let mut shell = Shell::new();
    let mut output = io::BufWriter::new(io::stdout().lock());
    for line in io::stdin().lock().lines() {
        let line = line.unwrap();
        if line == "exit" { break; }
        shell.process(&line, &mut output);
    }
}
