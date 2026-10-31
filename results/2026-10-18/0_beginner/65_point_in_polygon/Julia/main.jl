function main()
    polygon = [(1, 1), (11, 2), (13, 9), (9, 7), (7, 12), (5, 6), (2, 10), (3, 5)]
    for (px, py) in [(4, 8), (6, 4), (10, 8), (7, 11), (14, 3), (12, 8)]
        crossings = 0
        for i in eachindex(polygon)
            x1, y1 = polygon[i]
            x2, y2 = polygon[mod1(i+1, length(polygon))]
            if (y1 > py) != (y2 > py)
                intersection = x1+(x2-x1)*(py-y1)/(y2-y1)
                crossings += intersection > px
            end
        end
        println("(", px, ", ", py, "): ", isodd(crossings) ? "inside" : "outside")
    end
end

main()
