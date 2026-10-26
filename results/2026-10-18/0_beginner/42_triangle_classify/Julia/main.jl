function main()
    for sides in [
        (3, 8, 5),
        (6, 6, 6),
        (5, 8, 5),
        (13, 5, 12),
        (2, 9, 4),
        (7, 4, 7),
        (8, 6, 7),
        (4, 9, 6),
    ]
        a, b, c = sort(collect(sides))
        if a+b <= c
            result = "not a triangle"
        else
            side = a == c ? "equilateral" : a == b || b == c ? "isosceles" : "scalene"
            square_sum = a*a+b*b
            angle = c*c < square_sum ? "acute" : c*c == square_sum ? "right" : "obtuse"
            result = string(side, " ", angle)
        end
        println(join(sides, " "), ": ", result)
    end
end

main()
