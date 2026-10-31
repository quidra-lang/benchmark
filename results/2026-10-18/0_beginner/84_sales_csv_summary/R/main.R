lines <- c(
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
  "2026-04-04,west,marker,8,150"
)
fields <- do.call(rbind, strsplit(lines[-1], ",", fixed = TRUE))
quantities <- as.integer(fields[, 4])
amounts <- quantities * as.integer(fields[, 5])
regions <- tapply(amounts, fields[, 2], sum)
products <- tapply(quantities, fields[, 3], sum)
days <- tapply(amounts, fields[, 1], sum)
cat(sprintf("total: %d\n", sum(amounts)))
for (i in order(-regions, names(regions), method = "radix")) cat(sprintf("%s: %d\n", names(regions)[i], regions[i]))
for (product in sort(names(products), method = "radix")) cat(sprintf("%s: %d\n", product, products[product]))
best <- names(days)[which.max(days)]
cat(sprintf("best day: %s (%d)\n", best, days[best]))
