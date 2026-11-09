use std::fmt::Display;
use std::io::{self, BufRead, Write};
use std::rc::Rc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind { Seg, Lazy, Fen, Rfen, Sparse, Sqrt, Persist, Grid }
impl Kind {
    const ARRAYS: [Self; 7] = [Self::Seg, Self::Lazy, Self::Fen, Self::Rfen, Self::Sparse, Self::Sqrt, Self::Persist];
    fn name(self) -> &'static str {
        match self { Self::Seg => "SEG", Self::Lazy => "LAZY", Self::Fen => "FEN", Self::Rfen => "RFEN",
            Self::Sparse => "SPARSE", Self::Sqrt => "SQRT", Self::Persist => "PERSIST", Self::Grid => "GRID" }
    }
    fn parse(word: &str) -> Self {
        Self::ARRAYS.iter().copied().chain(std::iter::once(Self::Grid)).find(|kind| kind.name() == word).unwrap()
    }
}
#[derive(Clone, Copy)]
enum Operation { Sum, Min, Max, Gcd }
impl Operation {
    fn parse(word: &str) -> Result<Self, String> {
        match word { "SUM" => Ok(Self::Sum), "MIN" => Ok(Self::Min), "MAX" => Ok(Self::Max), "GCD" => Ok(Self::Gcd),
            _ => Err(format!("BAD OP {word}")) }
    }
    fn name(self) -> &'static str { match self { Self::Sum => "SUM", Self::Min => "MIN", Self::Max => "MAX", Self::Gcd => "GCD" } }
    fn label(self) -> &'static str { match self { Self::Sum => "sum", Self::Min => "min", Self::Max => "max", Self::Gcd => "gcd" } }
    fn combine(self, a: i64, b: i64) -> i64 {
        match self { Self::Sum => a + b, Self::Min => a.min(b), Self::Max => a.max(b), Self::Gcd => gcd(a, b) }
    }
    fn leaf(self, value: i64) -> i64 { if matches!(self, Self::Gcd) { value.abs() } else { value } }
}
fn gcd(a: i64, b: i64) -> i64 {
    let (mut a, mut b) = (a.abs(), b.abs());
    while b != 0 { (a, b) = (b, a % b); }
    a
}
fn isqrt(n: usize) -> usize {
    let mut result = 1;
    while (result + 1) * (result + 1) <= n { result += 1; }
    result
}
fn joined<T: Display>(values: impl IntoIterator<Item = T>) -> String {
    values.into_iter().map(|value| value.to_string()).collect::<Vec<_>>().join(" ")
}
#[derive(Clone, Copy)]
struct Span { left: usize, right: usize }
impl Span {
    fn whole(n: usize) -> Self { Self { left: 0, right: n - 1 } }
    fn len(self) -> usize { self.right - self.left + 1 }
    fn leaf(self) -> bool { self.left == self.right }
    fn covers(self, other: Self) -> bool { self.left <= other.left && other.right <= self.right }
    fn split(self) -> (Self, Self) {
        let mid = (self.left + self.right) / 2;
        (Self { left: self.left, right: mid }, Self { left: mid + 1, right: self.right })
    }
}
#[derive(Clone, Copy, Default, PartialEq, Eq)]
struct Aggregate { sum: i64, min: i64, max: i64 }
impl Aggregate {
    fn single(value: i64) -> Self { Self { sum: value, min: value, max: value } }
    fn combine(self, other: Self) -> Self {
        Self { sum: self.sum + other.sum, min: self.min.min(other.min), max: self.max.max(other.max) }
    }
    fn text(self) -> String { format!("sum={} min={} max={}", self.sum, self.min, self.max) }
}
#[derive(Default)]
struct Counts { visited: usize, covered: usize, pushes: usize }
#[derive(Default)]
struct Answer { value: i64, visited: usize }
#[derive(PartialEq, Eq)]
enum QueryValue { Scalar(i64), Triple(Aggregate), Extrema(i64, i64) }
struct Report { text: String, value: QueryValue }
impl Report {
    fn sum(answer: Answer) -> Self {
        Self { text: format!("sum={} visited={}", answer.value, answer.visited), value: QueryValue::Scalar(answer.value) }
    }
}
fn shape(n: usize) -> Vec<(usize, Span)> {
    fn visit(node: usize, span: Span, nodes: &mut Vec<(usize, Span)>) {
        nodes.push((node, span));
        if !span.leaf() {
            let (left, right) = span.split();
            visit(2 * node, left, nodes);
            visit(2 * node + 1, right, nodes);
        }
    }
    let mut nodes = Vec::new();
    visit(1, Span::whole(n), &mut nodes);
    nodes.sort_by_key(|&(node, _)| node);
    nodes
}

