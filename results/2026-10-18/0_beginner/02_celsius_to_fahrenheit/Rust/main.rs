fn main() {
    let celsius = [-40, -15, -3, 0, 22, 37, 100];
    for temperature in celsius {
        let fahrenheit = f64::from(temperature) * 9.0 / 5.0 + 32.0;
        let tenths = (fahrenheit.abs() * 10.0 + 0.5) as i32;
        let sign = if fahrenheit < 0.0 { "-" } else { "" };
        println!("{} C = {}{}.{} F", temperature, sign, tenths / 10, tenths % 10);
    }
}
