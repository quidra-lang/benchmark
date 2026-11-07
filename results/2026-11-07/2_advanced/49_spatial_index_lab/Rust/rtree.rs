#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Bounds(pub i64, pub i64, pub i64, pub i64);

impl Bounds {
    pub fn area(self) -> i64 {
        (self.2 - self.0) * (self.3 - self.1)
    }

    pub fn mbr(self, other: Self) -> Self {
        Self(self.0.min(other.0), self.1.min(other.1), self.2.max(other.2), self.3.max(other.3))
    }

    pub fn enlargement(self, other: Self) -> i64 {
        self.mbr(other).area() - self.area()
    }

    pub fn intersects(self, b: Self) -> bool {
        self.0 <= b.2 && b.0 <= self.2 && self.1 <= b.3 && b.1 <= self.3
    }

    pub fn contains(self, b: Self) -> bool {
        self.0 <= b.0 && b.2 <= self.2 && self.1 <= b.1 && b.3 <= self.3
    }

    pub fn overlap(self, b: Self) -> i64 {
        let width = self.2.min(b.2) - self.0.max(b.0);
        let height = self.3.min(b.3) - self.1.max(b.1);
        if width > 0 && height > 0 { width * height } else { 0 }
    }

    pub fn distance(self, x: i64, y: i64) -> i64 {
        let dx = if x < self.0 { self.0 - x } else if x > self.2 { x - self.2 } else { 0 };
        let dy = if y < self.1 { self.1 - y } else if y > self.3 { y - self.3 } else { 0 };
        dx * dx + dy * dy
    }

    pub fn text(self) -> String {
        format!("{} {} {} {}", self.0, self.1, self.2, self.3)
    }
}

#[derive(Clone, Copy)]
pub enum Target {
    Object(i64),
    Child(usize),
}

#[derive(Clone)]
pub struct Entry {
    pub bounds: Bounds,
    pub target: Target,
}

pub struct Node {
    pub level: usize,
    pub entries: Vec<Entry>,
}

pub struct Tree {
    pub nodes: Vec<Node>,
    pub root: usize,
    pub maximum: usize,
    pub minimum: usize,
}

impl Tree {
    pub fn new(maximum: usize, minimum: usize) -> Self {
        Self { nodes: vec![Node { level: 0, entries: Vec::new() }], root: 0, maximum, minimum }
    }

    pub fn bounds(&self, node: usize) -> Bounds {
        self.nodes[node].entries.iter().map(|e| e.bounds).reduce(Bounds::mbr).unwrap()
    }

    fn child(entry: &Entry) -> usize {
        if let Target::Child(child) = entry.target { child } else { unreachable!() }
    }

    fn split(&mut self, node: usize) -> usize {
        let entries = std::mem::take(&mut self.nodes[node].entries);
        let mut seeds = (0, 1);
        let mut maximum = i64::MIN;
        for i in 0..entries.len() {
            for j in i + 1..entries.len() {
                let waste = entries[i].bounds.mbr(entries[j].bounds).area() - entries[i].bounds.area() - entries[j].bounds.area();
                if waste > maximum { maximum = waste; seeds = (i, j); }
            }
        }
        let mut groups = [vec![entries[seeds.0].clone()], vec![entries[seeds.1].clone()]];
        let mut boxes = [entries[seeds.0].bounds, entries[seeds.1].bounds];
        let mut rest: Vec<Entry> = entries.into_iter().enumerate().filter(|(i, _)| *i != seeds.0 && *i != seeds.1).map(|(_, e)| e).collect();
        while !rest.is_empty() {
            if groups[0].len() + rest.len() == self.minimum {
                groups[0].extend(rest);
                break;
            }
            if groups[1].len() + rest.len() == self.minimum {
                groups[1].extend(rest);
                break;
            }
            let mut selected = 0;
            let mut difference = -1;
            for (i, entry) in rest.iter().enumerate() {
                let delta = (boxes[0].enlargement(entry.bounds) - boxes[1].enlargement(entry.bounds)).abs();
                if delta > difference { selected = i; difference = delta; }
            }
            let entry = rest.remove(selected);
            let key = |j: usize| (boxes[j].enlargement(entry.bounds), boxes[j].area(), groups[j].len(), j);
            let group = if key(0) <= key(1) { 0 } else { 1 };
            boxes[group] = boxes[group].mbr(entry.bounds);
            groups[group].push(entry);
        }
        let [left, right] = groups;
        self.nodes[node].entries = left;
        let index = self.nodes.len();
        self.nodes.push(Node { level: self.nodes[node].level, entries: right });
        index
    }

