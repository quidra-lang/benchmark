local limit, prime = 200, {}
for n = 0, limit do prime[n] = n >= 2 end
for p = 2, limit do
    if prime[p] then for multiple = 2*p, limit, p do prime[multiple] = false end end
end
local primes = {}
for n = 2, limit do if prime[n] then primes[#primes+1] = n end end
io.write(string.format("count: %d\n", #primes))
for first = 1, #primes, 10 do
    local row = {}
    for i = first, math.min(first+9, #primes) do row[#row+1] = primes[i] end
    io.write(table.concat(row, " "), "\n")
end
