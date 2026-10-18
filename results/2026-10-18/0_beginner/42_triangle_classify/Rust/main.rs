fn main() {
    for p in [[3, 8, 5], [6, 6, 6], [5, 8, 5], [13, 5, 12], [2, 9, 4], [7, 4, 7], [8, 6, 7], [4, 9,
        6]] {
        let mut a = p;
        a.sort();
        print!("{} {} {}: ", p[0], p[1], p[2]);
        if a[0] + a[1] <= a[2] {
            println!("not a triangle");
        } else {
            let side = if a[0] == a[2] {
                "equilateral"
            } else if a[0] == a[1] || a[1] == a[2] {
                "isosceles"
            } else {
                "scalene"
            };
            let d = a[2] * a[2] - a[0] * a[0] - a[1] * a[1];
            println!("{} {}", side, if d < 0 {
                "acute"
            } else if d == 0 {
                "right"
            } else {
                "obtuse"
            });
        }
    }
}
