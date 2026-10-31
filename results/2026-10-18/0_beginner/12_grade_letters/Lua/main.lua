local grades, counts = {"A", "B", "C", "D", "F"}, {0, 0, 0, 0, 0}
for _, score in ipairs({78, 90, 100, 59, 80, 85, 89, 70, 45, 93}) do
    local index = score >= 90 and 1 or score >= 80 and 2 or score >= 70 and 3 or score >= 60 and 4 or 5
    counts[index] = counts[index] + 1
    io.write(string.format("%d: %s\n", score, grades[index]))
end
for i, grade in ipairs(grades) do io.write(string.format("%s: %d\n", grade, counts[i])) end
