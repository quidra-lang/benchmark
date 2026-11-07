import Foundation

let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
let codes = ".- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----.".split(separator: " ").map(String.init)
let forward = Dictionary(uniqueKeysWithValues: zip(alphabet, codes))
let reverse = Dictionary(uniqueKeysWithValues: zip(codes, alphabet))
let message = "MEET ME AT PIER 9 AT 1745"
let encoded = message.split(separator: " ")
    .map { word in word.map { forward[$0]! }.joined(separator: " ") }
    .joined(separator: " / ")
let decoded = encoded.components(separatedBy: " / ")
    .map { word in String(word.split(separator: " ").map { reverse[String($0)]! }) }
    .joined(separator: " ")
print(encoded)
print(decoded)
