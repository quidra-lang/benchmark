local units = {"zero","one","two","three","four","five","six","seven","eight","nine","ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen","eighteen","nineteen"}
local tens = {"zero","ten","twenty","thirty","forty","fifty","sixty","seventy","eighty","ninety"}
local function small_words(number)
    local parts = {}
    local hundreds,remainder = number//100,number%100
    if hundreds > 0 then parts[#parts+1] = units[hundreds+1].." hundred" end
    if remainder >= 20 then
        local phrase = tens[remainder//10+1]
        if remainder%10 > 0 then phrase = phrase.."-"..units[remainder%10+1] end
        parts[#parts+1] = phrase
    elseif remainder > 0 then parts[#parts+1] = units[remainder+1] end
    return table.concat(parts," ")
end
local function number_words(number)
    if number == 0 then return "zero" end
    local parts = {}
    local thousands,remainder = number//1000,number%1000
    if thousands > 0 then parts[#parts+1] = small_words(thousands).." thousand" end
    if remainder > 0 then parts[#parts+1] = small_words(remainder) end
    return table.concat(parts," ")
end
for _,number in ipairs({0,13,40,100,568,71000,300019,999999}) do io.write(string.format("%d: %s\n",number,number_words(number))) end
