let names = ["Sato","Suzuki","Takahashi","Tanaka","Ito","Watanabe"], usages = [85,120,254,300,438,176]
var total = 0
for i in names.indices {
    let u = usages[i]
    let bill = 900 + min(u,120) * 30 + min(max(u - 120,0),180) * 36 + max(u - 300,0) * 40
    total += bill
    print("\(names[i]): \(u) kWh, \(bill) yen")
}
print("total: \(total) yen")
