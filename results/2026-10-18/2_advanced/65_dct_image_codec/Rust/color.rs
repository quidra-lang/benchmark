use crate::image_io::Image;

#[derive(Clone)]
pub struct Plane { pub width: usize, pub height: usize, pub pixels: Vec<i64> }

pub fn rgb(y: i64, cb: i64, cr: i64) -> [i64; 3] {
    [(y+(91881*(cr-128)+32768).div_euclid(65536)).clamp(0, 255),
     (y+(-22554*(cb-128)-46802*(cr-128)+32768).div_euclid(65536)).clamp(0, 255),
     (y+(116130*(cb-128)+32768).div_euclid(65536)).clamp(0, 255)]
}

pub fn convert(image: &Image) -> Vec<Plane> {
    let mut planes = vec![Plane { width: image.width, height: image.height, pixels: Vec::new() }; 3];
    for &[r, g, b] in &image.pixels {
        planes[0].pixels.push((19595*r+38470*g+7471*b+32768).div_euclid(65536));
        planes[1].pixels.push((-11059*r-21709*g+32768*b+8421375).div_euclid(65536));
        planes[2].pixels.push((32768*r-27439*g-5329*b+8421375).div_euclid(65536));
    }
    planes
}

pub fn components(image: &Image, factors: &[(usize, usize)]) -> Vec<Plane> {
    let original = convert(image);
    let hmax = factors.iter().map(|f| f.0).max().unwrap();
    let vmax = factors.iter().map(|f| f.1).max().unwrap();
    let mx = (image.width+8*hmax-1)/(8*hmax);
    let my = (image.height+8*vmax-1)/(8*vmax);
    factors.iter().enumerate().map(|(k, &(h, v))| {
        let (width, height, fx, fy) = (8*h*mx, 8*v*my, hmax/h, vmax/v);
        let mut pixels = Vec::new();
        for y in 0..height { for x in 0..width {
            let mut sum = 0;
            for j in 0..fy { for i in 0..fx {
                sum += original[k].pixels[(fy*y+j).min(image.height-1)*image.width+(fx*x+i).min(image.width-1)];
            } }
            pixels.push(sum/(fx*fy) as i64);
        } }
        Plane { width, height, pixels }
    }).collect()
}

pub fn upsample(planes: &[Plane], factors: &[(usize, usize)], width: usize, height: usize) -> (Image, Vec<Plane>) {
    let hmax = factors.iter().map(|f| f.0).max().unwrap();
    let vmax = factors.iter().map(|f| f.1).max().unwrap();
    let decoded: Vec<_> = planes.iter().enumerate().map(|(k, plane)| {
        let mut pixels = Vec::new();
        for y in 0..height { for x in 0..width { pixels.push(plane.pixels[(y*factors[k].1/vmax)*plane.width+x*factors[k].0/hmax]); } }
        Plane { width, height, pixels }
    }).collect();
    let pixels = (0..width*height).map(|p| rgb(decoded[0].pixels[p], decoded[1].pixels[p], decoded[2].pixels[p])).collect();
    (Image { width, height, pixels }, decoded)
}
