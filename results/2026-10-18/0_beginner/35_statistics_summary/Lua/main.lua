local numbers = {72,85,64,90,85,58,77,85,69,93,71}
local total = 0
for _, value in ipairs(numbers) do total = total + value end
local average, squares = total / #numbers, 0.0
for _, value in ipairs(numbers) do local difference = value-average; squares = squares + difference*difference end
local deviation = math.sqrt(squares / #numbers)
local ordered, frequencies = {}, {}
for i, value in ipairs(numbers) do ordered[i] = value; frequencies[value] = (frequencies[value] or 0)+1 end
table.sort(ordered)
local mode, best = ordered[1], 0
for _, value in ipairs(ordered) do if frequencies[value] > best then mode, best = value, frequencies[value] end end
io.write(string.format("mean: %.3f\nmedian: %d\nmode: %d\nrange: %d\nstdev: %.3f\n",math.floor(average*1000+0.5)/1000,ordered[6],mode,ordered[#ordered]-ordered[1],math.floor(deviation*1000+0.5)/1000))
