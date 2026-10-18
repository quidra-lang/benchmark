local characters,used,counter = "ABCD",{},0
local function visit(prefix)
    if #prefix == 4 then counter = counter+1; io.write(string.format("%d: %s\n",counter,prefix)); return end
    for i = 1,4 do
        if not used[i] then used[i] = true; visit(prefix..characters:sub(i,i)); used[i] = false end
    end
end
visit("")
