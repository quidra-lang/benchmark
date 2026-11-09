import Foundation

let neighborOffsets = [Pixel(x: -1, y: -1), Pixel(x: 0, y: -1), Pixel(x: 1, y: -1), Pixel(x: -1, y: 0), Pixel(x: 1, y: 0), Pixel(x: -1, y: 1), Pixel(x: 0, y: 1), Pixel(x: 1, y: 1)]

func directions(_ gradient: Gradient) -> Image {
    gradient.x.indices.map { y in gradient.x[0].indices.map { x in
        let dx = gradient.x[y][x], dy = gradient.y[y][x], ax = abs(dx), ay = abs(dy)
        return 29 * ay <= 12 * ax ? 0 : 29 * ay >= 70 * ax ? 90 : dx * dy < 0 ? 45 : 135
    } }
}

func suppress(_ magnitude: Image, _ direction: Image) -> Image {
    let height = magnitude.count, width = magnitude[0].count
    var output = Array(repeating: Array(repeating: 0, count: width), count: height)
    let offsets = [0: (Pixel(x: -1, y: 0), Pixel(x: 1, y: 0)), 45: (Pixel(x: 1, y: -1), Pixel(x: -1, y: 1)), 90: (Pixel(x: 0, y: -1), Pixel(x: 0, y: 1)), 135: (Pixel(x: -1, y: -1), Pixel(x: 1, y: 1))]
    for y in 1..<(height - 1) {
        for x in 1..<(width - 1) {
            let (before, after) = offsets[direction[y][x]]!, value = magnitude[y][x]
            if value > magnitude[y + before.y][x + before.x] && value >= magnitude[y + after.y][x + after.x] { output[y][x] = value }
        }
    }
    return output
}

struct Edges { let pixels: Set<Pixel>; let strongPixels: Set<Pixel>; let weakPixels: Set<Pixel> }

func hysteresis(_ nonmax: Image, _ low: Int, _ high: Int) -> Edges {
    var strong = Set<Pixel>(), weakPixels = Set<Pixel>()
    for y in nonmax.indices {
        for x in nonmax[0].indices {
            if nonmax[y][x] >= high { strong.insert(Pixel(x: x, y: y)) } else if nonmax[y][x] >= low { weakPixels.insert(Pixel(x: x, y: y)) }
        }
    }
    let allowed = strong.union(weakPixels)
    var edges = strong, queue = strong.sorted(), cursor = 0
    while cursor < queue.count {
        let point = queue[cursor]
        cursor += 1
        for offset in neighborOffsets { let next = point + offset; if allowed.contains(next) && edges.insert(next).inserted { queue.append(next) } }
    }
    return Edges(pixels: edges, strongPixels: strong, weakPixels: weakPixels)
}

func edgeComponents(_ edges: Set<Pixel>) -> [[Pixel]] {
    var waiting = edges, components: [[Pixel]] = []
    while let first = waiting.min() {
        waiting.remove(first)
        var queue = [first], cursor = 0
        while cursor < queue.count {
            let point = queue[cursor]
            cursor += 1
            for offset in neighborOffsets { let next = point + offset; if waiting.remove(next) != nil { queue.append(next) } }
        }
        components.append(queue)
    }
    return components
}
