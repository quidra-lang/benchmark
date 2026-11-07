pub struct Minstd { pub state: i64 }
impl Minstd {
    pub fn draw(&mut self) -> i64 { self.state = self.state * 48271 % 2147483647; self.state }
    pub fn rnd(&mut self, size: usize) -> usize { (self.draw() % size as i64) as usize }
    pub fn roll(&mut self, count: usize, sides: usize) -> i64 {
        let mut total = 0;
        for _ in 0..count { total += 1 + self.rnd(sides) as i64; }
        total
    }
    pub fn select(&mut self, weights: &[usize]) -> usize {
        let threshold = self.rnd(weights.iter().sum());
        let mut total = 0;
        for (index, &weight) in weights.iter().enumerate() { total += weight; if threshold < total { return index; } }
        unreachable!()
    }
}
