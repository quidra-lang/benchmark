use crate::pgm_io::Image;

pub fn clamped(values: &[i64], width: usize, height: usize, x: i64, y: i64) -> i64 {
    let x = x.max(0).min(width as i64 - 1) as usize;
    let y = y.max(0).min(height as i64 - 1) as usize;
    values[y * width + x]
}

pub fn smooth(image: &Image, size: usize, kernel: &[i64], divisor: i64) -> Vec<i64> {
    let half = size as i64 / 2;
    let mut values = Vec::new();
    for y in 0..image.height {
        for x in 0..image.width {
            let mut sum = 0;
            for j in 0..size {
                for i in 0..size {
                    sum += kernel[j * size + i] * clamped(&image.pixels, image.width, image.height, x as i64 + i as i64 - half, y as i64 + j as i64 - half);
                }
            }
            values.push(sum.div_euclid(divisor));
        }
    }
    values
}

pub fn gradient(values: &[i64], width: usize, height: usize) -> (Vec<i64>, Vec<i64>, Vec<i64>) {
    let (mut gx, mut gy, mut magnitude) = (Vec::new(), Vec::new(), Vec::new());
    for y in 0..height {
        for x in 0..width {
            let mut q = Vec::new();
            for dy in -1..=1 {
                for dx in -1..=1 { q.push(clamped(values, width, height, x as i64 + dx, y as i64 + dy)); }
            }
            let a = (q[2] + 2 * q[5] + q[8]) - (q[0] + 2 * q[3] + q[6]);
            let b = (q[6] + 2 * q[7] + q[8]) - (q[0] + 2 * q[1] + q[2]);
            gx.push(a);
            gy.push(b);
            magnitude.push(a.abs() + b.abs());
        }
    }
    (gx, gy, magnitude)
}
