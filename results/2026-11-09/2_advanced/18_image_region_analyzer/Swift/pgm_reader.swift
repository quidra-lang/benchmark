import Foundation

struct Image {
    let name: String
    let width: Int
    let height: Int
    let maxval: Int
    let pixels: [[Int64]]
}

func readImages(_ path: String) throws -> [Image] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    var words: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        words += content.split(separator: " ").map(String.init)
    }
    var images: [Image] = []
    var position = 0
    while position < words.count {
        let name = words[position + 1]
        let width = Int(words[position + 3])!
        let height = Int(words[position + 4])!
        let maxval = Int(words[position + 5])!
        position += 6
        var pixels: [[Int64]] = []
        for y in 0..<height { pixels.append((0..<width).map { Int64(words[position + y * width + $0])! }) }
        position += width * height
        images.append(Image(name: name, width: width, height: height, maxval: maxval, pixels: pixels))
    }
    return images
}
