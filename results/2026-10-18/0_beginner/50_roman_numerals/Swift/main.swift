import Foundation


let values = [1000,900,500,400,100,90,50,40,10,9,5,4,1], symbols = ["M","CM","D","CD","C","XC","L","XL","X","IX","V","IV","I"]
let digitValues = Dictionary(uniqueKeysWithValues: zip(Array("IVXLCDM"), [1,5,10,50,100,500,1000]))
for n in [9,14,49,94,444,1994,2768,3999] {
    var remaining = n, roman = ""
    for i in values.indices { while remaining >= values[i] { roman += symbols[i]; remaining -= values[i] } }
    let chars = Array(roman); var decoded = 0
    for i in chars.indices { let value = digitValues[chars[i]]!, next = i + 1 < chars.count ? digitValues[chars[i + 1]]! : 0; decoded += value < next ? -value : value }
    print("\(n) -> \(roman) -> \(decoded)")
}
