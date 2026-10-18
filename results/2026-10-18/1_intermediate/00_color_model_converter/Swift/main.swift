import Foundation

enum Invalid: Error { case command }
struct Entry {
    let name: String
    let color: [Int]
}
struct Cluster {
    let color: [Int]
    let count: Int
}

class Converter {
    let names = [
        "black", "maroon", "green", "olive", "navy", "purple", "teal", "silver",
        "gray", "red", "lime", "yellow", "blue", "magenta", "cyan", "white",
        "orange", "pink", "brown", "gold", "coral", "salmon", "violet", "indigo"
    ]
    let rgb = [
        0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xC0C0C0,
        0x808080, 0xFF0000, 0x00FF00, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
        0xFFA500, 0xFFC0CB, 0xA52A2A, 0xFFD700, 0xFF7F50, 0xFA8072, 0xEE82EE, 0x4B0082
    ]
    var registered = [Entry]()

    func check(_ condition: Bool) throws {
        if !condition { throw Invalid.command }
    }
    func arity(_ tokens: [String], _ count: Int) throws {
        try check(tokens.count == count + 1)
    }
    func matches(_ text: String, _ pattern: String) -> Bool {
        return text.range(of: "\\A(?:" + pattern + ")\\z", options: .regularExpression) != nil
    }
    func number(_ text: String, _ low: Int, _ high: Int) throws -> Int {
        try check(matches(text, "-?[0-9]{1,9}"))
        let value = Int(text)!
        try check(value >= low && value <= high)
        return value
    }
    func floor(_ n: Int64, _ d: Int64) -> Int64 {
        let quotient = n / d
        return n < 0 && n % d != 0 ? quotient - 1 : quotient
    }
    func round(_ n: Int64, _ d: Int64) -> Int {
        return Int(floor(2*n+d,2*d))
    }
    func round(_ n: Int, _ d: Int) -> Int {
        return round(Int64(n),Int64(d))
    }
    func away(_ n: Int, _ d: Int) -> Int {
        return n < 0 ? -round(-n,d) : round(n,d)
    }
    func percent(_ a: Int, _ b: Int) -> Int { return round(100*a,b) }
    func mod(_ value: Int, _ modulus: Int) -> Int { return (value % modulus + modulus) % modulus }
    func clamp(_ value: Int) -> Int { return min(255,max(0,value)) }
    func root(_ numerator: Int64, _ scale: Int64) -> Int {
        let value = numerator / scale
        var low: Int64 = 0
        var high = value + 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if middle * middle <= value { low = middle }
            else { high = middle }
        }
        return Int(low)
    }
    func unpack(_ value: Int) -> [Int] { return [value >> 16,(value >> 8) & 255,value & 255] }
    func hex(_ color: [Int]) -> String {
        return "#" + color.map {
            let digits = String($0,radix: 16,uppercase: true)
            return (digits.count == 1 ? "0" : "") + digits
        }.joined()
    }
    func table() -> [Entry] {
        return names.indices.map { Entry(name: names[$0],color: unpack(rgb[$0])) } + registered
    }
    func color(_ text: String) throws -> [Int] {
        if matches(text,"#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?") {
            var digits = String(text.dropFirst())
            if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
            return unpack(Int(digits,radix: 16)!)
        }
        if matches(text,#"rgb\(([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})\)"#) {
            let components = text.dropFirst(4).dropLast().split(separator: ",").map { Int($0)! }
            try check(components.allSatisfy { $0 <= 255 })
            return components
        }
        if let entry = table().first(where: { $0.name == text }) { return entry.color }
        throw Invalid.command
    }
    func maximum(_ c: [Int]) -> Int { return c.max()! }
    func minimum(_ c: [Int]) -> Int { return c.min()! }
    func hue(_ c: [Int]) -> Int {
        let largest = maximum(c), difference = largest - minimum(c)
        if difference == 0 { return 0 }
        var numerator: Int
        if largest == c[0] { numerator = 60*(c[1]-c[2]) }
        else if largest == c[1] { numerator = 60*(c[2]-c[0])+120*difference }
        else { numerator = 60*(c[0]-c[1])+240*difference }
        if numerator < 0 { numerator += 360*difference }
        return round(numerator,difference) % 360
    }
    func hsl(_ c: [Int]) -> [Int] {
        let largest = maximum(c), smallest = minimum(c), difference = largest - smallest
        let saturation = difference == 0 ? 0 : percent(difference,255-abs(largest+smallest-255))
        return [hue(c),saturation,percent(largest+smallest,510)]
    }
    func fromHue(_ h: Int, _ chroma: Int, _ offset: Int, _ denominator: Int) -> [Int] {
        let sector = h / 60, f = h % 60, x = sector % 2 == 0 ? f : 60-f
        let factors = [[60,x,0],[x,60,0],[0,60,x],[0,x,60],[x,0,60],[60,0,x]]
        return (0..<3).map { i in
            round(255*(Int64(chroma)*Int64(factors[sector][i])+60*Int64(offset)),60*Int64(denominator))
        }
    }
    func fromHsl(_ h: Int, _ s: Int, _ l: Int) -> [Int] {
        let c = (100-abs(2*l-100))*s
        return fromHue(h,2*c,200*l-c,20000)
    }
    func distance(_ a: [Int], _ b: [Int]) -> Int64 {
        return (0..<3).reduce(Int64(0)) { sum,i in
            let difference = Int64(a[i]-b[i])
            return sum + difference*difference
        }
    }
    func model(_ command: String, _ c: [Int]) -> String {
        let r = c[0], g = c[1], b = c[2], m = maximum(c), n = minimum(c), d = m-n
        switch command {
        case "HSL":
            let v = hsl(c)
            return "hsl(\(v[0]),\(v[1])%,\(v[2])%)"
        case "HSV": return "hsv(\(hue(c)),\(m == 0 ? 0 : percent(d,m))%,\(percent(m,255))%)"
        case "HWB": return "hwb(\(hue(c)),\(percent(n,255))%,\(percent(255-m,255))%)"
        case "CMYK":
            if m == 0 { return "cmyk(0%,0%,0%,100%)" }
            return "cmyk(\(percent(m-r,m))%,\(percent(m-g,m))%,\(percent(m-b,m))%,\(percent(255-m,255))%)"
        case "YCBCR":
            return "ycbcr(\(clamp(round(299*r+587*g+114*b,1000)))," +
                "\(clamp(round(128000-169*r-331*g+500*b,1000))),\(clamp(round(128000+500*r-419*g-81*b,1000))))"
        case "YIQ":
            return "yiq(\(round(299*r+587*g+114*b,1000))," +
                "\(round(596*r-274*g-322*b,1000)),\(round(211*r-523*g+312*b,1000)))"
        default: preconditionFailure("Unknown internal color model")
        }
    }
    func ansi(_ number: Int) -> [Int] {
        if number < 16 { return unpack(rgb[number]) }
        if number >= 232 { return [Int](repeating: 8+10*(number-232),count: 3) }
        let values = [0,95,135,175,215,255], v = number-16
        return [values[v/36],values[v/6%6],values[v%6]]
    }
    func gradient(_ a: [Int], _ b: [Int], _ index: Int, _ denominator: Int) -> [Int] {
        return (0..<3).map { a[$0]+away((b[$0]-a[$0])*index,denominator) }
    }
    func luminance(_ c: [Int]) -> Int64 {
        return 2126*Int64(c[0])*Int64(c[0])+7152*Int64(c[1])*Int64(c[1])+722*Int64(c[2])*Int64(c[2])
    }
    func contrast(_ a: [Int], _ b: [Int]) -> [Int64] {
        let first = luminance(a), second = luminance(b)
        return [max(first,second)+32512500,min(first,second)+32512500]
    }
    func ratio(_ a: [Int], _ b: [Int]) -> Int {
        let values = contrast(a,b)
        return round(100*values[0],values[1])
    }
    func readable(_ a: [Int], _ b: [Int]) -> Bool {
        let values = contrast(a,b)
        return 2*values[0] >= 9*values[1]
    }
    func contrastText(_ a: [Int], _ b: [Int]) -> String {
        let values = contrast(a,b), ratio = round(100*values[0],values[1])
        let verdict = values[0] >= 7*values[1] ? "AAA" : 2*values[0] >= 9*values[1] ? "AA" : "FAIL"
        let fraction = String(ratio % 100)
        return "\(ratio / 100).\(fraction.count == 1 ? "0" : "")\(fraction) \(verdict)"
    }
    func blendComponent(_ mode: String, _ x: Int, _ y: Int) throws -> Int {
        let multiply = x*y/255, screen = 255-(255-x)*(255-y)/255
        switch mode {
        case "MULTIPLY": return multiply
        case "SCREEN": return screen
        case "OVERLAY": return x < 128 ? 2*x*y/255 : 255-2*(255-x)*(255-y)/255
        case "HARDLIGHT": return y < 128 ? 2*x*y/255 : 255-2*(255-x)*(255-y)/255
        case "SOFTLIGHT": return ((255-x)*multiply+x*screen)/255
        case "DARKEN": return min(x,y)
        case "LIGHTEN": return max(x,y)
        case "DIFFERENCE": return abs(x-y)
        case "EXCLUSION": return x+y-2*x*y/255
        case "ADD": return min(255,x+y)
        case "SUBTRACT": return max(0,x-y)
        case "COLORDODGE": return y == 255 ? 255 : min(255,255*x/(255-y))
        case "COLORBURN": return y == 0 ? 0 : max(0,255-255*(255-x)/y)
        default: throw Invalid.command
        }
    }
    func blend(_ mode: String, _ base: [Int], _ top: [Int]) throws -> [Int] {
        if ["HUE","SATURATION","COLOR","LUMINOSITY"].contains(mode) {
            let a = hsl(base), b = hsl(top)
            return fromHsl(mode == "HUE" || mode == "COLOR" ? b[0] : a[0],
                mode == "SATURATION" || mode == "COLOR" ? b[1] : a[1],mode == "LUMINOSITY" ? b[2] : a[2])
        }
        return try (0..<3).map { try blendComponent(mode,base[$0],top[$0]) }
    }
    func mean(_ colors: [[Int]]) -> [Int] {
        return (0..<3).map { i in round(colors.reduce(0) { $0+$1[i] },colors.count) }
    }
    func ranges(_ colors: [[Int]]) -> [Int] {
        return (0..<3).map { i in colors.map { $0[i] }.max()! - colors.map { $0[i] }.min()! }
    }
    func palette(_ k: Int, _ colors: [[Int]]) -> [Cluster] {
        var boxes = [colors]
        while boxes.count < k {
            var selected = -1, width = -1
            for i in boxes.indices {
                if boxes[i].count < 2 { continue }
                let candidate = ranges(boxes[i]).max()!
                if candidate > width {
                    width = candidate
                    selected = i
                }
            }
            let range = ranges(boxes[selected])
            var component = 0
            for i in 1..<3 {
                if range[i] > range[component] { component = i }
            }
            let axis = component
            let sorted = boxes[selected].enumerated().sorted { a,b in
                return a.element[axis] == b.element[axis] ? a.offset < b.offset : a.element[axis] < b.element[axis]
            }.map { $0.element }
            let middle = sorted.count / 2
            boxes[selected] = Array(sorted.prefix(middle))
            boxes.insert(Array(sorted.dropFirst(middle)),at: selected+1)
        }
        return boxes.map { Cluster(color: mean($0),count: $0.count) }
    }
    func clusterText(_ clusters: [Cluster]) -> String {
        return clusters.map { "\(hex($0.color)):\($0.count)" }.joined(separator: " ")
    }
    func kmeans(_ k: Int, _ colors: [[Int]]) -> String {
        var representatives = palette(k,colors).map { $0.color }
        var result = [Cluster](), iteration = 0
        while iteration < 20 {
            iteration += 1
            var groups = [[[Int]]](repeating: [],count: k)
            for color in colors {
                var best = 0
                for j in 1..<k {
                    if distance(color,representatives[j]) < distance(color,representatives[best]) { best = j }
                }
                groups[best].append(color)
            }
            result = (0..<k).map { j in
                Cluster(color: groups[j].isEmpty ? representatives[j] : mean(groups[j]),count: groups[j].count)
            }
            let unchanged = result.indices.allSatisfy { result[$0].color == representatives[$0] }
            representatives = result.map { $0.color }
            if unchanged { break }
        }
        return "\(iteration) \(clusterText(result))"
    }
    func colors(_ tokens: [String], _ start: Int) throws -> [[Int]] {
        return try tokens.dropFirst(start).map { try color($0) }
    }
    func colorsText(_ colors: [[Int]]) -> String { return colors.map { hex($0) }.joined(separator: " ") }
    func execute(_ line: String) throws -> String {
        let t = line.split(separator: " ").map(String.init), command = t[0]
        switch command {
        case "DEFINE":
            try arity(t,2)
            try check(matches(t[1],"[a-z]{1,12}") && !names.contains(t[1]))
            let c = try color(t[2])
            let entry = Entry(name: t[1],color: c)
            if let index = registered.firstIndex(where: { $0.name == t[1] }) { registered[index] = entry }
            else { registered.append(entry) }
            return "\(t[1]) \(hex(c))"
        case "UNDEFINE":
            try arity(t,1)
            try check(matches(t[1],"[a-z]{1,12}"))
            guard let index = registered.firstIndex(where: { $0.name == t[1] }) else { throw Invalid.command }
            registered.remove(at: index)
            return "\(t[1]) removed"
        case "LIST":
            try arity(t,0)
            if registered.isEmpty { return "NONE" }
            return registered.sorted { $0.name < $1.name }.map { "\($0.name)=\(hex($0.color))" }.joined(separator: " ")
        case "PARSE":
            try arity(t,1)
            let c = try color(t[1]), name = table().first(where: { $0.color == c })?.name ?? "-"
            return "\(hex(c)) rgb(\(c[0]),\(c[1]),\(c[2])) " +
                "\(model("HSL",c)) \(model("HSV",c)) \(model("HWB",c)) \(model("CMYK",c)) " +
                "\(model("YCBCR",c)) \(model("YIQ",c)) \(name)"
        case "HSL", "HSV", "HWB", "CMYK", "YCBCR", "YIQ":
            try arity(t,1)
            return model(command,try color(t[1]))
        case "FROMHSL", "FROMHSV", "FROMHWB":
            try arity(t,3)
            let h = try number(t[1],0,359), s = try number(t[2],0,100), third = try number(t[3],0,100)
            if command == "FROMHSL" { return hex(fromHsl(h,s,third)) }
            if command == "FROMHSV" { return hex(fromHue(h,third*s,100*third-third*s,10000)) }
            if s+third >= 100 { return hex([Int](repeating: round(255*s,s+third),count: 3)) }
            return hex(fromHue(h,100-s-third,s,100))
        case "FROMCMYK":
            try arity(t,4)
            let k = try number(t[4],0,100)
            let c = try (0..<3).map { round(255*(100-(try number(t[$0+1],0,100)))*(100-k),10000) }
            return hex(c)
        case "FROMYCBCR", "FROMYIQ":
            try arity(t,3)
            let y = try number(t[1],0,255), iq = command == "FROMYIQ"
            let a = try number(t[2],iq ? -255 : 0,255), b = try number(t[3],iq ? -255 : 0,255)
            let numerators: [Int]
            if iq { numerators = [1000*y+956*a+619*b,1000*y-272*a-647*b,1000*y-1106*a+1703*b] }
            else { numerators = [1000*y+1402*(b-128),1000*y-344*(a-128)-714*(b-128),1000*y+1772*(a-128)] }
            return hex(numerators.map { clamp(round($0,1000)) })
        case "RGB565":
            try arity(t,1)
            let c = try color(t[1])
            let value = 2048*round(31*c[0],255)+32*round(63*c[1],255)+round(31*c[2],255)
            let digits = String(value,radix: 16,uppercase: true)
            return "0x" + String(repeating: "0",count: 4-digits.count) + digits
        case "FROM565":
            try arity(t,1)
            try check(matches(t[1],"0x[0-9a-fA-F]{4}"))
            let v = Int(t[1].dropFirst(2),radix: 16)!
            return hex([round(255*(v/2048),31),round(255*(v/32%64),63),round(255*(v%32),31)])
        case "FROMANSI":
            try arity(t,1)
            return hex(ansi(try number(t[1],0,255)))
        case "ANSI":
            try arity(t,1)
            let c = try color(t[1])
            var best = 16
            for i in 17...255 {
                if distance(c,ansi(i)) < distance(c,ansi(best)) { best = i }
            }
            return "\(best) \(hex(ansi(best))) \(distance(c,ansi(best)))"
        case "WEBSAFE", "INVERT":
            try arity(t,1)
            let c = try color(t[1])
            return hex(c.map { command == "INVERT" ? 255-$0 : 51*round($0,51) })
        case "GRAY":
            try arity(t,2)
            let c = try color(t[1])
            let value: Int
            switch t[2] {
            case "LUMA": value = round(299*c[0]+587*c[1]+114*c[2],1000)
            case "AVERAGE": value = round(c.reduce(0,+),3)
            case "LIGHTNESS": value = round(maximum(c)+minimum(c),2)
            case "HSP": value = root(Int64(299*c[0]*c[0]+587*c[1]*c[1]+114*c[2]*c[2]),1000)
            default: throw Invalid.command
            }
            return hex([Int](repeating: value,count: 3))
        case "MIX", "MIXHSL":
            try arity(t,3)
            let a = try color(t[1]), b = try color(t[2]), p = try number(t[3],0,100)
            if command == "MIX" { return hex((0..<3).map { round(a[$0]*(100-p)+b[$0]*p,100) }) }
            let first = hsl(a), second = hsl(b)
            var e = mod(second[0]-first[0],360)
            if e > 180 { e -= 360 }
            return hex(fromHsl(mod(first[0]+away(e*p,100),360),
                first[1]+away((second[1]-first[1])*p,100),first[2]+away((second[2]-first[2])*p,100)))
        case "GRADIENT", "TINTS", "SHADES", "TONES":
            try arity(t,command == "GRADIENT" ? 3 : 2)
            let a = try color(t[1])
            if command == "GRADIENT" {
                let b = try color(t[2]), n = try number(t[3],2,16)
                return colorsText((0..<n).map { gradient(a,b,$0,n-1) })
            }
            let n = try number(t[2],1,10), target = command == "TINTS" ? 255 : command == "SHADES" ? 0 : 128
            let b = [Int](repeating: target,count: 3)
            return colorsText((1...n).map { gradient(a,b,$0,n+1) })
        case "BLEND":
            try arity(t,3)
            let base = try color(t[2]), top = try color(t[3])
            return hex(try blend(t[1],base,top))
        case "ALPHA":
            try arity(t,4)
            let fg = try color(t[1]), p = try number(t[2],0,100)
            let bg = try color(t[3]), q = try number(t[4],0,100), a = 100*p+q*(100-p)
            let result = (0..<3).map { a == 0 ? 0 : round(100*p*fg[$0]+q*(100-p)*bg[$0],a) }
            return "\(hex(result)) \(round(a,100))%"
        case "SIMULATE":
            try arity(t,2)
            let c = try color(t[1])
            let coefficients: [[Int]]
            switch t[2] {
            case "PROTANOPIA": coefficients = [[567,433,0],[558,442,0],[0,242,758]]
            case "DEUTERANOPIA": coefficients = [[625,375,0],[700,300,0],[0,300,700]]
            case "TRITANOPIA": coefficients = [[950,50,0],[0,433,567],[0,475,525]]
            case "ACHROMATOPSIA": coefficients = [[299,587,114],[299,587,114],[299,587,114]]
            default: throw Invalid.command
            }
            return hex((0..<3).map { i in round((0..<3).reduce(0) { $0+coefficients[i][$1]*c[$1] },1000) })
        case "ROTATE", "COMPLEMENT", "TRIADIC", "TETRADIC", "SPLITCOMP", "ANALOGOUS":
            try arity(t,command == "ROTATE" ? 2 : command == "ANALOGOUS" ? 3 : 1)
            let values = hsl(try color(t[1]))
            let rotations: [Int]
            switch command {
            case "ROTATE": rotations = [try number(t[2],-720,720)]
            case "COMPLEMENT": rotations = [180]
            case "TRIADIC": rotations = [120,240]
            case "TETRADIC": rotations = [90,180,270]
            case "SPLITCOMP": rotations = [150,210]
            default:
                let k = try number(t[2],1,6), step = try number(t[3],1,60)
                rotations = (-k...k).filter { $0 != 0 }.map { $0*step }
            }
            return colorsText(rotations.map { fromHsl(mod(values[0]+$0,360),values[1],values[2]) })
        case "LIGHTEN", "DARKEN", "SATURATE", "DESATURATE":
            try arity(t,2)
            var values = hsl(try color(t[1]))
            let p = try number(t[2],0,100)
            switch command {
            case "LIGHTEN": values[2] = min(100,values[2]+p)
            case "DARKEN": values[2] = max(0,values[2]-p)
            case "SATURATE": values[1] = min(100,values[1]+p)
            default: values[1] = max(0,values[1]-p)
            }
            return hex(fromHsl(values[0],values[1],values[2]))
        case "NEAREST":
            try arity(t,1)
            let c = try color(t[1]), entries = table()
            var best = entries[0]
            for entry in entries {
                if distance(c,entry.color) < distance(c,best.color) { best = entry }
            }
            return "\(best.name) \(hex(best.color)) \(distance(c,best.color))"
        case "DISTANCE":
            try arity(t,2)
            let a = try color(t[1]), b = try color(t[2])
            let dr = Int64(a[0]-b[0]), dg = Int64(a[1]-b[1]), db = Int64(a[2]-b[2])
            let w = (1024+Int64(a[0]+b[0]))*dr*dr+2048*dg*dg+(1534-Int64(a[0]+b[0]))*db*db
            return "\(distance(a,b)) \(root(w,512))"
        case "CONTRAST":
            try arity(t,2)
            return contrastText(try color(t[1]),try color(t[2]))
        case "ACCESSIBLE":
            try arity(t,2)
            let fg = try color(t[1]), bg = try color(t[2])
            if readable(fg,bg) { return "\(hex(fg)) \(contrastText(fg,bg))" }
            let values = hsl(fg)
            for d in 1...100 {
                for l in [values[2]-d,values[2]+d] {
                    if l < 0 || l > 100 { continue }
                    let candidate = fromHsl(values[0],values[1],l)
                    if readable(candidate,bg) { return "\(hex(candidate)) \(contrastText(candidate,bg))" }
                }
            }
            throw Invalid.command
        case "BEST":
            try check(t.count >= 3 && t.count <= 34)
            let bg = try color(t[1]), options = try colors(t,2)
            var best = options[0]
            for c in options {
                if ratio(c,bg) > ratio(best,bg) { best = c }
            }
            return "\(hex(best)) \(contrastText(best,bg))"
        case "DESCRIBE":
            try arity(t,1)
            let values = hsl(try color(t[1])), h = values[0], s = values[1], l = values[2]
            if l <= 5 { return "black" }
            if l >= 95 { return "white" }
            let lightness = l <= 20 ? "very dark" : l <= 40 ? "dark" : l <= 60 ? "medium" : l <= 80 ? "light" : "very light"
            if s < 10 { return lightness + " gray" }
            let saturation = s < 40 ? "muted" : s < 80 ? "moderate" : "vivid"
            let hues = ["red","orange","yellow","chartreuse","green","spring-green",
                "cyan","azure","blue","violet","magenta","rose"]
            return lightness + " " + saturation + " " + hues[(h+15)%360/30]
        case "PALETTE", "KMEANS":
            try check(t.count >= 3 && t.count <= 34)
            let k = try number(t[1],1,t.count-2), options = try colors(t,2)
            return command == "PALETTE" ? clusterText(palette(k,options)) : kmeans(k,options)
        case "SORT":
            try check(t.count >= 2 && t.count <= 33)
            let options = try colors(t,1)
            let sorted = options.enumerated().sorted { a,b in
                let first = hsl(a.element), second = hsl(b.element)
                for i in 0..<3 {
                    if first[i] != second[i] { return first[i] < second[i] }
                }
                return a.offset < b.offset
            }.map { $0.element }
            return colorsText(sorted)
        case "DITHER":
            try check(t.count >= 2 && t.count <= 33)
            let options = try colors(t,1)
            var error = [0,0,0], result = [String]()
            for c in options {
                let adjusted = (0..<3).map { clamp(c[$0]+error[$0]) }
                var best = 0
                for i in 1..<16 {
                    if distance(adjusted,unpack(rgb[i])) < distance(adjusted,unpack(rgb[best])) { best = i }
                }
                result.append(names[best])
                let chosen = unpack(rgb[best])
                error = (0..<3).map { adjusted[$0]-chosen[$0] }
            }
            return result.joined(separator: " ")
        case "RANDOM":
            try arity(t,2)
            var state = Int64(try number(t[1],1,999999999))
            let n = try number(t[2],1,16)
            var result = [[Int]]()
            for _ in 0..<n {
                state = state*48271%2147483647
                let h = Int(state%360)
                state = state*48271%2147483647
                let s = 40+Int(state%61)
                state = state*48271%2147483647
                let l = 25+Int(state%51)
                result.append(fromHsl(h,s,l))
            }
            return colorsText(result)
        default: throw Invalid.command
        }
    }
}

let count = Int(readLine()!)!
let converter = Converter()
for _ in 0..<count {
    let line = readLine()!
    do { print(try converter.execute(line)) }
    catch { print("INVALID") }
}