struct Segment { op: Operation, n: usize, tree: Vec<i64>, max_node: usize }
impl Segment {
    fn new(values: &[i64], op: Operation) -> Self {
        let mut result = Self { op, n: values.len(), tree: vec![0; 4 * values.len()], max_node: 0 };
        result.build(1, Span::whole(values.len()), values);
        result
    }
    fn build(&mut self, node: usize, span: Span, values: &[i64]) {
        self.max_node = self.max_node.max(node);
        if span.leaf() { self.tree[node] = self.op.leaf(values[span.left]); }
        else {
            let (left, right) = span.split();
            self.build(2 * node, left, values);
            self.build(2 * node + 1, right, values);
            self.tree[node] = self.op.combine(self.tree[2 * node], self.tree[2 * node + 1]);
        }
    }
    fn query_at(&self, node: usize, span: Span, wanted: Span) -> Answer {
        if wanted.covers(span) { return Answer { value: self.tree[node], visited: 1 }; }
        let (left, right) = span.split();
        let mut answer = if wanted.right <= left.right { self.query_at(2 * node, left, wanted) }
            else if wanted.left >= right.left { self.query_at(2 * node + 1, right, wanted) }
            else {
                let a = self.query_at(2 * node, left, wanted);
                let b = self.query_at(2 * node + 1, right, wanted);
                Answer { value: self.op.combine(a.value, b.value), visited: a.visited + b.visited }
            };
        answer.visited += 1;
        answer
    }
    fn query(&self, span: Span) -> Report {
        let answer = self.query_at(1, Span::whole(self.n), span);
        Report { text: format!("{}={} visited={}", self.op.label(), answer.value, answer.visited), value: QueryValue::Scalar(answer.value) }
    }
    fn update_at(&mut self, node: usize, span: Span, index: usize, value: i64) -> usize {
        if span.leaf() { self.tree[node] = self.op.leaf(value); return 1; }
        let (left, right) = span.split();
        let visited = if index <= left.right { self.update_at(2 * node, left, index, value) }
            else { self.update_at(2 * node + 1, right, index, value) };
        self.tree[node] = self.op.combine(self.tree[2 * node], self.tree[2 * node + 1]);
        visited + 1
    }
    fn dump(&self) -> Vec<String> {
        let mut rows = vec![format!("SEG DUMP {} nodes={}", self.op.name(), 2 * self.n - 1)];
        rows.extend(shape(self.n).into_iter().map(|(node, span)| format!("NODE {node} {} {} {}", span.left, span.right, self.tree[node])));
        rows
    }
}
#[derive(Clone, Copy, Default)]
struct LazyNode { value: Aggregate, assign: Option<i64>, add: i64 }
struct Lazy { n: usize, nodes: Vec<LazyNode> }
impl Lazy {
    fn new(values: &[i64]) -> Self {
        let mut result = Self { n: values.len(), nodes: vec![LazyNode::default(); 4 * values.len()] };
        result.build(1, Span::whole(values.len()), values);
        result
    }
    fn build(&mut self, node: usize, span: Span, values: &[i64]) {
        if span.leaf() { self.nodes[node].value = Aggregate::single(values[span.left]); }
        else {
            let (left, right) = span.split();
            self.build(2 * node, left, values);
            self.build(2 * node + 1, right, values);
            self.pull(node);
        }
    }
    fn pull(&mut self, node: usize) { self.nodes[node].value = self.nodes[2 * node].value.combine(self.nodes[2 * node + 1].value); }
    fn apply(&mut self, node: usize, span: Span, value: i64, assign: bool) {
        let current = &mut self.nodes[node];
        if assign { current.value = Aggregate { sum: value * span.len() as i64, min: value, max: value }; }
        else { current.value.sum += value * span.len() as i64; current.value.min += value; current.value.max += value; }
        if !span.leaf() {
            if assign { current.assign = Some(value); current.add = 0; } else { current.add += value; }
        }
    }
    fn push(&mut self, node: usize, span: Span, counts: &mut Counts) {
        let current = self.nodes[node];
        if current.assign.is_none() && current.add == 0 { return; }
        counts.pushes += 1;
        let (left, right) = span.split();
        for (child, range) in [(2 * node, left), (2 * node + 1, right)] {
            if let Some(value) = current.assign { self.apply(child, range, value, true); }
            if current.add != 0 { self.apply(child, range, current.add, false); }
        }
        self.nodes[node].assign = None;
        self.nodes[node].add = 0;
    }
    fn update_at(&mut self, node: usize, span: Span, wanted: Span, value: i64, assign: bool, counts: &mut Counts) {
        counts.visited += 1;
        if wanted.covers(span) { counts.covered += 1; self.apply(node, span, value, assign); return; }
        self.push(node, span, counts);
        let (left, right) = span.split();
        if wanted.left <= left.right { self.update_at(2 * node, left, wanted, value, assign, counts); }
        if wanted.right >= right.left { self.update_at(2 * node + 1, right, wanted, value, assign, counts); }
        self.pull(node);
    }
    fn update(&mut self, span: Span, value: i64, assign: bool) -> Counts {
        let mut counts = Counts::default();
        self.update_at(1, Span::whole(self.n), span, value, assign, &mut counts);
        counts
    }
    fn query_at(&mut self, node: usize, span: Span, wanted: Span, counts: &mut Counts) -> Aggregate {
        counts.visited += 1;
        if wanted.covers(span) { return self.nodes[node].value; }
        self.push(node, span, counts);
        let (left, right) = span.split();
        if wanted.right <= left.right { return self.query_at(2 * node, left, wanted, counts); }
        if wanted.left >= right.left { return self.query_at(2 * node + 1, right, wanted, counts); }
        let a = self.query_at(2 * node, left, wanted, counts);
        let b = self.query_at(2 * node + 1, right, wanted, counts);
        a.combine(b)
    }
    fn query(&mut self, span: Span) -> Report {
        let mut counts = Counts::default();
        let answer = self.query_at(1, Span::whole(self.n), span, &mut counts);
        Report { text: format!("{} visited={} pushes={}", answer.text(), counts.visited, counts.pushes), value: QueryValue::Triple(answer) }
    }
    fn dump(&self) -> Vec<String> {
        let mut rows = vec![format!("LAZY DUMP nodes={}", 2 * self.n - 1)];
        for (node, span) in shape(self.n) {
            let current = self.nodes[node];
            let assign = current.assign.map_or_else(|| "-".into(), |value| value.to_string());
            rows.push(format!("NODE {node} {} {} {} assign={assign} add={}", span.left, span.right, current.value.text(), current.add));
        }
        rows
    }
}
struct Bit { tree: Vec<i64> }
impl Bit {
    fn empty(n: usize) -> Self { Self { tree: vec![0; n + 1] } }
    fn new(values: &[i64]) -> Self {
        let mut bit = Self::empty(values.len());
        for (i, &value) in values.iter().enumerate() { bit.add(i + 1, value); }
        bit
    }
    fn add(&mut self, mut position: usize, value: i64) -> usize {
        let mut visited = 0;
        while position < self.tree.len() { self.tree[position] += value; visited += 1; position += position & position.wrapping_neg(); }
        visited
    }
    fn prefix(&self, mut position: usize) -> Answer {
        let mut answer = Answer::default();
        while position > 0 { answer.value += self.tree[position]; answer.visited += 1; position -= position & position.wrapping_neg(); }
        answer
    }
    fn range(&self, span: Span) -> Answer {
        let a = self.prefix(span.right + 1);
        let b = self.prefix(span.left);
        Answer { value: a.value - b.value, visited: a.visited + b.visited }
    }
    fn lower(&self, mut rest: i64) -> (Option<usize>, usize) {
        let n = self.tree.len() - 1;
        let (mut step, mut position, mut visited) = (1, 0, 0);
        while 2 * step <= n { step *= 2; }
        while step > 0 {
            if position + step <= n {
                visited += 1;
                if self.tree[position + step] < rest { rest -= self.tree[position + step]; position += step; }
            }
            step /= 2;
        }
        ((position < n).then_some(position), visited)
    }
}
struct Fenwick { values: Vec<i64>, bit: Bit }
impl Fenwick { fn new(values: &[i64]) -> Self { Self { values: values.to_vec(), bit: Bit::new(values) } } }
struct RangeFenwick { first: Bit, second: Bit }
impl RangeFenwick {
    fn new(values: &[i64]) -> Self {
        let mut result = Self { first: Bit::empty(values.len()), second: Bit::empty(values.len()) };
        for (i, &value) in values.iter().enumerate() {
            let difference = value - if i == 0 { 0 } else { values[i - 1] };
            result.first.add(i + 1, difference);
            result.second.add(i + 1, difference * i as i64);
        }
        result
    }
    fn add(&mut self, span: Span, value: i64) -> usize {
        let mut visited = self.first.add(span.left + 1, value);
        visited += self.first.add(span.right + 2, -value);
        visited += self.second.add(span.left + 1, value * span.left as i64);
        visited += self.second.add(span.right + 2, -value * (span.right + 1) as i64);
        visited
    }
    fn prefix(&self, position: usize) -> Answer {
        let a = self.first.prefix(position);
        let b = self.second.prefix(position);
        Answer { value: position as i64 * a.value - b.value, visited: a.visited + b.visited }
    }
    fn range(&self, span: Span) -> Answer {
        let a = self.prefix(span.right + 1);
        let b = self.prefix(span.left);
        Answer { value: a.value - b.value, visited: a.visited + b.visited }
    }
}
struct Sparse { values: Vec<i64>, min: Vec<Vec<usize>>, max: Vec<Vec<usize>> }
impl Sparse {
    fn new(values: &[i64]) -> Self {
        let n = values.len();
        let mut result = Self { values: values.to_vec(), min: vec![(0..n).collect()], max: vec![(0..n).collect()] };
        let mut length = 2;
        while length <= n {
            let level = result.min.len();
            let (mut lows, mut highs) = (Vec::new(), Vec::new());
            for i in 0..=n - length {
                let (a, b) = (result.min[level - 1][i], result.min[level - 1][i + length / 2]);
                lows.push(if values[a] <= values[b] { a } else { b });
                let (a, b) = (result.max[level - 1][i], result.max[level - 1][i + length / 2]);
                highs.push(if values[a] >= values[b] { a } else { b });
            }
            result.min.push(lows); result.max.push(highs);
            length *= 2;
        }
        result
    }
    fn query(&self, span: Span) -> Report {
        let (mut level, mut length) = (0, 1);
        while 2 * length <= span.len() { length *= 2; level += 1; }
        let end = span.right + 1 - length;
        let (a, b) = (self.min[level][span.left], self.min[level][end]);
        let low = if self.values[a] <= self.values[b] { a } else { b };
        let (a, b) = (self.max[level][span.left], self.max[level][end]);
        let high = if self.values[a] >= self.values[b] { a } else { b };
        Report { text: format!("min={} minpos={low} max={} maxpos={high} level={level}", self.values[low], self.values[high]),
            value: QueryValue::Extrema(self.values[low], self.values[high]) }
    }
    fn dump(&self) -> Vec<String> {
        let mut rows = vec![format!("SPARSE DUMP levels={}", self.min.len())];
        for level in 0..self.min.len() {
            rows.push(format!("MIN {level} {}", joined(&self.min[level])));
            rows.push(format!("MAX {level} {}", joined(&self.max[level])));
        }
        rows
    }
}
struct Sqrt { block: usize, values: Vec<i64>, tags: Vec<i64>, sums: Vec<i64> }
impl Sqrt {
    fn new(values: &[i64], block: usize) -> Self {
        let blocks = (values.len() + block - 1) / block;
        let mut result = Self { block, values: values.to_vec(), tags: vec![0; blocks], sums: vec![0; blocks] };
        for (i, &value) in values.iter().enumerate() { result.sums[i / block] += value; }
        result
    }
    fn split(&self, span: Span) -> (Vec<usize>, Vec<usize>) {
        let (first, last) = (span.left / self.block, span.right / self.block);
        let cells = (span.left..=span.right).filter(|&i| i / self.block == first || i / self.block == last).collect();
        (cells, (first + 1..last).collect())
    }
    fn add(&mut self, span: Span, value: i64) -> (usize, usize) {
        let (cells, blocks) = self.split(span);
        for &i in &cells { self.values[i] += value; self.sums[i / self.block] += value; }
        for &block in &blocks { self.tags[block] += value; self.sums[block] += value * self.block as i64; }
        (blocks.len(), cells.len())
    }
    fn query(&self, span: Span) -> Report {
        let (cells, blocks) = self.split(span);
        let mut sum: i64 = cells.iter().map(|&i| self.values[i] + self.tags[i / self.block]).sum();
        for &block in &blocks { sum += self.sums[block]; }
        Report { text: format!("sum={sum} whole={} cells={}", blocks.len(), cells.len()), value: QueryValue::Scalar(sum) }
    }
    fn dump(&self) -> Vec<String> {
        let mut rows = vec![format!("SQRT DUMP block={} blocks={}", self.block, self.tags.len())];
        for block in 0..self.tags.len() {
            let first = block * self.block;
            let end = ((block + 1) * self.block).min(self.values.len());
            rows.push(format!("BLOCK {block} {first} {} add={} sum={} {}", end - 1, self.tags[block], self.sums[block], joined(&self.values[first..end])));
        }
        rows
    }
}

