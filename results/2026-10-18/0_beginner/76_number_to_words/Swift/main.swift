func underThousand(_ n: Int) -> String {
    let ones = ["zero","one","two","three","four","five","six","seven","eight","nine",
        "ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen","eighteen","nineteen"]
    let tens = ["", "", "twenty","thirty","forty","fifty","sixty","seventy","eighty","ninety"]
    var parts = [String]()
    if n >= 100 { parts.append(ones[n / 100] + " hundred") }
    let remainder = n % 100
    if remainder >= 20 { parts.append(tens[remainder / 10] + (remainder % 10 > 0 ? "-" + ones[remainder % 10] : "")) }
    else if remainder > 0 { parts.append(ones[remainder]) }
    return parts.joined(separator: " ")
}
for n in [0,13,40,100,568,71000,300019,999999] {
    var parts = [String]()
    if n == 0 { parts.append("zero") }
    if n >= 1000 { parts.append(underThousand(n / 1000) + " thousand") }
    if n % 1000 > 0 { parts.append(underThousand(n % 1000)) }
    print("\(n): \(parts.joined(separator: " "))")
}
