pub struct Generator {
    state: i64,
    pub draws: usize
}
impl Generator {
    pub fn new(seed: i64) -> Self {
        Self {
            state: seed,
            draws: 0
        }
    }
    pub fn next(&mut self) -> i64 {
        self.state = 48271*self.state%2147483647;
        self.draws += 1;
        self.state
    }
    pub fn range(&mut self, low: usize, high: usize) -> usize {
        low+self.next() as usize%(high-low+1)
    }
}
