#[derive(Clone,Copy)] pub struct Line {
    pub block: usize,
    pub state: u8
}
pub struct Set {
    pub ways: Vec<Option<Line>>,
    stamps: Vec<usize>,
    pub bits: Vec<usize>,
    pub fills: usize,
    pub evictions: usize
}
pub struct Cache {
    pub sets: Vec<Set>,
    pub policy: String,
    clock: usize
}
impl Cache {
    pub fn new(sets: usize, ways: usize, policy: &str) -> Self {
        Self {
            sets: (0..sets).map(|_| Set {
                ways: vec![None;ways],
                stamps: vec![0;ways],
                bits: vec![0;ways],
                fills: 0,
                evictions: 0
            }).collect(),
            policy: policy.to_owned(),
            clock: 0
        }
    }
    pub fn find(&self, block: usize) -> Option<(usize,usize)> {
        let set = block%self.sets.len();
        self.sets[set].ways.iter().position(|line| line.map_or(false,|l| l.block == block)).map(|way| (set,way))
    }
    pub fn state(&self, block: usize) -> u8 {
        self.find(block).map_or(b'I',|(s,w)| self.sets[s].ways[w].unwrap().state)
    }
    pub fn change(&mut self, block: usize, state: u8) {
        let (s,w) = self.find(block).unwrap();
        self.sets[s].ways[w].as_mut().unwrap().state = state;
    }
    pub fn remove(&mut self, block: usize) -> Option<Line> {
        self.find(block).and_then(|(s,w)| self.sets[s].ways[w].take())
    }
    fn touch_way(&mut self, set: usize, way: usize, fill: bool) {
        if self.policy == "LRU" || (self.policy == "FIFO" && fill) {
            self.clock += 1;
            self.sets[set].stamps[way] = self.clock;
        }
        if self.policy == "PLRU" {
            let (mut node,mut first,mut count) = (1,0,self.sets[set].ways.len());
            while count > 1 {
                count /= 2;
                if way < first+count {
                    self.sets[set].bits[node] = 1;
                    node *= 2;
                } else {
                    self.sets[set].bits[node] = 0;
                    first += count;
                    node = 2*node+1;
                }
            }
        }
    }
    pub fn touch(&mut self, block: usize) {
        let (s,w) = self.find(block).unwrap();
        self.touch_way(s,w,false);
    }
    fn victim(&self, set: usize) -> usize {
        let s = &self.sets[set];
        if let Some(way) = s.ways.iter().position(Option::is_none) {
            return way;
        }
        if self.policy != "PLRU" {
            return (0..s.ways.len()).min_by_key(|&w| (s.stamps[w],w)).unwrap();
        }
        let (mut node,mut first,mut count) = (1,0,s.ways.len());
        while count > 1 {
            count /= 2;
            if s.bits[node] == 0 {
                node *= 2;
            } else {
                first += count;
                node = 2*node+1;
            }
        }
        first
    }
    pub fn fill(&mut self, block: usize, state: u8) -> Option<Line> {
        let set = block%self.sets.len();
        let way = self.victim(set);
        let evicted = self.sets[set].ways[way].replace(Line {
            block,
            state
        });
        self.sets[set].fills += 1;
        self.sets[set].evictions += usize::from(evicted.is_some());
        self.touch_way(set,way,true);
        evicted
    }
    pub fn order(&self, set: usize) -> String {
        let s = &self.sets[set];
        if self.policy == "PLRU" {
            if s.ways.len() == 1 {
                "-".to_owned()
            } else {
                s.bits[1..].iter().map(usize::to_string).collect()
            }
        } else {
            let mut ways: Vec<_> = (0..s.ways.len()).filter(|&w| s.ways[w].is_some()).collect();
            ways.sort_by_key(|&w| (std::cmp::Reverse(s.stamps[w]),w));
            if ways.is_empty() {
                "-".to_owned()
            } else {
                ways.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")
            }
        }
    }
}
