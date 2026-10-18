local students = {{"Tanaka",78,85,94},{"Suzuki",88,74,82},{"Yamada",65,90,71},{"Ito",80,79,85},{"Kato",92,88,95},{"Mori",70,62,78}}
for _, student in ipairs(students) do student.total = student[2]+student[3]+student[4] end
table.sort(students,function(a,b) if a.total ~= b.total then return a.total > b.total end return a[1] < b[1] end)
local rank,previous = 0,-1
for position,student in ipairs(students) do
    if student.total ~= previous then rank = position end
    local average = student.total/3
    io.write(string.format("%d. %s total=%d average=%.2f\n",rank,student[1],student.total,math.floor(average*100+0.5)/100))
    previous = student.total
end
