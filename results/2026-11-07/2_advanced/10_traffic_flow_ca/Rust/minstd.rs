pub struct Minstd { state: i64 }
impl Minstd {
    pub fn new(state: i64) -> Self { Self { state } }
    pub fn draw(&mut self) -> i64 { self.state = 48271 * self.state % 2147483647; self.state }
}
pub fn select(weights: &[i64], value: i64) -> usize {
    let remainder = value % weights.iter().sum::<i64>(); let mut total = 0;
    for (j, &weight) in weights.iter().enumerate() { total += weight; if remainder < total { return j; } } unreachable!()
}
