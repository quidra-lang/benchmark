import Foundation


let lines = [
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
    "2026-04-04,west,marker,8,150"]
var regions = [String:Int](), products = [String:Int](), days = [String:Int](), total = 0
for line in lines.dropFirst() {
    let fields = line.split(separator: ",").map(String.init)
    let quantity = Int(fields[3])!, amount = quantity * Int(fields[4])!
    total += amount
    regions[fields[1], default: 0] += amount
    products[fields[2], default: 0] += quantity
    days[fields[0], default: 0] += amount
}
print("total: \(total)")
let names = regions.keys.sorted { regions[$0]! == regions[$1]! ? $0 < $1 : regions[$0]! > regions[$1]! }
for name in names { print("\(name): \(regions[name]!)") }
for name in products.keys.sorted() { print("\(name): \(products[name]!)") }
let best = days.keys.sorted { days[$0]! == days[$1]! ? $0 < $1 : days[$0]! > days[$1]! }.first!
print("best day: \(best) (\(days[best]!))")
