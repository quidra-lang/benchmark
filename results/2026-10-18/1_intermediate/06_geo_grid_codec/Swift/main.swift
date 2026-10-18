import Foundation

let gh = "0123456789bcdefghjkmnpqrstuvwxyz"
let l24 = "ABCDEFGHJKLMNPQRSTUVWXYZ"
let plusAlphabet = "23456789CFGHJMPQRVWX"
let g25 = "ABCDEFGHJKLMNOPQRSTUVWXYZ"
let bands = "CDEFGHJKLMNPQRSTUVWX"
let mrows = "ABCDEFGHJKLMNPQRSTUV"
let precisionTable = [
    "GEOHASH":[1,2,3,4,5,6,7,8,9], "MAIDENHEAD":[2,4,6,8],
    "PLUSCODE":[2,4,6,8,10,11], "GARS":[5,6,7],
    "GEOREF":[2,4,8,10,12], "MESH":[4,6,8,9,10,11]
]
let meshScale = [1,8,80,160,320,640]
let maiden = ["ABCDEFGHIJKLMNOPQR","0123456789","abcdefghijklmnopqrstuvwx","0123456789"]
extension String {
    subscript(_ i: Int) -> Character { self[index(startIndex,offsetBy:i)] }
    func take(_ n: Int) -> String { String(prefix(n)) }
    func drop(_ n: Int) -> String { String(dropFirst(n)) }
    func slice(_ a: Int, _ b: Int) -> String { String(dropFirst(a).prefix(b-a)) }
}
struct Cell: Hashable {
    let system: String
    let level: Int
    let x: Int
    let y: Int
    let w: Int
    let h: Int
}
enum Invalid: Error { case argument }
func need(_ condition: Bool) throws { if !condition { throw Invalid.argument } }
func matches(_ s: String, _ pattern: String) -> Bool {
    s.range(of:"\\A(?:"+pattern+")\\z",options:.regularExpression) != nil
}
func integer(_ s: String) throws -> Int {
    try need(matches(s,"-?[0-9]{1,9}"))
    return Int(s)!
}
func range(_ s: String, _ low: Int, _ high: Int) throws -> Int {
    let value = try integer(s)
    try need(value >= low && value <= high)
    return value
}
func coordinate(_ s: String, _ latitude: Bool) throws -> Int {
    try need(matches(s,"-?[0-9]{1,3}(\\.[0-9]{1,6})?"))
    let negative = s.hasPrefix("-")
    let pieces = (negative ? s.drop(1) : s).split(separator:".").map(String.init)
    var value = Int(pieces[0])!*1000000
    if pieces.count == 2 { value += Int(pieces[1]+String(repeating:"0",count:6-pieces[1].count))! }
    if negative { value = -value }
    try need(latitude ? value >= -90000000 && value <= 90000000 : value >= -180000000 && value < 180000000)
    return value
}
func precisions(_ system: String) throws -> [Int] {
    guard let result = precisionTable[system] else { throw Invalid.argument }
    return result
}
func level(_ system: String, _ precision: Int) throws -> Int {
    guard let result = try precisions(system).firstIndex(of:precision) else { throw Invalid.argument }
    return result
}
func grid(_ system: String, _ level: Int, _ x: Int = 0, _ y: Int = 0) throws -> Cell {
    let p = try precisions(system)[level]
    let w: Int
    let h: Int
    switch system {
    case "GEOHASH":
        w = 1 << ((5*p+1)/2)
        h = 1 << (5*p/2)
    case "MAIDENHEAD":
        w = [18,180,4320,43200][level]
        h = w
    case "PLUSCODE":
        w = [18,360,7200,144000,2880000,11520000][level]
        h = [9,180,3600,72000,1440000,7200000][level]
    case "GARS":
        w = [720,1440,4320][level]
        h = [360,720,2160][level]
    case "GEOREF":
        w = [24,360,21600,216000,2160000][level]
        h = [12,180,10800,108000,1080000][level]
    default:
        w = 360*meshScale[level]
        h = 270*meshScale[level]
    }
    return Cell(system:system,level:level,x:x,y:y,w:w,h:h)
}
func point(_ system: String, _ level: Int, _ lat: Int, _ lon: Int) throws -> Cell {
    let g = try grid(system,level)
    return try grid(system,level,(lon+180000000)*g.w/360000000,min((lat+90000000)*g.h/180000000,g.h-1))
}
func digit(_ c: Character, _ alphabet: String) throws -> Int {
    guard let i = Array(alphabet).firstIndex(of:c) else { throw Invalid.argument }
    return i
}
func digits(_ s: String) throws -> Int {
    try need(!s.isEmpty && s.utf8.allSatisfy { $0 >= 48 && $0 <= 57 })
    return Int(s)!
}
func pad(_ n: Int, _ width: Int) -> String {
    let s = String(n)
    return String(repeating:"0",count:max(0,width-s.count))+s
}
func power(_ n: Int) -> Int {
    var result = 1
    if n > 0 { for _ in 0..<n { result *= 10 } }
    return result
}
func radix(_ value: Int, _ bases: [Int], _ count: Int) -> [Int] {
    var rest = value
    var result = [Int](repeating:0,count:count)
    for i in stride(from:count-1,through:0,by:-1) {
        result[i] = rest%bases[i]
        rest /= bases[i]
    }
    return result
}
func code(_ c: Cell) -> String? {
    let p = precisionTable[c.system]![c.level]
    var x = c.x
    var y = c.y
    var result = ""
    switch c.system {
    case "GEOHASH":
        var ax = (5*p+1)/2
        var ay = 5*p/2
        var group = 0
        for bit in 0..<5*p {
            let b: Int
            if bit%2 == 0 {
                ax -= 1
                b = (x >> ax)&1
            } else {
                ay -= 1
                b = (y >> ay)&1
            }
            group = group*2+b
            if bit%5 == 4 {
                result.append(gh[group])
                group = 0
            }
        }
    case "MAIDENHEAD":
        let a = radix(x,[18,10,24,10],p/2)
        let b = radix(y,[18,10,24,10],p/2)
        for i in a.indices {
            result.append(maiden[i][a[i]])
            result.append(maiden[i][b[i]])
        }
    case "PLUSCODE":
        let extra = p == 11 ? 4*(y%5)+x%4 : -1
        if p == 11 {
            x /= 4
            y /= 5
        }
        let count = min(p,10)/2
        let a = radix(x,[18,20,20,20,20],count)
        let b = radix(y,[9,20,20,20,20],count)
        for i in 0..<count {
            result.append(plusAlphabet[b[i]])
            result.append(plusAlphabet[a[i]])
        }
        if extra >= 0 { result.append(plusAlphabet[extra]) }
        return p < 8 ? result+String(repeating:"0",count:8-p)+"+" : result.take(8)+"+"+result.drop(8)
    case "GARS":
        let scale = c.level == 0 ? 1 : c.level == 1 ? 2 : 6
        let bx = x/scale
        let by = y/scale
        result = pad(bx+1,3)+String(l24[by/24])+String(l24[by%24])
        if p >= 6 {
            let divisor = p == 7 ? 3 : 1
            result += String(1+x/divisor%2+2*(1-y/divisor%2))
        }
        if p == 7 { result += String(1+x%3+3*(2-y%3)) }
    case "GEOREF":
        if p == 2 { return String(l24[x])+String(l24[y]) }
        let m = (p-4)/2
        let scale = p == 4 ? 1 : 6*power(m-1)
        let bx = x/scale
        let by = y/scale
        result = String(l24[bx/15])+String(l24[by/15])+String(l24[bx%15])+String(l24[by%15])
        if p >= 8 { result += pad(x%scale,m)+pad(y%scale,m) }
    default:
        let scale = meshScale[c.level]
        let u = x-280*scale
        let v = y-135*scale
        if u < 0 || u >= 80*scale || v < 0 || v >= 100*scale { return nil }
        let count = c.level+1
        let a = radix(u,[80,8,10,2,2,2],count)
        let b = radix(v,[100,8,10,2,2,2],count)
        result = pad(b[0],2)+pad(a[0],2)
        if count > 1 {
            for i in 1..<count {
                if i <= 2 { result += String(b[i])+String(a[i]) }
                else { result += String(1+a[i]+2*b[i]) }
            }
        }
    }
    return result
}
func decode(_ system: String, _ text: String) throws -> Cell {
    _ = try precisions(system)
    var p = text.count
    var x = 0
    var y = 0
    switch system {
    case "GEOHASH":
        try need(p >= 1 && p <= 9)
        var bit = 0
        for ch in text {
            let d = try digit(ch,gh)
            for i in stride(from:4,through:0,by:-1) {
                if bit%2 == 0 { x = x*2+((d >> i)&1) }
                else { y = y*2+((d >> i)&1) }
                bit += 1
            }
        }
    case "MAIDENHEAD":
        _ = try level(system,p)
        for i in 0..<p/2 {
            x = try x*maiden[i].count+digit(text[2*i],maiden[i])
            y = try y*maiden[i].count+digit(text[2*i+1],maiden[i])
        }
    case "PLUSCODE":
        try need(p >= 9 && text.firstIndex(of:"+") == text.index(text.startIndex,offsetBy:8) && text.filter { $0 == "+" }.count == 1)
        let firstZero = Array(text.take(8)).firstIndex(of:"0")
        let before = firstZero ?? 8
        let after = p-9
        try need([2,4,6,8].contains(before))
        try need(before == 8 ? [0,2,3].contains(after) : after == 0)
        if before < 8 { for i in before..<8 { try need(text[i] == "0") } }
        let sequence = text.take(before)+text.drop(9)
        p = sequence.count
        try need(digit(sequence[0],plusAlphabet) <= 8 && digit(sequence[1],plusAlphabet) <= 17)
        for i in stride(from:0,to:min(p,10),by:2) {
            y = try y*20+digit(sequence[i],plusAlphabet)
            x = try x*20+digit(sequence[i+1],plusAlphabet)
        }
        if p == 11 {
            let d = try digit(sequence[10],plusAlphabet)
            x = x*4+d%4
            y = y*5+d/4
        }
    case "GARS":
        try need(p >= 5 && p <= 7)
        let e = try digits(text.take(3))
        try need(e >= 1 && e <= 720)
        x = e-1
        y = try digit(text[3],l24.take(15))*24+digit(text[4],l24)
        if p >= 6 {
            let q = try digit(text[5],"1234")
            x = x*2+q%2
            y = y*2+1-q/2
        }
        if p == 7 {
            let q = try digit(text[6],"123456789")
            x = x*3+q%3
            y = y*3+2-q/3
        }
    case "GEOREF":
        _ = try level(system,p)
        x = try digit(text[0],l24)
        y = try digit(text[1],l24.take(12))
        if p >= 4 {
            x = try x*15+digit(text[2],l24.take(15))
            y = try y*15+digit(text[3],l24.take(15))
        }
        if p >= 8 {
            let m = (p-4)/2
            let scale = 6*power(m-1)
            let a = try digits(text.slice(4,4+m))
            let b = try digits(text.drop(4+m))
            try need(a < scale && b < scale)
            x = x*scale+a
            y = y*scale+b
        }
    default:
        let l = try level(system,p)
        _ = try digits(text)
        var v = try digits(text.take(2))
        var u = try digits(text.slice(2,4))
        try need(u < 80)
        if p >= 6 {
            v = try v*8+digit(text[4],"01234567")
            u = try u*8+digit(text[5],"01234567")
        }
        if p >= 8 {
            v = try v*10+digit(text[6],"0123456789")
            u = try u*10+digit(text[7],"0123456789")
        }
        if p > 8 {
            for i in 8..<p {
                let q = try digit(text[i],"1234")
                v = v*2+q/2
                u = u*2+q%2
            }
        }
        x = u+280*meshScale[l]
        y = v+135*meshScale[l]
    }
    let result = try grid(system,level(system,p),x,y)
    try need(text == code(result))
    return result
}
func ancestor(_ c: Cell, _ level: Int) throws -> Cell {
    let g = try grid(c.system,level)
    return try grid(c.system,level,c.x*g.w/c.w,c.y*g.h/c.h)
}
func shown(_ c: Cell) -> String { code(c) ?? "-" }
func coordinateFormat(_ n: Int) -> String { (n < 0 ? "-" : "")+String(abs(n)/1000000)+"."+pad(abs(n)%1000000,6) }
func boundary(_ c: Cell, _ latitude: Bool, _ offset: Int, _ center: Bool) -> Int {
    let extent = latitude ? 180000000 : 360000000
    let total = latitude ? c.h : c.w
    let value = latitude ? c.y : c.x
    return -extent/2+(center ? extent*(2*value+1)/(2*total) : extent*(value+offset)/total)
}
func compare(_ a: Int, _ ad: Int, _ b: Int, _ bd: Int) -> Int {
    let left = a*bd
    let right = b*ad
    return left < right ? -1 : left > right ? 1 : 0
}
func inside(_ a: Cell, _ b: Cell) -> Bool {
    compare(a.x,a.w,b.x,b.w) >= 0 && compare(a.x+1,a.w,b.x+1,b.w) <= 0 &&
    compare(a.y,a.h,b.y,b.h) >= 0 && compare(a.y+1,a.h,b.y+1,b.h) <= 0
}
func mod(_ a: Int, _ n: Int) -> Int { (a%n+n)%n }
func floorDiv(_ a: Int, _ n: Int) -> Int { a/n-(a%n < 0 ? 1 : 0) }
func steps(_ a: Cell, _ b: Cell) -> (Int,Int) {
    var dx = mod(b.x-a.x,a.w)
    if dx > a.w/2 { dx -= a.w }
    return (dx,b.y-a.y)
}
func detail(_ a: String, _ b: String) throws -> (Int,Int,Int) {
    try need(matches(a,"[0-9]{1,5}") && matches(b,"[0-9]{1,5}") && a.count == b.count)
    let size = power(5-a.count)
    return try (digits(a)*size,digits(b)*size,size)
}
func columns(_ zone: Int) -> String { zone%3 == 1 ? "ABCDEFGH" : zone%3 == 2 ? "JKLMNPQR" : "STUVWXYZ" }
func auxiliary(_ t: [String]) throws -> String {
    let n = t.count-1
    switch t[0] {
    case "UTMZONE":
        try need(n == 2)
        let lat = try coordinate(t[1],true)
        let lon = try coordinate(t[2],false)
        if lat < -80000000 || lat >= 84000000 { return "NONE" }
        let band = bands[min((lat+80000000)/8000000,19)]
        var zone = (lon+180000000)/6000000+1
        if band == "V" && lon >= 3000000 && lon < 12000000 { zone = 32 }
        if band == "X" {
            if lon >= 0 && lon < 9000000 { zone = 31 }
            else if lon >= 9000000 && lon < 21000000 { zone = 33 }
            else if lon >= 21000000 && lon < 33000000 { zone = 35 }
            else if lon >= 33000000 && lon < 42000000 { zone = 37 }
        }
        return String(zone)+String(band)
    case "OSGB":
        try need(n == 3)
        let e = try range(t[1],0,699999)
        let north = try range(t[2],0,1299999)
        let d = try range(t[3],0,5)
        let letters = String(g25[(3-north/500000)*5+2+e/500000])+String(g25[(4-north/100000%5)*5+e/100000%5])
        return letters+(d == 0 ? "" : " "+pad(e%100000,5).take(d)+" "+pad(north%100000,5).take(d))
    case "UNOSGB":
        try need(n == 1 || n == 3)
        try need(t[1].count == 2)
        let a = try digit(t[1][0],g25)
        let b = try digit(t[1][1],g25)
        var e = 500000*(a%5-2)+100000*(b%5)
        var north = 500000*(3-a/5)+100000*(4-b/5)
        var size = 100000
        try need(e >= 0 && e < 700000 && north >= 0 && north < 1300000)
        if n == 3 {
            let values = try detail(t[2],t[3])
            e += values.0
            north += values.1
            size = values.2
        }
        return "sw=\(e),\(north) size=\(size)"
    case "MGRS":
        try need(n == 5)
        let zone = try range(t[1],1,60)
        let e = try range(t[3],100000,899999)
        let north = try range(t[4],0,9999999)
        try need(t[2].count == 1)
        _ = try digit(t[2][0],bands)
        let d = try range(t[5],0,5)
        let offset = zone%2 == 0 ? 5 : 0
        let square = String(columns(zone)[e/100000-1])+String(mrows[(north/100000+offset)%20])
        return String(zone)+t[2]+" "+square+(d == 0 ? "" : " "+pad(e%100000,5).take(d)+" "+pad(north%100000,5).take(d))
    case "UNMGRS":
        try need(n == 2 || n == 4)
        try need(matches(t[1],"[1-9][0-9]?[CDEFGHJKLMNPQRSTUVWX]"))
        let zone = Int(t[1].dropLast())!
        try need(zone <= 60 && t[2].count == 2)
        let a = try digit(t[2][0],columns(zone))
        let b = try digit(t[2][1],mrows)
        let offset = zone%2 == 0 ? 5 : 0
        var e = 100000*(a+1)
        var north = 100000*mod(b-offset,20)
        var size = 100000
        if n == 4 {
            let values = try detail(t[3],t[4])
            e += values.0
            north += values.1
            size = values.2
        }
        return t[1]+" sw=\(e),\(north) size=\(size)"
    case "QUADKEY":
        try need(n == 3)
        let z = try range(t[3],1,23)
        let x = try range(t[1],0,(1 << z)-1)
        let y = try range(t[2],0,(1 << z)-1)
        return stride(from:z-1,through:0,by:-1).map { String(((x >> $0)&1)+2*((y >> $0)&1)) }.joined()
    case "UNQUADKEY":
        try need(n == 1 && matches(t[1],"[0-3]{1,23}"))
        var x = 0
        var y = 0
        for ch in t[1].utf8 {
            let d = Int(ch)-48
            x = x*2+d%2
            y = y*2+d/2
        }
        return "x=\(x) y=\(y) z=\(t[1].count)"
    default: throw Invalid.argument
    }
}
func execute(_ line: String) throws -> String {
    let t = line.split(separator:" ").map(String.init)
    let command = t[0]
    let counts = ["ENCODE":4,"DECODE":2,"NEIGHBORS":2,"PARENT":2,"CHILDREN":2,"COMMON":3,
        "CONTAINS":4,"COVER":6,"CONVERT":5,"STEPS":3,"PATH":3,"RELATE":4,"SIZE":2,"SHORTEN":3,"RECOVER":3]
    if counts[command] == nil && command != "COMPACT" { return try auxiliary(t) }
    try need(command == "COMPACT" ? t.count >= 3 && t.count <= 102 : t.count == counts[command]!+1)
    if command == "SHORTEN" || command == "RECOVER" {
        let lat = try coordinate(t[2],true)
        let lon = try coordinate(t[3],false)
        if command == "SHORTEN" {
            let c = try decode("PLUSCODE",t[1])
            try need(precisions(c.system)[c.level] >= 8)
            let yn = -90000000*2*c.h+180000000*(2*c.y+1)
            let xn = -180000000*2*c.w+360000000*(2*c.x+1)
            if abs(yn-lat*2*c.h) < 15000*2*c.h && abs(xn-lon*2*c.w) < 15000*2*c.w { return t[1].drop(6) }
            if abs(yn-lat*2*c.h) < 300000*2*c.h && abs(xn-lon*2*c.w) < 300000*2*c.w { return t[1].drop(4) }
            return t[1]
        }
        let plus = Array(t[1]).firstIndex(of:"+") ?? -1
        try need(plus == 2 || plus == 4)
        try need(t[1].filter { $0 == "+" }.count == 1 && [0,2,3].contains(t[1].count-plus-1))
        for ch in t[1] where ch != "+" { _ = try digit(ch,plusAlphabet) }
        let missing = 8-plus
        let prefix = try code(point("PLUSCODE",4,lat,lon))!.take(missing)
        let c = try decode("PLUSCODE",prefix+t[1])
        let d = missing == 4 ? 1000000 : 50000
        var x = c.x
        var y = c.y
        let yn = -90000000*2*c.h+180000000*(2*y+1)
        let xn = -180000000*2*c.w+360000000*(2*x+1)
        let my = d*c.h/180000000
        let mx = d*c.w/360000000
        if (lat+d/2)*2*c.h < yn && yn-d*2*c.h >= -90000000*2*c.h { y -= my }
        else if (lat-d/2)*2*c.h > yn && yn+d*2*c.h <= 90000000*2*c.h { y += my }
        if (lon+d/2)*2*c.w < xn { x = mod(x-mx,c.w) }
        else if (lon-d/2)*2*c.w > xn { x = mod(x+mx,c.w) }
        return try code(grid("PLUSCODE",c.level,x,y))!
    }
    let system = t[1]
    _ = try precisions(system)
    switch command {
    case "ENCODE": return try code(point(system,level(system,integer(t[4])),coordinate(t[2],true),coordinate(t[3],false))) ?? "OUT OF AREA"
    case "SIZE":
        let l = try level(system,integer(t[2]))
        let c = try grid(system,l)
        let count = system == "MESH" ? 8000*meshScale[l]*meshScale[l] : c.w*c.h
        return "w=\(coordinateFormat(360000000/c.w)) h=\(coordinateFormat(180000000/c.h)) cells=\(count)"
    case "COVER":
        let l = try level(system,integer(t[2]))
        let lat1 = try coordinate(t[3],true)
        let lon1 = try coordinate(t[4],false)
        let lat2 = try coordinate(t[5],true)
        let lon2 = try coordinate(t[6],false)
        try need(lat1 <= lat2)
        let a = try point(system,l,lat1,lon1)
        let b = try point(system,l,lat2,lon2)
        let columns = lon1 <= lon2 ? b.x-a.x+1 : min(a.w,b.x-a.x+1+a.w)
        if columns*(b.y-a.y+1) > 100 { return "TOO MANY" }
        var result: [String] = []
        for y in stride(from:b.y,through:a.y,by:-1) {
            for i in 0..<columns { result.append(try shown(grid(system,l,(a.x+i)%a.w,y))) }
        }
        return result.joined(separator:" ")
    case "COMPACT":
        var cells = Set(try t.dropFirst(2).map { try decode(system,$0) })
        var covered = Set<Cell>()
        for c in cells {
            for a in cells where a.level < c.level {
                if try ancestor(c,a.level) == a { covered.insert(c) }
            }
        }
        cells.subtract(covered)
        var changed = true
        while changed {
            changed = false
            for child in Array(cells) {
                if child.level == 0 { continue }
                let parent = try ancestor(child,child.level-1)
                let g = try grid(system,child.level)
                let rx = g.w/parent.w
                let ry = g.h/parent.h
                if rx*ry > cells.count { continue }
                var siblings = Set<Cell>()
                for j in 0..<ry {
                    for i in 0..<rx { siblings.insert(try grid(system,child.level,parent.x*rx+i,parent.y*ry+j)) }
                }
                if cells.isSuperset(of:siblings) {
                    cells.subtract(siblings)
                    cells.insert(parent)
                    changed = true
                    break
                }
            }
        }
        return cells.sorted {
            if $0.level != $1.level { return $0.level < $1.level }
            if $0.y != $1.y { return $0.y > $1.y }
            return $0.x < $1.x
        }.map { code($0)! }.joined(separator:" ")
    default: break
    }
    let a = try decode(system,t[2])
    switch command {
    case "DECODE": return "sw=\(coordinateFormat(boundary(a,true,0,false))),\(coordinateFormat(boundary(a,false,0,false)))"+
        " ne=\(coordinateFormat(boundary(a,true,1,false))),\(coordinateFormat(boundary(a,false,1,false)))"+
        " c=\(coordinateFormat(boundary(a,true,0,true))),\(coordinateFormat(boundary(a,false,0,true)))"
    case "NEIGHBORS":
        let dx = [0,1,1,1,0,-1,-1,-1]
        let dy = [1,1,0,-1,-1,-1,0,1]
        return try (0..<8).map { i in
            return try a.y+dy[i] < 0 || a.y+dy[i] >= a.h ? "-" : shown(grid(system,a.level,mod(a.x+dx[i],a.w),a.y+dy[i]))
        }.joined(separator:" ")
    case "PARENT": return try a.level == 0 ? "NONE" : code(ancestor(a,a.level-1))!
    case "CHILDREN":
        if a.level+1 == precisionTable[system]!.count { return "NONE" }
        let g = try grid(system,a.level+1)
        let rx = g.w/a.w
        let ry = g.h/a.h
        if rx*ry > 100 { return "TOO MANY" }
        var result: [String] = []
        for j in stride(from:ry-1,through:0,by:-1) {
            for i in 0..<rx { result.append(try shown(grid(system,g.level,a.x*rx+i,a.y*ry+j))) }
        }
        return result.joined(separator:" ")
    case "COMMON":
        let b = try decode(system,t[3])
        for l in stride(from:min(a.level,b.level),through:0,by:-1) {
            let parent = try ancestor(a,l)
            if try parent == ancestor(b,l) { return code(parent)! }
        }
        return "NONE"
    case "CONTAINS": return try a == point(system,a.level,coordinate(t[3],true),coordinate(t[4],false)) ? "YES" : "NO"
    case "CONVERT":
        try need(t[3] == "TO")
        let g = try grid(t[4],level(t[4],integer(t[5])))
        return try code(grid(g.system,g.level,(2*a.x+1)*g.w/(2*a.w),(2*a.y+1)*g.h/(2*a.h))) ?? "OUT OF AREA"
    case "STEPS", "PATH":
        let b = try decode(system,t[3])
        if a.level != b.level { return "MISMATCH" }
        let (dx,dy) = steps(a,b)
        if command == "STEPS" { return "dx=\(dx) dy=\(dy)" }
        let n = max(abs(dx),abs(dy))
        if n+1 > 100 { return "TOO MANY" }
        return try (0...n).map { i in
            let ox = n == 0 ? 0 : floorDiv(2*i*dx+n,2*n)
            let oy = n == 0 ? 0 : floorDiv(2*i*dy+n,2*n)
            return try shown(grid(system,a.level,mod(a.x+ox,a.w),a.y+oy))
        }.joined(separator:" ")
    case "RELATE":
        let b = try decode(t[3],t[4])
        let ab = inside(a,b)
        let ba = inside(b,a)
        if ab && ba { return "EQUAL" }
        if ab { return "INSIDE" }
        if ba { return "CONTAINS" }
        let ew = compare(a.x+1,a.w,b.x,b.w)
        let we = compare(b.x+1,b.w,a.x,a.w)
        let ns = compare(a.y+1,a.h,b.y,b.h)
        let sn = compare(b.y+1,b.h,a.y,a.h)
        if ew > 0 && we > 0 && ns > 0 && sn > 0 { return "OVERLAP" }
        let dateline = a.x+1 == a.w && b.x == 0 || b.x+1 == b.w && a.x == 0
        return ns >= 0 && sn >= 0 && (ew >= 0 && we >= 0 || dateline) ? "TOUCH" : "DISJOINT"
    default: throw Invalid.argument
    }
}
let commandCount = Int(readLine()!)!
for _ in 0..<commandCount {
    do { print(try execute(readLine()!)) }
    catch { print("INVALID") }
}
