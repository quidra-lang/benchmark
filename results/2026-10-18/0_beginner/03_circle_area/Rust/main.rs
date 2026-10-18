fn main() {
    let radii = [3, 7, 12, 25, 41];
    let pi: f64 = 3.141592653589793;
    for radius in radii {
        let r = f64::from(radius);
        let area = pi * r * r;
        let circumference = 2.0 * pi * r;
        let area_milli = (area * 1000.0 + 0.5) as i64;
        let circumference_milli = (circumference * 1000.0 + 0.5) as i64;
        println!("r={} area={}.{:03} circumference={}.{:03}", radius,
                 area_milli / 1000, area_milli % 1000,
                 circumference_milli / 1000, circumference_milli % 1000);
    }
}