    fn insert_at(&mut self, node: usize, entry: Entry, level: usize) -> Option<usize> {
        if self.nodes[node].level == level {
            self.nodes[node].entries.push(entry);
        } else {
            let index = (0..self.nodes[node].entries.len()).min_by_key(|&i| {
                let b = self.nodes[node].entries[i].bounds;
                (b.enlargement(entry.bounds), b.area(), i)
            }).unwrap();
            let child = Self::child(&self.nodes[node].entries[index]);
            let split = self.insert_at(child, entry, level);
            self.nodes[node].entries[index].bounds = self.bounds(child);
            if let Some(new) = split {
                let bounds = self.bounds(new);
                self.nodes[node].entries.push(Entry { bounds, target: Target::Child(new) });
            }
        }
        if self.nodes[node].entries.len() > self.maximum { Some(self.split(node)) } else { None }
    }

    pub fn insert(&mut self, entry: Entry, level: usize) {
        if let Some(new) = self.insert_at(self.root, entry, level) {
            let root = self.root;
            let entries = vec![Entry { bounds: self.bounds(root), target: Target::Child(root) }, Entry { bounds: self.bounds(new), target: Target::Child(new) }];
            self.root = self.nodes.len();
            self.nodes.push(Node { level: self.nodes[root].level + 1, entries });
        }
    }

    pub fn insert_object(&mut self, id: i64, bounds: Bounds) {
        self.insert(Entry { bounds, target: Target::Object(id) }, 0);
    }

    fn find_path(&self, node: usize, id: i64, path: &mut Vec<(usize, usize)>) -> bool {
        for (i, entry) in self.nodes[node].entries.iter().enumerate() {
            path.push((node, i));
            let found = match entry.target {
                Target::Object(object) => object == id,
                Target::Child(child) => self.find_path(child, id, path),
            };
            if found { return true; }
            path.pop();
        }
        false
    }

    pub fn locate(&self, id: i64) -> Vec<usize> {
        let mut path = Vec::new();
        self.find_path(self.root, id, &mut path);
        path.into_iter().map(|(_, i)| i + 1).collect()
    }

    pub fn delete(&mut self, id: i64) {
        let mut path = Vec::new();
        self.find_path(self.root, id, &mut path);
        let (leaf, index) = path.pop().unwrap();
        self.nodes[leaf].entries.remove(index);
        let mut current = leaf;
        let mut removed = Vec::new();
        while let Some((parent, index)) = path.pop() {
            if self.nodes[current].entries.len() < self.minimum {
                self.nodes[parent].entries.remove(index);
                removed.push(current);
            } else {
                self.nodes[parent].entries[index].bounds = self.bounds(current);
            }
            current = parent;
        }
        for node in removed {
            let entries = self.nodes[node].entries.clone();
            let level = self.nodes[node].level;
            for entry in entries { self.insert(entry, level); }
        }
        while self.nodes[self.root].level > 0 && self.nodes[self.root].entries.len() == 1 {
            self.root = Self::child(&self.nodes[self.root].entries[0]);
        }
    }

    pub fn bulk(objects: &[(i64, Bounds)], maximum: usize, minimum: usize) -> Self {
        let mut tree = Self { nodes: Vec::new(), root: 0, maximum, minimum };
        let mut entries: Vec<(Entry, i64)> = objects.iter().map(|&(id, bounds)| (Entry { bounds, target: Target::Object(id) }, id)).collect();
        let mut level = 0;
        loop {
            let p = (entries.len() + maximum - 1) / maximum;
            let mut s = 1;
            while s * s < p { s += 1; }
            entries.sort_by_key(|(e, number)| (e.bounds.0 + e.bounds.2, e.bounds.1 + e.bounds.3, *number));
            let mut created = Vec::new();
            for slab in entries.chunks(s * maximum) {
                let mut sorted = slab.to_vec();
                sorted.sort_by_key(|(e, number)| (e.bounds.1 + e.bounds.3, e.bounds.0 + e.bounds.2, *number));
                for group in sorted.chunks(maximum) {
                    let node = tree.nodes.len();
                    tree.nodes.push(Node { level, entries: group.iter().map(|(e, _)| e.clone()).collect() });
                    created.push(node);
                }
            }
            if created.len() == 1 { tree.root = created[0]; break; }
            entries = created.iter().enumerate().map(|(number, &child)| (Entry { bounds: tree.bounds(child), target: Target::Child(child) }, number as i64)).collect();
            level += 1;
        }
        tree
    }
}
