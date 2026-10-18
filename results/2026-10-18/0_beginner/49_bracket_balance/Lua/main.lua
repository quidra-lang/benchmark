local strings = {"(a + b) * [c - d]","{x = [1, 2, (3 + 4)]}","f(a[i] + g(b)}","(1 + 2)) * 3","if (a < b) { c = d[0]; }","((a + b] * c","[{(x * y) - z}"}
local matching = {["("]=")",["["]="]",["{"]="}"}
for _, text in ipairs(strings) do
    local stack,error_index = {},-1
    for position = 1,#text do
        local c = text:sub(position,position)
        if matching[c] then stack[#stack+1] = c
        elseif c == ")" or c == "]" or c == "}" then
            if #stack == 0 or matching[stack[#stack]] ~= c then error_index = position-1; break end
            table.remove(stack)
        end
    end
    if error_index < 0 and #stack > 0 then error_index = #text end
    io.write(text," -> ",error_index < 0 and "balanced" or string.format("error at index %d",error_index),"\n")
end
