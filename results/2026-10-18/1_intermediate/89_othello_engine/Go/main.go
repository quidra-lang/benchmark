package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type Board [64]byte
var weights=[64]int{100,-20,10,5,5,10,-20,100,-20,-50,-2,-2,-2,-2,-50,-20,10,-2,-1,-1,-1,-1,-2,10,5,-2,-1,-1,-1,-1,-2,5,5,-2,-1,-1,-1,-1,-2,5,10,-2,-1,-1,-1,-1,-2,10,-20,-50,-2,-2,-2,-2,-50,-20,100,-20,10,5,5,10,-20,100}
func wordSet(s string)map[string]bool{m:=map[string]bool{};for _,x:=range strings.Fields(s){m[x]=true};return m}
var transforms=wordSet("rot90 rot180 rot270 mirror flip diag anti")
var zero=wordSet("NEW DUMP SHOW SCORE LEGAL HISTORY SHEET STATS EVAL STABLE SOLVE")
var numeric=wordSet("UNDO REDO HINT PV AI ANALYZE RANDOM PERFT DIVIDE")
var active=wordSet("FLIPS MOVE PLAY HINT PV AI SOLVE AUTOPLAY RANDOM MC DIVIDE")
var extra=wordSet("LOAD TRANSFORM AUTOPLAY MC FLIPS MOVE PLAY RECORD")
func other(s byte)byte{if s=='B'{return 'W'};return 'B'}
func name(p int)string{return string([]byte{byte('a'+p%8),byte('1'+p/8)})}
func square(s string)int{return int(s[1]-'1')*8+int(s[0]-'a')}
func inside(r,c int)bool{return r>=0&&r<8&&c>=0&&c<8}
func initial()Board{var b Board;for i:=range b{b[i]='.'};b[27]='W';b[36]='W';b[28]='B';b[35]='B';return b}
func flips(b Board,s byte,p int)[]int{out:=[]int{};if b[p]!='.'{return out};row,col:=p/8,p%8;for dr:=-1;dr<=1;dr++{for dc:=-1;dc<=1;dc++{if dr==0&&dc==0{continue};r,c:=row+dr,col+dc;line:=[]int{};for inside(r,c)&&b[8*r+c]==other(s){line=append(line,8*r+c);r+=dr;c+=dc};if len(line)>0&&inside(r,c)&&b[8*r+c]==s{out=append(out,line...)}}};sort.Ints(out);return out}
func legal(b Board,s byte)[]int{ms:=[]int{};for p:=range b{if b[p]=='.'&&len(flips(b,s,p))>0{ms=append(ms,p)}};return ms}
func place(b Board,s byte,p int)Board{for _,q:=range flips(b,s,p){b[q]=s};b[p]=s;return b}
func count(b Board,s byte)int{n:=0;for _,x:=range b{if x==s{n++}};return n}
func terminal(b Board)bool{return len(legal(b,'B'))==0&&len(legal(b,'W'))==0}
func gameOver(b Board)string{x,y:=count(b,'B'),count(b,'W');result:="draw";if x>y{result="winner B"}else if x<y{result="winner W"};return fmt.Sprintf("game over B %d W %d %s",x,y,result)}
func evaluate(b Board,s byte)[4]int{w:=0;for i,x:=range b{if x==s{w+=weights[i]}else if x==other(s){w-=weights[i]}};own,enemy:=len(legal(b,s)),len(legal(b,other(s)));return [4]int{w+10*(own-enemy),w,own,enemy}}
type key struct{board Board;side byte;depth int}
var searchCache=map[key]int{};var perftCache=map[key]int{}
func search(b Board,s byte,d int)int{k:=key{b,s,d};if v,ok:=searchCache[k];ok{return v};moves,o:=legal(b,s),other(s);v:=0;if len(moves)==0&&len(legal(b,o))==0{scale:=1000;if d<0{scale=1};v=scale*(count(b,s)-count(b,o))}else if d==0{v=evaluate(b,s)[0]}else{next:=d-1;if d<0{next=-1};if len(moves)==0{v=-search(b,o,next)}else{v=-1000000;for _,p:=range moves{x:=-search(place(b,s,p),o,next);if x>v{v=x}}}};if len(searchCache)>300000{clear(searchCache)};searchCache[k]=v;return v}
type ranking struct{value,square int}
func ranked(b Board,s byte,d int)[]ranking{rows:=[]ranking{};next:=d-1;if d<0{next=-1};for _,p:=range legal(b,s){rows=append(rows,ranking{-search(place(b,s,p),other(s),next),p})};sort.Slice(rows,func(i,j int)bool{if rows[i].value!=rows[j].value{return rows[i].value>rows[j].value};return rows[i].square<rows[j].square});return rows}
func variation(b Board,s byte,d int)([]string,Board){steps:=[]string{};for d!=0&&!terminal(b){rows:=ranked(b,s,d);if len(rows)==0{steps=append(steps,"pass")}else{p:=rows[0].square;steps=append(steps,name(p));b=place(b,s,p)};s=other(s);if d>0{d--}};return steps,b}
func perft(b Board,s byte,d int)int{if d==0{return 1};k:=key{b,s,d};if v,ok:=perftCache[k];ok{return v};moves,o:=legal(b,s),other(s);n:=0;if len(moves)==0{if len(legal(b,o))==0{n=1}else{n=perft(b,o,d-1)}}else{for _,p:=range moves{n+=perft(place(b,s,p),o,d-1)}};if len(perftCache)>200000{clear(perftCache)};perftCache[k]=n;return n}
func stable(b Board)(int,int){var stable [64]bool;axes:=[][2]int{{0,1},{1,0},{1,1},{1,-1}};for{found:=[]int{};for p,x:=range b{if x=='.'||stable[p]{continue};ok:=true;for _,axis:=range axes{dr,dc:=axis[0],axis[1];full,anchor:=true,false;for _,sign:=range []int{-1,1}{r,c:=p/8+dr*sign,p%8+dc*sign;if !inside(r,c)||(stable[8*r+c]&&b[8*r+c]==b[p]){anchor=true};for inside(r,c){if b[8*r+c]=='.'{full=false};r+=dr*sign;c+=dc*sign}};if !full&&!anchor{ok=false;break}};if ok{found=append(found,p)}};if len(found)==0{break};for _,p:=range found{stable[p]=true}};black,white:=0,0;for p,yes:=range stable{if yes{if b[p]=='B'{black++}else{white++}}};return black,white}
func transform(p int,op string)int{r,c:=p/8,p%8;switch op{case "rot90":return 8*c+7-r;case "rot180":return 63-p;case "rot270":return 8*(7-c)+r;case "mirror":return 8*r+7-c;case "flip":return 8*(7-r)+c;case "diag":return 8*c+r;default:return 8*(7-c)+7-r}}
func transformBoard(b Board,op string)Board{var a Board;for p,x:=range b{a[transform(p,op)]=x};return a}
type minstd struct{value int64}
func(r *minstd)draw()int64{r.value=r.value*48271%2147483647;return r.value}
func randomGame(b Board,s byte,rng *minstd)Board{for{moves:=legal(b,s);if len(moves)>0{b=place(b,s,moves[int(rng.draw()%int64(len(moves)))])}else if len(legal(b,other(s)))==0{return b};s=other(s)}}
func average(f,n int)string{v:=100*f/n;return fmt.Sprintf("%d.%02d",v/100,v%100)}
type position struct{board Board;side byte;over bool}
type moveRecord struct{side byte;square,count int;passed bool;before,after position}
type Othello struct{board Board;side byte;over bool;history,redo []moveRecord;out *bufio.Writer}
func newEngine(out *bufio.Writer)*Othello{return &Othello{board:initial(),side:'B',out:out}}
func(e *Othello)emit(s string){fmt.Fprintln(e.out,s)}
func(e *Othello)reset(){e.board=initial();e.side='B';e.over=false;e.history=nil;e.redo=nil}
func(e *Othello)snapshot()position{return position{e.board,e.side,e.over}}
func(e *Othello)restore(p position){e.board=p.board;e.side=p.side;e.over=p.over}
func(e *Othello)status()string{if e.over{return gameOver(e.board)};return string(e.side)+" to move"}
func(e *Othello)adjust(quiet bool)bool{if len(legal(e.board,e.side))>0{return false};if len(legal(e.board,other(e.side)))>0{if !quiet{e.emit(string(e.side)+" passes")};e.side=other(e.side);return true};e.over=true;if !quiet{e.emit(gameOver(e.board))};return false}
func(e *Othello)move(p int,quiet bool,value *int)bool{before,s,k:=e.snapshot(),e.side,len(flips(e.board,e.side,p));e.board=place(e.board,s,p);if !quiet{text:=fmt.Sprintf("%c %s flips %d",s,name(p),k);if value!=nil{text+=fmt.Sprintf(" value %d",*value)};e.emit(text)};e.side=other(s);passed:=e.adjust(quiet);e.history=append(e.history,moveRecord{s,p,k,passed,before,e.snapshot()});e.redo=nil;return passed}
func(e *Othello)reason(p int)string{if e.over{return "game over"};if e.board[p]!='.'{return "occupied"};if len(flips(e.board,e.side,p))==0{return "no flips"};return ""}
func(e *Othello)record(text string){temp:=newEngine(e.out);ps:=[]int{};passes:=0;for i:=0;i<len(text);i+=2{p:=square(text[i:i+2]);if why:=temp.reason(p);why!=""{e.emit(fmt.Sprintf("ILLEGAL move %d %s %s",i/2+1,name(p),why));return};ps=append(ps,p);if temp.move(p,true,nil){passes++}};e.restore(temp.snapshot());e.history=temp.history;e.redo=nil;op:=map[string]string{"f5":"","e6":"diag","d3":"anti","c4":"rot180"}[name(ps[0])];var normal strings.Builder;for _,p:=range ps{if op!=""{p=transform(p,op)};normal.WriteString(name(p))};e.emit(fmt.Sprintf("record %d moves %d passes",len(ps),passes));e.emit("normal "+normal.String());e.emit(e.status())}
func(e *Othello)sheet(){b:=e.board;if len(e.history)>0{b=e.history[0].before.board};fields:=make([]string,64);for p,x:=range b{fields[p]=string(x)};for i,r:=range e.history{fields[r.square]=strconv.Itoa(i+1)};e.emit("   a  b  c  d  e  f  g  h");for r:=0;r<8;r++{row:=strconv.Itoa(r+1);for c:=0;c<8;c++{row+=fmt.Sprintf("%3s",fields[8*r+c])};e.emit(row)}}
func(e *Othello)stats(){total,passes:=0,0;for _,r:=range e.history{total+=r.count;if r.passed{passes++}};if len(e.history)==0{e.emit("moves 0")}else{e.emit(fmt.Sprintf("moves %d flips %d avg %s passes %d",len(e.history),total,average(total,len(e.history)),passes))};for _,s:=range []byte{'B','W'}{n,sum,maximum,p,corners:=0,0,-1,-1,0;for _,r:=range e.history{if r.side==s{n++;sum+=r.count;if r.count>maximum{maximum=r.count;p=r.square};if r.square==0||r.square==7||r.square==56||r.square==63{corners++}}};if n==0{e.emit(string(s)+" moves 0")}else{e.emit(fmt.Sprintf("%c moves %d flips %d avg %s max %d %s corners %d",s,n,sum,average(sum,n),maximum,name(p),corners))}}}
func(e *Othello)auto(black,white int,seed int64){rng:=minstd{seed};ps:=[]string{};passes:=0;for !e.over{moves:=legal(e.board,e.side);p:=0;if seed!=0{p=moves[int(rng.draw()%int64(len(moves)))]}else{depth:=black;if e.side=='W'{depth=white};p=ranked(e.board,e.side,depth)[0].square};ps=append(ps,name(p));if e.move(p,true,nil){passes++}};kind:="autoplay";if seed!=0{kind="random"};e.emit(fmt.Sprintf("%s %d moves %d passes",kind,len(ps),passes));e.emit("moves "+strings.Join(ps,""));e.emit(gameOver(e.board))}
func(e *Othello)monteCarlo(k int,seed int64){rng:=minstd{seed};best,bp:=-1,-1;for _,p:=range legal(e.board,e.side){w,d,l:=0,0,0;start:=place(e.board,e.side,p);for i:=0;i<k;i++{b:=randomGame(start,other(e.side),&rng);diff:=count(b,e.side)-count(b,other(e.side));if diff>0{w++}else if diff<0{l++}else{d++}};e.emit(fmt.Sprintf("%s %d %d %d",name(p),w,d,l));if 2*w+d>best{best=2*w+d;bp=p}};e.emit(fmt.Sprintf("best %s %d",name(bp),best))}
func validSquare(s string)bool{return len(s)==2&&s[0]>='a'&&s[0]<='h'&&s[1]>='1'&&s[1]<='8'}
func digits(s string)bool{if s==""{return false};for _,c:=range s{if c<'0'||c>'9'{return false}};return true}
func(e *Othello)execute(text string){words:=strings.Fields(text);cmd,a:=words[0],words[1:];problem:="";if !zero[cmd]&&!numeric[cmd]&&!extra[cmd]{problem="unknown command"}else if cmd=="LOAD"{valid:=len(a)==2;if valid{valid=len(a[0])==64&&(a[1]=="B"||a[1]=="W");for _,c:=range a[0]{if c!='.'&&c!='B'&&c!='W'{valid=false}}};if !valid{problem="bad board"}}else if cmd=="MOVE"||cmd=="FLIPS"{if len(a)!=1{problem="bad arguments"}else if !validSquare(a[0]){problem="bad square"}}else if cmd=="PLAY"||cmd=="RECORD"{if len(a)!=1{problem="bad arguments"}else{valid:=len(a[0])>=2&&len(a[0])<=120&&len(a[0])%2==0;for i:=0;i+1<len(a[0]);i+=2{if !validSquare(a[0][i:i+2]){valid=false}};if !valid{problem="bad record"}}}else if zero[cmd]{if len(a)!=0{problem="bad arguments"}}else if cmd=="TRANSFORM"{if len(a)!=1||!transforms[a[0]]{problem="bad arguments"}}else{expected:=1;if cmd=="AUTOPLAY"||cmd=="MC"{expected=2};valid:=len(a)==expected;ns:=[]int64{};for _,s:=range a{if !digits(s){valid=false}else{x,err:=strconv.ParseInt(s,10,64);if err!=nil{valid=false}else{ns=append(ns,x)}}};if valid{n:=ns[0];switch cmd{case "AUTOPLAY":valid=n>=1&&n<=4&&ns[1]>=1&&ns[1]<=4;case "HINT","PV","AI","ANALYZE":valid=n>=1&&n<=4;case "PERFT","DIVIDE":valid=n>=1&&n<=8;case "MC":valid=n>=1&&n<=100&&ns[1]>=1&&ns[1]<=2147483646;case "RANDOM":valid=n>=1&&n<=2147483646;default:valid=n>=1}};if !valid{problem="bad arguments"}};if problem!=""{e.emit("ERROR "+problem);return};if e.over&&active[cmd]{e.emit("ERROR game over");return};n:=0;if len(a)>0{n,_=strconv.Atoi(a[0])}
    switch cmd{
    case "NEW":e.reset();e.emit("OK")
    case "LOAD":copy(e.board[:],a[0]);e.side=a[1][0];e.over=false;e.history=nil;e.redo=nil;e.emit("OK");e.adjust(false)
    case "DUMP":e.emit("board "+string(e.board[:])+" "+string(e.side))
    case "SHOW":e.emit("  a b c d e f g h");ms:=map[int]bool{};if !e.over{for _,p:=range legal(e.board,e.side){ms[p]=true}};for r:=0;r<8;r++{row:=strconv.Itoa(r+1);for c:=0;c<8;c++{x:=e.board[8*r+c];if ms[8*r+c]{x='*'};row+=" "+string(x)};e.emit(row)};e.emit(e.status())
    case "SCORE":e.emit(fmt.Sprintf("score B %d W %d empty %d",count(e.board,'B'),count(e.board,'W'),count(e.board,'.')))
    case "LEGAL":moves:=[]int{};if !e.over{moves=legal(e.board,e.side)};line:="legal "+strconv.Itoa(len(moves));for _,p:=range moves{line+=" "+name(p)};e.emit(line)
    case "MOVE","FLIPS":p:=square(a[0]);if why:=e.reason(p);why!=""{e.emit("ILLEGAL "+why)}else if cmd=="MOVE"{e.move(p,false,nil)}else{f:=flips(e.board,e.side,p);line:=fmt.Sprintf("flips %s %d",a[0],len(f));for _,q:=range f{line+=" "+name(q)};e.emit(line)}
    case "PLAY":for i:=0;i<len(a[0]);i+=2{p:=square(a[0][i:i+2]);if why:=e.reason(p);why!=""{e.emit(fmt.Sprintf("ILLEGAL move %d %s %s",i/2+1,name(p),why));break};e.move(p,false,nil)}
    case "RECORD":e.record(a[0])
    case "UNDO":if n>len(e.history){e.emit("ERROR cannot undo")}else{start:=len(e.history)-n;removed:=append([]moveRecord(nil),e.history[start:]...);e.restore(removed[0].before);e.history=e.history[:start];e.redo=append(removed,e.redo...);e.emit(e.status())}
    case "REDO":if n>len(e.redo){e.emit("ERROR cannot redo")}else{added:=append([]moveRecord(nil),e.redo[:n]...);e.redo=e.redo[n:];e.history=append(e.history,added...);e.restore(added[n-1].after);e.emit(e.status())}
    case "HISTORY":e.emit("history "+strconv.Itoa(len(e.history)));for i,r:=range e.history{line:=fmt.Sprintf("%d %c %s %d",i+1,r.side,name(r.square),r.count);if r.passed{line+=" pass"};e.emit(line)}
    case "SHEET":e.sheet()
    case "STATS":e.stats()
    case "TRANSFORM":op:=a[0];e.board=transformBoard(e.board,op);tr:=func(r moveRecord)moveRecord{r.square=transform(r.square,op);r.before.board=transformBoard(r.before.board,op);r.after.board=transformBoard(r.after.board,op);return r};for i,r:=range e.history{e.history[i]=tr(r)};for i,r:=range e.redo{e.redo[i]=tr(r)};e.emit("OK")
    case "EVAL":v:=evaluate(e.board,e.side);e.emit(fmt.Sprintf("eval %d weights %d mobility %d %d",v[0],v[1],v[2],v[3]))
    case "STABLE":b,w:=stable(e.board);e.emit(fmt.Sprintf("stable B %d W %d",b,w))
    case "HINT":for _,r:=range ranked(e.board,e.side,n){e.emit(fmt.Sprintf("%s %d",name(r.square),r.value))}
    case "PV":steps,_:=variation(e.board,e.side,n);out:=[]string{"pv",strconv.Itoa(search(e.board,e.side,n))};e.emit(strings.Join(append(out,steps...)," "))
    case "AI":r:=ranked(e.board,e.side,n)[0];e.move(r.square,false,&r.value)
    case "ANALYZE":loss:=map[byte]int{'B':0,'W':0};for i,r:=range e.history{rows:=ranked(r.before.board,r.side,n);best,bp:=rows[0].value,rows[0].square;value:=0;for _,row:=range rows{if row.square==r.square{value=row.value;break}};loss[r.side]+=best-value;e.emit(fmt.Sprintf("%d %c %s %d best %s %d",i+1,r.side,name(r.square),value,name(bp),best))};e.emit(fmt.Sprintf("loss B %d W %d",loss['B'],loss['W']))
    case "SOLVE":if count(e.board,'.')>=9{e.emit("ERROR too many empties")}else{for _,r:=range ranked(e.board,e.side,-1){e.emit(fmt.Sprintf("%s %d",name(r.square),r.value))};steps,b:=variation(e.board,e.side,-1);e.emit(strings.Join(append([]string{"line"},steps...)," "));e.emit(fmt.Sprintf("final B %d W %d",count(b,'B'),count(b,'W')))}
    case "AUTOPLAY":white,_:=strconv.Atoi(a[1]);e.auto(n,white,0)
    case "RANDOM":e.auto(0,0,int64(n))
    case "MC":seed,_:=strconv.ParseInt(a[1],10,64);e.monteCarlo(n,seed)
    case "PERFT":e.emit(fmt.Sprintf("perft %d %d",n,perft(e.board,e.side,n)))
    case "DIVIDE":total:=0;for _,p:=range legal(e.board,e.side){v:=perft(place(e.board,e.side,p),other(e.side),n-1);e.emit(fmt.Sprintf("%s %d",name(p),v));total+=v};e.emit("total "+strconv.Itoa(total))
    }
}
func main(){in:=bufio.NewScanner(os.Stdin);out:=bufio.NewWriter(os.Stdout);defer out.Flush();in.Scan();n,_:=strconv.Atoi(in.Text());e:=newEngine(out);for i:=0;i<n&&in.Scan();i++{e.execute(in.Text());out.Flush()}}
