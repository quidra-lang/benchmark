for _, sides in ipairs({{3,8,5},{6,6,6},{5,8,5},{13,5,12},{2,9,4},{7,4,7},{8,6,7},{4,9,6}}) do
    local ordered = {table.unpack(sides)}
    table.sort(ordered)
    local a,b,c = table.unpack(ordered)
    local result
    if a+b <= c then result = "not a triangle"
    else
        local side = a == c and "equilateral" or (a == b or b == c) and "isosceles" or "scalene"
        local square_sum = a*a+b*b
        local angle = c*c < square_sum and "acute" or c*c == square_sum and "right" or "obtuse"
        result = side.." "..angle
    end
    io.write(table.concat(sides," "),": ",result,"\n")
end
