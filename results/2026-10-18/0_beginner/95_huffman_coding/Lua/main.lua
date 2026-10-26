local text = "she sells sea shells by the sea shore"
local frequencies = {}
for symbol in text:gmatch(".") do frequencies[symbol] = (frequencies[symbol] or 0) + 1 end
local symbols, trees = {}, {}
for symbol, frequency in pairs(frequencies) do
    symbols[#symbols + 1] = symbol
    trees[#trees + 1] = {weight = frequency, smallest = symbol:byte(), symbol = symbol}
end
table.sort(symbols)
while #trees > 1 do
    table.sort(trees, function(a, b)
        return a.weight < b.weight or (a.weight == b.weight and a.smallest < b.smallest)
    end)
    local left = table.remove(trees, 1)
    local right = table.remove(trees, 1)
    trees[#trees + 1] = {
        weight = left.weight + right.weight,
        smallest = math.min(left.smallest, right.smallest),
        left = left,
        right = right,
    }
end
local codes = {}

local function visit(node, prefix)
    if node.symbol then
        codes[node.symbol] = prefix
    else
        visit(node.left, prefix .. "0")
        visit(node.right, prefix .. "1")
    end
end

visit(trees[1], "")
local bits = 0
for _, symbol in ipairs(symbols) do
    io.write(string.format("'%s' freq=%d code=%s\n", symbol, frequencies[symbol], codes[symbol]))
    bits = bits + frequencies[symbol] * #codes[symbol]
end
io.write(string.format("encoded bits: %d\nfixed 8-bit: %d\n", bits, #text * 8))
