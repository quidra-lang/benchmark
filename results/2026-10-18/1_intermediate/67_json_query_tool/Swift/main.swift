import Foundation
indirect enum Value {
    case object([(String,Value)]), array([Value]), string(String), number(Int64), boolean(Bool), null
}
struct Problem: Error {
    let text:String
}
struct ParseProblem: Error {
    let position:Int, reason:String
}
func ascii(_ b:[UInt8]) -> String {
    String(decoding:b,as:UTF8.self)
}
func identifier(_ s:String) -> Bool {
    let bytes = Array(s.utf8)
    guard let first = bytes.first, letter(first) || first == 95 else { return false }
    return bytes.dropFirst().allSatisfy { letter($0) || (48...57).contains($0) || $0 == 95 }
}
func integer(_ s:String) -> Int64? {
    s.range(of:"^(?:0|-?[1-9][0-9]{0,8})$",options:.regularExpression) != nil ? Int64(s) : nil
}
func quote(_ s:String,_ q:UInt8) -> String {
    var out=String(UnicodeScalar(q))
    for c in s.utf8 {
        if c==q || c==92 {
            out += "\\"+String(UnicodeScalar(c))
        }
        else {
            switch c {
                case 8: out += "\\b"
                case 12: out += "\\f"
                case 10: out += "\\n"
                case 13: out += "\\r"
                case 9: out += "\\t"
                case 0..<32,127: out += String(format:"\\u%04x",Int(c))
                default: out += String(UnicodeScalar(c))
            }
        }
    }
    return out+String(UnicodeScalar(q))
}
func kind(_ v:Value) -> String {
    switch v {
        case .object: return "object"
        case .array: return "array"
        case .string: return "string"
        case .number: return "number"
        case .boolean: return "boolean"
        case .null: return "null"
    }
}
func compact(_ v:Value) -> String {
    switch v {
        case .object(let o): return "{"+o.map {
            quote($0.0,34)+":"+compact($0.1)
        }.joined(separator:",")+"}"
        case .array(let a): return "["+a.map(compact).joined(separator:",")+"]"
        case .string(let s): return quote(s,34)
        case .number(let n): return String(n)
        case .boolean(let b): return b ? "true" : "false"
        case .null: return "null"
    }
}
func pretty(_ v:Value,_ indent:String="") -> String {
    let next=indent+"  "
    switch v {
        case .object(let o) where !o.isEmpty: return "{\n"+o.map {
            next+quote($0.0,34)+": "+pretty($0.1,next)
        }.joined(separator:",\n")+"\n"+indent+"}"
        case .array(let a) where !a.isEmpty: return "[\n"+a.map {
            next+pretty($0,next)
        }.joined(separator:",\n")+"\n"+indent+"]"
        default: return compact(v)
    }
}
func children(_ v:Value) -> Int {
    switch v {
        case .object(let o): return o.count
        case .array(let a): return a.count
        default: return 0
    }
}
func child(_ v:Value,_ i:Int) -> Value {
    switch v {
        case .object(let o): return o[i].1
        case .array(let a): return a[i]
        default: fatalError("not a container")
    }
}
func length(_ v:Value) -> Int? {
    switch v {
        case .object(let o): return o.count
        case .array(let a): return a.count
        case .string(let s): return s.utf8.count
        default: return nil
    }
}
func sizeDepth(_ v:Value) -> (Int,Int) {
    var size=1, depth=1
    for i in 0..<children(v) {
        let (n,d)=sizeDepth(child(v,i))
        size += n
        depth=max(depth,d+1)
    }
    return (size,depth)
}
func equal(_ a:Value,_ b:Value) -> Bool {
    switch (a,b) {
        case (.null,.null): return true
        case (.number(let a),.number(let b)): return a==b
        case (.string(let a),.string(let b)): return a==b
        case (.boolean(let a),.boolean(let b)): return a==b
        case (.array(let a),.array(let b)): return a.count==b.count && zip(a,b).allSatisfy {
            equal($0.0,$0.1)
        }
        case (.object(let a),.object(let b)): return a.count==b.count && a.allSatisfy {
            key,value in b.first {
                $0.0==key
            }.map {
                equal(value,$0.1)
            } ?? false
        }
        default: return false
    }
}
final class JsonParser {
    let text:[UInt8]
    var at=0
    init(_ s:String) {
        text=Array(s.utf8)
    }
    func current() -> UInt8? {
        at<text.count ? text[at] : nil
    }
    func fail(_ reason:String,_ position:Int?=nil) throws -> Never {
        throw ParseProblem(position:position ?? at,reason:reason)
    }
    func skip() {
        while current()==32 || current()==10 {
            at += 1
        }
    }
    func string() throws -> String {
        at += 1
        var out:[UInt8]=[]
        while true {
            guard let c=current(), c != 10 else {
                try fail("unterminated string")
            }
            if c==34 {
                at += 1
                return ascii(out)
            }
            if c != 92 {
                out.append(c)
                at += 1
                continue
            }
            guard at+1<text.count, text[at+1] != 10 else {
                try fail("unterminated string",at+1)
            }
            let e=text[at+1]
            if e==117 {
                guard at+6<=text.count, text[(at+2)..<(at+6)].allSatisfy({
                    hex($0) != nil
                }) else {
                    try fail("bad unicode escape")
                }
                let n=Int(ascii(Array(text[(at+2)..<(at+6)])),radix:16)!
                if n>127 {
                    try fail("non-ascii escape")
                }
                out.append(UInt8(n))
                at += 6
            } else {
                let decoded:UInt8
                switch e {
                    case 34,92,47: decoded=e
                    case 98: decoded=8
                    case 102: decoded=12
                    case 110: decoded=10
                    case 114: decoded=13
                    case 116: decoded=9
                    default: try fail("invalid escape '\\"+String(UnicodeScalar(e))+"'")
                }
                out.append(decoded)
                at += 2
            }
        }
    }
    func value() throws -> Value {
        skip()
        guard let c=current() else {
            try fail("unexpected end of input")
        }
        if c==34 {
            return .string(try string())
        }
        if c==123 {
            at += 1
            skip()
            var object:[(String,Value)]=[]
            if current()==125 {
                at += 1
                return .object(object)
            }
            while true {
                skip()
                let start=at
                guard let next=current() else {
                    try fail("unexpected end of input")
                }
                if next != 34 {
                    try fail("expected key")
                }
                let key=try string()
                if object.contains(where: {
                    $0.0==key
                }) {
                    try fail("duplicate key "+quote(key,34),start)
                }
                skip()
                guard let next=current() else {
                    try fail("unexpected end of input")
                }
                if next != 58 {
                    try fail("expected ':'")
                }
                at += 1
                object.append((key,try value()))
                skip()
                guard let next=current() else {
                    try fail("unexpected end of input")
                }
                if next==125 {
                    at += 1
                    break
                }
                if next != 44 {
                    try fail("expected ',' or '}'")
                }
                at += 1
                skip()
                if current()==125 {
                    try fail("trailing comma")
                }
            }
            return .object(object)
        }
        if c==91 {
            at += 1
            skip()
            var array:[Value]=[]
            if current()==93 {
                at += 1
                return .array(array)
            }
            while true {
                array.append(try value())
                skip()
                guard let next=current() else {
                    try fail("unexpected end of input")
                }
                if next==93 {
                    at += 1
                    break
                }
                if next != 44 {
                    try fail("expected ',' or ']'")
                }
                at += 1
                skip()
                if current()==93 {
                    try fail("trailing comma")
                }
            }
            return .array(array)
        }
        if c==45 || (48...57).contains(c) {
            let start=at
            if c==45 {
                at += 1
            }
            let digits=at
            while let x=current(), (48...57).contains(x) {
                at += 1
            }
            if at==digits {
                try fail("invalid number",start)
            }
            if at-digits>=2 && text[digits]==48 {
                try fail("leading zero",digits)
            }
            if current()==46 {
                try fail("fraction not allowed")
            }
            if current()==101 || current()==69 {
                try fail("exponent not allowed")
            }
            if at-digits>=10 {
                try fail("number out of range",start)
            }
            return .number(Int64(ascii(Array(text[start..<at])))!)
        }
        if letter(c) {
            let start=at
            while let x=current(), letter(x) {
                at += 1
            }
            let word=ascii(Array(text[start..<at]))
            switch word {
                case "true": return .boolean(true)
                case "false": return .boolean(false)
                case "null": return .null
                default: try fail("invalid literal '\(word)'",start)
            }
        }
        try fail("unexpected character '"+String(UnicodeScalar(c))+"'")
    }
    func parse() throws -> Value {
        let v=try value()
        skip()
        if at != text.count {
            try fail("trailing characters")
        }
        return v
    }
}
func letter(_ c:UInt8) -> Bool {
    (65...90).contains(c) || (97...122).contains(c)
}
func hex(_ c:UInt8) -> Int? {
    switch c {
        case 48...57: return Int(c-48)
        case 65...70: return Int(c-65+10)
        case 97...102: return Int(c-97+10)
        default: return nil
    }
}
enum Selector {
    case key(String), index(Int64), all, slice(Int64?,Int64?)
}
struct Segment {
    let descendant:Bool, selector:Selector
}
final class PathParser {
    let text:[UInt8]
    var at=0
    init(_ s:String) {
        text=Array(s.utf8)
    }
    func current() -> UInt8? {
        at<text.count ? text[at] : nil
    }
    func quoted() -> String? {
        guard current()==39 else {
            return nil
        }
        at += 1
        var out:[UInt8]=[]
        while let c=current() {
            at += 1
            if c==39 {
                return ascii(out)
            }
            if c != 92 {
                out.append(c)
                continue
            }
            guard let e=current() else {
                return nil
            }
            at += 1
            if e==117 {
                guard at+4<=text.count, text[at..<(at+4)].allSatisfy({
                    hex($0) != nil
                }) else {
                    return nil
                }
                let n=Int(ascii(Array(text[at..<(at+4)])),radix:16)!
                if n>127 {
                    return nil
                }
                out.append(UInt8(n))
                at += 4
            } else {
                switch e {
                    case 39,92,47: out.append(e)
                    case 98: out.append(8)
                    case 102: out.append(12)
                    case 110: out.append(10)
                    case 114: out.append(13)
                    case 116: out.append(9)
                    default: return nil
                }
            }
        }
        return nil
    }
    func parse(_ field:Bool) -> [Segment]? {
        guard text.first==(field ? 64 : 36) else {
            return nil
        }
        at=1
        var segments:[Segment]=[]
        while at<text.count {
            var descendant=false
            if current()==46 {
                at += 1
                if current()==46 {
                    if field {
                        return nil
                    }
                    descendant=true
                    at += 1
                } else if current()==91 {
                    return nil
                }
            }
            else if current() != 91 {
                return nil
            }
            let selector:Selector
            if current()==91 {
                at += 1
                if current()==39 {
                    guard let key=quoted(), current()==93 else {
                        return nil
                    }
                    at += 1
                    selector = .key(key)
                }
                else {
                    guard let end=(at..<text.count).first(where: {
                        text[$0]==93
                    }) else {
                        return nil
                    }
                    let item=ascii(Array(text[at..<end]))
                    at=end+1
                    if item=="*" && !field {
                        selector = .all
                    }
                    else if item.contains(":") {
                        let pair=item.components(separatedBy:":")
                        guard !field && pair.count==2 else {
                            return nil
                        }
                        let a=pair[0].isEmpty ? nil : integer(pair[0]), b=pair[1].isEmpty ? nil : integer(pair[1])
                        guard (pair[0].isEmpty || a != nil) && (pair[1].isEmpty || b != nil) else {
                            return nil
                        }
                        selector = .slice(a,b)
                    } else {
                        guard let n=integer(item) else {
                            return nil
                        }
                        selector = .index(n)
                    }
                }
            } else if current()==42 && !field {
                at += 1
                selector = .all
            }
            else {
                let start=at
                while let c=current(), letter(c) || (48...57).contains(c) || c==95 {
                    at += 1
                }
                let key=ascii(Array(text[start..<at]))
                guard identifier(key) else {
                    return nil
                }
                selector = .key(key)
            }
            segments.append(Segment(descendant:descendant,selector:selector))
        }
        return segments
    }
}
// Child positions preserve document order even when object keys are renamed.
typealias Location = [Int]
func valueAt(_ root:Value,_ location:Location) -> Value {
    location.reduce(root) {
        child($0,$1)
    }
}
func update(_ root:Value,_ location:Location,_ change:(Value)throws->Value) rethrows -> Value {
    if location.isEmpty {
        return try change(root)
    }
    let i=location[0], next=try update(child(root,i),Array(location.dropFirst()),change)
    switch root {
        case .object(var o): o[i].1=next
        return .object(o)
        case .array(var a): a[i]=next
        return .array(a)
        default: fatalError("not a container")
    }
}
func notation(_ root:Value,_ location:Location) -> String {
    var text="$", value=root
    for i in location {
        if case .object(let o)=value {
            let key=o[i].0
            text += identifier(key) ? "."+key : "["+quote(key,39)+"]"
        }
        else {
            text += "[\(i)]"
        }
        value=child(value,i)
    }
    return text
}
func preorder(_ root:Value,_ location:Location,_ out:inout [Location]) {
    out.append(location)
    for i in 0..<children(valueAt(root,location)) {
        preorder(root,location+[i],&out)
    }
}
func selection(_ value:Value,_ selector:Selector) -> [Int] {
    switch (value,selector) {
        case (.object(let o),.key(let key)): return o.firstIndex {
            $0.0==key
        }.map {
            [$0]
        } ?? []
        case (.object,.all),(.array,.all): return Array(0..<children(value))
        case (.array(let a),.index(let i)): let j=i<0 ? Int64(a.count)+i : i
        return j>=0 && j<Int64(a.count) ? [Int(j)] : []
        case (.array(let a),.slice(let start,let end)):
        let n=Int64(a.count)
        func bound(_ x:Int64) -> Int {
            Int(max(0,min(n,x<0 ? x+n : x)))
        }
        let first=bound(start ?? 0), last=bound(end ?? n)
        return first<last ? Array(first..<last) : []
        default: return []
    }
}
func apply(_ root:Value,_ matches:[Location],_ segment:Segment) -> [Location] {
    var out:[Location]=[]
    for location in matches {
        var parents:[Location]=[]
        if segment.descendant {
            preorder(root,location,&parents)
        } else {
            parents=[location]
        }
        for parent in parents {
            for i in selection(valueAt(root,parent),segment.selector) {
                out.append(parent+[i])
            }
        }
    }
    return out
}
func evaluate(_ root:Value,_ path:[Segment]) -> [Location] {
    path.reduce([[]]) {
        apply(root,$0,$1)
    }
}
func fieldValue(_ root:Value,_ field:[Segment]) -> Value? {
    var value=root
    for segment in field {
        guard let i=selection(value,segment.selector).first else {
            return nil
        }
        value=child(value,i)
    }
    return value
}
func sortOrder(_ a:Value?,_ b:Value?) -> Int {
    func rank(_ v:Value?) -> Int {
        switch v {
            case .some(.null): return 0
            case .some(.number): return 1
            case .some(.string): return 2
            default: return 3
        }
    }
    if rank(a) != rank(b) {
        return rank(a)<rank(b) ? -1 : 1
    }
    switch (a,b) {
        case (.some(.number(let a)),.some(.number(let b))): return a==b ? 0 : (a<b ? -1 : 1)
        case (.some(.string(let a)),.some(.string(let b))): return a==b ? 0 : (a<b ? -1 : 1)
        default: return 0
    }
}
func merge(_ target:Value,_ source:Value) -> Value {
    guard case .object(var t)=target, case .object(let m)=source else {
        fatalError("merge objects")
    }
    for (key,value) in m {
        if let i=t.firstIndex(where: {
            $0.0==key
        }) {
            if case .object=t[i].1, case .object=value {
                t[i].1=merge(t[i].1,value)
            } else {
                t[i].1=value
            }
        }
        else {
            t.append((key,value))
        }
    }
    return .object(t)
}
final class Tool {
    var root=Value.null, history:[Value]=[]
    func load(_ text:String) {
        do {
            let value=try JsonParser(text).parse(), (nodes,depth)=sizeDepth(value)
            history.append(root)
            root=value
            print("LOADED nodes=\(nodes) depth=\(depth)")
        }
        catch let p as ParseProblem {
            let prefix=Array(text.utf8).prefix(p.position), line=prefix.filter {
                $0==10
            }.count+1, col=prefix.reversed().prefix {
                $0 != 10
            }.count+1
            print("PARSE ERROR line \(line) col \(col): \(p.reason)")
        }
        catch {
            fatalError("unexpected error")
        }
    }
    func command(_ line:String) throws -> [String] {
        let split=line.split(separator:" ",maxSplits:1,omittingEmptySubsequences:false), command=String(split[0]), arg=split.count==2 ? String(split[1]) : nil
        let known=["GET","COMPACT","PRETTY","TYPE","LENGTH","KEYS","FLATTEN","COUNT","SUM","MIN","MAX","AVG","FILTER","SET","DELETE","INSERT","MERGE","SORT","RENAME","UNDO"]
        guard known.contains(command) else {
            throw Problem(text:"ERROR unknown command '\(command)'")
        }
        let limit=command=="SET" || command=="MERGE" ? 1 : (command=="INSERT" ? 2 : (command=="FILTER" ? 3 : Int.max))
        let words=arg.map {
            $0.split(separator:" ",maxSplits:limit,omittingEmptySubsequences:false).map(String.init)
        } ?? []
        let shape:Bool
        switch command {
            case "UNDO": shape=words.isEmpty
            case "COMPACT","PRETTY","FLATTEN": shape=words.count<=1
            case "SET","MERGE","RENAME": shape=words.count==2
            case "INSERT": shape=words.count==3
            case "FILTER": shape=words.count>=3 && (words[2]=="EXISTS" ? words.count==3 : words.count==4)
            case "SORT": shape=(1...3).contains(words.count) && (words.count<3 || (words[1] != "DESC" && words[2]=="DESC"))
            default: shape=words.count==1
        }
        guard shape else {
            throw Problem(text:"ERROR bad arguments")
        }
        if command=="UNDO" {
            guard let value=history.popLast() else {
                throw Problem(text:"ERROR nothing to undo")
            }
            root=value
            return ["UNDO \(history.count)"]
        }
        guard let path=PathParser(words.first ?? "$").parse(false) else {
            throw Problem(text:"ERROR bad path")
        }
        var field:[Segment]=[], index:Int64=0, rename="", supplied:Value?=nil
        if command=="FILTER" || command=="SORT" {
            let f=command=="FILTER" ? words[1] : (words.count>1 && words[1] != "DESC" ? words[1] : "@")
            guard let parsed=PathParser(f).parse(true) else {
                throw Problem(text:"ERROR bad field")
            }
            field=parsed
        }
        if command=="FILTER" && !["==","!=","<","<=",">",">=","EXISTS"].contains(words[2]) {
            throw Problem(text:"ERROR bad operator")
        }
        if command=="INSERT" {
            guard let n=integer(words[1]) else {
                throw Problem(text:"ERROR bad index")
            }
            index=n
        }
        if command=="RENAME" {
            if identifier(words[1]) {
                rename=words[1]
            }
            else {
                let parser=PathParser(words[1])
                guard let key=parser.quoted(), parser.at==parser.text.count else {
                    throw Problem(text:"ERROR bad key")
                }
                rename=key
            }
        }
        let json:String?
        switch command {
            case "SET","MERGE": json=words[1]
            case "INSERT": json=words[2]
            case "FILTER" where words[2] != "EXISTS": json=words[3]
            default: json=nil
        }
        if let json {
            do {
                supplied=try JsonParser(json).parse()
            } catch let p as ParseProblem {
                throw Problem(text:"PARSE ERROR col \(p.position+1): \(p.reason)")
            }
        }
        if command == "MERGE" {
            guard case .some(.object) = supplied else {
                throw Problem(text: "ERROR merge value is not an object")
            }
        }
        let matches=evaluate(root,path), required=["FILTER":"array","INSERT":"array","SORT":"array","MERGE":"object","KEYS":"object"][command]
        for location in matches {
            let value=valueAt(root,location), loc=notation(root,location)
            if let required, kind(value) != required {
                throw Problem(text:"ERROR not an \(required) at \(loc)")
            }
            if command=="LENGTH" && length(value)==nil {
                throw Problem(text:"ERROR no length at \(loc)")
            }
            if command=="RENAME" {
                if location.isEmpty {
                    throw Problem(text:"ERROR not a member at \(loc)")
                }
                if case .object=valueAt(root,Array(location.dropLast())) {
                } else {
                    throw Problem(text:"ERROR not a member at \(loc)")
                }
            }
        }
        if command=="INSERT" {
            for location in matches {
                let n=Int64(children(valueAt(root,location)))
                if index < -n-1 || index>n {
                    throw Problem(text:"ERROR index out of range at "+notation(root,location))
                }
            }
        }
        if command=="COUNT" {
            return ["COUNT \(matches.count)"]
        }
        if ["SUM","MIN","MAX","AVG"].contains(command) {
            let nums:[Int64]=matches.compactMap {
                if case .number(let n)=valueAt(root,$0) {
                    return n
                }
                return nil
            }, sum=nums.reduce(0,+), result:String
            switch command {
                case "SUM": result=String(sum)
                case "MIN": result=nums.min().map(String.init) ?? "null"
                case "MAX": result=nums.max().map(String.init) ?? "null"
                default: if nums.isEmpty {
                    result="null"
                } else {
                    let n=Int64(nums.count), q=(abs(sum)*200+n)/(2*n)
                    result=(sum<0 && q>0 ? "-" : "")+String(q/100)+String(format:".%02d",Int(q%100))
                }
            }
            return [command+" "+result]
        }
        if ["GET","COMPACT","PRETTY","TYPE","LENGTH","KEYS","FLATTEN","FILTER"].contains(command) {
            var output:[String]=[]
            for location in matches {
                let value=valueAt(root,location), loc=notation(root,location)
                switch command {
                    case "GET": output.append(loc+" = "+compact(value))
                    case "COMPACT": output.append(compact(value))
                    case "PRETTY": output.append(pretty(value))
                    case "TYPE": output.append(loc+" "+kind(value))
                    case "LENGTH": output.append(loc+" "+String(length(value)!))
                    case "KEYS": if case .object(let o)=value {
                        output.append(loc+" "+compact(.array(o.map {
                            .string($0.0)
                        })))
                    }
                    case "FLATTEN": var leaves:[Location]=[]
                    preorder(root,location,&leaves)
                    for leaf in leaves where children(valueAt(root,leaf))==0 {
                        output.append(notation(root,leaf)+" = "+compact(valueAt(root,leaf)))
                    }
                    default:
                    for i in 0..<children(value) {
                        let element=child(value,i), f=fieldValue(element,field), eq=f.flatMap {
                            a in supplied.map {
                                equal(a,$0)
                            }
                        } ?? false
                        var cmp:Int?=nil
                        switch (f,supplied) {
                            case (.some(.number(let a)),.some(.number(let b))): cmp=a==b ? 0 : (a<b ? -1 : 1)
                            case (.some(.string(let a)),.some(.string(let b))): cmp=a==b ? 0 : (a<b ? -1 : 1)
                            default: break
                        }
                        let good:Bool
                        switch words[2] {
                            case "EXISTS": good=f != nil
                            case "==": good=eq
                            case "!=": good = !eq
                            case "<": good=cmp.map {
                                $0<0
                            } ?? false
                            case "<=": good=cmp.map {
                                $0<=0
                            } ?? false
                            case ">": good=cmp.map {
                                $0>0
                            } ?? false
                            default: good=cmp.map {
                                $0>=0
                            } ?? false
                        }
                        if good {
                            output.append(notation(root,location+[i])+" = "+compact(element))
                        }
                    }
                }
            }
            return output.isEmpty ? ["no match"] : output
        }
        if command=="DELETE" && path.isEmpty {
            throw Problem(text:"ERROR cannot delete root")
        }
        var newKey:String?=nil
        if command=="SET", let last=path.last, !last.descendant, case .key(let key)=last.selector {
            newKey=key
        }
        var targets=matches
        if command=="SET", let key=newKey {
            targets=[]
            for parent in evaluate(root,Array(path.dropLast())) {
                if case .object(let o)=valueAt(root,parent) {
                    targets.append(parent+[o.firstIndex {
                        $0.0==key
                    } ?? o.count])
                }
            }
        }
        let unique=Array(Set(targets)).sorted {
            $1.lexicographicallyPrecedes($0)
        }
        var changed=root
        for location in unique {
            if ["SET","DELETE","RENAME"].contains(command), let i=location.last {
                changed=try update(changed,Array(location.dropLast())) {
                    parent in
                    switch parent {
                        case .object(var o):
                        if command=="SET" {
                            if i==o.count {
                                o.append((newKey!,supplied!))
                            } else {
                                o[i].1=supplied!
                            }
                        }
                        else if command=="DELETE" {
                            o.remove(at:i)
                        }
                        else {
                            if o[i].0 != rename && o.contains(where: {
                                $0.0==rename
                            }) {
                                throw Problem(text:"ERROR key exists at "+notation(root,location))
                            }
                            o[i].0=rename
                        }
                        return .object(o)
                        case .array(var a): if command=="SET" {
                            a[i]=supplied!
                        } else {
                            a.remove(at:i)
                        }
                        return .array(a)
                        default: fatalError("not a container")
                    }
                }
            } else {
                changed=update(changed,location) {
                    target in
                    switch command {
                        case "SET": return supplied!
                        case "MERGE": return merge(target,supplied!)
                        case "INSERT": guard case .array(var a)=target else {
                            fatalError("array")
                        }
                        let j=index<0 ? Int64(a.count)+1+index : index
                        a.insert(supplied!,at:Int(j))
                        return .array(a)
                        default:
                        guard case .array(let a)=target else {
                            fatalError("array")
                        }
                        let desc=words.last=="DESC"
                        return .array(a.enumerated().sorted {
                            let order=sortOrder(fieldValue($0.element,field),fieldValue($1.element,field))
                            return order==0 ? $0.offset<$1.offset : (desc ? order>0 : order<0)
                        }.map {
                            $0.element
                        })
                    }
                }
            }
        }
        history.append(root)
        root=changed
        return [command+" "+String(unique.count)]
    }
}
var lines:[String]=[]
while let line=readLine() {
    lines.append(line)
}
var at=0
let tool=Tool()
while true {
    let start=at
    while lines[at] != "%%" {
        at += 1
    }
    tool.load(lines[start..<at].joined(separator:"\n"))
    at += 1
    while lines[at] != "LOAD" && lines[at] != "END" {
        do {
            for line in try tool.command(lines[at]) {
                print(line)
            }
        }
        catch let p as Problem {
            print(p.text)
        }
        catch {
            fatalError("unexpected error")
        }
        at += 1
    }
    if lines[at]=="END" {
        break
    }
    at += 1
}
