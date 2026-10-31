fn main() {
    let values = [7, 98000, 4096, 50301, 2718281, 123456789];
    for value in values {
        let (mut remaining, mut digits, mut sum, mut reversed) = (value, 0, 0, 0);
        while remaining > 0 {
            let digit = remaining % 10;
            digits += 1;
            sum += digit;
            reversed = reversed * 10 + digit;
            remaining /= 10;
        }
        println!(
            "{}: digits={} sum={} reversed={}",
            value, digits, sum, reversed
        );
    }
}
