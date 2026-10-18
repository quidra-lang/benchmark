fn main() {
    let values: [i32; 10] = [17, -8, 42, 5, -23, 36, 5, 0, -11, 29];
    let mut sum = 0;
    let mut maximum = values[0];
    let mut minimum = values[0];
    for value in values {
        sum += value;
        maximum = maximum.max(value);
        minimum = minimum.min(value);
    }
    println!("sum: {}\nmax: {}\nmin: {}", sum, maximum, minimum);
}
