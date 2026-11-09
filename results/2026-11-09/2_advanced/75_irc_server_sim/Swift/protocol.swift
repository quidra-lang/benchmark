import Foundation

func ircFold(_ value: String) -> String {
    String(bytes: value.utf8.map { byte in
        switch byte {
        case 65...90: return byte + 32
        case 91: return 123
        case 93: return 125
        case 92: return 124
        case 94: return 126
        default: return byte
        }
    }, encoding: .ascii)!
}

func digits(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
}

func validNickname(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    func initial(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
            || Array("[]\\`_^{}|".utf8).contains(byte)
    }
    return !bytes.isEmpty && initial(bytes[0])
        && bytes.dropFirst().allSatisfy { initial($0) || (48...57).contains($0) || $0 == 45 }
}

func validChannel(_ value: String, maximum: Int) -> Bool {
    value.count >= 2 && value.count <= maximum && value.hasPrefix("#") && !value.contains(":")
}

func parseMessage(_ raw: String) -> (String, [String]) {
    let bytes = Array(raw.utf8)
    var position = 0
    if bytes.first == 58 {
        guard let space = bytes.firstIndex(of: 32) else { return ("", []) }
        position = space
    }
    while position < bytes.count && bytes[position] == 32 { position += 1 }
    let start = position
    while position < bytes.count && bytes[position] != 32 { position += 1 }
    let command = String(bytes: bytes[start..<position], encoding: .ascii)!.uppercased()
    var parameters: [String] = []
    while position < bytes.count {
        while position < bytes.count && bytes[position] == 32 { position += 1 }
        if position == bytes.count { break }
        if bytes[position] == 58 {
            parameters.append(String(bytes: bytes[(position + 1)...], encoding: .ascii)!)
            break
        }
        if parameters.count == 14 {
            parameters.append(String(bytes: bytes[position...], encoding: .ascii)!)
            break
        }
        let start = position
        while position < bytes.count && bytes[position] != 32 { position += 1 }
        parameters.append(String(bytes: bytes[start..<position], encoding: .ascii)!)
    }
    return (command, parameters)
}
