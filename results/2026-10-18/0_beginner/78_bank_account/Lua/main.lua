local balances = {Nina = 12000, Leo = 3500, Emma = 800}
local transactions = {
    "deposit Emma 1200", "withdraw Leo 4000", "transfer Nina Leo 5000", "withdraw Leo 4000",
    "transfer Emma Nina 2500", "transfer Emma Nina 2000", "withdraw Emma 300", "deposit Nina 750",
    "transfer Leo Emma 3200", "withdraw Nina 9800",
}
for number, transaction in ipairs(transactions) do
    local parts = {}
    for part in transaction:gmatch("%S+") do parts[#parts + 1] = part end
    local operation, name, amount = parts[1], parts[2], tonumber(parts[#parts])
    local success = operation == "deposit" or balances[name] >= amount
    if success then
        if operation == "deposit" then
            balances[name] = balances[name] + amount
        else
            balances[name] = balances[name] - amount
            if operation == "transfer" then balances[parts[3]] = balances[parts[3]] + amount end
        end
    end
    io.write(string.format("op %d: %s %s\n", number, transaction, success and "ok" or "failed (insufficient funds)"))
end
local names = {}
for name in pairs(balances) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do io.write(string.format("%s: %d\n", name, balances[name])) end
