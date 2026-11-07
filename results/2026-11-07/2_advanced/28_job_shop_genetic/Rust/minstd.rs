pub struct Minstd {
    pub state: i64
}
impl Minstd {
    pub fn draw(&mut self) -> i64 {
        self.state = self.state*48271%2147483647;
        self.state
    }
    pub fn below(&mut self, m: usize) -> usize {
        self.draw() as usize%m
    }
    pub fn chance(&mut self, p: (usize, usize)) -> bool {
        self.below(p.1)<p.0
    }
    pub fn shuffle(&mut self, items: &mut [usize]) {
        for n in (2..=items.len()).rev() {
            let i = self.below(n);
            items.swap(n-1, i);
        }
    }
}
