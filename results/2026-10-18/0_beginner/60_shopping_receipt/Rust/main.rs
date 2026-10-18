fn main() {
    let items = [("milk", 198, 2, 0), ("notebook", 165, 3, 1), ("bread", 248, 1, 0), ("apple", 128,
        4, 0), ("detergent", 437, 1, 1), ("eggs", 268, 1, 0)];
    let mut totals = [0; 2];
    for (name, price, quantity, category) in items {
        let subtotal = price * quantity;
        totals[category] += subtotal;
        println!("{} {} x {} = {}", name, price, quantity, subtotal);
    }
    let food_tax = totals[0] * 8 / 100;
    let general_tax = totals[1] * 10 / 100;
    println!("food: {} yen, tax {} yen\ngeneral: {} yen, tax {} yen\ntotal: {} yen", totals[0], food_tax,
        totals[1], general_tax, totals[0] + totals[1] + food_tax + general_tax);
}
