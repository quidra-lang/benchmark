import Foundation

let bases = "ACGT"
let symbols = "ACGTRYSWKMBDHVN"
let complements = "TGCAYRSWMKVHDBN"
let hexAlphabet = "0123456789ABCDEF"
let masks = [1,2,4,8,5,10,6,9,12,3,14,13,11,7,15]
let amino = "ACDEFGHIKLMNPQRSTVWY"
let residues = [71079,103139,115089,129116,147177,57052,137141,113160,128174,113160,131193,114104,97117,128131,156188,87078,101105,99133,186213,163176]
let baseMass = [331222,307197,347221,322208]
let enzymes = ["EcoRI","BamHI","HindIII","PstI","SmaI","KpnI","XbaI","NotI","EcoRV","HaeIII","AluI","TaqI","Sau3AI","HincII","AvaI"]
let sites = ["GAATTC","GGATCC","AAGCTT","CTGCAG","CCCGGG","GGTACC","TCTAGA","GCGGCCGC","GATATC","GGCC","AGCT","TCGA","GATC","GTYRAC","CYCGRG"]
let cuts = [1,1,1,5,3,5,1,2,3,2,2,1,0,3,1]
let genetic: [String:Character] = {
    let groups = ["A GCT GCC GCA GCG",
            "C TGT TGC",
            "D GAT GAC",
            "E GAA GAG",
            "F TTT TTC",
            "G GGT GGC GGA GGG",
            "H CAT CAC",
            "I ATT ATC ATA",
            "K AAA AAG",
            "L TTA TTG CTT CTC CTA CTG",
            "M ATG",
            "N AAT AAC",
            "P CCT CCC CCA CCG",
            "Q CAA CAG",
            "R CGT CGC CGA CGG AGA AGG",
            "S TCT TCC TCA TCG AGT AGC",
            "T ACT ACC ACA ACG",
            "V GTT GTC GTA GTG",
            "W TGG",
            "Y TAT TAC",
            "* TAA TAG TGA"]
    var result: [String:Character] = [:]
    for group in groups {
        let t = group.split(separator:" ").map(String.init)
        for codon in t.dropFirst() { result[codon] = t[0].first! }
    }
    return result
}()
extension String {
    subscript(_ i: Int) -> Character {
        Character(UnicodeScalar(utf8[utf8.index(utf8.startIndex,offsetBy:i)]))
    }
    func part(_ from: Int, _ to: Int) -> String {
        let a = utf8.index(utf8.startIndex,offsetBy:from)
        let b = utf8.index(utf8.startIndex,offsetBy:to)
        return String(decoding:utf8[a..<b],as:UTF8.self)
    }
}
enum Fault: Error { case reason(String) }
func error(_ condition: Bool, _ reason: String) throws {
    if condition { throw Fault.reason(reason) }
}
func matches(_ s: String, _ pattern: String) -> Bool { s.range(of:"\\A(?:"+pattern+")\\z",options:.regularExpression) != nil }
func number(_ s: String, _ low: Int, _ high: Int) throws -> Int {
    try error(!matches(s,"-?[0-9]{1,6}"),"invalid number "+s)
    let n = Int(s)!
    try error(n < low || n > high,"invalid number "+s)
    return n
}
func complement(_ s: String) -> String { String(s.map { complements[Array(symbols).firstIndex(of:$0)!] }) }
func revcomp(_ s: String) -> String { String(complement(s).reversed()) }
func complementBase(_ c: Character) -> Character { bases[3-Array(bases).firstIndex(of:c)!] }
func gc(_ s: String) -> Int { s.utf8.filter { $0 == 71 || $0 == 67 }.count }
func fixed(_ n: Int, _ divisor: Int, _ width: Int) -> String {
    let fraction = String(n%divisor)
    return "\(n/divisor)."+String(repeating:"0",count:width-fraction.count)+fraction
}
func pct(_ a: Int, _ b: Int) -> String { fixed(10000*a/b,100,2) }
func milli(_ n: Int) -> String { fixed(n,1000,3) }
func list<T>(_ values: [T]) -> String { values.isEmpty ? "none" : values.map { String(describing:$0) }.joined(separator:" ") }
func codons(_ s: String, _ frame: Int) -> [String] {
    let strand = frame > 0 ? s : revcomp(s)
    var result: [String] = []
    var i = abs(frame)-1
    while i+3 <= s.count {
        result.append(strand.part(i,i+3))
        i += 3
    }
    return result
}
func translation(_ codons: [String]) -> String { String(codons.map { genetic[$0]! }) }
func wordCounts(_ words: [String]) -> [String:Int] {
    var result: [String:Int] = [:]
    for word in words { result[word,default:0] += 1 }
    return result
}
func frequency(_ counts: [String:Int]) -> [String] { counts.keys.sorted { counts[$0] == counts[$1] ? $0 < $1 : counts[$0]! > counts[$1]! } }
func occurrences(_ s: String, _ motif: String) -> [Int] {
    let sequence = Array(s)
    let pattern = Array(motif).map { masks[Array(symbols).firstIndex(of:$0)!] }
    if pattern.count > sequence.count { return [] }
    let codes = sequence.map { 1 << Array(bases).firstIndex(of:$0)! }
    var result: [Int] = []
    for i in 0...(sequence.count-pattern.count) {
        if pattern.indices.allSatisfy({ pattern[$0]&codes[i+$0] != 0 }) { result.append(i+1) }
    }
    return result
}
func transition(_ a: Character, _ b: Character) -> Bool {
    a != b && ("AG".contains(a) && "AG".contains(b) || "CT".contains(a) && "CT".contains(b))
}
func repeatCount(_ s: String, _ i: Int, _ u: Int) -> Int {
    let unit = s.part(i,i+u)
    var count = 1
    while i+(count+1)*u <= s.count && s.part(i+count*u,i+(count+1)*u) == unit { count += 1 }
    return count
}
func primitive(_ s: String) -> Bool {
    if s.count > 1 {
        for d in 1..<s.count where s.count%d == 0 {
            if String(repeating:s.part(0,d),count:s.count/d) == s { return false }
        }
    }
    return true
}
func selfcomp(_ s: String) -> Int {
    let a = Array(s)
    var maximum = 0
    if a.count > 1 {
        for center in 1..<a.count {
            var left = center-1
            var right = center
            while left >= 0 && right < a.count && complementBase(a[left]) == a[right] {
                maximum = max(maximum,right-left+1)
                left -= 1
                right += 1
            }
        }
    }
    return maximum
}
func tm(_ s: String) -> Int {
    let n = s.count
    let g = gc(s)
    return n < 14 ? 10*(2*(n-g)+4*g) : (649*n+410*g-6724)/n
}
func mass(_ s: String) -> Int { s.reduce(0) { $0+baseMass[Array(bases).firstIndex(of:$1)!] }-(s.count-1)*18015 }
func overlap(_ a: String, _ b: String) -> Int {
    let joined = Array((b+"#"+a).utf8)
    var prefix = Array(repeating:0,count:joined.count)
    for i in 1..<joined.count {
        var j = prefix[i-1]
        while j > 0 && joined[i] != joined[j] { j = prefix[j-1] }
        if joined[i] == joined[j] { j += 1 }
        prefix[i] = j
    }
    var result = prefix.last!
    let limit = min(a.count,b.count)
    while result >= limit { result = prefix[result-1] }
    return result
}
struct Orf {
    let frame: Int
    let left: Int
    let right: Int
    let protein: String
}
struct Repeat {
    let start: Int
    let end: Int
    let unitLength: Int
    let unit: String
    let count: Int
}
final class Toolkit {
    var registry: [String:String] = [:]
    var schemas: [String:[String]] = [:]
    var arities: [String:ClosedRange<Int>] = [:]
    var output: [String] = []
    init() {
        schema("SEQ",2,2,"NEW","SEQ")
        schema("SLICE",4,4,"NAME","POS","POS","NEW")
        schema("JOIN",3,9,"NEW","NAME")
        schema("MUTATE",3,3,"NAME","POS","BASE")
        for c in ["DEL","REVCOMP","COMPLEMENT","REVERSE","TRANSCRIBE","GC","SKEW","TM","MASS","PRIMER","PACK"] { schema(c,1,1,"NAME") }
        schema("LIST",0,0)
        for c in ["TRANSLATE","CODONS","PROTEIN"] { schema(c,2,2,"NAME","FRAME") }
        schema("ORFS",2,2,"NAME","1:200")
        schema("GCWINDOW",3,3,"NAME","1:500","1:500")
        schema("KMERS",3,3,"NAME","1:12","1:100")
        schema("FIND",2,2,"NAME","MOTIF")
        schema("RESTRICT",2,7,"NAME","ENZYME")
        schema("PALINDROMES",3,3,"NAME","2:20","2:20")
        schema("REPEATS",4,4,"NAME","1:6","1:6","2:50")
        schema("HAMMING",2,2,"NAME","NAME")
        schema("ALIGN",6,6,"NAME","NAME","MODE","1:20","-20:0","-20:-1")
        schema("CONSENSUS",2,10,"NAME")
        schema("FOLD",2,2,"NAME","0:10")
        schema("ASSEMBLE",4,10,"NEW","1:100","NAME")
        schema("UNPACK",3,3,"NEW","1:500","HEX")
    }
    func schema(_ c: String, _ low: Int, _ high: Int, _ args: String...) {
        schemas[c] = args
        arities[c] = low...high
    }
    func emit(_ s: String) { output.append(s) }
    func store(_ name: String, _ sequence: String) throws {
        try error(sequence.count > 500,"too long")
        let replacing = registry[name] != nil
        registry[name] = sequence
        emit((replacing ? "replaced " : "stored ")+"\(name) \(sequence.count) nt")
    }
    func validate(_ command: String, _ a: [String], _ nums: inout [Int], _ sequences: inout [String]) throws {
        guard let schema = schemas[command] else { throw Fault.reason("unknown command "+command) }
        try error(!arities[command]!.contains(a.count),"wrong argument count")
        var seen = Set<String>()
        for (i,value) in a.enumerated() {
            let kind = schema[min(i,schema.count-1)]
            switch kind {
            case "NAME":
                guard let sequence = registry[value] else { throw Fault.reason("unknown sequence "+value) }
                sequences[i] = sequence
            case "NEW": try error(!matches(value,"[a-z][a-z0-9]{0,9}"),"invalid name "+value)
            case "SEQ":
                for (j,c) in value.enumerated() { try error(!bases.contains(c),"invalid base \(c) at \(j+1)") }
            case "BASE": try error(value.count != 1 || !bases.contains(value.first!),"invalid base "+value)
            case "MOTIF": try error(!matches(value,"[ACGTRYSWKMBDHVN]{1,30}"),"invalid motif "+value)
            case "ENZYME":
                try error(!enzymes.contains(value),"unknown enzyme "+value)
                try error(!seen.insert(value).inserted,"duplicate enzyme "+value)
            case "MODE": try error(value != "GLOBAL" && value != "LOCAL","invalid mode "+value)
            case "HEX": try error(value.count != 2*((nums[1]+3)/4) || !matches(value,"[0-9A-F]+"),"invalid hex")
            case "FRAME":
                nums[i] = try number(value,-3,3)
                try error(nums[i] == 0,"invalid number "+value)
            case "POS": nums[i] = try number(value,1,sequences[0].count)
            default:
                let bounds = kind.split(separator:":")
                nums[i] = try number(value,Int(bounds[0])!,Int(bounds[1])!)
            }
        }
    }
    func align(_ a: String, _ b: String, _ local: Bool, _ match: Int, _ mismatch: Int, _ gap: Int) {
        let x = Array(a)
        let y = Array(b)
        let m = x.count
        let n = y.count
        var h = Array(repeating:Array(repeating:0,count:n+1),count:m+1)
        if !local {
            for i in 0...m { h[i][0] = i*gap }
            for j in 0...n { h[0][j] = j*gap }
        }
        var best = 0
        var bi = 0
        var bj = 0
        for i in 1...m {
            for j in 1...n {
                let value = max(h[i-1][j-1]+(x[i-1] == y[j-1] ? match : mismatch),max(h[i-1][j]+gap,h[i][j-1]+gap))
                h[i][j] = local ? max(0,value) : value
                if local && h[i][j] > best {
                    best = h[i][j]
                    bi = i
                    bj = j
                }
            }
        }
        if !local {
            bi = m
            bj = n
            best = h[m][n]
        }
        if local && best == 0 {
            emit("score 0")
            return
        }
        var i = bi
        var j = bj
        var left: [Character] = []
        var right: [Character] = []
        while (local ? h[i][j] != 0 : i != 0 || j != 0) {
            if i > 0 && j > 0 && h[i][j] == h[i-1][j-1]+(x[i-1] == y[j-1] ? match : mismatch) {
                i -= 1
                j -= 1
                left.append(x[i])
                right.append(y[j])
            } else if i > 0 && h[i][j] == h[i-1][j]+gap {
                i -= 1
                left.append(x[i])
                right.append("-")
            } else {
                j -= 1
                left.append("-")
                right.append(y[j])
            }
        }
        left.reverse()
        right.reverse()
        let middle: [Character] = left.indices.map { k in left[k] == "-" || right[k] == "-" ? "-" : left[k] == right[k] ? "|" : "*" }
        let identity = middle.filter { $0 == "|" }.count
        let gaps = middle.filter { $0 == "-" }.count
        emit("score \(best) a \(i+1)-\(bi) b \(j+1)-\(bj) identity \(identity)/\(left.count) gaps \(gaps)")
        emit(String(left))
        emit(String(middle))
        emit(String(right))
    }
    func pair(_ a: Character, _ b: Character) -> Bool { complementBase(a) == b || a == "G" && b == "T" || a == "T" && b == "G" }
    func value(_ f: [[Int]], _ i: Int, _ j: Int) -> Int { i > j ? 0 : f[i][j] }
    func fold(_ s: String, _ loop: Int) throws {
        let a = Array(s)
        let n = a.count
        try error(n > 100,"too long")
        var f = Array(repeating:Array(repeating:0,count:n),count:n)
        for length in 1...n {
            for i in 0...(n-length) {
                let j = i+length-1
                f[i][j] = value(f,i,j-1)
                if i <= j-loop-1 {
                    for k in i...(j-loop-1) where pair(a[k],a[j]) { f[i][j] = max(f[i][j],value(f,i,k-1)+1+value(f,k+1,j-1)) }
                }
            }
        }
        var structure = Array(repeating:Character("."),count:n)
        var intervals = [(0,n-1)]
        while let (i,j) = intervals.popLast() {
            if value(f,i,j) == 0 { continue }
            if f[i][j] == value(f,i,j-1) { intervals.append((i,j-1)) }
            else if i <= j-loop-1 {
                for k in i...(j-loop-1) {
                    if pair(a[k],a[j]) && value(f,i,k-1)+1+value(f,k+1,j-1) == f[i][j] {
                        structure[k] = "("
                        structure[j] = ")"
                        intervals.append((i,k-1))
                        intervals.append((k+1,j-1))
                        break
                    }
                }
            }
        }
        emit(String(structure))
        emit("pairs \(f[0][n-1])")
    }
    func primer(_ s: String) {
        let a = Array(s)
        let n = a.count
        let g = gc(s)
        let temperature = tm(s)
        let clamp = gc(String(s.suffix(5)))
        var run = 1
        var bestRun = 1
        var repeats = 0
        if n > 1 {
            for i in 1..<n {
                run = a[i] == a[i-1] ? run+1 : 1
                bestRun = max(bestRun,run)
            }
            for i in 0..<n-1 where a[i] != a[i+1] { repeats = max(repeats,repeatCount(s,i,2)) }
        }
        let selfMatch = selfcomp(s)
        let names = ["length","gc","tm","clamp","run","repeat","selfcomp"]
        let values = [String(n),pct(g,n),fixed(temperature,10,1),String(clamp),String(bestRun),String(repeats),String(selfMatch)]
        let ok = [n >= 18 && n <= 25,40*n <= 100*g && 100*g <= 60*n,temperature >= 520 && temperature <= 620,clamp >= 1 && clamp <= 3,bestRun <= 4,repeats <= 4,selfMatch <= 6]
        var failed: [String] = []
        for i in 0..<7 {
            emit(names[i]+" "+values[i]+" "+(ok[i] ? "OK" : "FAIL"))
            if !ok[i] { failed.append(names[i]) }
        }
        emit(failed.isEmpty ? "PASS" : "FAIL "+list(failed))
    }
    func assemble(_ name: String, _ minimum: Int, _ sequences: [String]) throws {
        var unique: [String] = []
        for s in sequences.dropFirst(2) where !unique.contains(s) { unique.append(s) }
        var fragments = unique.filter { s in !unique.contains { $0 != s && $0.contains(s) } }
        while fragments.count >= 2 {
            var best = -1
            var bx = 0
            var by = 0
            for x in fragments.indices {
                for y in fragments.indices where x != y {
                    let current = overlap(fragments[x],fragments[y])
                    if current > best {
                        best = current
                        bx = x
                        by = y
                    }
                }
            }
            if best < minimum { break }
            let merged = fragments[bx]+fragments[by].part(best,fragments[by].count)
            fragments[bx] = merged
            fragments.remove(at:by)
            var keep = bx-(by < bx ? 1 : 0)
            for i in stride(from:fragments.count-1,through:0,by:-1) {
                if i != keep && merged.contains(fragments[i]) {
                    fragments.remove(at:i)
                    if i < keep { keep -= 1 }
                }
            }
        }
        var longest = fragments[0]
        for s in fragments where s.count > longest.count { longest = s }
        try error(longest.count > 500,"too long")
        emit("contigs \(fragments.count)")
        for s in fragments { emit("\(s.count) \(s)") }
        try store(name,longest)
    }
    func execute(_ line: String) throws {
        let t = line.split(separator:" ").map(String.init)
        let a = Array(t.dropFirst())
        var nums = Array(repeating:0,count:a.count)
        var sequences = Array(repeating:"",count:a.count)
        let command = t[0]
        try validate(command,a,&nums,&sequences)
        let s = sequences.first ?? ""
        let n = s.count
        switch command {
        case "SEQ": try store(a[0],a[1])
        case "SLICE":
            let part = s.part(min(nums[1],nums[2])-1,max(nums[1],nums[2]))
            try store(a[3],nums[1] <= nums[2] ? part : revcomp(part))
        case "JOIN": try store(a[0],sequences.dropFirst().joined())
        case "MUTATE":
            let old = s[nums[1]-1]
            let next = a[2][0]
            try error(old == next,"no change")
            registry[a[0]] = s.part(0,nums[1]-1)+String(next)+s.part(nums[1],n)
            emit("\(a[0]) \(old)\(nums[1])\(next) "+(transition(old,next) ? "transition" : "transversion"))
        case "DEL":
            registry.removeValue(forKey:a[0])
            emit("deleted "+a[0])
        case "LIST":
            if registry.isEmpty { emit("no sequences") }
            for name in registry.keys.sorted() { emit("\(name) \(registry[name]!.count) nt") }
        case "REVCOMP": emit(revcomp(s))
        case "COMPLEMENT": emit(complement(s))
        case "REVERSE": emit(String(s.reversed()))
        case "TRANSCRIBE": emit(s.replacingOccurrences(of:"T",with:"U"))
        case "TRANSLATE":
            let protein = translation(codons(s,nums[1]))
            emit(protein.isEmpty ? "none" : protein)
        case "CODONS":
            let counts = wordCounts(codons(s,nums[1]))
            if counts.isEmpty { emit("none") }
            for c in frequency(counts) { emit("\(c) \(genetic[c]!) \(counts[c]!)") }
        case "PROTEIN":
            let full = translation(codons(s,nums[1]))
            let protein = String(full.prefix { $0 != "*" })
            try error(protein.isEmpty,"empty protein")
            let weight = 18015+protein.reduce(0) { $0+residues[Array(amino).firstIndex(of:$1)!] }
            let charge = protein.filter { "KR".contains($0) }.count-protein.filter { "DE".contains($0) }.count
            let counts = wordCounts(protein.map { String($0) })
            emit(protein)
            emit("length \(protein.count) mass \(milli(weight)) charge "+(charge > 0 ? "+" : "")+String(charge))
            emit(frequency(counts).map { "\($0)=\(counts[$0]!)" }.joined(separator:" "))
        case "ORFS":
            var found: [Orf] = []
            for frame in [1,2,3,-1,-2,-3] {
                let codonList = codons(s,frame)
                var start = -1
                for i in codonList.indices {
                    if start < 0 && codonList[i] == "ATG" { start = i }
                    else if start >= 0 && genetic[codonList[i]] == "*" {
                        if i-start >= nums[1] {
                            let left = abs(frame)-1+3*start
                            let right = abs(frame)-1+3*(i+1)-1
                            found.append(Orf(frame:frame,left:frame > 0 ? left+1 : n-right,right:frame > 0 ? right+1 : n-left,protein:translation(Array(codonList[start..<i]))))
                        }
                        start = -1
                    }
                }
            }
            if found.isEmpty { emit("none") }
            for o in found.sorted(by:{ $0.left < $1.left }) { emit((o.frame > 0 ? "+" : "")+"\(o.frame) \(o.left) \(o.right) \(o.protein.count) \(o.protein)") }
        case "GC":
            let composition = bases.map { base in "\(base)=\(s.filter { $0 == base }.count)" }.joined(separator:" ")
            emit(composition+" GC=\(pct(gc(s),n))%")
        case "GCWINDOW":
            try error(nums[1] > n,"window too large")
            for i in stride(from:0,through:n-nums[1],by:nums[2]) { emit("\(i+1)-\(i+nums[1]) \(pct(gc(s.part(i,i+nums[1])),nums[1]))%") }
        case "SKEW":
            var skew = [0]
            for c in s { skew.append(skew.last!+(c == "G" ? 1 : c == "C" ? -1 : 0)) }
            let low = skew.min()!
            let high = skew.max()!
            emit("min \(low) at "+list(skew.indices.filter { skew[$0] == low }))
            emit("max \(high) at "+list(skew.indices.filter { skew[$0] == high }))
        case "KMERS":
            try error(nums[1] > n,"k too large")
            let words = (0...(n-nums[1])).map { s.part($0,$0+nums[1]) }
            let counts = wordCounts(words)
            emit("\(words.count) windows \(counts.count) distinct")
            for word in frequency(counts).prefix(nums[2]) { emit("\(word) \(counts[word]!)") }
        case "FIND":
            emit("forward "+list(occurrences(s,a[1])))
            emit("reverse "+list(occurrences(s,revcomp(a[1]))))
        case "RESTRICT":
            var allCuts = Set<Int>()
            for enzyme in a.dropFirst() {
                let e = enzymes.firstIndex(of:enzyme)!
                let found = occurrences(s,sites[e]).map { $0+cuts[e]-1 }.filter { $0 >= 1 && $0 < n }
                allCuts.formUnion(found)
                emit(enzyme+" "+list(found))
            }
            let ends = allCuts.sorted()+[n]
            var previous = 0
            var fragments: [String] = []
            var sizes: [Int] = []
            for end in ends {
                fragments.append("\(previous+1)-\(end)")
                sizes.append(end-previous)
                previous = end
            }
            emit("fragments "+list(fragments))
            emit("sizes "+list(sizes.sorted(by:>)))
        case "PALINDROMES":
            try error(nums[1] > nums[2],"invalid range")
            var count = 0
            for i in 0..<n {
                let last = min(nums[2],n-i)
                if nums[1] <= last {
                    for length in nums[1]...last {
                        let part = s.part(i,i+length)
                        if part == revcomp(part) {
                            emit("\(i+1) \(length) \(part)")
                            count += 1
                        }
                    }
                }
            }
            if count == 0 { emit("none") }
        case "REPEATS":
            try error(nums[1] > nums[2],"invalid range")
            var found: [Repeat] = []
            for u in nums[1]...nums[2] {
                var i = 0
                while i+u <= n {
                    let unit = s.part(i,i+u)
                    let count = repeatCount(s,i,u)
                    if primitive(unit) && count >= nums[3] {
                        found.append(Repeat(start:i+1,end:i+count*u,unitLength:u,unit:unit,count:count))
                        i += count*u
                    } else { i += 1 }
                }
            }
            if found.isEmpty { emit("none") }
            for r in found.sorted(by:{ $0.start == $1.start ? $0.unitLength < $1.unitLength : $0.start < $1.start }) { emit("\(r.start)-\(r.end) \(r.unit)x\(r.count)") }
        case "HAMMING":
            let b = sequences[1]
            try error(n != b.count,"length mismatch")
            let left = Array(s)
            let right = Array(b)
            var distance = 0
            var transitions = 0
            for i in left.indices where left[i] != right[i] {
                distance += 1
                if transition(left[i],right[i]) { transitions += 1 }
            }
            emit("distance \(distance) transitions \(transitions) transversions \(distance-transitions)")
        case "ALIGN": align(s,sequences[1],a[2] == "LOCAL",nums[3],nums[4],nums[5])
        case "CONSENSUS":
            try error(sequences.contains { $0.count != n },"length mismatch")
            let rows = sequences.map { Array($0) }
            var profile = Array(repeating:Array(repeating:0,count:n),count:4)
            var consensus = ""
            var iupac = ""
            for i in 0..<n {
                for sequence in rows { profile[Array(bases).firstIndex(of:sequence[i])!][i] += 1 }
                let maximum = (0..<4).map { profile[$0][i] }.max()!
                let winners = (0..<4).filter { profile[$0][i] == maximum }
                consensus.append(bases[winners[0]])
                let mask = winners.reduce(0) { $0+(1 << $1) }
                iupac.append(symbols[masks.firstIndex(of:mask)!])
            }
            for b in 0..<4 { emit("\(bases[b]) "+list(profile[b])) }
            emit("consensus "+consensus)
            emit("iupac "+iupac)
        case "TM": emit("Tm \(fixed(tm(s),10,1)) "+(n < 14 ? "wallace" : "gc"))
        case "MASS": emit("ss \(milli(mass(s))) ds \(milli(mass(s)+mass(revcomp(s))))")
        case "PRIMER": primer(s)
        case "FOLD": try fold(s,nums[1])
        case "ASSEMBLE": try assemble(a[0],nums[1],sequences)
        case "PACK":
            let sequence = Array(s)
            var hex = ""
            for i in stride(from:0,to:n,by:4) {
                var value = 0
                for j in 0..<4 { value = 4*value+(i+j < n ? Array(bases).firstIndex(of:sequence[i+j])! : 0) }
                hex.append(hexAlphabet[value/16])
                hex.append(hexAlphabet[value%16])
            }
            emit("\(n) \(hex)")
        case "UNPACK":
            let hex = Array(a[2])
            var decoded: [Character] = []
            for i in stride(from:0,to:hex.count,by:2) {
                let value = 16*Array(hexAlphabet).firstIndex(of:hex[i])!+Array(hexAlphabet).firstIndex(of:hex[i+1])!
                for shift in [6,4,2,0] { decoded.append(bases[(value >> shift)&3]) }
            }
            for i in nums[1]..<decoded.count { try error(decoded[i] != "A","invalid padding") }
            try store(a[0],String(decoded.prefix(nums[1])))
        default: break
        }
    }
    func process(_ line: String) -> [String] {
        output = []
        do { try execute(line) }
        catch Fault.reason(let reason) {
            output = []
            emit("ERROR "+reason)
        }
        catch { fatalError("Unexpected error") }
        return output
    }
}
let toolkit = Toolkit()
let commandCount = Int(readLine()!)!
for _ in 0..<commandCount {
    for line in toolkit.process(readLine()!) { print(line) }
}
