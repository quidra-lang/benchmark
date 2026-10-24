let years = [1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100]
for year in years {
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    print("\(year): \(leap ? "leap year" : "common year")")
}
