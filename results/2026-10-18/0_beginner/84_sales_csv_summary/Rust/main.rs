fn main() {
    let lines = ["date,region,product,quantity,unit_price", "2026-04-01,north,notebook,10,200", "2026-04-01,east,marker,6,150",
        "2026-04-01,south,eraser,25,80", "2026-04-02,west,stapler,4,600", "2026-04-02,north,marker,8,150",
        "2026-04-02,east,notebook,9,200", "2026-04-03,south,stapler,3,600", "2026-04-03,west,eraser,15,80",
        "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600", "2026-04-04,south,notebook,6,200",
        "2026-04-04,west,marker,8,150"];
    let (mut regions, mut products, mut days) = (std::collections::BTreeMap::new(),
    std::collections::BTreeMap::new(),
        std::collections::BTreeMap::new());
    let mut total = 0;
    for line in &lines[1..] {
        let f: Vec<&str> = line.split(',').collect();
        let quantity: i32 = f[3].parse().unwrap();
        let price: i32 = f[4].parse().unwrap();
        let amount = quantity * price;
        total += amount;
        * regions.entry(f[1]).or_insert(0) += amount;
        * products.entry(f[2]).or_insert(0) += quantity;
        * days.entry(f[0]).or_insert(0) += amount;
    }
    let mut ranked: Vec<(&str, i32)> = regions.into_iter().collect();
    ranked.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    println!("total: {}", total);
    for (name, amount) in ranked {
        println!("{}: {}", name, amount);
    }
    for (name, quantity) in products {
        println!("{}: {}", name, quantity);
    }
    let (mut best, mut amount) = ("", -1);
    for (date, sales) in days {
        if sales> amount {
            best = date;
            amount = sales;
        }
    }
    println!("best day: {} ({})", best, amount);
}
