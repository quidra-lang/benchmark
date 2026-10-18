using Printf
function main()
    data = [("Tanaka",78,85,94),("Suzuki",88,74,82),("Yamada",65,90,71),("Ito",80,79,85),("Kato",92,88,95),("Mori",70,62,78)]
    students = [(name=row[1], total=row[2]+row[3]+row[4]) for row in data]
    sort!(students; by=student -> (-student.total,student.name))
    rank = 0
    previous = -1
    for (position,student) in enumerate(students)
        if student.total != previous
            rank = position
        end
        @printf("%d. %s total=%d average=%.2f\n",rank,student.name,student.total,student.total/3)
        previous = student.total
    end
end
main()
