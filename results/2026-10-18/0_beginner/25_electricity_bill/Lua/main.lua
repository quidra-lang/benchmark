local households = {{"Sato", 85}, {"Suzuki", 120}, {"Takahashi", 254}, {"Tanaka", 300}, {"Ito", 438}, {"Watanabe", 176}}
local total = 0
for _, household in ipairs(households) do
    local name, usage = household[1], household[2]
    local bill = 900 + math.min(usage, 120) * 30 + math.min(math.max(usage - 120, 0), 180) * 36
        + math.max(usage - 300, 0) * 40
    total = total + bill
    io.write(string.format("%s: %d kWh, %d yen\n", name, usage, bill))
end
io.write(string.format("total: %d yen\n", total))
