import Foundation

for seconds in [0, 59, 3725, 45296, 86400, 312047] {
    print(String(format: "%d seconds = %02d:%02d:%02d", locale: Locale(identifier: "en_US_POSIX"),
                 seconds, seconds / 3600, seconds / 60 % 60, seconds % 60))
}
