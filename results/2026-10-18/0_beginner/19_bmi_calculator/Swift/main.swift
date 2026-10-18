import Foundation

func fixed(_ value: Double, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    return "\(value < 0 ? "-" : "")\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}
let names = ["Aiko","Kenji","Mika","Ryo","Yuki"]
let heights = [158,172,165,180,150], weights = [45,68,70,101,52]
for i in names.indices {
    let bmi = Double(weights[i] * 10000) / Double(heights[i] * heights[i])
    let category = bmi < 18.5 ? "underweight" : bmi < 25 ? "normal" : bmi < 30 ? "overweight" : "obese"
    print("\(names[i]): BMI \(fixed(bmi, 1)) (\(category))")
}
