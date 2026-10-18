lines <- c("date,region,product,quantity,unit_price","2026-04-01,north,notebook,10,200","2026-04-01,east,marker,6,150","2026-04-01,south,eraser,25,80","2026-04-02,west,stapler,4,600","2026-04-02,north,marker,8,150","2026-04-02,east,notebook,9,200","2026-04-03,south,stapler,3,600","2026-04-03,west,eraser,15,80","2026-04-03,north,eraser,20,80","2026-04-04,east,stapler,5,600","2026-04-04,south,notebook,6,200","2026-04-04,west,marker,8,150")
regions <- products <- days <- numeric(0)
add_total <- function(values,key,amount) {
    if (!key %in% names(values)) values[key] <- 0
    values[key] <- values[key]+amount
    values
}
total <- 0
for (line in lines[-1]) {
    fields <- strsplit(line,",",fixed=TRUE)[[1]]
    date <- fields[1]; region <- fields[2]; product <- fields[3]
    quantity <- as.integer(fields[4]); price <- as.integer(fields[5])
    amount <- quantity*price
    total <- total+amount
    regions <- add_total(regions,region,amount)
    products <- add_total(products,product,quantity)
    days <- add_total(days,date,amount)
}
cat(sprintf("total: %d\n",total))
for (i in order(-regions,names(regions),method="radix")) cat(sprintf("%s: %d\n",names(regions)[i],regions[i]))
for (product in sort(names(products),method="radix")) cat(sprintf("%s: %d\n",product,products[product]))
best <- names(days)[order(-days,names(days),method="radix")[1]]
cat(sprintf("best day: %s (%d)\n",best,days[best]))
