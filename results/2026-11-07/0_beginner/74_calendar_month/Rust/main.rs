fn main() {
    let names = [
        "January",
        "February",
        "March",
        "April",
        "May",
        "June",
        "July",
        "August",
        "September",
        "October",
        "November",
        "December",
    ];
    let lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    for (k, &(y, m)) in [(2024, 2), (2026, 8), (2026, 11)].iter().enumerate() {
        let (mut yy, mut mm) = (y, m);
        if mm < 3 {
            mm += 12;
            yy -= 1;
        }
        let h =
            (1 + 13 * (mm + 1) / 5 + yy % 100 + (yy % 100) / 4 + (yy / 100) / 4 + 5 * (yy / 100))
                % 7;
        let start = (h + 6) % 7;
        let days = lengths[(m - 1) as usize]
            + i32::from(m == 2 && (y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)));
        if k > 0 {
            println!();
        }
        println!("{} {}\nSu Mo Tu We Th Fr Sa", names[(m - 1) as usize], y);
        print!("{}", " ".repeat((start * 3) as usize));
        for d in 1..=days {
            let col = (start + d - 1) % 7;
            if d > 1 && col > 0 {
                print!(" ");
            }
            print!("{:2}", d);
            if col == 6 || d == days {
                println!();
            }
        }
    }
}
