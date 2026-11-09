import Foundation

let names = ["Aiko", "Kenji", "Mika", "Ryo", "Yuki"]
let heights = [158, 172, 165, 180, 150], weights = [45, 68, 70, 101, 52]
for i in names.indices {
    let bmi = Double(weights[i] * 10000) / Double(heights[i] * heights[i])
    let category = bmi < 18.5 ? "underweight" : bmi < 25 ? "normal" : bmi < 30 ? "overweight" : "obese"
    print("\(names[i]): BMI \(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), bmi)) (\(category))")
}
