a = Set([12, 5, 8, 21, 5, 17, 3, 12, 9])
b = Set([8, 14, 21, 6, 14, 3, 25, 6])
for (label, result) in [("union", union(a,b)), ("intersection", intersect(a,b)), ("difference", setdiff(a,b)), ("symmetric difference", symdiff(a,b))]
    println(label, ": ", join(sort(collect(result)), " "))
end
