fn main() {
    let celsius = [-40, -15, -3, 0, 22, 37, 100];
    for temperature in celsius {
        println!("{} C = {:.1} F", temperature, f64::from(temperature) * 9.0 / 5.0 + 32.0);
    }
}
