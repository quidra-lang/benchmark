from collections import Counter

rows = [
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
]
regions, products, dates = Counter(), Counter(), Counter()
total = 0
for line in rows[1:]:
    date, region, product, quantity, price = line.split(",")
    quantity, price = int(quantity), int(price)
    sales = quantity * price
    total += sales
    regions[region] += sales
    products[product] += quantity
    dates[date] += sales
print(f"total: {total}")
for region in sorted(regions, key=lambda name: (-regions[name], name)):
    print(f"{region}: {regions[region]}")
for product in sorted(products):
    print(f"{product}: {products[product]}")
best = min(dates, key=lambda date: (-dates[date], date))
print(f"best day: {best} ({dates[best]})")
