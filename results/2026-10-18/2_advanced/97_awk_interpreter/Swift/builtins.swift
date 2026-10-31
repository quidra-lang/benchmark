import Foundation
struct RuntimeError: Error {
    let position: Position, message: String
}
enum Builtins {
    static func format(_ values: [Value], _ position: Position) throws -> String {
        let bytes = Array(values[0].text.utf8);
        var output = "", i = 0, argument = 1
        func error(_ message: String) -> RuntimeError {
            RuntimeError(position: position, message: message)
        }
        while i < bytes.count {
            if bytes[i] != 37 {
                output.append(Character(UnicodeScalar(bytes[i])));
                i += 1;
                continue
            };
            i += 1
            if i < bytes.count && bytes[i] == 37 {
                output += "%";
                i += 1;
                continue
            }
            var left = false, zero = false
            while i < bytes.count && (bytes[i] == 45 || bytes[i] == 48) {
                left = left || bytes[i] == 45;
                zero = zero || bytes[i] == 48;
                i += 1
            }
            let start = i;
            while i < bytes.count && Lexer.digit(bytes[i]) {
                i += 1
            };
            let width = Int(String(decoding: bytes[start..<i], as: UTF8.self)) ?? 0
            var precision: Int?
            if i < bytes.count && bytes[i] == 46 {
                i += 1;
                let start = i;
                while i < bytes.count && Lexer.digit(bytes[i]) {
                    i += 1
                };
                precision = Int(String(decoding: bytes[start..<i], as: UTF8.self)) ?? 0
            }
            guard i < bytes.count, Array("discxo".utf8).contains(bytes[i]) else {
                throw error("invalid format")
            };
            let conversion = bytes[i];
            i += 1
            guard argument < values.count else {
                throw error("not enough arguments")
            };
            let value = values[argument];
            argument += 1
            let numeric = Array("dixo".utf8).contains(conversion);
            var body: String
            if numeric {
                let n = value.number;
                var digits = String(abs(n), radix: conversion == 120 ? 16 : conversion == 111 ? 8 : 10)
                if let p = precision {
                    if p == 0 && n == 0 {
                        digits = ""
                    } else if digits.count < p {
                        digits = String(repeating: "0", count: p - digits.count) + digits
                    }
                };
                body = (n < 0 ? "-" : "") + digits
            } else if conversion == 115 {
                body = value.text;
                if let p = precision {
                    body = String(body.prefix(p))
                }
            }
            else if value.numericKind {
                let code = value.number;
                guard code == 10 || (32...126).contains(code) else {
                    throw error("invalid character code")
                };
                body = String(UnicodeScalar(code)!)
            }
            else {
                body = String(value.text.prefix(1))
            }
            if body.count < width {
                let padding = width - body.count
                if left {
                    body += String(repeating: " ", count: padding)
                }
                else if numeric && zero && precision == nil {
                    if body.first == "-" {
                        body = "-" + String(repeating: "0", count: padding) + body.dropFirst()
                    } else {
                        body = String(repeating: "0", count: padding) + body
                    }
                }
                else {
                    body = String(repeating: " ", count: padding) + body
                }
            };
            output += body
        };
        return output
    }
    static func scalar(_ name: String, _ values: [Value], _ position: Position) throws -> Value {
        switch name {
            case "substr": let text = Array(values[0].text), original = values[1].number, start = max(1, original), end = min(text.count + 1, values.count == 3 ? original + values[2].number : text.count + 1);
            return .string(end > start ? String(text[(start - 1)..<(end - 1)]) : "")
            case "index": let text = values[0].text, target = values[1].text;
            return .number(target.isEmpty ? 0 : text.range(of: target).map {
                text.distance(from: text.startIndex, to: $0.lowerBound) + 1
            } ?? 0)
            case "toupper": return .string(String(decoding: values[0].text.utf8.map {
                (97...122).contains($0) ? $0 - 32 : $0
            }, as: UTF8.self))
            case "tolower": return .string(String(decoding: values[0].text.utf8.map {
                (65...90).contains($0) ? $0 + 32 : $0
            }, as: UTF8.self))
            case "int": return .number(values[0].number)
            default: return .string(try format(values, position))
        }
    }
}
