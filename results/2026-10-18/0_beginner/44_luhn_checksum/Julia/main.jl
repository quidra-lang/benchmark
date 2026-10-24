for number in ["688126340316","0128469655154","92181914514156","177332430060552","7982377590420309","9884593615513906"]
    total = 0
    for (position, c) in enumerate(reverse(number))
        value = Int(c)-Int('0')
        if iseven(position)
            value *= 2
            value = value > 9 ? value-9 : value
        end
        total += value
    end
    if total % 10 == 0
        println(number,": valid")
    else
        expected = mod(-(total-(Int(number[end])-Int('0'))),10)
        println(number,": invalid (expected check digit ",expected,")")
    end
end
