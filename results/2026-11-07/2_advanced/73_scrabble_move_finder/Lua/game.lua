local M = {TILE_ORDER = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ?'}
function M.generator(seed) return {state = seed} end
function M.next_random(random) random.state = random.state * 48271 % 2147483647; return random.state end
function M.shuffle(bag, random)
    for position = #bag, 2, -1 do local other = M.next_random(random) % position + 1; bag[position], bag[other] = bag[other], bag[position] end
end
function M.make_bag(counts, random)
    local bag = {}
    for i = 1, 27 do local letter = M.TILE_ORDER:sub(i, i); for _ = 1, counts[letter] do bag[#bag + 1] = letter end end
    M.shuffle(bag, random)
    return bag
end
function M.draw(bag, count)
    local drawn = {}
    for _ = 1, math.min(count, #bag) do drawn[#drawn + 1] = table.remove(bag) end
    return table.concat(drawn)
end
function M.exchange(bag, returned, random)
    local drawn, tiles = M.draw(bag, #returned), {}
    for i = 1, #returned do tiles[i] = returned:sub(i, i) end
    table.sort(tiles)
    for _, tile in ipairs(tiles) do bag[#bag + 1] = tile end
    M.shuffle(bag, random)
    return drawn
end
function M.points(collection, values)
    local result = 0
    for i = 1, #collection do result = result + values[collection:sub(i, i)] end
    return result
end
return M
