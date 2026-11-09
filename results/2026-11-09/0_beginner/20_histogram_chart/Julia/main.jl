for (day, amount) in
    zip(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], [7, 12, 4, 15, 9, 18, 11])
    println(day, " | ", repeat("*", amount), " ", amount)
end