struct PersistentNode { value: i64, left: Option<Rc<PersistentNode>>, right: Option<Rc<PersistentNode>> }
impl PersistentNode {
    fn build(values: Option<&[i64]>, span: Span, created: &mut usize) -> Rc<Self> {
        *created += 1;
        if span.leaf() { return Rc::new(Self { value: values.map_or(0, |items| items[span.left]), left: None, right: None }); }
        let (left, right) = span.split();
        let left = Self::build(values, left, created);
        let right = Self::build(values, right, created);
        Rc::new(Self { value: left.value + right.value, left: Some(left), right: Some(right) })
    }
    fn set(source: &Rc<Self>, span: Span, index: usize, value: i64, increment: bool, created: &mut usize) -> Rc<Self> {
        *created += 1;
        if span.leaf() { return Rc::new(Self { value: if increment { source.value + value } else { value }, left: None, right: None }); }
        let (left_span, right_span) = span.split();
        let mut left = Rc::clone(source.left.as_ref().unwrap());
        let mut right = Rc::clone(source.right.as_ref().unwrap());
        if index <= left_span.right { left = Self::set(&left, left_span, index, value, increment, created); }
        else { right = Self::set(&right, right_span, index, value, increment, created); }
        Rc::new(Self { value: left.value + right.value, left: Some(left), right: Some(right) })
    }
    fn query(&self, span: Span, wanted: Span) -> Answer {
        if wanted.covers(span) { return Answer { value: self.value, visited: 1 }; }
        let (left, right) = span.split();
        let mut answer = if wanted.right <= left.right { self.left.as_ref().unwrap().query(left, wanted) }
            else if wanted.left >= right.left { self.right.as_ref().unwrap().query(right, wanted) }
            else {
                let a = self.left.as_ref().unwrap().query(left, wanted);
                let b = self.right.as_ref().unwrap().query(right, wanted);
                Answer { value: a.value + b.value, visited: a.visited + b.visited }
            };
        answer.visited += 1;
        answer
    }
}
struct Persistent { n: usize, roots: Vec<Rc<PersistentNode>>, prefixes: Vec<Rc<PersistentNode>>, values: Vec<i64>, position_nodes: usize, value_nodes: usize }
impl Persistent {
    fn new(values: &[i64]) -> Self {
        let mut result = Self { n: values.len(), roots: Vec::new(), prefixes: Vec::new(), values: values.to_vec(), position_nodes: 0, value_nodes: 0 };
        result.roots.push(PersistentNode::build(Some(values), Span::whole(values.len()), &mut result.position_nodes));
        result.values.sort_unstable(); result.values.dedup();
        let span = Span::whole(result.values.len());
        result.prefixes.push(PersistentNode::build(None, span, &mut result.value_nodes));
        for value in values {
            let rank = result.values.binary_search(value).unwrap();
            let root = PersistentNode::set(result.prefixes.last().unwrap(), span, rank, 1, true, &mut result.value_nodes);
            result.prefixes.push(root);
        }
        result
    }
    fn set(&mut self, version: usize, index: usize, value: i64) -> (usize, usize) {
        let before = self.position_nodes;
        let version_number = self.roots.len();
        let root = PersistentNode::set(&self.roots[version], Span::whole(self.n), index, value, false, &mut self.position_nodes);
        self.roots.push(root);
        (version_number, self.position_nodes - before)
    }
    fn query(&self, version: usize, span: Span) -> Report { Report::sum(self.roots[version].query(Span::whole(self.n), span)) }
    fn kth(&self, span: Span, mut k: i64) -> Answer {
        let (mut u, mut w) = (&self.prefixes[span.right + 1], &self.prefixes[span.left]);
        let mut range = Span::whole(self.values.len());
        let mut visited = 1;
        while !range.leaf() {
            let (left, right) = range.split();
            let count = u.left.as_ref().unwrap().value - w.left.as_ref().unwrap().value;
            if k <= count { u = u.left.as_ref().unwrap(); w = w.left.as_ref().unwrap(); range = left; }
            else { k -= count; u = u.right.as_ref().unwrap(); w = w.right.as_ref().unwrap(); range = right; }
            visited += 1;
        }
        Answer { value: self.values[range.left], visited }
    }
}
struct Grid { height: usize, width: usize, tree: Vec<Vec<i64>> }
impl Grid {
    fn new(height: usize, width: usize, values: &[i64]) -> Self {
        let mut result = Self { height, width, tree: vec![vec![0; width + 1]; height + 1] };
        for (i, &value) in values.iter().enumerate() { result.add(i / width, i % width, value); }
        result
    }
    fn cell(&self, row: i64, col: i64) -> Result<(usize, usize), String> {
        if row < 0 || row >= self.height as i64 || col < 0 || col >= self.width as i64 { Err(format!("BAD CELL {row} {col}")) }
        else { Ok((row as usize, col as usize)) }
    }
    fn add(&mut self, row: usize, col: usize, value: i64) -> usize {
        let (mut y, mut visited) = (row + 1, 0);
        while y <= self.height {
            let mut x = col + 1;
            while x <= self.width { self.tree[y][x] += value; visited += 1; x += x & x.wrapping_neg(); }
            y += y & y.wrapping_neg();
        }
        visited
    }
    fn prefix(&self, mut row: usize, col: usize) -> Answer {
        let mut answer = Answer::default();
        while row > 0 {
            let mut x = col;
            while x > 0 { answer.value += self.tree[row][x]; answer.visited += 1; x -= x & x.wrapping_neg(); }
            row -= row & row.wrapping_neg();
        }
        answer
    }
    fn query(&self, row: usize, col: usize, bottom: usize, right: usize) -> Answer {
        let a = self.prefix(bottom + 1, right + 1);
        let b = self.prefix(row, right + 1);
        let c = self.prefix(bottom + 1, col);
        let d = self.prefix(row, col);
        Answer { value: a.value - b.value - c.value + d.value, visited: a.visited + b.visited + c.visited + d.visited }
    }
    fn dump(&self) -> Vec<String> {
        let mut rows = vec![format!("GRID DUMP rows={} cols={}", self.height, self.width)];
        rows.extend((1..=self.height).map(|row| format!("ROW {row} {}", joined(&self.tree[row][1..]))));
        rows
    }
}

