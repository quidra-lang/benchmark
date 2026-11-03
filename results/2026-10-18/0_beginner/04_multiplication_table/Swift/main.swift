import Foundation

for i in 1...9 {
    print((1...9).map {
        String(format: "%3d", locale: Locale(identifier: "en_US_POSIX"), i * $0)
    }.joined())
}
