pub struct Minstd { pub state: i64 }
impl Minstd {
    pub fn draw(&mut self) -> i64 { self.state = 48271 * self.state % 2147483647; self.state }
    pub fn draw_below(&mut self, limit: usize) -> usize { (self.draw() % limit as i64) as usize }
    pub fn shuffle<T>(&mut self, items: &mut [T]) {
        for index in (1..items.len()).rev() { let other = self.draw_below(index + 1); items.swap(index, other); }
    }
}
