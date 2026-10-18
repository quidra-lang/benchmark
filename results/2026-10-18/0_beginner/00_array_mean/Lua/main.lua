local values = {48, 73, 56, 91, 35, 62, 84}
local total = 0
for _, value in ipairs(values) do
    total = total + value
end
local mean = total / #values
local rounded = math.floor(mean * 100 + 0.5) / 100
io.write(string.format("%.2f\n", rounded))
