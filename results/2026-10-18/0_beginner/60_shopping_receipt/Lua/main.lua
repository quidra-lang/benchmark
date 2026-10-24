local items = {{"milk",198,2,"food"},{"notebook",165,3,"general"},{"bread",248,1,"food"},{"apple",128,4,"food"},{"detergent",437,1,"general"},{"eggs",268,1,"food"}}
local totals = {food=0,general=0}
for _, item in ipairs(items) do
    local name,price,quantity,category = table.unpack(item)
    local subtotal = price*quantity
    totals[category] = totals[category]+subtotal
    io.write(string.format("%s %d x %d = %d\n",name,price,quantity,subtotal))
end
local payment = 0
for _, category in ipairs({"food","general"}) do
    local rate = category == "food" and 8 or 10
    local tax = (totals[category]*rate)//100
    payment = payment+totals[category]+tax
    io.write(string.format("%s: %d yen, tax %d yen\n",category,totals[category],tax))
end
io.write(string.format("total: %d yen\n",payment))
