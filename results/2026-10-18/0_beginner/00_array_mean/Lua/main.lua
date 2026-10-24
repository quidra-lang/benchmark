local values = {48, 73, 56, 91, 35, 62, 84}
local total = 0
for _, value in ipairs(values) do
    total = total + value
end
local mean = total / #values
io.write(string.format("%.2f\n", mean))
