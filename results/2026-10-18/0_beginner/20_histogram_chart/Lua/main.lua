local days, amounts = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}, {7, 12, 4, 15, 9, 18, 11}
for i, day in ipairs(days) do io.write(string.format("%s | %s %d\n", day, string.rep("*", amounts[i]), amounts[i])) end
