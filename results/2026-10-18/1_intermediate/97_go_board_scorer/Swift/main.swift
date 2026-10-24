import Foundation

let columns=Array("ABCDEFGHJKLMNOPQRST")
let handicapPoints=[9:"C3 G7 C7 G3 C5 G5 E3 E7 E5",13:"D4 K10 D10 K4 D7 K7 G4 G10 G7",19:"D4 Q16 D16 Q4 D10 Q10 K4 K16 K10"].mapValues{$0.split(separator:" ").map(String.init)}
let arity=["BOARD":2,"KOMI":1,"SUPERKO":1,"HANDICAP":1,"PLAY":2,"PASS":1,"REPLAY":1,"UNDO":0,"SHOW":0,"MAP":0,"STATUS":0,"CAPTURES":0,"HISTORY":0,"MOVES":0,"GROUP":1,"GROUPS":0,"ATARI":0,"LEGAL":1,"EYES":1,"SAFE":1,"LADDER":1,"DEAD":1,"REGIONS":0,"SCORE":1]
func other(_ c:Character)->Character {c=="B" ? "W":"B"}
func half(_ x:Int)->String {(x<0 ? "-":"")+String(abs(x)/2)+(abs(x)%2==0 ? ".0":".5")}
func emit(_ a:[String]) {print(a.joined(separator:" "))}
func matches(_ s:String,_ pattern:String)->Bool {s.range(of:"\\A(?:"+pattern+")\\z",options:.regularExpression) != nil}
func komi(_ s:String)->Int? {if !matches(s,"-?(0|[1-9][0-9]*)(?:\\.[05])?") {return nil};let negative=s.hasPrefix("-"),a=(negative ? String(s.dropFirst()):s).split(separator:".");guard let whole=Int(a[0]),whole<=100 else {return nil};let x=2*whole+(a.count==2 && a[1]=="5" ? 1:0);return negative && x==0 ? nil:negative ? -x:x}
func adjacent(_ p:Int,_ n:Int,_ diagonal:Bool=false)->[Int] {let r=p/n,c=p%n;let steps=diagonal ? [(-1,-1),(-1,1),(1,-1),(1,1)]:[(-1,0),(1,0),(0,-1),(0,1)];return steps.compactMap{dr,dc in r+dr>=0 && r+dr<n && c+dc>=0 && c+dc<n ? (r+dr)*n+c+dc:nil}}
func flood(_ b:[Character],_ n:Int,_ p:Int,_ allowed:Set<Character>)->Set<Int> {var seen:Set<Int>=[p],todo=[p];while let s=todo.popLast() {for q in adjacent(s,n) {if !seen.contains(q) && allowed.contains(b[q]) {seen.insert(q);todo.append(q)}}};return seen}
struct Group {let color:Character,first:Int,stones:Set<Int>,liberties:Set<Int>}
func group(_ b:[Character],_ n:Int,_ p:Int)->Group {let stones=flood(b,n,p,[b[p]]);var liberties:Set<Int>=[];for q in stones {for t in adjacent(q,n) {if b[t]=="." {liberties.insert(t)}}};return Group(color:b[p],first:stones.min()!,stones:stones,liberties:liberties)}
func groups(_ b:[Character],_ n:Int,_ color:Character?=nil)->[Group] {var out:[Group]=[],seen:Set<Int>=[];for p in b.indices {if b[p] != "." && !seen.contains(p) && (color==nil || b[p]==color) {let g=group(b,n,p);seen.formUnion(g.stones);out.append(g)}};return out}
struct Placement {let board:[Character],captured:Int;var reason:String}
func placement(_ b:[Character],_ n:Int,_ c:Character,_ p:Int)->Placement {
    if b[p] != "." {return Placement(board:b,captured:0,reason:"occupied")};var next=b;next[p]=c;var captured=0,seen:Set<Int>=[]
    for q in adjacent(p,n) {if next[q]==other(c) && !seen.contains(q) {let g=group(next,n,q);seen.formUnion(g.stones);if g.liberties.isEmpty {for t in g.stones {next[t]="."};captured+=g.stones.count}}}
    return Placement(board:next,captured:captured,reason:group(next,n,p).liberties.isEmpty ? "suicide":"")
}
struct Region {let first:Int,points:Set<Int>,owner:String}
func regions(_ b:[Character],_ n:Int)->[Region] {var out:[Region]=[],seen:Set<Int>=[];for p in b.indices {if b[p]=="." && !seen.contains(p) {let points=flood(b,n,p,["."]);seen.formUnion(points);var border:Set<Character>=[];for q in points {for t in adjacent(q,n) {if b[t] != "." {border.insert(b[t])}}};out.append(Region(first:p,points:points,owner:border.count==1 ? String(border.first!):"neutral"))}};return out}
func safeGroups(_ b:[Character],_ n:Int,_ c:Character)->[Group] {
    let own=groups(b,n,c);var touch:[Set<Int>]=[],vital:[Set<Int>]=[],seen:Set<Int>=[]
    for p in b.indices {if b[p] != c && !seen.contains(p) {let area=flood(b,n,p,[".",other(c)]);seen.formUnion(area);let empty=Set(area.filter{b[$0]=="."});var t:Set<Int>=[],v:Set<Int>=[];for i in own.indices {if area.contains(where:{q in adjacent(q,n).contains{own[i].stones.contains($0)}}) {t.insert(i)};if empty.isSubset(of:own[i].liberties) {v.insert(i)}};touch.append(t);vital.append(v)}}
    var s=Set(own.indices),t=Set(touch.indices)
    while true {let before=s.count+t.count;s=Set(s.filter{i in t.filter{vital[$0].contains(i)}.count>=2});t=Set(t.filter{touch[$0].isSubset(of:s)});if before==s.count+t.count {break}}
    return s.sorted().map{own[$0]}
}
struct ReadKey:Hashable {let board:[Character],depth:Int,defending:Bool}
struct Reading {let success:Bool,move:Int}
func ladder(_ b:[Character],_ n:Int,_ p:Int)->(String,Int) {
    let defender=b[p],attacker=other(defender);var memo:[ReadKey:Reading]=[:]
    func read(_ current:[Character],_ depth:Int,_ defending:Bool)->Reading {
        if depth>=40 {return Reading(success:defending,move:-1)};let key=ReadKey(board:current,depth:depth,defending:defending);if let r=memo[key] {return r};let g=group(current,n,p);var candidates=g.liberties,seen:Set<Int>=[]
        if defending {for q in g.stones {for t in adjacent(q,n) {if current[t]==attacker && !seen.contains(t) {let e=group(current,n,t);seen.formUnion(e.stones);if e.liberties.count==1 {candidates.formUnion(e.liberties)}}}}}
        for q in candidates.sorted() {let next=placement(current,n,defending ? defender:attacker,q);if !next.reason.isEmpty {continue};let success:Bool;if defending {let count=group(next.board,n,p).liberties.count;success=count>=3 || (count==2 && !read(next.board,depth+1,false).success)} else {success = !read(next.board,depth+1,true).success};if success {let r=Reading(success:true,move:q);memo[key]=r;return r}}
        let r=Reading(success:false,move:-1);memo[key]=r;return r
    }
    let count=group(b,n,p).liberties.count;if count>=3 {return("safe",-1)};let r=read(b,0,count==1);return((count==1 ? r.success:!r.success) ? "escapes":"captured",r.move)
}
struct Snapshot {let board:[Character],turn:Character,black:Int,white:Int,passes:Int,over:Bool}
struct Move {let color:Character,point:Int,captured:Int,before:Snapshot}
final class Game {
    var n=19,komi2=13,board=Array(repeating:Character("."),count:361),turn:Character="B",captures:[Character:Int]=["B":0,"W":0],passes=0,over=false,superko=false
    var handicap:[Int]=[],history:[Move]=[],positions:[[Character]]=[Array(repeating:".",count:361)],dead:Set<Int>=[]
    func reset(_ size:Int,_ k:Int) {n=size;komi2=k;board=Array(repeating:".",count:n*n);turn="B";captures=["B":0,"W":0];passes=0;over=false;handicap=[];history=[];positions=[board];dead=[]}
    func point(_ s:String)->Int {if !matches(s,"[A-HJ-T](?:[1-9]|1[0-9])") {return -1};let c=columns.firstIndex(of:s.first!)!,r=Int(s.dropFirst())!;return c<n && r<=n ? (r-1)*n+c:-1}
    func name(_ p:Int)->String {String(columns[p%n])+String(p/n+1)}
    func sgf(_ p:Int)->String {String(UnicodeScalar(97+p%n)!)+String(UnicodeScalar(97+n-1-p/n)!)}
    func check(_ c:Character,_ p:Int)->Placement {var r=placement(board,n,c,p);if r.reason.isEmpty && positions.count>=2 && r.board==positions[positions.count-2] {r.reason="ko"};if r.reason.isEmpty && superko && positions.contains(r.board) {r.reason="superko"};return r}
    @discardableResult func move(_ c:Character,_ p:Int,_ checked:Placement?=nil)->Int {let before=Snapshot(board:board,turn:turn,black:captures["B"]!,white:captures["W"]!,passes:passes,over:over);var captured=0;if p<0 {passes+=1;if passes==2 {over=true}} else {let r=checked ?? check(c,p);board=r.board;captured=r.captured;captures[c,default:0]+=captured;passes=0};turn=other(c);history.append(Move(color:c,point:p,captured:captured,before:before));positions.append(board);dead=[];return captured}
    func clean()->[Character] {var b=board;for p in dead {b[p]="."};return b}
    func show(_ map:Bool=false) {let b=map ? clean():board;var chars=b;let stars=Set(handicapPoints[n]!.enumerated().filter{n==19 || $0.offset<4 || $0.offset==8}.map{point($0.element)});if map {for r in regions(b,n) {for p in r.points {chars[p]=r.owner=="B" ? "x":r.owner=="W" ? "o":"."}}};for p in b.indices {if b[p] != "." {let c:Character=b[p]=="B" ? "X":"O";chars[p] = !map && dead.contains(p) ? Character(c.lowercased()):c} else if !map {chars[p]=stars.contains(p) ? "+":"."}};let header="   "+columns.prefix(n).map(String.init).joined(separator:" ");emit([header]);for r in stride(from:n,through:1,by:-1) {emit([String(format:"%2d",r),chars[((r-1)*n)..<(r*n)].map(String.init).joined(separator:" "),String(r)])};emit([header])}
    func score(_ method:String) {let b=clean();var territory:[Character:Int]=["B":0,"W":0],total:[Character:Int]=[:];for r in regions(b,n) {if r.owner != "neutral" {territory[Character(r.owner),default:0]+=r.points.count}};for c in [Character("B"),Character("W")] {var fields=[String(c)];if method=="AREA" {let stones=b.filter{$0==c}.count;total[c]=2*(stones+territory[c]!)+(c=="W" ? komi2:0);fields += ["stones",String(stones),"territory",String(territory[c]!)]} else {let prisoners=captures[c]!+dead.filter{board[$0]==other(c)}.count;total[c]=2*(territory[c]!+prisoners)+(c=="W" ? komi2:0);fields += ["territory",String(territory[c]!),"prisoners",String(prisoners)]};if c=="W" {fields += ["komi",half(komi2)]};fields += ["total",half(total[c]!)];emit(fields)};let d=total["B"]!-total["W"]!;emit(["result",d>0 ? "B+"+half(d):d<0 ? "W+"+half(-d):"Draw"])}
    func execute(_ line:String) {
        let words=line.components(separatedBy:" "),c=words[0],a=Array(words.dropFirst());guard let count=arity[c] else {emit(["ERROR unknown command"]);return};if a.count != count {emit(["ERROR bad arguments"]);return}
        let valid:Bool;switch c {case "BOARD":valid=["9","13","19"].contains(a[0]) && komi(a[1]) != nil;case "KOMI":valid=komi(a[0]) != nil;case "SUPERKO":valid=["ON","OFF"].contains(a[0]);case "HANDICAP":valid=matches(a[0],"[2-9]");case "PLAY","PASS","LEGAL","EYES","SAFE":valid=["B","W"].contains(a[0]);case "SCORE":valid=["AREA","TERRITORY"].contains(a[0]);default:valid=true};if !valid {emit(["ERROR bad arguments"]);return}
        var p = -1;if ["PLAY","GROUP","LADDER","DEAD"].contains(c) {p=point(a[c=="PLAY" ? 1:0]);if p<0 {emit(["ERROR bad point"]);return}}
        var records:[(Character,Int)]=[]
        if c=="REPLAY" {if !matches(a[0],"(?:;[BW]\\[[a-z]{0,2}\\])+") {emit(["ERROR bad sequence"]);return};let pattern=try! NSRegularExpression(pattern:";([BW])\\[([a-z]*)\\]");let text=a[0] as NSString;for m in pattern.matches(in:a[0],range:NSRange(location:0,length:text.length)) {let color=Character(text.substring(with:m.range(at:1))),s=text.substring(with:m.range(at:2)),codes=Array(s.utf8);if !s.isEmpty && (codes.count != 2 || codes.contains{Int($0)-97>=n}) {emit(["ERROR bad sequence"]);return};let q=s.isEmpty ? -1:(n-1-(Int(codes[1])-97))*n+Int(codes[0])-97;records.append((color,q))}}
        if ["PLAY","PASS","REPLAY"].contains(c) && over {emit(["ERROR game over"]);return}
        switch c {
        case "BOARD":reset(Int(a[0])!,komi(a[1])!);emit(["board",String(n),"komi",half(komi2)])
        case "KOMI":komi2=komi(a[0])!;emit(["komi",half(komi2)])
        case "SUPERKO":superko=a[0]=="ON";emit(["superko",superko ? "on":"off"])
        case "HANDICAP":if !history.isEmpty || board.contains(where:{$0 != "."}) {emit(["ERROR handicap not allowed"]);return};let k=Int(a[0])!,indices=k==5 ? [0,1,2,3,8]:k==7 ? [0,1,2,3,4,5,8]:Array(0..<k);handicap=indices.map{point(handicapPoints[n]![$0])};for q in handicap {board[q]="B"};turn="W";positions=[board];dead=[];emit(["handicap",String(k)]+handicap.map(name))
        case "PLAY":let color=Character(a[0]),r=check(color,p),reason=color != turn ? "turn":r.reason;if !reason.isEmpty {emit(["ILLEGAL",String(color),a[1],reason])} else {let captured=move(color,p,r);emit([String(color),a[1]]+(captured>0 ? ["captures",String(captured)]:[]))}
        case "PASS":let color=Character(a[0]);if color != turn {emit(["ILLEGAL",a[0],"pass turn"])} else {move(color,-1);emit([a[0],"pass"]);if over {emit(["game over"])}}
        case "REPLAY":var played=0,stop:[String]=[];for (color,q) in records {let next=q<0 ? nil:check(color,q),reason=over ? "game over":color != turn ? "turn":next?.reason ?? "";if !reason.isEmpty {stop=["stopped",String(color),q<0 ? "pass":name(q),reason];break};move(color,q,next);played+=1};emit(["replay",String(played),"moves"]+stop);if over {emit(["game over"])}
        case "UNDO":guard let m=history.popLast() else {emit(["ERROR nothing to undo"]);return};let s=m.before;board=s.board;turn=s.turn;captures=["B":s.black,"W":s.white];passes=s.passes;over=s.over;positions.removeLast();dead=[];emit(["undo",String(m.color),m.point<0 ? "pass":name(m.point)])
        case "SHOW":show();case "MAP":show(true)
        case "STATUS":emit(["size",String(n),"komi",half(komi2),"handicap",String(handicap.count),"superko",superko ? "on":"off"]);emit(["moves",String(history.count)]+(over ? ["game over"]:["next",String(turn),"passes",String(passes)]))
        case "CAPTURES":emit(["captures B",String(captures["B"]!),"W",String(captures["W"]!)])
        case "HISTORY":emit(["history",String(history.count)]);for (i,m) in history.enumerated() {emit([String(i+1),String(m.color),m.point<0 ? "pass":name(m.point)]+(m.captured>0 ? ["captures",String(m.captured)]:[]))}
        case "MOVES":var s="(;GM[1]FF[4]SZ[\(n)]KM[\(half(komi2))]";if !handicap.isEmpty {s+="HA[\(handicap.count)]AB"+handicap.map{"[\(sgf($0))]"}.joined()};for m in history {s+=";\(m.color)[\(m.point<0 ? "":sgf(m.point))]"};emit([s+")"])
        case "GROUP","DEAD","LADDER":if board[p]=="." {emit(["ERROR no stone"]);return};let g=group(board,n,p);if c=="GROUP" {emit(["group",String(g.color),name(g.first),"size",String(g.stones.count),"liberties",String(g.liberties.count)]);emit(["stones"]+g.stones.sorted().map(name));emit(["liberties"]+g.liberties.sorted().map(name))} else if c=="DEAD" {let alive=dead.contains(p);if alive {dead.subtract(g.stones)} else {dead.formUnion(g.stones)};emit([alive ? "alive":"dead",String(g.color),name(g.first),"size",String(g.stones.count)])} else {let(status,q)=ladder(board,n,p);emit(["ladder",a[0],status]+(q<0 ? []:[name(q)]))}
        case "GROUPS":let gs=groups(board,n);emit(["groups",String(gs.count)]);for g in gs {emit([String(g.color),name(g.first),"size",String(g.stones.count),"liberties",String(g.liberties.count)]+(dead.contains(g.first) ? ["dead"]:[]))}
        case "ATARI":let gs=groups(board,n).filter{$0.liberties.count==1};if gs.isEmpty {emit(["atari none"])};for g in gs {emit(["atari",String(g.color),name(g.first),"size",String(g.stones.count),"at",name(g.liberties.first!)])}
        case "LEGAL":var rejected:[[String]]=[],legal=0;for q in board.indices {if board[q]=="." {let reason=check(Character(a[0]),q).reason;if reason.isEmpty {legal+=1} else {rejected.append([name(q),reason])}}};emit(["legal",a[0],String(legal)]);for row in rejected {emit(row)}
        case "EYES":var found:[[String]]=[];for q in board.indices {if board[q]=="." {let ns=adjacent(q,n);if ns.allSatisfy({board[$0]==Character(a[0])}) {let enemies=adjacent(q,n,true).filter{board[$0]==other(Character(a[0]))}.count;found.append([name(q),enemies<=(ns.count==4 ? 1:0) ? "real":"false"])}}};emit(["eyes",a[0],String(found.count)]);for row in found {emit(row)}
        case "SAFE":let gs=safeGroups(board,n,Character(a[0]));emit(["safe",a[0],String(gs.count)]);for g in gs {emit([name(g.first),"size",String(g.stones.count)])}
        case "REGIONS":let rs=regions(clean(),n);emit(["regions",String(rs.count)]);for r in rs {emit([name(r.first),"size",String(r.points.count),r.owner])}
        case "SCORE":score(a[0]);default:break
        }
    }
}
let game=Game(),count=Int(readLine()!)!
for _ in 0..<count {game.execute(readLine()!)}
