for year in [1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100]
    leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
    println(year, ": ", leap ? "leap year" : "common year")
end
