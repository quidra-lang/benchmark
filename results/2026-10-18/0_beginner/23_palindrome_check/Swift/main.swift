import Foundation


for phrase in ["Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!", "Step on no pets.", "No lemon, no melon"] {
    let normalized = phrase.lowercased().utf8.filter { $0 >= 97 && $0 <= 122 }
    print("\(phrase) -> \(normalized.elementsEqual(normalized.reversed()) ? "yes" : "no")")
}
