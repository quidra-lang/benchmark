function main()
    total = 0
    households = [
        ("Sato", 85),
        ("Suzuki", 120),
        ("Takahashi", 254),
        ("Tanaka", 300),
        ("Ito", 438),
        ("Watanabe", 176),
    ]
    for (name, usage) in households
        bill =
            900 + min(usage, 120)*30 + min(max(usage-120, 0), 180)*36 + max(usage-300, 0)*40
        total += bill
        println(name, ": ", usage, " kWh, ", bill, " yen")
    end
    println("total: ", total, " yen")
end

main()
