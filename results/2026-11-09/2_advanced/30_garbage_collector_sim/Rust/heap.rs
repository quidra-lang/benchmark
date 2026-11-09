use std::collections::BTreeSet;
#[derive(Clone)]
pub struct HeapObject {
    pub size: usize,
    pub fields: Vec<Option<usize>>,
    pub address: usize,
    pub marked: bool,
    pub moves: usize,
    pub age: usize,
    pub count: usize,
    pub present: bool
}
impl HeapObject {
    pub fn new(p: usize, d: usize) -> Self {
        Self {
            size: 1+p+d,
            fields: vec![None; p],
            address: 0,
            marked: false,
            moves: 0,
            age: 0,
            count: 0,
            present: true
        }
    }
}
#[derive(Clone, Copy, Default)]
pub struct Pair {
    pub count: usize,
    pub words: usize
}
impl Pair {
    pub fn add(&mut self, o: &HeapObject) {
        self.count += 1;
        self.words += o.size;
    }
    pub fn merge(&mut self, p: Pair) {
        self.count += p.count;
        self.words += p.words;
    }
    pub fn text(self) -> String {
        format!("{} {}", self.count, self.words)
    }
}
pub struct Record {
    pub line: usize,
    pub request: usize,
    pub kind: String,
    pub live: Pair,
    pub freed: Pair,
    pub moved: Pair,
    pub promoted: Pair,
    pub stack: usize,
    pub work: usize,
    pub before: (usize, usize),
    pub after: (usize, usize)
}
impl Record {
    pub fn new(line: usize, request: usize, kind: &str, blocks: &[(usize, usize)]) -> Self {
        Self {
            line,
            request,
            kind: kind.into(),
            live: Pair::default(),
            freed: Pair::default(),
            moved: Pair::default(),
            promoted: Pair::default(),
            stack: 0,
            work: 0,
            before: free_amount(blocks),
            after: (0, 0)
        }
    }
}
pub struct Memory {
    pub algorithm: String,
    pub size: usize,
    pub objects: Vec<HeapObject>,
    pub base: usize,
    pub top: usize,
    pub young: usize,
    pub promotion_age: usize,
    pub remembered: BTreeSet<usize>,
    pub barriers: usize,
    pub remembers: usize,
    pub records: Vec<Record>
}
impl Memory {
    pub fn ids(&self) -> Vec<usize> {
        self.objects.iter().enumerate().filter(|(_, o)|o.present).map(|(i, _)|i).collect()
    }
    pub fn old_blocks(&self) -> Vec<(usize, usize)> {
        free_blocks(&self.objects, self.young, self.size)
    }
    pub fn free_list(&self) -> Vec<(usize, usize)> {
        match self.algorithm.as_str() {
            "MARK_SWEEP"|"REFCOUNT" => free_blocks(&self.objects, 0, self.size), "MARK_COMPACT" => if self.top<self.size {
                vec![(self.top, self.size-self.top)]
            }else {
                vec![]
            }, _ => {
                let half = if self.algorithm == "COPYING" {
                    self.size/2
                }else {
                    self.young/2
                };
                let mut out = if self.top<self.base+half {
                    vec![(self.top, self.base+half-self.top)]
                }else {
                    vec![]
                };
                if self.algorithm == "GENERATIONAL" {
                    out.extend(self.old_blocks())
                }
                out
            }
        }
    }
    pub fn inactive(&self) -> (usize, usize) {
        let half = if self.algorithm == "COPYING" {
            self.size/2
        }else if self.algorithm == "GENERATIONAL" {
            self.young/2
        }else {
            0
        };
        (half-self.base, 2*half-self.base)
    }
    pub fn pair(&self, ids: impl IntoIterator<Item = usize>) -> Pair {
        let mut p = Pair::default();
        for i in ids {
            p.add(&self.objects[i])
        }
        p
    }
    pub fn ordered(&self, ids: impl IntoIterator<Item = usize>) -> Vec<usize> {
        let mut out = ids.into_iter().collect::<Vec<_>>();
        out.sort_by_key(|&i|self.objects[i].address);
        out
    }
}
pub fn free_blocks(objects: &[HeapObject], start: usize, end: usize) -> Vec<(usize, usize)> {
    let mut ids = objects.iter().filter(|o|o.present && o.address >= start && o.address<end).collect::<Vec<_>>();
    ids.sort_by_key(|o|o.address);
    let mut pos = start;
    let mut out = vec![];
    for o in ids {
        if o.address>pos {
            out.push((pos, o.address-pos))
        }
        pos = o.address+o.size;
    }
    if pos<end {
        out.push((pos, end-pos))
    }
    out
}
pub fn first_fit(blocks: &[(usize, usize)], size: usize) -> Option<usize> {
    blocks.iter().find(|p|p.1 >= size).map(|p|p.0)
}
pub fn free_amount(blocks: &[(usize, usize)]) -> (usize, usize) {
    (blocks.iter().map(|p|p.1).sum(), blocks.iter().map(|p|p.1).max().unwrap_or(0))
}
pub fn dec2(a: usize, b: usize) -> String {
    let z = (200*a+b)/(2*b);
    format!("{}.{:02}", z/100, z%100)
}
pub fn pct(a: usize, b: usize) -> String {
    if b == 0 {
        "-".into()
    }else {
        dec2(100*a, b)
    }
}
pub fn class_table(values: impl IntoIterator<Item = usize>) -> String {
    let mut counts = [0; 5];
    for v in values {
        let k = [1, 3, 7, 15].iter().position(|&limit|v <= limit).unwrap_or(4);
        counts[k] += 1;
    }
    ["1", "2-3", "4-7", "8-15", "16+"].iter().zip(counts).map(|(k, v)|format!("{k}:{v}")).collect::<Vec<_>>().join(" ")
}
pub fn heap_map(memory: &Memory, reached: &BTreeSet<usize>) -> String {
    let mut cells = vec![b'.'; memory.size];
    let(lo, hi) = memory.inactive();
    for c in &mut cells[lo..hi] {
        *c = b'-'
    }
    for(i, o)in memory.objects.iter().enumerate() {
        if !o.present {
            continue
        }
        let live = reached.contains(&i);
        cells[o.address] = if live {
            b'A'+(i%26)as u8
        }else {
            b'#'
        };
        for a in o.address+1..o.address+o.size {
            cells[a] = if live {
                b'a'+(i%26)as u8
            }else {
                b'='
            };
        }
    }
    String::from_utf8(cells).unwrap()
}
