import Foundation
let types=["A","NS","CNAME","SOA","PTR","MX","TXT","AAAA"]
let kinds=["ANSWER","CNAME","REFERRAL","NODATA","NXDOMAIN","LAME","TIMEOUT"]
struct Problem: Error {
    let reason:String
}
func integer(_ s:String) -> Int? {
    s.range(of:"^(?:0|[1-9][0-9]{0,8})$",options:.regularExpression) != nil ? Int(s) : nil
}
func ip(_ s:String) -> Int? {
    let fields=s.components(separatedBy:".")
    guard fields.count==4 else {
        return nil
    }
    var a=0
    for p in fields {
        guard p.count<=3, let n=integer(p), n<=255 else {
            return nil
        }
        a=a*256+n
    }
    return a
}
func address(_ a:Int) -> String {
    "\(a>>24).\((a>>16)&255).\((a>>8)&255).\(a&255)"
}
func ipv6(_ s:String) -> [Int]? {
    func groups(_ s:String) -> [Int]? {
        if s.isEmpty {
            return []
        }
        let parts=s.components(separatedBy:":")
        guard parts.allSatisfy({
            $0.range(of:"^[0-9A-Fa-f]{1,4}$",options:.regularExpression) != nil
        }) else {
            return nil
        }
        return parts.map {
            Int($0,radix:16)!
        }
    }
    let parts=s.components(separatedBy:"::")
    if parts.count==1 {
        guard let a=groups(s), a.count==8 else {
            return nil
        }
        return a
    }
    guard parts.count==2, let left=groups(parts[0]), let right=groups(parts[1]), left.count+right.count<=7 else {
        return nil
    }
    return left+Array(repeating:0,count:8-left.count-right.count)+right
}
func address6(_ a:[Int]) -> String {
    var best=0, size=0, at=0
    while at<8 {
        if a[at] != 0 {
            at += 1
            continue
        }
        let start=at
        while at<8 && a[at]==0 {
            at += 1
        }
        if at-start>=2 && at-start>size {
            best=start
            size=at-start
        }
    }
    func text(_ a:[Int]) -> String {
        a.map {
            String($0,radix:16)
        }.joined(separator:":")
    }
    return size==0 ? text(a) : text(Array(a[..<best]))+"::"+text(Array(a[(best+size)...]))
}
func name(_ word:String,_ wild:Bool,_ origin:String?=nil) throws -> String {
    if word=="@", let origin {
        return origin
    }
    if word=="." {
        return "."
    }
    let parts=(word.hasSuffix(".") ? String(word.dropLast()) : word).components(separatedBy:".")
    for (i,p) in parts.enumerated() {
        if wild && i==0 && p=="*" {
            continue
        }
        guard (1...63).contains(p.count), !p.hasPrefix("-"), !p.hasSuffix("-"), p.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0==45
        }) else {
            throw Problem(reason:"bad name \(word)")
        }
    }
    let suffix = !word.hasSuffix(".") && origin != nil && origin != "." ? origin! : ""
    return parts.joined(separator:".").lowercased()+"."+suffix
}
func labels(_ s:String) -> [String] {
    s=="." ? [] : String(s.dropLast()).components(separatedBy:".")
}
func nameOrder(_ a:String,_ b:String) -> Int {
    let x=Array(labels(a).reversed()), y=Array(labels(b).reversed())
    for i in 0..<min(x.count,y.count) {
        if x[i] != y[i] {
            return x[i]<y[i] ? -1 : 1
        }
    }
    return x.count==y.count ? 0 : (x.count<y.count ? -1 : 1)
}
func below(_ a:String,_ b:String) -> Bool {
    b=="." || a==b || a.hasSuffix("."+b)
}
func ancestors(_ s:String) -> [String] {
    let p=labels(s)
    return p.indices.map {
        p[$0...].joined(separator:".")+"."
    }+["."]
}
func checkedIP(_ s:String) throws -> Int {
    guard let a=ip(s) else {
        throw Problem(reason:"bad address \(s)")
    }
    return a
}
func checkedType(_ s:String) throws {
    if !types.contains(s) {
        throw Problem(reason:"bad type \(s)")
    }
}
func ttl(_ s:String) throws -> Int {
    var seconds=integer(s)
    if seconds==nil {
        let b=Array(s.utf8), units=Array("wdhms".utf8), factors=[604800,86400,3600,60,1]
        var at=0, previous = -1, total=0, valid=true
        while at<b.count {
            let start=at
            while at<b.count && (48...57).contains(b[at]) {
                at += 1
            }
            guard at<b.count, at-start<=3, let n=integer(String(decoding:b[start..<at],as:UTF8.self)), let unit=units.firstIndex(of:b[at]>=65 && b[at]<=90 ? b[at]+32 : b[at]), unit>previous else {
                valid=false
                break
            }
            total += n*factors[unit]
            previous=unit
            at += 1
        }
        if valid && previous>=0 {
            seconds=total
        }
    }
    guard let seconds, (1...604800).contains(seconds) else {
        throw Problem(reason:"bad ttl \(s)")
    }
    return seconds
}
enum Data: Equatable {
    case a(Int), aaaa([Int]), target(String), mx(Int,String), txt(String), soa(String,String,[Int])
    var text:String {
        switch self {
            case .a(let a): return address(a)
            case .aaaa(let a): return address6(a)
            case .target(let n): return n
            case .mx(let p,let n): return "\(p) \(n)"
            case .txt(let s): return s
            case .soa(let a,let b,let n): return a+" "+b+" "+n.map(String.init).joined(separator:" ")
        }
    }
}
func dataOrder(_ a:Data,_ b:Data) -> Int {
    switch (a,b) {
        case (.a(let a),.a(let b)): return a==b ? 0 : (a<b ? -1 : 1)
        case (.aaaa(let a),.aaaa(let b)): return a==b ? 0 : (a.lexicographicallyPrecedes(b) ? -1 : 1)
        case (.target(let a),.target(let b)): return nameOrder(a,b)
        case (.mx(let a,let x),.mx(let b,let y)): return a==b ? nameOrder(x,y) : (a<b ? -1 : 1)
        case (.txt(let a),.txt(let b)): return a==b ? 0 : (a<b ? -1 : 1)
        default: return 0
    }
}
struct Record {
    var owner:String, ttl:Int, type:String, data:Data
    var text:String {
        "\(owner) \(ttl) \(type) \(data.text)"
    }
}
func recordBefore(_ a:Record,_ b:Record) -> Bool {
    let order=nameOrder(a.owner,b.owner)
    if order != 0 {
        return order<0
    }
    let x=types.firstIndex(of:a.type)!, y=types.firstIndex(of:b.type)!
    return x==y ? dataOrder(a.data,b.data)<0 : x<y
}
final class Zone {
    let origin:String, server:Int, line:Int
    var records:[Record]=[]
    init(_ origin:String,_ server:Int,_ line:Int) {
        self.origin=origin
        self.server=server
        self.line=line
    }
}
struct Response {
    var kind:Int, answer:[Record]=[], authority:[Record]=[], additional:[Record]=[], cut=""
    var text:String {
        kind==1 ? "CNAME "+answer[0].data.text : (kind==2 ? "REFERRAL "+cut : kinds[kind])
    }
}
struct CacheKey: Hashable {
    let name:String, type:String
    init(_ name:String,_ type:String) {
        self.name=name
        self.type=type
    }
}
struct Cache {
    let kind:Int, records:[Record], expiry:Int
}
struct Resolution {
    let status:String, answer:[Record]
}
final class Resolver {
    var roots:[Int]=[], zones:[Zone]=[], current:Int?=nil, down=Set<Int>(), cache:[CacheKey:Cache]=[:], settings=[1,86400,3600], clock=0, queries:[Int:[Int]]=[:], hits=0, resolutions=[0,0,0,0], out:[String]=[]
    func zoneLine(_ w:[String],_ line:Int) throws {
        if w[0]=="ROOT" {
            var added:[Int]=[]
            for word in w.dropFirst() {
                let a=try checkedIP(word)
                if roots.contains(a) || added.contains(a) {
                    throw Problem(reason:"duplicate root \(word)")
                }
                added.append(a)
            }
            roots += added
            return
        }
        if w[0]=="ZONE" {
            current=nil
            let origin=try name(w[1],false), server=try checkedIP(w[2])
            if zones.contains(where: {
                $0.origin==origin && $0.server==server
            }) {
                throw Problem(reason:"duplicate zone \(origin) at \(w[2])")
            }
            current=zones.count
            zones.append(Zone(origin,server,line))
            return
        }
        guard let i=current else {
            throw Problem(reason:"no current zone")
        }
        let z=zones[i], owner=try name(w[0],true,z.origin)
        if !below(owner,z.origin) {
            throw Problem(reason:"out of zone \(owner)")
        }
        let seconds=try ttl(w[1]), type=w[2]
        try checkedType(type)
        let fields=Array(w.dropFirst(3)), count=type=="MX" ? 2 : (type=="SOA" ? 7 : (type=="TXT" ? fields.count : 1))
        guard fields.count==count else {
            throw Problem(reason:"wrong field count")
        }
        let data:Data
        switch type {
            case "A": data = .a(try checkedIP(fields[0]))
            case "AAAA": guard let a=ipv6(fields[0]) else {
                throw Problem(reason:"bad address \(fields[0])")
            }
            data = .aaaa(a)
            case "NS","CNAME","PTR": data = .target(try name(fields[0],false,z.origin))
            case "MX": guard let p=integer(fields[0]), p<=65535 else {
                throw Problem(reason:"bad preference \(fields[0])")
            }
            data = .mx(p,try name(fields[1],false,z.origin))
            case "TXT":
            let text=fields.joined(separator:" ")
            guard text.count>=2, text.hasPrefix("\""), text.hasSuffix("\""), !text.dropFirst().dropLast().contains("\"") else {
                throw Problem(reason:"bad text \(text)")
            }
            data = .txt(text)
            default:
            let a=try name(fields[0],false,z.origin), b=try name(fields[1],false,z.origin)
            var nums:[Int]=[]
            for j in 2...5 {
                guard let n=integer(fields[j]) else {
                    throw Problem(reason:"bad number \(fields[j])")
                }
                nums.append(n)
            }
            guard let minimum=integer(fields[6]), (1...86400).contains(minimum) else {
                throw Problem(reason:"bad minimum \(fields[6])")
            }
            nums.append(minimum)
            data = .soa(a,b,nums)
        }
        if type=="NS" && owner.hasPrefix("*.") {
            throw Problem(reason:"ns at wildcard")
        }
        if type=="SOA" && owner != z.origin {
            throw Problem(reason:"soa not at origin")
        }
        if type=="SOA" && z.records.contains(where: {
            $0.type=="SOA"
        }) {
            throw Problem(reason:"duplicate soa")
        }
        if z.records.contains(where: {
            $0.owner==owner && $0.type==type && $0.data==data
        }) {
            throw Problem(reason:"duplicate record")
        }
        if z.records.contains(where: {
            $0.owner==owner && (type=="CNAME" || $0.type=="CNAME")
        }) {
            throw Problem(reason:"cname conflict \(owner)")
        }
        z.records.append(Record(owner:owner,ttl:seconds,type:type,data:data))
    }
    func finishZones() {
        var kept:[Zone]=[]
        for z in zones {
            if z.records.contains(where: {
                $0.type=="SOA"
            }) {
                out.append("zone \(z.origin) at \(address(z.server)) records=\(z.records.count)")
                kept.append(z)
            }
            else {
                out.append("error line \(z.line): zone \(z.origin) at \(address(z.server)) has no soa")
            }
        }
        zones=kept
        out.append("loaded roots=\(roots.count) zones=\(zones.count) records=\(zones.reduce(0) { $0+$1.records.count })")
    }
    func records(_ z:Zone,_ n:String,_ t:String) -> [Record] {
        z.records.filter {
            $0.owner==n && $0.type==t
        }.sorted {
            dataOrder($0.data,$1.data)<0
        }
    }
    func authoritative(_ server:Int,_ n:String,_ t:String,_ cut:String) -> Response {
        if down.contains(server) || !zones.contains(where: {
            $0.server==server
        }) {
            return Response(kind:6)
        }
        guard let z=zones.filter({
            $0.server==server && below(n,$0.origin)
        }).max(by: {
            labels($0.origin).count<labels($1.origin).count
        }), labels(z.origin).count>=labels(cut).count else {
            return Response(kind:5)
        }
        for d in ancestors(n).reversed() where d != z.origin && below(d,z.origin) {
            let ns=records(z,d,"NS")
            if !ns.isEmpty {
                return Response(kind:2,authority:ns,additional:ns.flatMap {
                    records(z,$0.data.text,"A")
                },cut:d)
            }
        }
        func exists(_ x:String) -> Bool {
            z.records.contains {
                below($0.owner,x)
            }
        }
        let soa=records(z,z.origin,"SOA")
        var owner=n
        if !z.records.contains(where: {
            $0.owner==n
        }) {
            if exists(n) {
                return Response(kind:3,authority:soa)
            }
            let e=ancestors(n).first {
                $0 != n && exists($0)
            }!
            owner=e=="." ? "*." : "*."+e
            if !z.records.contains(where: {
                $0.owner==owner
            }) {
                return Response(kind:4,authority:soa)
            }
        }
        var answer=records(z,owner,t), kind=0
        if answer.isEmpty && t != "CNAME" {
            answer=records(z,owner,"CNAME")
            kind=1
        }
        if answer.isEmpty {
            return Response(kind:3,authority:soa)
        }
        return Response(kind:kind,answer:answer.map {
            var r=$0
            r.owner=n
            return r
        })
    }
    func ask(_ a:Int,_ n:String,_ t:String,_ cut:String) -> Response {
        let r=authoritative(a,n,t,cut)
        queries[a,default:Array(repeating:0,count:7)][r.kind] += 1
        return r
    }
    func trace(_ depth:Int,_ text:String) {
        out.append(String(repeating:" ",count:2*(depth+1))+text)
    }
    @discardableResult func positive(_ records:[Record]) -> Int {
        let seconds=min(max(records.map(\.ttl).min()!,settings[0]),settings[1])
        cache[CacheKey(records[0].owner,records[0].type)]=Cache(kind:0,records:records,expiry:clock+seconds)
        return seconds
    }
    func cachedRecords(_ key:CacheKey) -> [Record]? {
        guard let e=cache[key], e.kind==0 else {
            return nil
        }
        return e.records.map {
            var r=$0
            r.ttl=e.expiry-clock
            return r
        }
    }
    func queryServers(_ n:String,_ t:String,_ cut:String,_ servers:[String]?,_ depth:Int,_ stack:inout [CacheKey]) -> Response? {
        if let servers {
            for host in servers.sorted(by: {
                nameOrder($0,$1)<0
            }) {
                let records:[Record]
                if let cached=cachedRecords(CacheKey(host,"A")) {
                    records=cached
                }
                else if stack.contains(CacheKey(host,"A")) {
                    trace(depth,"GLUELESS \(host) -> LOOP")
                    records=[]
                }
                else {
                    trace(depth,"GLUELESS \(host)")
                    let r=resolve(host,"A",depth+1,&stack)
                    records=r.status=="NOERROR" ? r.answer : []
                }
                let addresses=Set(records.compactMap {
                    if case .a(let a)=$0.data {
                        return a
                    }
                    return nil
                }).sorted()
                for a in addresses {
                    let r=ask(a,n,t,cut)
                    trace(depth,"ASK \(address(a)) \(n) \(t) -> \(r.text)")
                    if r.kind<5 {
                        return r
                    }
                }
            }
        } else {
            for a in roots {
                let r=ask(a,n,t,cut)
                trace(depth,"ASK \(address(a)) \(n) \(t) -> \(r.text)")
                if r.kind<5 {
                    return r
                }
            }
        }
        return nil
    }
    func lookup(_ n:String,_ t:String,_ depth:Int,_ stack:inout [CacheKey]) throws -> Response {
        if let e=cache[CacheKey(n,t)] {
            hits += 1
            trace(depth,"CACHE HIT \(n) \(t) -> \(e.kind==0 ? "ANSWER" : kinds[e.kind])")
            return Response(kind:e.kind,answer:e.kind==0 ? cachedRecords(CacheKey(n,t))! : [])
        }
        if cache.contains(where: {
            $0.value.kind==4 && below(n,$0.key.name)
        }) {
            hits += 1
            trace(depth,"CACHE HIT \(n) \(t) -> NXDOMAIN")
            return Response(kind:4)
        }
        if t != "CNAME", let records=cachedRecords(CacheKey(n,"CNAME")) {
            let r=Response(kind:1,answer:records)
            hits += 1
            trace(depth,"CACHE HIT \(n) \(t) -> \(r.text)")
            return r
        }
        let referral=cache.filter {
            $0.key.type=="NS" && $0.value.kind==0 && below(n,$0.key.name)
        }.max {
            labels($0.key.name).count<labels($1.key.name).count
        }
        var cut=referral?.key.name ?? ".", servers=referral?.value.records.map {
            $0.data.text
        }
        if referral != nil {
            hits += 1
            trace(depth,"CACHE HIT \(n) \(t) -> REFERRAL \(cut)")
        }
        while true {
            guard var r=queryServers(n,t,cut,servers,depth,&stack) else {
                throw Problem(reason:"SERVFAIL no server for \(cut)")
            }
            switch r.kind {
                case 2:
                positive(r.authority)
                for records in Dictionary(grouping:r.additional,by: \.owner).values {
                    positive(records)
                }
                cut=r.cut
                servers=r.authority.map {
                    $0.data.text
                }
                case 0,1:
                let seconds=positive(r.answer)
                r.answer=r.answer.map {
                    var r=$0
                    r.ttl=seconds
                    return r
                }
                return r
                case 3,4:
                let soa=r.authority[0]
                guard case .soa(_,_,let nums)=soa.data else {
                    fatalError("SOA")
                }
                let seconds=min(soa.ttl,min(nums[4],settings[2]))
                cache[CacheKey(n,t)]=Cache(kind:r.kind,records:[],expiry:clock+seconds)
                return r
                default: fatalError("unexpected response")
            }
        }
    }
    func resolve(_ n:String,_ t:String,_ depth:Int,_ stack:inout [CacheKey]) -> Resolution {
        stack.append(CacheKey(n,t))
        var chain:[Record]=[], seen:Set<String>=[n], current=n, result:Resolution
        while true {
            let r:Response
            do {
                r=try lookup(current,t,depth,&stack)
            }
            catch let p as Problem {
                result=Resolution(status:p.reason,answer:[])
                break
            }
            catch {
                fatalError("unexpected error")
            }
            if r.kind==1 {
                let target=r.answer[0].data.text
                chain += r.answer
                if seen.contains(target) {
                    result=Resolution(status:"SERVFAIL cname loop",answer:[])
                    break
                }
                if chain.count==9 {
                    result=Resolution(status:"SERVFAIL cname chain too long",answer:[])
                    break
                }
                seen.insert(target)
                current=target
            } else {
                if r.kind==0 {
                    chain += r.answer
                }
                result=Resolution(status:r.kind==0 ? "NOERROR" : kinds[r.kind],answer:chain)
                break
            }
        }
        stack.removeLast()
        let i=["NOERROR","NODATA","NXDOMAIN"].firstIndex(of:result.status) ?? 3
        resolutions[i] += 1
        return result
    }
    @discardableResult func outputResolution(_ n:String,_ t:String) -> Resolution {
        var stack:[CacheKey]=[]
        let r=resolve(n,t,0,&stack)
        for record in r.answer {
            out.append("answer "+record.text)
        }
        out.append("status "+r.status)
        return r
    }
    func hostAddresses(_ n:String) -> [String] {
        var addresses:[String]=[]
        for t in ["A","AAAA"] {
            var stack:[CacheKey]=[]
            let r=resolve(n,t,0,&stack)
            if r.status=="NOERROR" {
                addresses += r.answer.filter {
                    $0.type==t
                }.map {
                    $0.data.text
                }
            }
        }
        return addresses
    }
    func command(_ w:[String]) throws {
        switch w[0] {
            case "RESOLVE": let n=try name(w[1],true)
            try checkedType(w[2])
            out.append("resolve \(n) \(w[2])")
            outputResolution(n,w[2])
            case "REVERSE":
            let a:String, n:String
            if w[1].contains(":") {
                guard let groups=ipv6(w[1]) else {
                    throw Problem(reason:"bad address \(w[1])")
                }
                a=address6(groups)
                n=groups.map {
                    String(format:"%04x",$0)
                }.joined().reversed().map(String.init).joined(separator:".")+".ip6.arpa."
            }
            else {
                let value=try checkedIP(w[1])
                a=address(value)
                n=a.components(separatedBy:".").reversed().joined(separator:".")+".in-addr.arpa."
            }
            out.append("reverse \(a) \(n)")
            outputResolution(n,"PTR")
            case "MX":
            let n=try name(w[1],true)
            out.append("mx \(n)")
            let r=outputResolution(n,"MX")
            if r.status=="NOERROR" {
                for record in r.answer {
                    if case .mx(let p,let host)=record.data {
                        if host=="." {
                            out.append("exchange \(p) . -> null")
                        } else {
                            let addresses=hostAddresses(host)
                            out.append("exchange \(p) \(host) -> \(addresses.isEmpty ? "no address" : addresses.joined(separator:" "))")
                        }
                    }
                }
            }
            else if r.status=="NODATA" {
                let host=r.answer.last {
                    $0.type=="CNAME"
                }?.data.text ?? n, addresses=hostAddresses(host)
                out.append("implicit \(host) -> \(addresses.isEmpty ? "no address" : addresses.joined(separator:" "))")
            }
            case "QUERY":
            let a=try checkedIP(w[1]), n=try name(w[2],true)
            try checkedType(w[3])
            let r=ask(a,n,w[3],".")
            out.append("query \(address(a)) \(n) \(w[3]) -> \(r.text)")
            let sections:[(String,[Record])]
            switch r.kind {
                case 0,1: sections=[("answer",r.answer)]
                case 2: sections=[("authority",r.authority),("additional",r.additional)]
                case 3,4: sections=[("authority",r.authority)]
                default: sections=[]
            }
            for (section,records) in sections {
                for record in records {
                    out.append(section+" "+record.text)
                }
            }
            case "DUMP":
            let a=try checkedIP(w[1]), n=try name(w[2],false)
            if down.contains(a) || !zones.contains(where: {
                $0.server==a
            }) {
                out.append("dump \(address(a)) \(n) -> TIMEOUT")
            }
            else if let z=zones.first(where: {
                $0.server==a && $0.origin==n
            }) {
                out.append("dump \(address(a)) \(n) records=\(z.records.count)")
                for r in z.records.sorted(by:recordBefore) {
                    out.append("  "+r.text)
                }
            }
            else {
                out.append("dump \(address(a)) \(n) -> REFUSED")
            }
            case "UP","DOWN":
            let a=try checkedIP(w[1])
            if w[0]=="DOWN" {
                if down.contains(a) {
                    throw Problem(reason:"server \(w[1]) already down")
                }
                down.insert(a)
            }
            else if down.remove(a)==nil {
                throw Problem(reason:"server \(w[1]) not down")
            }
            out.append(w[0].lowercased()+" "+address(a))
            case "SET":
            guard let i=["MINTTL","MAXTTL","NEGTTL"].firstIndex(of:w[1]) else {
                throw Problem(reason:"bad setting \(w[1])")
            }
            guard let n=integer(w[2]), (1...604800).contains(n) else {
                throw Problem(reason:"bad value \(w[2])")
            }
            var changed=settings
            changed[i]=n
            if changed[0]>changed[1] {
                throw Problem(reason:"minttl above maxttl")
            }
            settings=changed
            out.append("set \(w[1])=\(n)")
            case "TIME":
            guard let n=integer(w[1]), (1...1000000).contains(n) else {
                throw Problem(reason:"bad time \(w[1])")
            }
            clock += n
            let old=cache.count
            cache=cache.filter {
                $0.value.expiry>clock
            }
            out.append("time now=\(clock) expired=\(old-cache.count)")
            case "CACHE","FLUSH":
            let parent: String?
            if w.count == 2 {
                parent = try name(w[1], false)
            }
            else {
                parent = nil
            }
            let keys=cache.keys.filter {
                parent==nil || below($0.name,parent!)
            }.sorted {
                a,b in let order=nameOrder(a.name,b.name)
                return order==0 ? types.firstIndex(of:a.type)!<types.firstIndex(of:b.type)! : order<0
            }
            if w[0]=="FLUSH" {
                out.append("flush removed=\(keys.count)")
                for key in keys {
                    cache.removeValue(forKey:key)
                }
            }
            else {
                out.append("cache entries=\(keys.count)")
                for key in keys {
                    let e=cache[key]!
                    if e.kind==0 {
                        for r in cachedRecords(key)! {
                            out.append("  "+r.text)
                        }
                    } else {
                        out.append("  \(key.name) \(e.expiry-clock) \(key.type) \(kinds[e.kind])")
                    }
                }
            }
            default:
            let total=queries.values.reduce(0) {
                $0+$1.reduce(0,+)
            }
            out.append("stats queries=\(total) hits=\(hits)")
            for a in queries.keys.sorted() {
                let c=queries[a]!
                out.append("  \(address(a)) sent=\(c.reduce(0,+)) answer=\(c[0]) cname=\(c[1]) referral=\(c[2]) nodata=\(c[3]) nxdomain=\(c[4]) lame=\(c[5]) timeout=\(c[6])")
            }
            let c=resolutions
            out.append("resolutions noerror=\(c[0]) nodata=\(c[1]) nxdomain=\(c[2]) servfail=\(c[3])")
        }
    }
}
let resolver=Resolver()
var zones=true, lineNumber=0
while let line=readLine() {
    lineNumber += 1
    if line=="END" {
        break
    }
    if line=="END ZONES" {
        resolver.finishZones()
        zones=false
        continue
    }
    do {
        let w=line.components(separatedBy:" ")
        if zones {
            try resolver.zoneLine(w,lineNumber)
        } else {
            try resolver.command(w)
        }
    }
    catch let p as Problem {
        resolver.out.append("error line \(lineNumber): \(p.reason)")
    }
    catch {
        fatalError("unexpected error")
    }
}
for line in resolver.out {
    print(line)
}
