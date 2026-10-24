package main

import (
    "bufio"
    "fmt"
    "os"
    "regexp"
    "sort"
    "strconv"
    "strings"
)
const files="abcdefgh"
const ranks="12345678"
const initial="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
var rook=[][2]int{{0,1},{0,-1},{-1,0},{1,0}}
var bishop=[][2]int{{1,1},{-1,1},{1,-1},{-1,-1}}
var king=[][2]int{{0,1},{0,-1},{-1,0},{1,0},{1,1},{-1,1},{1,-1},{-1,-1}}
var knight=[][2]int{{1,2},{2,1},{2,-1},{1,-2},{-1,-2},{-2,-1},{-2,1},{-1,2}}
type Rule struct{king,rook,target,rookTarget int;path []int}
var rules=map[byte]Rule{'K':{4,7,6,5,[]int{5,6}},'Q':{4,0,2,3,[]int{1,2,3}},'k':{60,63,62,61,[]int{61,62}},'q':{60,56,58,59,[]int{57,58,59}}}
type Move struct{source,target int;promotion byte}
type Record struct{san,uci string;captured byte}
type InputError string
func(e InputError)Error()string{return string(e)}
func fail(s string){panic(InputError(s))}
func recoverInput(err *error){if e:=recover();e!=nil{if input,ok:=e.(InputError);ok{*err=input}else{panic(e)}}}
var out=bufio.NewWriter(os.Stdout)
func emit(s string){fmt.Fprintln(out,s)}
func upper(p byte)byte{if p>='a'&&p<='z'{return p-32};return p}
func lower(p byte)byte{if p>='A'&&p<='Z'{return p+32};return p}
func color(p byte)byte{if p==upper(p){return 'w'};return 'b'}
func opposite(c byte)byte{if c=='w'{return 'b'};return 'w'}
func colored(p,c byte)byte{if c=='w'{return p};return lower(p)}
func step(c byte)int{if c=='w'{return 8};return -8}
func square(s string)int{if len(s)!=2||s[0]<'a'||s[0]>'h'||s[1]<'1'||s[1]>'8'{return -1};return int(s[0]-'a')+8*int(s[1]-'1')}
func name(s int)string{return string([]byte{files[s%8],ranks[s/8]})}
func number(s string,lo,hi int)int{if s==""||len(s)>9||(len(s)>1&&s[0]=='0'){return -1};for _,c:=range s{if c<'0'||c>'9'{return -1}};n,_:=strconv.Atoi(s);if n<lo||n>hi{return -1};return n}
func shift(s,dx,dy int)int{x,y:=s%8+dx,s/8+dy;if x<0||x>7||y<0||y>7{return -1};return 8*y+x}
func targets(b [64]byte,s int)[]int{
    p:=b[s];kind:=upper(p);a:=[]int{}
    if strings.ContainsRune("PNK",rune(kind)){dirs:=king;if kind=='N'{dirs=knight}else if kind=='P'{dy:=1;if color(p)=='b'{dy=-1};dirs=[][2]int{{-1,dy},{1,dy}}};for _,d:=range dirs{t:=shift(s,d[0],d[1]);if t>=0{a=append(a,t)}};return a}
    dirs:=bishop;if kind=='R'{dirs=rook}else if kind=='Q'{dirs=king};for _,d:=range dirs{for t:=shift(s,d[0],d[1]);t>=0;t=shift(t,d[0],d[1]){a=append(a,t);if b[t]!='.'{break}}};return a
}
func attackers(b [64]byte,t int,c byte)[]int{a:=[]int{};for s,p:=range b{if p=='.'||color(p)!=c{continue};for _,x:=range targets(b,s){if x==t{a=append(a,s);break}}};return a}
type Position struct{board [64]byte;side byte;rights string;ep,half,full int}
func(p Position)check(c byte)bool{for s,x:=range p.board{if x==colored('K',c){return len(attackers(p.board,s,opposite(c)))>0}};return false}
func(p Position)castle(m Move)bool{d:=m.target-m.source;return upper(p.board[m.source])=='K'&&(d==2||d==-2)}
func(p Position)enpassant(m Move)bool{return upper(p.board[m.source])=='P'&&m.source%8!=m.target%8&&p.board[m.target]=='.'}
func(p Position)capture(m Move)bool{return p.board[m.target]!='.'||p.enpassant(m)}
func(p Position)captured(m Move)byte{if p.board[m.target]!='.'{return lower(p.board[m.target])};if p.enpassant(m){return 'p'};return '-'}
func(p Position)play(m Move)Position{
    q:=p;piece:=p.board[m.source];kind:=upper(piece)
    if p.enpassant(m){q.board[m.target-step(p.side)]='.'}
    if p.castle(m){right:=byte('Q');if m.target>m.source{right='K'};r:=rules[colored(right,p.side)];q.board[r.rookTarget]=q.board[r.rook];q.board[r.rook]='.'}
    q.board[m.target]=piece;if m.promotion!=0{q.board[m.target]=colored(m.promotion,p.side)};q.board[m.source]='.';q.rights=""
    for i:=range p.rights{r:=p.rights[i];if (kind!='K'||color(r)!=p.side)&&rules[r].rook!=m.source&&rules[r].rook!=m.target{q.rights+=string(r)}}
    q.ep=-1;d:=m.target-m.source;if kind=='P'&&(d==16||d==-16){q.ep=(m.source+m.target)/2};q.half=p.half+1;if kind=='P'||p.capture(m){q.half=0};if p.side=='b'{q.full++};q.side=opposite(p.side);return q
}
func(p Position)pseudo()[]Move{
    result:=[]Move{}
    for s,piece:=range p.board{if piece=='.'||color(piece)!=p.side{continue};pawn:=upper(piece)=='P';a:=[]int{}
        if pawn{d:=step(p.side);start:=1;if p.side=='b'{start=6};if p.board[s+d]=='.'{a=append(a,s+d);if s/8==start&&p.board[s+2*d]=='.'{a=append(a,s+2*d)}};for _,t:=range targets(p.board,s){if (p.board[t]!='.'&&color(p.board[t])!=p.side)||t==p.ep{a=append(a,t)}}}else{for _,t:=range targets(p.board,s){if p.board[t]=='.'||color(p.board[t])!=p.side{a=append(a,t)}}}
        last:=7;if p.side=='b'{last=0};for _,t:=range a{if pawn&&t/8==last{for _,promotion:=range []byte("QRBN"){result=append(result,Move{s,t,promotion})}}else{result=append(result,Move{s,t,0})}}
    };return result
}
func(p Position)castlingMove(kingside bool)Move{right:=byte('Q');if kingside{right='K'};r:=rules[colored(right,p.side)];return Move{r.king,r.target,0}}
func(p Position)castlingProblem(kingside bool)string{
    right:=byte('Q');if kingside{right='K'};right=colored(right,p.side);r:=rules[right]
    if !strings.ContainsRune(p.rights,rune(right)){return "no castling right"};for _,s:=range r.path{if p.board[s]!='.'{return "path blocked"}}
    if p.check(p.side){return "in check"};if len(attackers(p.board,r.rookTarget,opposite(p.side)))>0{return "through check"};if p.play(p.castlingMove(kingside)).check(p.side){return "into check"};return ""
}
func(p Position)legal()[]Move{a:=[]Move{};for _,m:=range p.pseudo(){if !p.play(m).check(p.side){a=append(a,m)}};for _,k:=range []bool{true,false}{if p.castlingProblem(k)==""{a=append(a,p.castlingMove(k))}};return a}
func(p Position)mark(m Move)string{q:=p.play(m);if !q.check(q.side){return ""};if len(q.legal())==0{return "#"};return "+"}
func(p Position)disambiguation(m Move)string{
    any,file,rank:=false,true,true;for _,x:=range p.legal(){if !p.castle(x)&&x.target==m.target&&x.source!=m.source&&p.board[x.source]==p.board[m.source]{any=true;file=file&&x.source%8!=m.source%8;rank=rank&&x.source/8!=m.source/8}}
    if !any{return ""};if file{return string(files[m.source%8])};if rank{return string(ranks[m.source/8])};return name(m.source)
}
func(p Position)san(m Move)string{
    kind:=upper(p.board[m.source]);text:=""
    if p.castle(m){text="O-O-O";if m.target>m.source{text="O-O"}}else if kind=='P'{if p.capture(m){text=string(files[m.source%8])+"x"};text+=name(m.target);if m.promotion!=0{text+="="+string(m.promotion)}}else{text=string(kind)+p.disambiguation(m);if p.capture(m){text+="x"};text+=name(m.target)};return text+p.mark(m)
}
func(p Position)key()string{ep:=-1;if p.ep>=0{for _,m:=range p.legal(){if p.enpassant(m){ep=p.ep;break}}};return string(p.board[:])+" "+string(p.side)+" "+p.rights+" "+strconv.Itoa(ep)}
func(p Position)state()string{any:=len(p.legal())>0;if p.check(p.side){if any{return "check"};return "checkmate"};if any{return "normal"};return "stalemate"}
func(p Position)insufficient()bool{a:=[]int{};for s,piece:=range p.board{if piece!='.'&&upper(piece)!='K'{if strings.ContainsRune("PRQ",rune(upper(piece))){return false};a=append(a,s)}};if len(a)<=1{return true};shade:=(a[0]%8+a[0]/8)%2;for _,s:=range a{if upper(p.board[s])!='B'||(s%8+s/8)%2!=shade{return false}};return true}
func(p Position)pins()[][2]int{
    k:=0;for s,piece:=range p.board{if piece==colored('K',p.side){k=s;break}};a:=[][2]int{}
    for _,d:=range king{first:=-1;for t:=shift(k,d[0],d[1]);t>=0;t=shift(t,d[0],d[1]){piece:=p.board[t];if piece=='.'{continue};if first<0{if color(piece)!=p.side{break};first=t}else{slider:=byte('B');if d[0]==0||d[1]==0{slider='R'};if color(piece)!=p.side&&(upper(piece)=='Q'||upper(piece)==slider){a=append(a,[2]int{first,t})};break}}};sort.Slice(a,func(i,j int)bool{return a[i][0]<a[j][0]});return a
}
func(p Position)fen()string{rows:=[]string{};for r:=7;r>=0;r--{row:="";empty:=0;for f:=0;f<8;f++{piece:=p.board[r*8+f];if piece=='.'{empty++}else{if empty>0{row+=strconv.Itoa(empty)};empty=0;row+=string(piece)}};if empty>0{row+=strconv.Itoa(empty)};rows=append(rows,row)};rights,ep:=p.rights,"-";if rights==""{rights="-"};if p.ep>=0{ep=name(p.ep)};return strings.Join(rows,"/")+" "+string(p.side)+" "+rights+" "+ep+" "+strconv.Itoa(p.half)+" "+strconv.Itoa(p.full)}
func parseFen(a []string)(p Position,err error){
    defer recoverInput(&err)
    if len(a)!=6{fail("fields")};rows:=strings.Split(a[0],"/");if len(rows)!=8{fail("placement")};for s:=range p.board{p.board[s]='.'}
    for i,row:=range rows{f:=0;digit:=false;for j:=range row{c:=row[j];if c>='1'&&c<='8'{if digit{fail("placement")};f+=int(c-'0');digit=true}else{if !strings.ContainsRune("KQRBNPkqrbnp",rune(c))||f>=8{fail("placement")};p.board[(7-i)*8+f]=c;f++;digit=false}};if f!=8{fail("placement")}}
    white,black:=0,0;for _,c:=range p.board{if c=='K'{white++};if c=='k'{black++}};if white!=1||black!=1{fail("kings")};for i:=0;i<8;i++{if upper(p.board[i])=='P'||upper(p.board[56+i])=='P'{fail("pawns")}}
    if a[1]!="w"&&a[1]!="b"{fail("side")};p.side=a[1][0];if a[2]!="-"{previous:=-1;for i:=range a[2]{j:=strings.IndexByte("KQkq",a[2][i]);if j<=previous{fail("castling")};previous=j};p.rights=a[2]}
    for i:=range p.rights{r:=p.rights[i];rule:=rules[r];if p.board[rule.king]!=colored('K',color(r))||p.board[rule.rook]!=colored('R',color(r)){fail("castling")}}
    p.ep=-1;if a[3]!="-"{p.ep=square(a[3]);expected:=5;if p.side=='b'{expected=2};d:=step(p.side);if p.ep<0||p.ep/8!=expected||p.board[p.ep]!='.'||p.board[p.ep+d]!='.'||p.board[p.ep-d]!=colored('P',opposite(p.side)){fail("en passant")}}
    p.half=number(a[4],0,999);p.full=number(a[5],1,999);if p.half<0||p.full<0||(p.ep>=0&&p.half!=0){fail("clocks")};if p.check(opposite(p.side)){fail("check")};return
}
func readSan(p Position,text string)(move Move,err error){
    defer recoverInput(&err)
    mark,body:="",text;if strings.HasSuffix(body,"+")||strings.HasSuffix(body,"#"){mark=body[len(body)-1:];body=body[:len(body)-1]};castling:=body=="O-O"||body=="O-O-O";promotion:=byte(0);target:=-1;capture:=false;kind:=byte('P');file,rank:="",""
    if !castling{if len(body)>=2&&body[len(body)-2]=='='{promotion=body[len(body)-1];if !strings.ContainsRune("QRBN",rune(promotion)){fail("syntax")};body=body[:len(body)-2]};if len(body)<2{fail("syntax")};target=square(body[len(body)-2:]);if target<0{fail("syntax")};body=body[:len(body)-2];capture=strings.HasSuffix(body,"x");if capture{body=body[:len(body)-1]};if len(body)>0&&strings.ContainsRune("KQRBN",rune(body[0])){kind=body[0];h:=regexp.MustCompile(`^([a-h]?)([1-8]?)$`).FindStringSubmatch(body[1:]);if h==nil||promotion!=0{fail("syntax")};file,rank=h[1],h[2]}else{if (capture&&(len(body)!=1||body[0]<'a'||body[0]>'h'))||(!capture&&body!=""){fail("syntax")};file=body}}
    legal:=p.legal();if len(legal)==0{fail("game over")}
    if castling{k:=body=="O-O";if problem:=p.castlingProblem(k);problem!=""{fail(problem)};move=p.castlingMove(k)}else{
        matches:=func(m Move)bool{return upper(p.board[m.source])==kind&&m.target==target&&!p.castle(m)&&(file==""||files[m.source%8]==file[0])&&(rank==""||ranks[m.source/8]==rank[0])&&(kind!='P'||(m.source%8!=m.target%8)==capture)}
        candidates:=[]Move{};for _,m:=range legal{if matches(m){candidates=append(candidates,m)}};if len(candidates)==0{for _,m:=range p.pseudo(){if matches(m){fail("leaves king in check")}};fail("no such move")};move=candidates[0];for _,m:=range candidates{if m.source!=move.source{fail("ambiguous")}};if p.capture(move)!=capture{fail("capture mark")};if move.promotion!=0&&promotion==0{fail("missing promotion")};if promotion!=0&&move.promotion==0{fail("invalid promotion")};if kind!='P'&&file+rank!=p.disambiguation(move){fail("disambiguation")};move.promotion=promotion
    };if p.mark(move)!=mark{fail("check mark")};return
}
func readUci(p Position,text string)(move Move,err error){
    defer recoverInput(&err)
    if !regexp.MustCompile(`^[a-h][1-8][a-h][1-8][qrbn]?$`).MatchString(text){fail("syntax")};s,t:=square(text[:2]),square(text[2:4]);promotion:=byte(0);if len(text)==5{promotion=upper(text[4])};legal:=p.legal();if len(legal)==0{fail("game over")};if p.board[s]=='.'||color(p.board[s])!=p.side{fail("no piece")};for _,m:=range legal{if m.source==s&&m.target==t{if m.promotion!=0&&promotion==0{fail("missing promotion")};if promotion!=0&&m.promotion==0{fail("invalid promotion")};return Move{s,t,promotion},nil}};for _,m:=range p.pseudo(){if m.source==s&&m.target==t{fail("leaves king in check")}};fail("no such move");return
}
func perft(p Position,d int,stats *[7]int64)int64{if d==0{return 1};var total int64;for _,m:=range p.legal(){q:=p.play(m);total+=perft(q,d-1,stats);if d==1&&stats!=nil{stats[0]++;if p.capture(m){stats[1]++};if p.enpassant(m){stats[2]++};if p.castle(m){stats[3]++};if m.promotion!=0{stats[4]++};if q.check(q.side){stats[5]++;if len(q.legal())==0{stats[6]++}}}};return total}
type Game struct{positions []Position;records []Record;loaded bool}
func newGame()*Game{p,_:=parseFen(strings.Split(initial," "));return &Game{positions:[]Position{p}}}
func(g *Game)current()Position{return g.positions[len(g.positions)-1]}
func(g *Game)play(m Move){p:=g.current();uci:=name(m.source)+name(m.target);if m.promotion!=0{uci+=string(lower(m.promotion))};g.records=append(g.records,Record{p.san(m),uci,p.captured(m)});g.positions=append(g.positions,p.play(m))}
func(g *Game)repetition()int{key:=g.current().key();n:=0;for _,p:=range g.positions{if p.key()==key{n++}};return n}
func(g *Game)draws()[]string{a:=[]string{};p:=g.current();if p.half>=100{a=append(a,"fifty")};if g.repetition()>=3{a=append(a,"threefold")};if p.insufficient(){a=append(a,"insufficient")};return a}
func(g *Game)result()string{p:=g.current();state:=p.state();if state=="checkmate"{if p.side=='b'{return "1-0"};return "0-1"};if state=="stalemate"||len(g.draws())>0{return "1/2-1/2"};return "*"}
func has(a []string,s string)bool{for _,x:=range a{if x==s{return true}};return false}
func execute(game **Game,line string){
    w:=strings.Split(line," ");cmd,a:=w[0],w[1:];if !has(strings.Fields("NEW LOAD FEN BOARD MOVE UCI LEGAL STATUS UNDO PERFT DIVIDE ATTACKS PINS HISTORY PGN"),cmd){emit("ERROR unknown command");return}
    bad:=has(strings.Fields("NEW FEN BOARD STATUS PINS HISTORY PGN"),cmd)&&len(a)!=0;if cmd=="MOVE"||cmd=="UCI"{bad=len(a)==0};if cmd=="LEGAL"{bad=len(a)>1||(len(a)==1&&square(a[0])<0)};if cmd=="ATTACKS"{bad=len(a)!=1||(len(a)==1&&square(a[0])<0)};n:=-1;if has([]string{"UNDO","PERFT","DIVIDE"},cmd){hi:=3;if cmd=="UNDO"{hi=9999};if len(a)==1{n=number(a[0],1,hi)};bad=n<0};if bad{emit("ERROR bad arguments");return};g:=*game;p:=g.current()
    switch cmd{
    case "NEW":*game=newGame();emit("OK")
    case "LOAD":q,err:=parseFen(a);if err!=nil{emit("ERROR bad fen ("+err.Error()+")")}else{*game=&Game{positions:[]Position{q},loaded:true};emit("OK")}
    case "FEN":emit(p.fen())
    case "BOARD":for r:=7;r>=0;r--{row:=[]string{strconv.Itoa(r+1)};for f:=0;f<8;f++{row=append(row,string(p.board[8*r+f]))};emit(strings.Join(row," "))};emit("  a b c d e f g h")
    case "MOVE","UCI":played:=[]string{};failure:="";for i,text:=range a{var m Move;var err error;if cmd=="MOVE"{m,err=readSan(g.current(),text)}else{m,err=readUci(g.current(),text)};if err!=nil{failure=fmt.Sprintf("ILLEGAL move %d: %s (%s)",i+1,text,err);break};g.play(m);played=append(played,g.records[len(g.records)-1].san)};if cmd=="UCI"&&len(played)>0{emit("san "+strings.Join(played," "))};if failure!=""{emit(failure)}else if cmd=="MOVE"{emit("OK")}
    case "LEGAL":list:=[]string{};for _,m:=range p.legal(){if len(a)==0||m.source==square(a[0]){list=append(list,p.san(m))}};sort.Strings(list);row:=append([]string{"legal",strconv.Itoa(len(list))},list...);emit(strings.Join(row," "))
    case "STATUS":side:="white";if p.side=='b'{side="black"};row:=append([]string{"status",side,p.state(),"rep",strconv.Itoa(g.repetition())},g.draws()...);emit(strings.Join(row," "))
    case "UNDO":if n>len(g.records){emit("ERROR cannot undo")}else{g.records=g.records[:len(g.records)-n];g.positions=g.positions[:len(g.positions)-n];emit("OK")}
    case "PERFT":stats:=[7]int64{};perft(p,n,&stats);row:=[]string{"perft",strconv.Itoa(n)};for i,f:=range []string{"nodes","captures","ep","castles","promotions","checks","mates"}{row=append(row,f,strconv.FormatInt(stats[i],10))};emit(strings.Join(row," "))
    case "DIVIDE":type Row struct{san string;count int64};rows:=[]Row{};var total int64;for _,m:=range p.legal(){v:=perft(p.play(m),n-1,nil);rows=append(rows,Row{p.san(m),v});total+=v};sort.Slice(rows,func(i,j int)bool{return rows[i].san<rows[j].san});for _,r:=range rows{emit(fmt.Sprintf("%s %d",r.san,r.count))};emit(fmt.Sprintf("total %d",total))
    case "ATTACKS":row:=[]string{"attacks",a[0]};for _,c:=range []byte{'w','b'}{found:=attackers(p.board,square(a[0]),c);label:="white";if c=='b'{label="black"};row=append(row,label,strconv.Itoa(len(found)));for _,s:=range found{row=append(row,name(s))}};emit(strings.Join(row," "))
    case "PINS":pins:=p.pins();row:=[]string{"pins",strconv.Itoa(len(pins))};for _,pair:=range pins{row=append(row,name(pair[0])+"-"+name(pair[1]))};emit(strings.Join(row," "))
    case "HISTORY":emit(fmt.Sprintf("history %d",len(g.records)));for i,r:=range g.records{emit(fmt.Sprintf("%d %s %s %c",i+1,r.uci,r.san,r.captured))}
    case "PGN":result:=g.result();emit(`[Result "`+result+`"]`);if g.loaded{emit(`[SetUp "1"]`);emit(`[FEN "`+g.positions[0].fen()+`"]`)};row:=[]string{};for i,r:=range g.records{q:=g.positions[i];if q.side=='w'{row=append(row,strconv.Itoa(q.full)+".")}else if i==0{row=append(row,strconv.Itoa(q.full)+"...")};row=append(row,r.san)};row=append(row,result);emit(strings.Join(row," "))
    }
}
func main(){defer out.Flush();scanner:=bufio.NewScanner(os.Stdin);scanner.Scan();n,_:=strconv.Atoi(scanner.Text());game:=newGame();for i:=0;i<n&&scanner.Scan();i++{execute(&game,scanner.Text())}}