#[derive(Default)]
struct Lab {
    values: Vec<i64>, original: Vec<i64>,
    seg: Option<Segment>, lazy: Option<Lazy>, fen: Option<Fenwick>, rfen: Option<RangeFenwick>,
    sparse: Option<Sparse>, sqrt: Option<Sqrt>, persist: Option<Persistent>, grid: Option<Grid>,
}
impl Lab {
    fn new(values: Vec<i64>) -> Self { Self { original: values.clone(), values, ..Self::default() } }
    fn has(&self, kind: Kind) -> bool {
        match kind { Kind::Seg => self.seg.is_some(), Kind::Lazy => self.lazy.is_some(), Kind::Fen => self.fen.is_some(),
            Kind::Rfen => self.rfen.is_some(), Kind::Sparse => self.sparse.is_some(), Kind::Sqrt => self.sqrt.is_some(),
            Kind::Persist => self.persist.is_some(), Kind::Grid => self.grid.is_some() }
    }
    fn ready(&self, kind: Kind) -> Result<(), String> {
        if self.has(kind) { Ok(()) } else { Err(format!("NOT BUILT {}", kind.name())) }
    }
    fn index(&self, index: i64) -> Result<usize, String> {
        if index < 0 || index >= self.values.len() as i64 { Err(format!("BAD INDEX {index}")) } else { Ok(index as usize) }
    }
    fn span(&self, left: i64, right: i64) -> Result<Span, String> {
        let start = self.index(left)?;
        let end = self.index(right)?;
        if start > end { Err(format!("BAD RANGE {left} {right}")) } else { Ok(Span { left: start, right: end }) }
    }
    fn version(&self, version: i64) -> Result<usize, String> {
        if version < 0 || version >= self.persist.as_ref().unwrap().roots.len() as i64 { Err(format!("BAD VERSION {version}")) }
        else { Ok(version as usize) }
    }
    fn build(&mut self, kind: Kind, operation: Option<Operation>, block: Option<usize>) -> String {
        let n = self.values.len();
        match kind {
            Kind::Seg => {
                let tree = Segment::new(&self.values, operation.unwrap());
                let row = format!("SEG BUILD {} nodes={} maxnode={} root={}", tree.op.name(), 2 * n - 1, tree.max_node, tree.tree[1]);
                self.seg = Some(tree); row
            }
            Kind::Lazy => {
                let tree = Lazy::new(&self.values);
                let row = format!("LAZY BUILD nodes={} {}", 2 * n - 1, tree.nodes[1].value.text());
                self.lazy = Some(tree); row
            }
            Kind::Fen => {
                self.fen = Some(Fenwick::new(&self.values));
                format!("FEN BUILD n={n} total={}", self.values.iter().sum::<i64>())
            }
            Kind::Rfen => {
                self.rfen = Some(RangeFenwick::new(&self.values));
                format!("RFEN BUILD n={n} total={}", self.values.iter().sum::<i64>())
            }
            Kind::Sparse => {
                let tree = Sparse::new(&self.values);
                let row = format!("SPARSE BUILD levels={} entries={}", tree.min.len(), tree.min.iter().map(Vec::len).sum::<usize>());
                self.sparse = Some(tree); row
            }
            Kind::Sqrt => {
                let tree = Sqrt::new(&self.values, block.unwrap());
                let row = format!("SQRT BUILD block={} blocks={}", tree.block, tree.tags.len());
                self.sqrt = Some(tree); row
            }
            Kind::Persist => {
                let tree = Persistent::new(&self.values);
                let row = format!("PERSIST BUILD nodes={} distinct={} valuenodes={}", tree.position_nodes, tree.values.len(), tree.value_nodes);
                self.persist = Some(tree); row
            }
            Kind::Grid => unreachable!(),
        }
    }
    fn query(&mut self, kind: Kind, version: usize, span: Span) -> Report {
        match kind {
            Kind::Seg => self.seg.as_ref().unwrap().query(span),
            Kind::Lazy => self.lazy.as_mut().unwrap().query(span),
            Kind::Fen => Report::sum(self.fen.as_ref().unwrap().bit.range(span)),
            Kind::Rfen => Report::sum(self.rfen.as_ref().unwrap().range(span)),
            Kind::Sparse => self.sparse.as_ref().unwrap().query(span),
            Kind::Sqrt => self.sqrt.as_ref().unwrap().query(span),
            Kind::Persist => self.persist.as_ref().unwrap().query(version, span),
            Kind::Grid => unreachable!(),
        }
    }
    fn dump(&self, kind: Kind) -> Vec<String> {
        match kind {
            Kind::Seg => self.seg.as_ref().unwrap().dump(),
            Kind::Lazy => self.lazy.as_ref().unwrap().dump(),
            Kind::Fen => vec![format!("FEN DUMP n={}", self.values.len()), format!("T {}", joined(&self.fen.as_ref().unwrap().bit.tree[1..]))],
            Kind::Rfen => {
                let tree = self.rfen.as_ref().unwrap();
                vec![format!("RFEN DUMP n={}", self.values.len()), format!("B1 {}", joined(&tree.first.tree[1..])), format!("B2 {}", joined(&tree.second.tree[1..]))]
            }
            Kind::Sparse => self.sparse.as_ref().unwrap().dump(),
            Kind::Sqrt => self.sqrt.as_ref().unwrap().dump(),
            Kind::Grid => self.grid.as_ref().unwrap().dump(),
            Kind::Persist => unreachable!(),
        }
    }
    fn check(&mut self, span: Span) -> Vec<String> {
        let values = &self.values[span.left..=span.right];
        let aggregate = Aggregate { sum: values.iter().sum(), min: *values.iter().min().unwrap(), max: *values.iter().max().unwrap() };
        let common = values.iter().fold(0, |value, &next| gcd(value, next));
        let mut rows = vec![format!("CHECK {} {} {} gcd={common}", span.left, span.right, aggregate.text())];
        let (mut ok, mut diff) = (0, 0);
        for kind in Kind::ARRAYS {
            if !self.has(kind) { continue; }
            let expected = match kind {
                Kind::Seg => QueryValue::Scalar(match self.seg.as_ref().unwrap().op {
                    Operation::Sum => aggregate.sum, Operation::Min => aggregate.min, Operation::Max => aggregate.max, Operation::Gcd => common }),
                Kind::Lazy => QueryValue::Triple(aggregate),
                Kind::Sparse => QueryValue::Extrema(aggregate.min, aggregate.max),
                _ => QueryValue::Scalar(aggregate.sum),
            };
            let version = self.persist.as_ref().map_or(0, |tree| tree.roots.len() - 1);
            let result = self.query(kind, version, span);
            let verdict = if result.value == expected { ok += 1; "OK" } else { diff += 1; "DIFF" };
            let prefix = if kind == Kind::Persist { format!("version={version} ") } else { String::new() };
            rows.push(format!("{} {verdict} {prefix}{}", kind.name(), result.text));
        }
        rows.push(format!("RESULT ok={ok} diff={diff}"));
        rows
    }
    fn mo(&self, queries: &[Span]) -> Vec<String> {
        let block = isqrt(self.values.len());
        let mut order: Vec<usize> = (0..queries.len()).collect();
        order.sort_by_key(|&i| {
            let group = queries[i].left / block;
            (group, if group % 2 == 0 { queries[i].right as i64 } else { -(queries[i].right as i64) }, i)
        });
        let mut unique = self.values.clone(); unique.sort_unstable(); unique.dedup();
        let ranks: Vec<usize> = self.values.iter().map(|value| unique.binary_search(value).unwrap()).collect();
        let mut frequencies = vec![0usize; unique.len()];
        let mut answers = vec![0; queries.len()];
        let (mut left, mut right, mut moves, mut distinct) = (0usize, 0usize, 0usize, 0usize);
        for &i in &order {
            let span = queries[i];
            let end = span.right + 1;
            moves += left.abs_diff(span.left) + right.abs_diff(end);
            while left > span.left { left -= 1; let rank = ranks[left]; if frequencies[rank] == 0 { distinct += 1; } frequencies[rank] += 1; }
            while right < end { let rank = ranks[right]; if frequencies[rank] == 0 { distinct += 1; } frequencies[rank] += 1; right += 1; }
            while left < span.left { let rank = ranks[left]; frequencies[rank] -= 1; if frequencies[rank] == 0 { distinct -= 1; } left += 1; }
            while right > end { right -= 1; let rank = ranks[right]; frequencies[rank] -= 1; if frequencies[rank] == 0 { distinct -= 1; } }
            answers[i] = distinct;
        }
        let mut rows = vec![format!("MO queries={} block={block} moves={moves}", queries.len()), format!("ORDER {}", joined(order.iter().map(|i| i + 1)))];
        rows.extend(queries.iter().enumerate().map(|(i, span)| format!("ANSWER {} {} {} distinct={}", i + 1, span.left, span.right, answers[i])));
        rows
    }
    fn execute(&mut self, line: &str) -> Result<Vec<String>, String> {
        let words: Vec<&str> = line.split_whitespace().collect();
        let number = |index: usize| words[index].parse::<i64>().unwrap();
        match words[0] {
            "LOAD" => {
                let values = words[1..].iter().map(|word| word.parse::<i64>().unwrap()).collect();
                let removed = Kind::ARRAYS.iter().filter(|&&kind| self.has(kind)).count();
                let grid = self.grid.take();
                *self = Self { grid, ..Self::new(values) };
                return Ok(vec![format!("LOAD n={} removed={removed}", self.values.len())]);
            }
            "RESET" => {
                self.values.clone_from(&self.original);
                let operation = self.seg.as_ref().map(|tree| tree.op);
                let block = self.sqrt.as_ref().map(|tree| tree.block);
                let mut rebuilt = 0;
                for kind in Kind::ARRAYS { if self.has(kind) { self.build(kind, operation, block); rebuilt += 1; } }
                return Ok(vec![format!("RESET rebuilt={rebuilt}")]);
            }
            "ARRAY" | "CHECK" => {
                let span = self.span(number(1), number(2))?;
                return Ok(if words[0] == "CHECK" { self.check(span) }
                    else { vec![format!("ARRAY {} {} {}", span.left, span.right, joined(&self.values[span.left..=span.right]))] });
            }
            "MO" => {
                let mut queries = Vec::new();
                for i in (1..words.len()).step_by(2) { queries.push(self.span(number(i), number(i + 1))?); }
                return Ok(self.mo(&queries));
            }
            _ => {}
        }
        let kind = Kind::parse(words[0]);
        let action = words[1];
        if action == "BUILD" {
            let operation = if kind == Kind::Seg { Some(Operation::parse(words[2])?) } else { None };
            let block = if kind == Kind::Sqrt {
                let value = if words.len() == 3 { number(2) as usize } else { isqrt(self.values.len()) };
                if value > self.values.len() { return Err(format!("BAD BLOCK {value}")); }
                Some(value)
            } else { None };
            if kind == Kind::Grid {
                let (height, width) = (number(2) as usize, number(3) as usize);
                if words.len() - 4 != height * width { return Err(format!("BAD COUNT {} {}", words.len() - 4, height * width)); }
                let values: Vec<i64> = (4..words.len()).map(number).collect();
                self.grid = Some(Grid::new(height, width, &values));
                return Ok(vec![format!("GRID BUILD rows={height} cols={width} total={}", values.iter().sum::<i64>())]);
            }
            return Ok(vec![self.build(kind, operation, block)]);
        }
        self.ready(kind)?;
        if action == "DUMP" { return Ok(self.dump(kind)); }
        if kind == Kind::Grid {
            let grid = self.grid.as_mut().unwrap();
            let (row, col) = grid.cell(number(2), number(3))?;
            if action == "ADD" {
                let value = number(4);
                let visited = grid.add(row, col, value);
                return Ok(vec![format!("GRID ADD {row} {col} {value} visited={visited}")]);
            }
            let (bottom, right) = grid.cell(number(4), number(5))?;
            if row > bottom || col > right { return Err(format!("BAD RECT {row} {col} {bottom} {right}")); }
            let answer = grid.query(row, col, bottom, right);
            return Ok(vec![format!("GRID SUM {row} {col} {bottom} {right} sum={} visited={}", answer.value, answer.visited)]);
        }
        if kind == Kind::Persist {
            if action == "NODES" {
                let tree = self.persist.as_ref().unwrap();
                return Ok(vec![format!("PERSIST NODES versions={} position={} value={}", tree.roots.len(), tree.position_nodes, tree.value_nodes)]);
            }
            if action == "KTH" {
                let span = self.span(number(2), number(3))?;
                let k = number(4);
                if k < 1 || k > span.len() as i64 { return Err(format!("BAD K {k}")); }
                let answer = self.persist.as_ref().unwrap().kth(span, k);
                return Ok(vec![format!("PERSIST KTH {} {} {k} value={} visited={}", span.left, span.right, answer.value, answer.visited)]);
            }
            let version = self.version(number(2))?;
            if action == "SET" {
                let index = self.index(number(3))?;
                let value = number(4);
                let (next, created) = self.persist.as_mut().unwrap().set(version, index, value);
                return Ok(vec![format!("PERSIST SET {version} {index} {value} version={next} created={created}")]);
            }
            let span = self.span(number(3), number(4))?;
            let result = self.query(kind, version, span);
            return Ok(vec![format!("PERSIST QUERY {version} {} {} {}", span.left, span.right, result.text)]);
        }
        if kind == Kind::Fen && action == "LOWER" {
            let tree = self.fen.as_ref().unwrap();
            if let Some(index) = tree.values.iter().position(|&value| value < 0) { return Err(format!("NEGATIVE {index}")); }
            let k = number(2);
            let (index, visited) = tree.bit.lower(k);
            let index = index.map_or_else(|| "none".into(), |value| value.to_string());
            return Ok(vec![format!("FEN LOWER {k} index={index} visited={visited}")]);
        }
        if kind == Kind::Seg && action == "UPDATE" {
            let index = self.index(number(2))?;
            let value = number(3);
            let tree = self.seg.as_mut().unwrap();
            let visited = tree.update_at(1, Span::whole(tree.n), index, value);
            self.values[index] = value;
            return Ok(vec![format!("SEG UPDATE {index} {value} root={} visited={visited}", tree.tree[1])]);
        }
        if kind == Kind::Fen && (action == "ADD" || action == "PREFIX") {
            let index = self.index(number(2))?;
            let tree = self.fen.as_mut().unwrap();
            if action == "ADD" {
                let value = number(3);
                tree.values[index] += value;
                self.values[index] += value;
                let visited = tree.bit.add(index + 1, value);
                return Ok(vec![format!("FEN ADD {index} {value} visited={visited}")]);
            }
            let answer = tree.bit.prefix(index + 1);
            return Ok(vec![format!("FEN PREFIX {index} sum={} visited={}", answer.value, answer.visited)]);
        }
        let span = self.span(number(2), number(3))?;
        if action == "ADD" || action == "ASSIGN" {
            let value = number(4);
            let assign = action == "ASSIGN";
            let details = match kind {
                Kind::Lazy => {
                    let counts = self.lazy.as_mut().unwrap().update(span, value, assign);
                    format!("visited={} covered={} pushes={}", counts.visited, counts.covered, counts.pushes)
                }
                Kind::Rfen => format!("visited={}", self.rfen.as_mut().unwrap().add(span, value)),
                Kind::Sqrt => {
                    let (whole, cells) = self.sqrt.as_mut().unwrap().add(span, value);
                    format!("whole={whole} cells={cells}")
                }
                _ => unreachable!(),
            };
            for item in &mut self.values[span.left..=span.right] { if assign { *item = value; } else { *item += value; } }
            Ok(vec![format!("{} {action} {} {} {value} {details}", kind.name(), span.left, span.right)])
        } else {
            let result = self.query(kind, 0, span);
            Ok(vec![format!("{} {action} {} {} {}", kind.name(), span.left, span.right, result.text)])
        }
    }
}

fn main() -> io::Result<()> {
    let input = io::stdin();
    let mut lines = input.lock().lines();
    let Some(first) = lines.next() else { return Ok(()); };
    let n: usize = first?.parse().unwrap();
    let values = lines.next().unwrap()?.split_whitespace().take(n).map(|word| word.parse::<i64>().unwrap()).collect();
    let mut lab = Lab::new(values);
    let commands: usize = lines.next().unwrap()?.parse().unwrap();
    let mut output = io::BufWriter::new(io::stdout().lock());
    for _ in 0..commands {
        let line = lines.next().unwrap()?;
        match lab.execute(&line) {
            Ok(rows) => for row in rows { writeln!(output, "{row}")?; },
            Err(reason) => writeln!(output, "ERROR {reason}")?,
        }
    }
    output.flush()
}
