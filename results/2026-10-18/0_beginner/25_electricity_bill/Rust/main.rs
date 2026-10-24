fn main() {
    let mut total = 0;
    for (name, u) in [("Sato", 85_i32), ("Suzuki", 120), ("Takahashi", 254), ("Tanaka", 300), ("Ito",
        438), ("Watanabe", 176)] {
        let bill = 900 + u.min(120) * 30 + (u - 120).clamp(0, 180) * 36 + (u - 300).max(0) * 40;
        total += bill;
        println!("{}: {} kWh, {} yen", name, u, bill);
    }
    println!("total: {} yen", total);
}
