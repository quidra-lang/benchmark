function main()
    lines = ["date,region,product,quantity,unit_price","2026-04-01,north,notebook,10,200","2026-04-01,east,marker,6,150","2026-04-01,south,eraser,25,80","2026-04-02,west,stapler,4,600","2026-04-02,north,marker,8,150","2026-04-02,east,notebook,9,200","2026-04-03,south,stapler,3,600","2026-04-03,west,eraser,15,80","2026-04-03,north,eraser,20,80","2026-04-04,east,stapler,5,600","2026-04-04,south,notebook,6,200","2026-04-04,west,marker,8,150"]
    regions,products,days = Dict{String,Int}(),Dict{String,Int}(),Dict{String,Int}()
    total = 0
    for line in lines[2:end]
        date,region,product,quantity_text,price_text = split(line,',')
        quantity,price = parse(Int,quantity_text),parse(Int,price_text)
        amount = quantity*price
        total += amount
        regions[region] = get(regions,region,0)+amount
        products[product] = get(products,product,0)+quantity
        days[date] = get(days,date,0)+amount
    end
    println("total: ",total)
    for region in sort(collect(keys(regions));by=region -> (-regions[region],region))
        println(region,": ",regions[region])
    end
    for product in sort(collect(keys(products)))
        println(product,": ",products[product])
    end
    best = argmax(date -> days[date],sort(collect(keys(days))))
    println("best day: ",best," (",days[best],")")
end
main()
