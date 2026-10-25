import Foundation
let faces=Array("URFDLB".utf8), colors=Array("WRGYOB".utf8), letters=Array("URFDLBMESudfblrxyz".utf8)
let corners=["URF","UFL","ULB","UBR","DFR","DLF","DBL","DRB"]
let edges=["UR","UF","UL","UB","DR","DF","DL","DB","FR","FL","BL","BR"]
let cornerStickers=[[8,9,20],[6,18,38],[0,36,47],[2,45,11],[29,26,15],[27,44,24],[33,53,42],[35,17,51]]
let edgeStickers=[[5,10],[7,19],[3,37],[1,46],[32,16],[28,25],[30,43],[34,52],[23,12],[21,41],[50,39],[48,14]]
typealias Permutation = [Int]
typealias State = [UInt8]
struct Problem: Error {
    let text:String
}
struct Move: Hashable {
    let letter:UInt8, amount:Int
    var text:String {
        String(UnicodeScalar(letter))+(amount==2 ? "2" : (amount==3 ? "'" : ""))
    }
    var inverse:Move {
        Move(letter:letter,amount:4-amount)
    }
}
func identity() -> Permutation {
    Array(0..<54)
}
func solvedState() -> State {
    (0..<54).map {
        colors[$0/9]
    }
}
func compose(_ a:Permutation,_ b:Permutation) -> Permutation {
    a.map {
        b[$0]
    }
}
func inversePermutation(_ p:Permutation) -> Permutation {
    var out=identity()
    for i in 0..<54 {
        out[p[i]]=i
    }
    return out
}
func apply(_ state:State,_ p:Permutation) -> State {
    var out=state
    for i in 0..<54 {
        out[p[i]]=state[i]
    }
    return out
}
func inverse(_ sequence:[Move]) -> [Move] {
    sequence.reversed().map(\.inverse)
}
func notation(_ sequence:[Move]) -> String {
    sequence.isEmpty ? "0" : "\(sequence.count) "+sequence.map(\.text).joined(separator:" ")
}
func axis(_ m:UInt8) -> UInt8 {
    "RLMrlx".utf8.contains(m) ? 120 : ("UDEudy".utf8.contains(m) ? 121 : 122)
}
func solved(_ state:State) -> Bool {
    state.indices.allSatisfy {
        state[$0]==state[$0/9*9+4]
    }
}
func simplify(_ input:[Move]) -> [Move] {
    var sequence=input
    while true {
        var out:[Move]=[], at=0
        while at<sequence.count {
            let a=axis(sequence[at].letter)
            var run:[Move]=[]
            while at<sequence.count && axis(sequence[at].letter)==a {
                let m=sequence[at]
                at += 1
                if let i=run.firstIndex(where: {
                    $0.letter==m.letter
                }) {
                    run[i]=Move(letter:m.letter,amount:(run[i].amount+m.amount)%4)
                }
                else {
                    run.append(m)
                }
            }
            out += run.filter {
                $0.amount != 0
            }
        }
        if out==sequence {
            return out
        }
        sequence=out
    }
}
func number(_ s:String) -> Int? {
    guard (1...10).contains(s.count), s.utf8.allSatisfy({
        (48...57).contains($0)
    }), s.count==1 || !s.hasPrefix("0") else {
        return nil
    }
    return Int(s)
}
func name(_ s:String) -> Bool {
    (1...8).contains(s.count) && s.utf8.allSatisfy {
        (97...122).contains($0)
    }
}
func simple(_ s:String) -> [Move] {
    let b=Array(s.utf8)
    var at=0, out:[Move]=[]
    while at<b.count {
        if b[at]==32 {
            at += 1
            continue
        }
        let letter=b[at]
        at += 1
        var amount=1
        if at<b.count && b[at]==50 {
            amount=2
            at += 1
        } else if at<b.count && b[at]==39 {
            amount=3
            at += 1
        }
        out.append(Move(letter:letter,amount:amount))
    }
    return out
}
final class SequenceParser {
    let line:[UInt8], macros:[String:[Move]]
    var at:Int
    init(_ line:String,_ at:Int,_ macros:[String:[Move]]) {
        self.line=Array(line.utf8)
        self.at=at
        self.macros=macros
    }
    func current() -> UInt8? {
        at<line.count ? line[at] : nil
    }
    func skip() {
        while current()==32 {
            at += 1
        }
    }
    func syntax() throws -> Never {
        throw Problem(text:"error: syntax at \(min(at+1,line.count+1))")
    }
    func power(_ sequence:[Move]) -> [Move] {
        var count=1
        if let c=current(), (49...57).contains(c) {
            count=Int(c-48)
            at += 1
            if let c=current(), (48...57).contains(c) {
                count=count*10+Int(c-48)
                at += 1
            }
        }
        let invert=current()==39
        if invert {
            at += 1
        }
        var repeated:[Move]=[]
        for _ in 0..<count {
            repeated += sequence
        }
        return invert ? inverse(repeated) : repeated
    }
    func sequence() throws -> [Move] {
        var out:[Move]=[]
        while true {
            skip()
            guard let c=current() else {
                break
            }
            let next:[Move]
            if letters.contains(c) {
                at += 1
                var amount=1
                if current()==50 {
                    at += 1
                    amount=2
                } else if current()==39 {
                    at += 1
                    amount=3
                }
                next=[Move(letter:c,amount:amount)]
            } else if c==40 {
                at += 1
                let x=try sequence()
                skip()
                if current() != 41 {
                    try syntax()
                }
                at += 1
                next=power(x)
            } else if c==91 {
                at += 1
                let a=try sequence()
                skip()
                let separator=current()
                if separator != 44 && separator != 58 {
                    try syntax()
                }
                at += 1
                let b=try sequence()
                skip()
                if current() != 93 {
                    try syntax()
                }
                at += 1
                next=power(a+b+inverse(a)+(separator==44 ? inverse(b) : []))
            } else if c==123 {
                at += 1
                let start=at
                while let c=current(), (97...122).contains(c) {
                    at += 1
                }
                if at==start || current() != 125 {
                    try syntax()
                }
                let name=String(decoding:line[start..<at],as:UTF8.self)
                guard let x=macros[name] else {
                    throw Problem(text:"error: undefined \(name)")
                }
                at += 1
                next=power(x)
            } else {
                break
            }
            out += next
        }
        return out
    }
    func parse() throws -> [Move] {
        let x=try sequence()
        skip()
        if current() != nil {
            try syntax()
        }
        if x.count>500 {
            throw Problem(text:"error: too long")
        }
        return x
    }
}
final class Cube {
    var state=solvedState(), history:[Move]=[], redo:[Move]=[], macros:[String:[Move]]=[:], saves:[String:(State,[Move])]=[:], moves:[Move:Permutation]=[:], rotations:[([Move],Permutation)]=[]
    init() {
        func index(_ face:UInt8,_ row:Int,_ col:Int) -> Int {
            faces.firstIndex(of:face)!*9+row*3+col
        }
        var basics:[UInt8:Permutation]=[:]
        for letter in "URFDLBMES".utf8 {
            var p=identity()
            if faces.contains(letter) {
                for i in 0..<3 {
                    for j in 0..<3 {
                        p[index(letter,i,j)]=index(letter,j,2-i)
                    }
                }
            }
            func link(_ f:UInt8,_ r:Int,_ c:Int,_ g:UInt8,_ s:Int,_ d:Int) {
                p[index(f,r,c)]=index(g,s,d)
            }
            for i in 0..<3 {
                switch letter {
                    case 85: link(70,0,i,76,0,i)
                    link(76,0,i,66,0,i)
                    link(66,0,i,82,0,i)
                    link(82,0,i,70,0,i)
                    case 82: link(70,i,2,85,i,2)
                    link(85,i,2,66,2-i,0)
                    link(66,i,0,68,2-i,2)
                    link(68,i,2,70,i,2)
                    case 70: link(85,2,i,82,i,0)
                    link(82,i,0,68,0,2-i)
                    link(68,0,i,76,i,2)
                    link(76,i,2,85,2,2-i)
                    case 68: link(70,2,i,82,2,i)
                    link(82,2,i,66,2,i)
                    link(66,2,i,76,2,i)
                    link(76,2,i,70,2,i)
                    case 76: link(85,i,0,70,i,0)
                    link(70,i,0,68,i,0)
                    link(68,i,0,66,2-i,2)
                    link(66,i,2,85,2-i,0)
                    case 66: link(85,0,i,76,2-i,0)
                    link(76,i,0,68,2,i)
                    link(68,2,i,82,2-i,2)
                    link(82,i,2,85,0,i)
                    case 77: link(85,i,1,70,i,1)
                    link(70,i,1,68,i,1)
                    link(68,i,1,66,2-i,1)
                    link(66,i,1,85,2-i,1)
                    case 69: link(70,1,i,82,1,i)
                    link(82,1,i,66,1,i)
                    link(66,1,i,76,1,i)
                    link(76,1,i,70,1,i)
                    default: link(85,1,i,82,i,1)
                    link(82,i,1,68,1,2-i)
                    link(68,1,i,76,i,1)
                    link(76,i,1,85,1,2-i)
                }
            }
            basics[letter]=p
        }
        for (letter,text) in [("r","RM'"),("l","LM"),("u","UE'"),("d","DE"),("f","FS"),("b","BS'"),("x","RM'L'"),("y","UE'D'"),("z","FSB'")] {
            var p=identity()
            for m in simple(text) {
                for _ in 0..<m.amount {
                    p=compose(p,basics[m.letter]!)
                }
            }
            basics[letter.utf8.first!]=p
        }
        for letter in letters {
            var p=identity()
            for amount in 1...3 {
                p=compose(p,basics[letter]!)
                moves[Move(letter:letter,amount:amount)]=p
            }
        }
        for base in ["","x","x2","x'","z","z'"] {
            for y in ["","y","y2","y'"] {
                let sequence=simple(base+" "+y)
                rotations.append((sequence,effect(sequence)))
            }
        }
    }
    func permutation(_ m:Move) -> Permutation {
        moves[m]!
    }
    func effect(_ sequence:[Move]) -> Permutation {
        sequence.reduce(identity()) {
            compose($0,permutation($1))
        }
    }
    func applySequence(_ state:State,_ sequence:[Move]) -> State {
        apply(state,effect(sequence))
    }
    func conjugate(_ p:Permutation,_ m:Move,_ outer:Bool) -> Move {
        let result=compose(compose(p,permutation(m)),inversePermutation(p))
        return moves.first {
            (!outer || faces.contains($0.key.letter)) && $0.value==result
        }!.key
    }
    func normalized(_ state:State) -> ([Move],State)? {
        for (sequence,p) in rotations {
            let s=apply(state,p)
            if (0..<6).allSatisfy({
                s[$0*9+4]==colors[$0]
            }) {
                return (sequence,s)
            }
        }
        return nil
    }
    func pieces(_ state:State,_ positions:[[Int]]) -> [(Int,Int)?] {
        let solved=solvedState()
        return positions.map {
            position in
            for (piece,p) in positions.enumerated() {
                for t in p.indices {
                    if p.indices.allSatisfy({
                        j in state[position[(t+j)%p.count]]==solved[p[j]]
                    }) {
                        return (piece,t)
                    }
                }
            }
            return nil
        }
    }
    func check(_ w:String) -> String? {
        let b=Array(w.utf8)
        if b.count != 54 {
            return "length \(b.count)"
        }
        if let i=b.firstIndex(where: {
            !colors.contains($0)
        }) {
            return "char \(i+1)"
        }
        for c in colors {
            let count=b.filter {
                $0==c
            }.count
            if count != 9 {
                return "count \(String(UnicodeScalar(c))) \(count)"
            }
        }
        guard let (_,normal)=normalized(b) else {
            return "centers"
        }
        let cp=pieces(b,cornerStickers), ep=pieces(b,edgeStickers)
        if let i=cp.firstIndex(where: {
            $0==nil
        }) {
            return "corner "+corners[i]
        }
        if let i=ep.firstIndex(where: {
            $0==nil
        }) {
            return "edge "+edges[i]
        }
        for (names,positions) in [(corners,cp),(edges,ep)] {
            for i in names.indices where !positions.contains(where: {
                $0!.0==i
            }) {
                return "missing "+names[i]
            }
        }
        let c=pieces(normal,cornerStickers), e=pieces(normal,edgeStickers)
        if c.reduce(0,{
            $0+$1!.1
        })%3 != 0 {
            return "twist"
        }
        if e.reduce(0,{
            $0+$1!.1
        })%2 != 0 {
            return "flip"
        }
        func parity(_ p:[(Int,Int)?]) -> Int {
            var count=0
            for i in p.indices {
                for j in (i+1)..<p.count {
                    if p[i]!.0>p[j]!.0 {
                        count += 1
                    }
                }
            }
            return count%2
        }
        return parity(c) != parity(e) ? "parity" : nil
    }
    func cycles(_ positions:[(Int,Int)?],_ names:[String],_ modulus:Int) -> String {
        var destination=Array(repeating:0,count:names.count), orientation=destination, seen=Array(repeating:false,count:names.count), out:[String]=[]
        for (q,entry) in positions.enumerated() {
            let (piece,t)=entry!
            destination[piece]=q
            orientation[piece]=t
        }
        for start in names.indices {
            if seen[start] {
                continue
            }
            var cycle:[String]=[], sum=0, p=start
            while !seen[p] {
                seen[p]=true
                cycle.append(names[p])
                sum += orientation[p]
                p=destination[p]
            }
            let mark=modulus==1 || sum%modulus==0 ? "" : (modulus==3 && sum%3==2 ? "-" : "+")
            if cycle.count>=2 || !mark.isEmpty {
                out.append("("+cycle.joined(separator:" ")+")"+mark)
            }
        }
        return out.isEmpty ? "none" : out.joined(separator:" ")
    }
    func order(_ sequence:[Move]) -> Int {
        func gcd(_ a:Int,_ b:Int) -> Int {
            var a=a, b=b
            while b != 0 {
                (a,b)=(b,a%b)
            }
            return a
        }
        let p=effect(sequence)
        var seen=Array(repeating:false,count:54), result=1
        for start in 0..<54 {
            var i=start, length=0
            while !seen[i] {
                seen[i]=true
                length += 1
                i=p[i]
            }
            if length != 0 {
                result=result/gcd(result,length)*length
            }
        }
        return result
    }
    func search(_ state:State,_ left:Int,_ previous:UInt8?,_ path:inout [Move]) -> Bool {
        if left==0 {
            return solved(state)
        }
        for face in faces {
            if previous==face || (previous==68 && face==85) || (previous==76 && face==82) || (previous==66 && face==70) {
                continue
            }
            for amount in 1...3 {
                let m=Move(letter:face,amount:amount)
                path.append(m)
                if search(apply(state,permutation(m)),left-1,face,&path) {
                    return true
                }
                path.removeLast()
            }
        }
        return false
    }
    func command(_ line:String) throws -> [String] {
        let parts=line.split(separator:" ",maxSplits:1).map(String.init), command=parts[0], arg=parts.count==2 ? parts[1] : nil
        let noArgs=["RESET","SHOW","STATE","ISSOLVED","HISTORY","SOLUTION","ANALYZE","STAGE","MACROS"], word=["CHECK","LOAD","UNDO","REDO","SEARCH","WHERE","SAVE","RESTORE","SCRAMBLE"], sequences=["APPLY","INVERT","SIMPLIFY","METRICS","ORDER","CYCLES","UNROTATE","UNTIL"], heads=["DEFINE","MIRROR","ROTATE"]
        if !noArgs.contains(command) && !word.contains(command) && !sequences.contains(command) && !heads.contains(command) {
            throw Problem(text:"error: unknown command \(command)")
        }
        let words=arg?.components(separatedBy:" ") ?? [], head=words.first ?? ""
        func bad() throws -> Never {
            throw Problem(text:"error: bad arguments")
        }
        if noArgs.contains(command) && arg != nil {
            try bad()
        }
        if word.contains(command) {
            if words.count != (command=="SCRAMBLE" ? 2 : 1) {
                try bad()
            }
            if ["UNDO","REDO","SEARCH","SCRAMBLE"].contains(command) && words.contains(where: {
                number($0)==nil
            }) {
                try bad()
            }
            if ["SAVE","RESTORE"].contains(command) && !name(head) {
                try bad()
            }
        }
        if heads.contains(command) {
            if arg==nil {
                try bad()
            }
            if (command=="DEFINE" && !name(head)) || (command=="MIRROR" && !["LR","UD","FB"].contains(head)) || (command=="ROTATE" && !["x","x'","x2","y","y'","y2","z","z'","z2"].contains(head)) {
                try bad()
            }
        }
        let sequence:[Move]
        if sequences.contains(command) || heads.contains(command) {
            let start=min(line.utf8.count,command.utf8.count+(heads.contains(command) ? head.utf8.count+2 : 1))
            sequence=try SequenceParser(line,start,macros).parse()
        }
        else {
            sequence=[]
        }
        let n=["UNDO","REDO","SEARCH","SCRAMBLE"].contains(command) ? number(head)! : 0
        if (["UNDO","REDO"].contains(command) && n==0) || (command=="SEARCH" && n>4) || (command=="SCRAMBLE" && (!(1...50).contains(n) || !(1...2147483646).contains(number(words[1])!))) {
            throw Problem(text:"error: bad value")
        }
        if command=="WHERE" && !corners.contains(head) && !edges.contains(head) {
            throw Problem(text:"error: unknown piece \(head)")
        }
        let text:String
        switch command {
            case "RESET": state=solvedState()
            history.removeAll()
            redo.removeAll()
            text="reset"
            case "SHOW":
            var out:[String]=[]
            for group in [[0],[4,2,1,5],[3]] {
                for row in 0..<3 {
                    let s=group.flatMap {
                        face in (0..<3).map {
                            String(UnicodeScalar(state[face*9+row*3+$0]))
                        }
                    }.joined(separator:" ")
                    out.append((group.count==1 ? "      " : "")+s)
                }
            }
            return out
            case "STATE": text="state "+String(decoding:state,as:UTF8.self)
            case "ISSOLVED": text=solved(state) ? "solved" : "unsolved \(state.indices.filter { state[$0] != state[$0/9*9+4] }.count)"
            case "HISTORY": text="history "+notation(history)
            case "SOLUTION": text="solution "+notation(simplify(inverse(history)))
            case "MACROS": return ["macros \(macros.count)"]+macros.keys.sorted().map {
                "macro \($0) \(notation(macros[$0]!))"
            }
            case "CHECK","LOAD":
            if let reason=check(head) {
                if command=="LOAD" {
                    throw Problem(text:"error: invalid "+reason)
                }
                text="invalid "+reason
            }
            else if command=="CHECK" {
                text="valid"
            }
            else {
                state=Array(head.utf8)
                history.removeAll()
                redo.removeAll()
                text="loaded"
            }
            case "UNDO","REDO":
            let undo=command=="UNDO", count=min(n,undo ? history.count : redo.count)
            if count==0 {
                throw Problem(text:"error: nothing to "+command.lowercased())
            }
            for _ in 0..<count {
                let m=undo ? history.removeLast() : redo.removeLast()
                state=apply(state,permutation(undo ? m.inverse : m))
                if undo {
                    redo.append(m)
                } else {
                    history.append(m)
                }
            }
            text=(undo ? "undone " : "redone ")+String(count)
            case "SAVE": saves[head]=(state,history)
            text="saved "+head
            case "RESTORE": guard let save=saves[head] else {
                throw Problem(text:"error: no save "+head)
            }
            state=save.0
            history=save.1
            redo.removeAll()
            text="restored "+head
            case "APPLY": state=applySequence(state,sequence)
            history += sequence
            redo.removeAll()
            text="applied \(sequence.count)"
            case "DEFINE": macros[head]=sequence
            text="defined \(head) \(sequence.count)"
            case "INVERT": text="inverse "+notation(inverse(sequence))
            case "SIMPLIFY": text="simplified "+notation(simplify(sequence))
            case "ORDER": text="order \(order(sequence))"
            case "METRICS":
            var htm=0, qtm=0, stm=0
            for m in sequence where !"xyz".utf8.contains(m.letter) {
                let h="MES".utf8.contains(m.letter) ? 2 : 1
                htm += h
                qtm += h*(m.amount==2 ? 2 : 1)
                stm += 1
            }
            text="metrics htm \(htm) qtm \(qtm) stm \(stm) etm \(sequence.count)"
            case "ROTATE": let p=permutation(simple(head)[0])
            text="rotated "+notation(sequence.map {
                conjugate(p,$0,false)
            })
            case "MIRROR":
            let mirror:UInt8=head=="LR" ? 120 : (head=="UD" ? 121 : 122), from=Array("RLrlUDudFBfb".utf8), to=Array("LRlrDUduBFbf".utf8)
            let out=sequence.map {
                m -> Move in if axis(m.letter)==mirror {
                    if let i=from.firstIndex(of:m.letter) {
                        return Move(letter:to[i],amount:4-m.amount)
                    }
                    return m
                }
                return m.inverse
            }
            text="mirror "+notation(out)
            case "UNROTATE":
            var out:[Move]=[], rotation=identity()
            let replacements:[UInt8:String]=[77:"RL'x'",69:"UD'y'",83:"F'Bz",114:"Lx",108:"Rx'",117:"Dy",100:"Uy'",102:"Bz",98:"Fz'"]
            for m in sequence {
                let expanded:[Move]
                if let replacement=replacements[m.letter] {
                    expanded=simple(replacement).map {
                        Move(letter:$0.letter,amount:$0.amount*m.amount%4)
                    }.filter {
                        $0.amount != 0
                    }
                } else {
                    expanded=[m]
                }
                for n in expanded {
                    if "xyz".utf8.contains(n.letter) {
                        rotation=compose(rotation,permutation(n))
                    } else {
                        out.append(conjugate(rotation,n,true))
                    }
                }
            }
            out += rotations.first {
                $0.1==rotation
            }!.0
            text="unrotated "+notation(out)
            case "UNTIL":
            let p=effect(sequence)
            var current=state, found:Int?=nil
            for i in 1...order(sequence) {
                current=apply(current,p)
                if solved(current) {
                    found=i
                    break
                }
            }
            text="until "+(found.map(String.init) ?? "never")
            case "SEARCH":
            var answer:[Move]?=nil
            for depth in 0...n {
                var path:[Move]=[]
                if search(state,depth,nil,&path) {
                    answer=path
                    break
                }
            }
            text=answer.map {
                "found "+notation($0)
            } ?? "not found"
            case "SCRAMBLE":
            var x=number(words[1])!, out:[Move]=[]
            for _ in 0..<n {
                let usable=faces.filter {
                    f in out.last?.letter != f && (out.count<2 || axis(out[out.count-1].letter) != axis(out[out.count-2].letter) || axis(f) != axis(out[out.count-1].letter))
                }
                x=48271*x%2147483647
                let letter=usable[x%usable.count]
                x=48271*x%2147483647
                out.append(Move(letter:letter,amount:[1,3,2][x%3]))
            }
            state=applySequence(state,out)
            history += out
            redo.removeAll()
            text="scramble "+out.map(\.text).joined(separator:" ")
            case "ANALYZE","STAGE","WHERE":
            let (rotation,normal)=normalized(state)!, cp=pieces(normal,cornerStickers), ep=pieces(normal,edgeStickers)
            if command=="ANALYZE" {
                return ["rotation "+(rotation.isEmpty ? "none" : rotation.map(\.text).joined(separator:" ")),"corners "+cycles(cp,corners,3),"edges "+cycles(ep,edges,2)]
            }
            if command=="WHERE" {
                let corner=corners.contains(head), names=corner ? corners : edges, positions=corner ? cp : ep, piece=names.firstIndex(of:head)!, q=positions.firstIndex {
                    $0!.0==piece
                }!
                text="\(head) at \(names[q]) \(corner ? "twist" : "flip") \(positions[q]!.1)"
            } else {
                func correct(_ entry:(Int,Int)?,_ i:Int) -> Bool {
                    guard let entry else {
                        return false
                    }
                    return entry.0==i && entry.1==0
                }
                let cross=(4..<8).filter {
                    correct(ep[$0],$0)
                }.count, slots=(4..<8).filter {
                    correct(cp[$0],$0) && correct(ep[$0+4],$0+4)
                }.count, top=normal[..<9].filter {
                    $0==87
                }.count
                let stage=solved(normal) ? "solved" : (cross==4 && slots==4 && top==9 ? "oll" : (cross==4 && slots==4 ? "f2l" : (cross==4 ? "cross" : "none")))
                text="stage \(stage) cross \(cross) slots \(slots) top \(top)"
            }
            default:
            let state=applySequence(solvedState(),sequence), centers:[(Int,Int)?]=(0..<6).map {
                (colors.firstIndex(of:state[$0*9+4])!,0)
            }
            return ["corners "+cycles(pieces(state,cornerStickers),corners,3),"edges "+cycles(pieces(state,edgeStickers),edges,2),"centers "+cycles(centers,["U","R","F","D","L","B"],1)]
        }
        return [text]
    }
}
let cube=Cube()
for _ in 0..<Int(readLine()!)! {
    do {
        for line in try cube.command(readLine()!) {
            print(line)
        }
    }
    catch let p as Problem {
        print(p.text)
    }
    catch {
        fatalError("unexpected error")
    }
}
