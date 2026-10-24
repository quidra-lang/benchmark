fn main() {
    for (name, h, w) in [("Aiko", 158, 45), ("Kenji", 172, 68), ("Mika", 165, 70), ("Ryo", 180, 101),
        ("Yuki", 150, 52)] {
        let numerator = w * 10000;
        let denominator = h * h;
        let bmi = f64::from(numerator) / f64::from(denominator);
        let category = if bmi < 18.5 {
            "underweight"
        } else if bmi < 25.0 {
            "normal"
        } else if bmi < 30.0 {
            "overweight"
        } else {
            "obese"
        };
        println!("{}: BMI {:.1} ({})", name, bmi, category);
    }
}
