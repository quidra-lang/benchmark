local cache,hits,misses = {},0,0
for _,key in ipairs({"B","A","C","B","D","A","B","E","A","D","D","C","A","E","B"}) do
    local index
    for i,value in ipairs(cache) do
        if value == key then
            index = i
            break
        end
    end
    local result
    if index then
        hits = hits+1
        table.remove(cache,index)
        result = "hit"
    else
        misses = misses+1
        result = #cache == 3 and "miss, evict "..table.remove(cache) or "miss"
    end
    table.insert(cache,1,key)
    io.write(string.format("%s: %s [%s]\n",key,result,table.concat(cache," ")))
end
io.write(string.format("hits: %d misses: %d\n",hits,misses))
