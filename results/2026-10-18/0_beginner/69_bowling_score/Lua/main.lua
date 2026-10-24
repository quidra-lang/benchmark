local games = {{8,1,10,7,3,9,0,10,10,2,6,6,4,0,9,10,7,2},{3,4,5,2,7,1,0,6,8,1,4,4,2,3,6,2,9,0,1,5},{5,5,0,10,7,3,9,1,6,4,8,2,3,7,4,6,1,9,7,3,5},{10,10,10,10,10,10,10,10,10,10,10,10},{10,9,1,10,10,7,2,0,0,10,8,1,10,6,4,10}}
for number,rolls in ipairs(games) do
    local position,total,cumulative = 1,0,{}
    for frame = 1,9 do
        local score
        if rolls[position] == 10 then
            score = 10+rolls[position+1]+rolls[position+2]
            position = position+1
        elseif rolls[position]+rolls[position+1] == 10 then
            score = 10+rolls[position+2]
            position = position+2
        else
            score = rolls[position]+rolls[position+1]
            position = position+2
        end
        total = total+score
        cumulative[#cumulative+1] = total
    end
    for i = position,#rolls do total = total+rolls[i] end
    cumulative[#cumulative+1] = total
    io.write(string.format("game %d: %s\n",number,table.concat(cumulative," ")))
end
