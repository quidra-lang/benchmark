function to_roman(number)
    result = ""
    for (value,symbol) in [(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),(90,"XC"),(50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")]
        while number >= value
            result *= symbol
            number -= value
        end
    end
    return result
end
function from_roman(roman)
    table = Dict('I'=>1,'V'=>5,'X'=>10,'L'=>50,'C'=>100,'D'=>500,'M'=>1000)
    total = 0
    for i in 1:length(roman)
        value = table[roman[i]]
        total += i < length(roman) && value < table[roman[i+1]] ? -value : value
    end
    return total
end
for number in [9,14,49,94,444,1994,2768,3999]
    roman = to_roman(number)
    println(number," -> ",roman," -> ",from_roman(roman))
end
