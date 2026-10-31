local lines = {
    "date,region,product,quantity,unit_price",
    "2026-04-01,north,notebook,10,200",
    "2026-04-01,east,marker,6,150",
    "2026-04-01,south,eraser,25,80",
    "2026-04-02,west,stapler,4,600",
    "2026-04-02,north,marker,8,150",
    "2026-04-02,east,notebook,9,200",
    "2026-04-03,south,stapler,3,600",
    "2026-04-03,west,eraser,15,80",
    "2026-04-03,north,eraser,20,80",
    "2026-04-04,east,stapler,5,600",
    "2026-04-04,south,notebook,6,200",
    "2026-04-04,west,marker,8,150",
}
local regions, products, days, total = {}, {}, {}, 0
for i = 2, #lines do
    local fields = {}
    for field in lines[i]:gmatch("[^,]+") do fields[#fields + 1] = field end
    local date, region, product = fields[1], fields[2], fields[3]
    local quantity, price = tonumber(fields[4]), tonumber(fields[5])
    local amount = quantity * price
    total = total + amount
    regions[region] = (regions[region] or 0) + amount
    products[product] = (products[product] or 0) + quantity
    days[date] = (days[date] or 0) + amount
end

local function keys(values)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    return result
end

io.write(string.format("total: %d\n", total))
local region_names = keys(regions)
table.sort(region_names, function(a, b)
    if regions[a] ~= regions[b] then return regions[a] > regions[b] end
    return a < b
end)
for _, region in ipairs(region_names) do io.write(string.format("%s: %d\n", region, regions[region])) end
local product_names = keys(products)
table.sort(product_names)
for _, product in ipairs(product_names) do io.write(string.format("%s: %d\n", product, products[product])) end
local dates = keys(days)
table.sort(dates, function(a, b)
    if days[a] ~= days[b] then return days[a] > days[b] end
    return a < b
end)
io.write(string.format("best day: %s (%d)\n", dates[1], days[dates[1]]))
