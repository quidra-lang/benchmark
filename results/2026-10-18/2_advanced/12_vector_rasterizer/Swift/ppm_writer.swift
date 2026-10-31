import Foundation

func writePPM(_ path: String, _ image: [Color], _ width: Int, _ height: Int) throws {
    let lines = ["P3", "\(width) \(height)", "255"] + (0..<height).map { row in image[(row * width)..<((row + 1) * width)].map(\.rgbText).joined(separator: " ") }
    try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
}
func writePreview(_ path: String, _ image: [Color], _ width: Int, _ height: Int) throws {
    let ramp = Array("@%#*+=-:,.")
    let lines = stride(from: 0, to: height, by: 4).map { top in String(stride(from: 0, to: width, by: 2).map { left -> Character in
        var total = 0
        for y in top..<(top + 4) { for x in left..<(left + 2) { let color = image[y * width + x]; total += 299 * color.red + 587 * color.green + 114 * color.blue } }
        return ramp[(total / 8000) * 10 / 256]
    }) }
    try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
}
