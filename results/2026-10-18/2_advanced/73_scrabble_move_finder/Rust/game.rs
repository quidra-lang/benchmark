pub struct Generator {
    pub state: i64
}
impl Generator {
    pub fn next(&mut self) -> i64 {
        self.state = 48271*self.state%2147483647;
        self.state
    }
}
pub fn index(tile: u8) -> usize {
    if tile == b'?' || tile.is_ascii_lowercase() {
        26
    } else {
        (tile-b'A') as usize
    }
}
pub fn shuffle(bag: &mut [u8], generator: &mut Generator) {
    for i in (1..bag.len()).rev() {
        let j = (generator.next()%(i+1) as i64) as usize;
        bag.swap(i,j);
    }
}
pub fn bag(counts: &[usize;27], generator: &mut Generator) -> Vec<u8> {
    let mut bag = Vec::new();
    for (i,&count) in counts.iter().enumerate() {
        bag.extend(std::iter::repeat(if i == 26 {
            b'?'
        } else {
            b'A'+i as u8
        }).take(count));
    }
    shuffle(&mut bag,generator);
    bag
}
pub fn draw(bag: &mut Vec<u8>, count: usize) -> Vec<u8> {
    let mut drawn = Vec::new();
    for _ in 0..count {
        if let Some(tile) = bag.pop() {
            drawn.push(tile);
        } else {
            break;
        }
    }
    drawn
}
pub fn exchange(bag: &mut Vec<u8>, returned: &[u8], generator: &mut Generator) -> Vec<u8> {
    let drawn = draw(bag,returned.len());
    let mut returned = returned.to_vec();
    returned.sort_unstable();
    bag.extend(returned);
    shuffle(bag,generator);
    drawn
}
pub fn value(tiles: &[u8], values: &[i64;27]) -> i64 {
    tiles.iter().map(|&tile| values[index(tile)]).sum()
}
