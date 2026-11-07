import Foundation

for i in 1...9 {
    print((1...9).map { column in
        String(format: "%3d", locale: Locale(identifier: "en_US_POSIX"), i * column)
    }.joined())
}
