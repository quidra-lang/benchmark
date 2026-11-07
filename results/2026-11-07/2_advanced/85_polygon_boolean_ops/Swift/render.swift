enum Render {
    static func draw(_ region: Region, _ operands: (Rings, Rings)?, _ values: [Int128]) -> ([String], [Int]) {
        let x = values[0], y = values[1], cw = values[2], ch = values[3], cols = Int(values[4]), rows = Int(values[5])
        let all = region.flatMap {
            $0
        }
        var lines: [String] = [], counts = [0, 0, 0, 0]
        for j in 0..<rows {
            var line = ""
            for i in 0..<cols {
                let point = Point(2 * x + Int128(2 * i + 1) * cw, 2 * y + Int128(2 * (rows - 1 - j) + 1) * ch, 2)
                if RingOps.interior(point, all) {
                    counts[0] += 1;
                    line += "#"
                }
                else if let (a, b) = operands {
                    switch (RingOps.interior(point, a), RingOps.interior(point, b)) {
                        case (true, true): counts[3] += 1;
                        line += "+"
                        case (true, false): counts[1] += 1;
                        line += "a"
                        case (false, true): counts[2] += 1;
                        line += "b"
                        default: line += "."
                    }
                } else {
                    line += "."
                }
            }
            lines.append(line)
        }
        return (lines, counts)
    }
}
