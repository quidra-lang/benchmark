import Foundation


var values = [52,17,38,9,61,38,24,45], total = 0
for i in 1..<values.count {
    let value = values[i]; var j = i - 1, shifts = 0
    while j >= 0 && values[j] > value { values[j + 1] = values[j]; j -= 1; shifts += 1 }
    values[j + 1] = value; total += shifts
    print("i=\(i) shifts=\(shifts): \(values.map(String.init).joined(separator: " "))")
}
print("total shifts: \(total)")
