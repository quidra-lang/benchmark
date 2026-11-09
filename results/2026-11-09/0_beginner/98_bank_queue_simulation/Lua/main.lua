local state, arrival, total_wait, max_wait = 42, 0, 0, 0
local free_times = {0, 0}
for customer = 1, 20 do
    state = (state * 48271) % 2147483647
    arrival = arrival + state % 5 + 1
    state = (state * 48271) % 2147483647
    local service = state % 7 + 2
    local teller = free_times[1] <= free_times[2] and 1 or 2
    local start = math.max(arrival, free_times[teller])
    local departure = start + service
    local wait = start - arrival
    free_times[teller] = departure
    total_wait = total_wait + wait
    max_wait = math.max(max_wait, wait)
    io.write(string.format("customer %d: arrive=%d start=%d end=%d teller=%d wait=%d\n",
        customer, arrival, start, departure, teller, wait))
end
io.write(string.format("average wait: %.2f\nmax wait: %d\nlast departure: %d\n",
    total_wait / 20, max_wait, math.max(table.unpack(free_times))))
