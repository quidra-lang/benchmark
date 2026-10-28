use crate::suffix_array::symbol;

pub struct Index {
    pub bwt: Vec<u8>, pub cumulative: [usize; 6], pub checkpoints: Vec<[usize; 6]>,
    pub interval: usize, pub samples: Vec<Option<usize>>,
}
impl Index {
    pub fn new(text: &[u8], order: &[usize], interval: usize, sample: Option<usize>) -> Self {
        let n = text.len(); let bwt: Vec<_> = order.iter().map(|&p| text[if p == 0 { n-1 } else { p-1 }]).collect();
        let mut counts = [0; 6]; for &c in text { counts[symbol(c)] += 1; }
        let mut cumulative = [0; 6]; for i in 1..6 { cumulative[i] = cumulative[i-1]+counts[i-1]; }
        let mut checkpoints = vec![[0; 6]]; let mut running = [0; 6];
        for (i, &c) in bwt.iter().enumerate() { running[symbol(c)] += 1; if (i+1)%interval == 0 { checkpoints.push(running); } }
        let samples = order.iter().map(|&p| if sample.map_or(false, |s| p%s == 0) { Some(p) } else { None }).collect();
        Self { bwt, cumulative, checkpoints, interval, samples }
    }
    pub fn occurrence(&self, c: u8, position: usize) -> usize {
        let checkpoint = position/self.interval;
        self.checkpoints[checkpoint][symbol(c)]+self.bwt[checkpoint*self.interval..position].iter().filter(|&&b| b == c).count()
    }
    pub fn lf(&self, row: usize) -> usize { self.cumulative[symbol(self.bwt[row])]+self.occurrence(self.bwt[row], row) }
    pub fn extend(&self, interval: (usize, usize), base: u8) -> (usize, usize) {
        if base == b'N' { return (0, 0); }
        let c = self.cumulative[symbol(base)]; (c+self.occurrence(base, interval.0), c+self.occurrence(base, interval.1))
    }
    pub fn exact(&self, sequence: &[u8]) -> (usize, usize) {
        let mut interval = (0, self.bwt.len());
        for &c in sequence.iter().rev() { interval = self.extend(interval, c); if interval.0 >= interval.1 { break; } }
        interval
    }
    pub fn locate(&self, row: usize) -> (usize, usize) {
        let mut current = row; let mut steps = 0;
        while self.samples[current].is_none() { current = self.lf(current); steps += 1; }
        (self.samples[current].unwrap()+steps, steps)
    }
    pub fn inverse(&self) -> Vec<u8> {
        let mut text = vec![b'$'; self.bwt.len()]; let mut row = 0;
        for p in (0..text.len()-1).rev() { text[p] = self.bwt[row]; row = self.lf(row); } text
    }
    pub fn runs(&self) -> usize { 1+self.bwt.windows(2).filter(|p| p[0] != p[1]).count() }
}
