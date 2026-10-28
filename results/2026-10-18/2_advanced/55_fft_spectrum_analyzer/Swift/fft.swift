import Foundation

let pi = 3.141592653589793
struct Complex {
    let real: Double
    let imaginary: Double
    init(_ real: Double = 0, _ imaginary: Double = 0) { self.real = real; self.imaginary = imaginary }
    var conjugate: Complex { Complex(real, -imaginary) }
    var squaredMagnitude: Double { real * real + imaginary * imaginary }
    var magnitude: Double { sqrt(squaredMagnitude) }
    var argument: Double { atan2(imaginary, real) }
    static func + (a: Complex, b: Complex) -> Complex { Complex(a.real + b.real, a.imaginary + b.imaginary) }
    static func - (a: Complex, b: Complex) -> Complex { Complex(a.real - b.real, a.imaginary - b.imaginary) }
    static func * (a: Complex, b: Complex) -> Complex { Complex(a.real * b.real - a.imaginary * b.imaginary, a.real * b.imaginary + a.imaginary * b.real) }
    static func * (a: Complex, b: Double) -> Complex { Complex(a.real * b, a.imaginary * b) }
    static func / (a: Complex, b: Double) -> Complex { Complex(a.real / b, a.imaginary / b) }
}
func powerOfTwo(_ minimum: Int) -> Int { var value = 1; while value < minimum { value *= 2 }; return value }
func rotation(_ angle: Double) -> Complex { Complex(cos(angle), -sin(angle)) }
func complexValues(_ values: [Double]) -> [Complex] { values.map { Complex($0) } }
func radix2(_ source: [Complex], inverse: Bool = false) -> [Complex] {
    let count = source.count
    var values = source, bits = 0, size = 1
    while size < count { bits += 1; size *= 2 }
    for n in 1..<count {
        var reversed = 0, remainder = n
        for _ in 0..<bits { reversed = 2 * reversed + remainder % 2; remainder /= 2 }
        if n < reversed { values.swapAt(n, reversed) }
    }
    let twiddles = (0..<(count / 2)).map { k -> Complex in let factor = rotation(2 * pi * Double(k) / Double(count)); return inverse ? factor.conjugate : factor }
    size = 2
    while size <= count {
        let half = size / 2, step = count / size
        for start in stride(from: 0, to: count, by: size) {
            for j in 0..<half { let t = twiddles[j * step] * values[start + j + half], u = values[start + j]; values[start + j] = u + t; values[start + j + half] = u - t }
        }
        size *= 2
    }
    return inverse ? values.map { $0 / Double(count) } : values
}
func bluestein(_ source: [Complex]) -> [Complex] {
    let count = source.count, size = powerOfTwo(2 * count - 1), chirps = (0..<count).map { rotation(pi * Double($0 * $0 % (2 * count)) / Double(count)) }
    var a = Array(repeating: Complex(), count: size), b = a
    for n in 0..<count { a[n] = source[n] * chirps[n]; b[n] = chirps[n].conjugate; if n > 0 { b[size - n] = chirps[n].conjugate } }
    let af = radix2(a), bf = radix2(b), convolution = radix2((0..<size).map { af[$0] * bf[$0] }, inverse: true)
    return (0..<count).map { chirps[$0] * convolution[$0] }
}
func dft(_ values: [Complex]) -> [Complex] { values.count & (values.count - 1) == 0 ? radix2(values) : bluestein(values) }
func dft(_ values: [Double]) -> [Complex] { dft(complexValues(values)) }
func idft(_ values: [Complex]) -> [Complex] { values.count & (values.count - 1) == 0 ? radix2(values, inverse: true) : bluestein(values.map { $0.conjugate }).map { $0.conjugate / Double(values.count) } }
func packedReal(_ values: [Double]) -> [Complex] {
    let count = values.count, half = count / 2, transformed = radix2((0..<half).map { Complex(values[2 * $0], values[2 * $0 + 1]) })
    return (0...half).map { k in
        let a = transformed[k % half], b = transformed[(half - k) % half].conjugate, difference = a - b
        let even = (a + b) / 2, odd = Complex(difference.imaginary / 2, -difference.real / 2)
        return even + rotation(2 * pi * Double(k) / Double(count)) * odd
    }
}
func convolution(_ a: [Double], _ b: [Double]) -> [Double] {
    let count = a.count + b.count - 1, size = powerOfTwo(count)
    let af = radix2(complexValues(a) + Array(repeating: Complex(), count: size - a.count)), bf = radix2(complexValues(b) + Array(repeating: Complex(), count: size - b.count))
    return radix2((0..<size).map { af[$0] * bf[$0] }, inverse: true).prefix(count).map { $0.real }
}
func chirpZ(_ weighted: [Double], _ sampleRate: Double, _ lower: Int, _ upper: Int, _ points: Int) -> [Complex] {
    let length = weighted.count, step = Double(upper - lower) / Double(points - 1), size = powerOfTwo(length + points - 1)
    var a = Array(repeating: Complex(), count: size), b = a
    for n in weighted.indices { let t = Double(n); a[n] = rotation(2 * pi * Double(lower) * t / sampleRate) * weighted[n] * rotation(pi * step * t * t / sampleRate) }
    for offset in (-(length - 1))..<points { let t = Double(offset); b[offset < 0 ? offset + size : offset] = rotation(pi * step * t * t / sampleRate).conjugate }
    let af = radix2(a), bf = radix2(b), g = radix2((0..<size).map { af[$0] * bf[$0] }, inverse: true)
    return (0..<points).map { j in rotation(pi * step * Double(j) * Double(j) / sampleRate) * g[j] }
}
