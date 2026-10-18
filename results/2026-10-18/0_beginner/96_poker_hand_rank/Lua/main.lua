local categories = {"high card","one pair","two pair","three of a kind","straight","flush","full house","four of a kind","straight flush"}
local function describe(original)
    local alphabet,frequencies,suits = "23456789TJQKA",{},{}
    for card in original:gmatch("%S+") do
        local rank = alphabet:find(card:sub(1,1),1,true)+1
        frequencies[rank] = (frequencies[rank] or 0)+1
        suits[card:sub(2,2)] = true
    end
    local distinct,counts,suit_count = {},{},0
    for rank = 2,14 do
        if frequencies[rank] then
            distinct[#distinct+1] = rank
            counts[#counts+1] = frequencies[rank]
        end
    end
    for _ in pairs(suits) do suit_count = suit_count+1 end
    local wheel = #distinct == 5 and distinct[1] == 2 and distinct[2] == 3 and distinct[3] == 4 and distinct[4] == 5 and distinct[5] == 14
    local straight = #distinct == 5 and (distinct[5]-distinct[1] == 4 or wheel)
    local flush = suit_count == 1
    table.sort(counts,function(a,b) return a > b end)
    local strength
    if straight and flush then strength = 9
    elseif counts[1] == 4 then strength = 8
    elseif counts[1] == 3 and counts[2] == 2 then strength = 7
    elseif flush then strength = 6
    elseif straight then strength = 5
    elseif counts[1] == 3 then strength = 4
    elseif counts[1] == 2 and counts[2] == 2 then strength = 3
    elseif counts[1] == 2 then strength = 2
    else strength = 1 end
    table.sort(distinct,function(a,b)
        if frequencies[a] ~= frequencies[b] then return frequencies[a] > frequencies[b] end
        return a > b
    end)
    if wheel and straight then distinct = {5,4,3,2,1} end
    return {original=original,strength=strength,sequence=distinct,category=categories[strength]}
end
local hands = {}
for _,original in ipairs({"9C 9D 5H QH 2C","4D AH 3C 5S 2H","KS 8S 2S JS 6S","7H 7D KC 7S KD","3H 6C 4S 2D 5C","JD TC 4H 8C AS","QC 6D QS 3S 6H","9H KH 9S 8H 3D"}) do hands[#hands+1] = describe(original) end
table.sort(hands,function(a,b)
    if a.strength ~= b.strength then return a.strength > b.strength end
    for i = 1,#a.sequence do
        if a.sequence[i] ~= b.sequence[i] then return a.sequence[i] > b.sequence[i] end
    end
    return false
end)
for position,hand in ipairs(hands) do io.write(string.format("%d. %s: %s\n",position,hand.original,hand.category)) end
