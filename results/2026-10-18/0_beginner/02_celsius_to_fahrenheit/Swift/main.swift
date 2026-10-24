import Foundation

let temperatures = [-40, -15, -3, 0, 22, 37, 100]
for celsius in temperatures {
    let fahrenheit = Double(celsius) * 9 / 5 + 32
    print(String(format: "%d C = %.1f F", locale: Locale(identifier: "en_US_POSIX"), celsius, fahrenheit))
}
