function main()
    items = [("tent",10,120),("stove",3,65),("lantern",2,45),("rope",3,20),("camera",5,90),("blanket",5,85),("water",6,100)]
    capacity = 20
    table = zeros(Int,length(items)+1,capacity+1)
    for i in eachindex(items), weight in 0:capacity
        item_weight,item_value = items[i][2],items[i][3]
        table[i+1,weight+1] = table[i,weight+1]
        if item_weight <= weight
            table[i+1,weight+1] = max(table[i+1,weight+1],table[i,weight-item_weight+1]+item_value)
        end
    end
    chosen = falses(length(items))
    remaining = capacity
    for i in length(items):-1:1
        if table[i+1,remaining+1] != table[i,remaining+1]
            chosen[i] = true
            remaining -= items[i][2]
        end
    end
    println("max value: ",table[end,end])
    println("total weight: ",capacity-remaining)
    println("items: ",join((items[i][1] for i in eachindex(items) if chosen[i])," "))
end
main()
