fn value(c: u8) -> i32 {
    match c {
        b'I' => 1,
        b'V' => 5,
        b'X' => 10,
        b'L' => 50,
        b'C' => 100,
        b'D' => 500,
        b'M' => 1000,
        _ => 0,
    }
}

fn main() {
    let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    let symbols = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"];
    for n in [9, 14, 49, 94, 444, 1994, 2768, 3999] {
        let mut remaining = n;
        let mut roman = String::new();
        for i in 0..13 {
            while remaining >= values[i] {
                roman.push_str(symbols[i]);
                remaining -= values[i];
            }
        }
        let bytes = roman.as_bytes();
        let mut result = 0;
        for i in 0..bytes.len() {
            let v = value(bytes[i]);
            let next = bytes.get(i + 1).map_or(0, |&c| value(c));
            result += if v < next { -v } else { v };
        }
        println!("{} -> {} -> {}", n, roman, result);
    }
}
