use crate::pgm_io::Image;
pub type Volume = Vec<Vec<i64>>;

pub fn clamped(image: &[i64], width: usize, height: usize, x: i64, y: i64) -> i64 {
    image[y.clamp(0, height as i64-1) as usize*width+x.clamp(0, width as i64-1) as usize]
}

pub fn box_sum(image: &[i64], width: usize, height: usize, window: usize) -> Vec<i64> {
    let h = (window-1)/2;
    let (w, rows) = (width+2*h, height+2*h);
    let mut prefix = vec![vec![0; w+1]; rows+1];
    for y in 0..rows {
        for x in 0..w {
            let value = clamped(image, width, height, x as i64-h as i64, y as i64-h as i64);
            prefix[y+1][x+1] = value+prefix[y][x+1]+prefix[y+1][x]-prefix[y][x];
        }
    }
    (0..height).flat_map(|y| {
        let prefix = &prefix;
        (0..width).map(move |x| prefix[y+window][x+window]-prefix[y][x+window]-prefix[y+window][x]+prefix[y][x])
    }).collect()
}

pub fn census(image: &Image) -> Vec<i64> {
    (0..image.pixels.len()).map(|p| {
        let mut code = 0;
        for dy in -2..=2 { for dx in -2..=2 {
            if dx == 0 && dy == 0 { continue; }
            code = 2*code+i64::from(clamped(&image.pixels, image.width, image.height, (p%image.width) as i64+dx, (p/image.width) as i64+dy) < image.pixels[p]);
        } }
        code
    }).collect()
}

pub fn texture(image: &Image, window: usize) -> Vec<i64> {
    let gradient: Vec<_> = (0..image.pixels.len()).map(|p| {
        let (x, y) = ((p%image.width) as i64, (p/image.width) as i64);
        (clamped(&image.pixels, image.width, image.height, x+1, y)-clamped(&image.pixels, image.width, image.height, x-1, y)).abs()
    }).collect();
    box_sum(&gradient, image.width, image.height, window)
}

pub fn volume(left: &Image, right: &Image, lc: &[i64], rc: &[i64], kind: &str, window: usize, minimum: i64, maximum: i64) -> Volume {
    let mut result = vec![vec![0; (maximum-minimum+1) as usize]; left.pixels.len()];
    for d in minimum..=maximum {
        let raw: Vec<_> = (0..left.pixels.len()).map(|p| {
            let x = p%left.width;
            let q = p-x+(x as i64-d).max(0) as usize;
            let difference = left.pixels[p]-right.pixels[q];
            match kind { "sad" => difference.abs(), "ssd" => difference*difference, _ => (lc[p]^rc[q]).count_ones() as i64 }
        }).collect();
        let sums = box_sum(&raw, left.width, left.height, window);
        for p in 0..result.len() { result[p][(d-minimum) as usize] = sums[p]; }
    }
    result
}
