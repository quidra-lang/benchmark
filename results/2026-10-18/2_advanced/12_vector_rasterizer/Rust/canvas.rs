pub type Color = [i64; 4];
pub type Rgb = [i64; 3];
pub type Image = Vec<Vec<Rgb>>;

pub fn round_ratio(mut n: i64, mut d: i64) -> i64 { if d < 0 { n = -n; d = -d; } (2 * n + d).div_euclid(2 * d) }
pub fn effective_alpha(alpha: i64, opacity: i64) -> i64 { round_ratio(alpha * opacity, 255) }

pub struct Layer {
    pub width: usize, pub height: usize, pub opacity: i64, pub mode: String,
    pub colors: Vec<Vec<Option<Color>>>, pub lines: Vec<Vec<usize>>,
}
impl Layer {
    pub fn new(width: usize, height: usize, opacity: i64, mode: String) -> Self {
        Self { width, height, opacity, mode, colors: vec![vec![None; width]; height], lines: vec![vec![0; width]; height] }
    }
    pub fn paint(&mut self, x: i64, y: i64, color: Color, line: usize) { self.colors[y as usize][x as usize] = Some(color); self.lines[y as usize][x as usize] = line; }
    pub fn erase(&mut self, x: i64, y: i64) -> bool { self.colors[y as usize][x as usize].take().is_some() }
    pub fn alpha_at(&self, x: usize, y: usize) -> i64 { self.colors[y][x].map_or(0, |c| effective_alpha(c[3], self.opacity)) }
    fn blend(&self, x: usize, y: usize, mut current: Rgb) -> Rgb {
        let Some(color) = self.colors[y][x] else { return current; };
        let alpha = effective_alpha(color[3], self.opacity);
        for channel in 0..3 {
            let (s, v) = (color[channel], current[channel]);
            let source = match self.mode.as_str() { "multiply" => round_ratio(s * v, 255), "screen" => 255 - round_ratio((255 - s) * (255 - v), 255), _ => s };
            current[channel] = round_ratio(alpha * source + (255 - alpha) * v, 255);
        }
        current
    }
}
pub fn composite(layers: &[Layer], background: Color, width: usize, height: usize) -> Image {
    (0..height).map(|y| (0..width).map(|x| layers.iter().fold([background[0], background[1], background[2]], |color, layer| layer.blend(x, y, color))).collect()).collect()
}
