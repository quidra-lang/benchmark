local function to_roman(number)
    local result = ""
    for _, pair in ipairs({{1000,"M"},{900,"CM"},{500,"D"},{400,"CD"},{100,"C"},{90,"XC"},{50,"L"},{40,"XL"},{10,"X"},{9,"IX"},{5,"V"},{4,"IV"},{1,"I"}}) do
        while number >= pair[1] do result = result..pair[2]; number = number-pair[1] end
    end
    return result
end
local function from_roman(roman)
    local values,total = {I=1,V=5,X=10,L=50,C=100,D=500,M=1000},0
    for i = 1,#roman do
        local value = values[roman:sub(i,i)]
        total = total + (i < #roman and value < values[roman:sub(i+1,i+1)] and -value or value)
    end
    return total
end
for _, number in ipairs({9,14,49,94,444,1994,2768,3999}) do
    local roman = to_roman(number)
    io.write(string.format("%d -> %s -> %d\n",number,roman,from_roman(roman)))
end
