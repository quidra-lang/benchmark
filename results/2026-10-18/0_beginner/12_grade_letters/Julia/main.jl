function main()
    grades = ["A", "B", "C", "D", "F"]
    counts = zeros(Int, 5)
    for score in [78, 90, 100, 59, 80, 85, 89, 70, 45, 93]
        index = score >= 90 ? 1 : score >= 80 ? 2 : score >= 70 ? 3 : score >= 60 ? 4 : 5
        counts[index] += 1
        println(score, ": ", grades[index])
    end
    for (grade, total) in zip(grades, counts)
        println(grade, ": ", total)
    end
end
main()
