fn under(mut n: usize) -> String {
    let small = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"];
    let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"];
    let mut out = String::new();
    if n >= 100 {
        out = format!("{} hundred", small[n / 100]);
        n %= 100;
        if n > 0 {
            out.push(' ');
        }
    }
    if n >= 20 {
        out.push_str(tens[n / 10]);
        if n % 10 > 0 {
            out.push('-');
            out.push_str(small[n % 10]);
        }
    } else if n > 0 {
        out.push_str(small[n]);
    }
    out
}

fn main() {
    for n in [0, 13, 40, 100, 568, 71000, 300019, 999999] {
        let mut parts = Vec::new();
        if n == 0 {
            parts.push("zero".to_string());
        }
        if n >= 1000 {
            parts.push(format!("{} thousand", under(n / 1000)));
        }
        if n % 1000 > 0 {
            parts.push(under(n % 1000));
        }
        println!("{}: {}", n, parts.join(" "));
    }
}
