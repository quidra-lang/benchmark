import 'dart:io';
import 'dart:math' as math;
const weights=[100,-20,10,5,5,10,-20,100,-20,-50,-2,-2,-2,-2,-50,-20,10,-2,-1,-1,-1,-1,-2,10,5,-2,-1,-1,-1,-1,-2,5,5,-2,-1,-1,-1,-1,-2,5,10,-2,-1,-1,-1,-1,-2,10,-20,-50,-2,-2,-2,-2,-50,-20,100,-20,10,5,5,10,-20,100];
const transforms=['rot90','rot180','rot270','mirror','flip','diag','anti'];
final zero='NEW DUMP SHOW SCORE LEGAL HISTORY SHEET STATS EVAL STABLE SOLVE'.split(' ');
final numeric='UNDO REDO HINT PV AI ANALYZE RANDOM PERFT DIVIDE'.split(' ');
final active='FLIPS MOVE PLAY HINT PV AI SOLVE AUTOPLAY RANDOM MC DIVIDE'.split(' ');
final commands={
    ...zero,...numeric,...'LOAD TRANSFORM AUTOPLAY MC FLIPS MOVE PLAY RECORD'.split(' ')
};
String other(String s)=>s=='B'?'W':'B';
String name(int p)=>'${'abcdefgh'[p%8]}${p~/8+1}';
int square(String s)=>(int.parse(s[1])-1)*8+s.codeUnitAt(0)-97;
bool inside(int r,int c)=>r>=0&&r<8&&c>=0&&c<8;
String initial(){
    var b=List.filled(64,'.');
    b[27]=b[36]='W';
    b[28]=b[35]='B';
    return b.join();
}
List<int> flips(String b,String s,int p){
    if(b[p]!='.')return [];
    var out=<int>[];
    var row=p~/8;
    var col=p%8;
    for(var dr=-1;dr<=1;dr++){
        for(var dc=-1;dc<=1;dc++){
            if(dr==0&&dc==0)continue;
            var r=row+dr;
            var c=col+dc;
            var line=<int>[];
            while(inside(r,c)&&b[8*r+c]==other(s)){
                line.add(8*r+c);
                r+=dr;
                c+=dc;
            }
            if(line.isNotEmpty&&inside(r,c)&&b[8*r+c]==s)out.addAll(line);
        }
    }
    out.sort();
    return out;
}
List<int> legal(String b,String s)=>[for(var p=0;p<64;p++)if(b[p]=='.'&&flips(b,s,p).isNotEmpty)p];
String place(String b,String s,int p){
    var a=b.split('');
    for(var q in flips(b,s,p))a[q]=s;
    a[p]=s;
    return a.join();
}
int count(String b,String s)=>b.split('').where((x)=>x==s).length;
bool terminal(String b)=>legal(b,'B').isEmpty&&legal(b,'W').isEmpty;
String gameOver(String b){
    var x=count(b,'B');
    var y=count(b,'W');
    return 'game over B $x W $y ${x>y?'winner B':x<y?'winner W':'draw'}';
}
(int,int,int,int) evaluate(String b,String s){
    var w=0;
    for(var i=0;i<64;i++)w+=b[i]==s?weights[i]:b[i]==other(s)?-weights[i]:0;
    var own=legal(b,s).length;
    var enemy=legal(b,other(s)).length;
    return (w+10*(own-enemy),w,own,enemy);
}
final searchCache=<(String,String,int),int>{
};
final perftCache=<(String,String,int),int>{
};
int search(String b,String s,int d){
    var key=(b,s,d);
    if(searchCache.containsKey(key))return searchCache[key]!;
    var moves=legal(b,s);
    var o=other(s);
    int v;
    if(moves.isEmpty&&legal(b,o).isEmpty){
        v=(d<0?1:1000)*(count(b,s)-count(b,o));
    }else if(d==0){
        v=evaluate(b,s).$1;
    }else if(moves.isEmpty){
        v=-search(b,o,d<0?-1:d-1);
    }else{
        v=-1000000;
        for(var p in moves)v=math.max(v,-search(place(b,s,p),o,d<0?-1:d-1));
    }
    if(searchCache.length>300000)searchCache.clear();
    searchCache[key]=v;
    return v;
}
List<(int,int)> ranked(String b,String s,int d){
    var rows=[for(var p in legal(b,s))(-search(place(b,s,p),other(s),d<0?-1:d-1),p)];
    rows.sort((a,b)=>a.$1==b.$1?a.$2.compareTo(b.$2):b.$1.compareTo(a.$1));
    return rows;
}
(List<String>,String) variation(String b,String s,int d){
    var steps=<String>[];
    while(d!=0&&!terminal(b)){
        var moves=ranked(b,s,d);
        if(moves.isEmpty){
            steps.add('pass');
        }else{
            var p=moves[0].$2;
            steps.add(name(p));
            b=place(b,s,p);
        }
        s=other(s);
        if(d>0)d--;
    }
    return(steps,b);
}
int perft(String b,String s,int d){
    if(d==0)return 1;
    var key=(b,s,d);
    if(perftCache.containsKey(key))return perftCache[key]!;
    var moves=legal(b,s);
    var o=other(s);
    var n=0;
    if(moves.isEmpty){
        n=legal(b,o).isEmpty?1:perft(b,o,d-1);
    }else{
        for(var p in moves)n+=perft(place(b,s,p),o,d-1);
    }
    if(perftCache.length>200000)perftCache.clear();
    perftCache[key]=n;
    return n;
}
(int,int) stable(String b){
    var stable=List.filled(64,false);
    const axes=[(0,1),(1,0),(1,1),(1,-1)];
    while(true){
        var found=<int>[];
        for(var p=0;p<64;p++){
            if(b[p]=='.'||stable[p])continue;
            var ok=true;
            for(var (dr,dc) in axes){
                var full=true;
                var anchor=false;
                for(var sign in [-1,1]){
                    var r=p~/8+dr*sign;
                    var c=p%8+dc*sign;
                    if(!inside(r,c)||(stable[8*r+c]&&b[8*r+c]==b[p]))anchor=true;
                    while(inside(r,c)){
                        if(b[8*r+c]=='.')full=false;
                        r+=dr*sign;
                        c+=dc*sign;
                    }
                }
                if(!full&&!anchor){
                    ok=false;
                    break;
                }
            }
            if(ok)found.add(p);
        }
        if(found.isEmpty)break;
        for(var p in found)stable[p]=true;
    }
    return([for(var i=0;i<64;i++)if(stable[i]&&b[i]=='B')i].length,[for(var i=0;i<64;i++)if(stable[i]&&b[i]=='W')i].length);
}
int transform(int p,String op){
    var r=p~/8;
    var c=p%8;
    return switch(op){
        'rot90'=>8*c+7-r,'rot180'=>63-p,'rot270'=>8*(7-c)+r,'mirror'=>8*r+7-c,'flip'=>8*(7-r)+c,'diag'=>8*c+r,_=>8*(7-c)+7-r
    };
}
String transformBoard(String b,String op){
    var a=List.filled(64,'.');
    for(var p=0;p<64;p++)a[transform(p,op)]=b[p];
    return a.join();
}
class Minstd {
    int value;
    Minstd(this.value);
    int draw()=>value=value*48271%2147483647;
}
String randomGame(String b,String s,Minstd rng){
    while(true){
        var moves=legal(b,s);
        if(moves.isNotEmpty){
            b=place(b,s,moves[rng.draw()%moves.length]);
        }else if(legal(b,other(s)).isEmpty){
            return b;
        }
        s=other(s);
    }
}
String average(int f,int n){
    var v=100*f~/n;
    return '${v~/100}.${(v%100).toString().padLeft(2,'0')}';
}
class Position {
    final String board,side;
    final bool over;
    Position(this.board,this.side,this.over);
}
class Move {
    final String side;
    final int square,count;
    final bool passed;
    final Position before,after;
    Move(this.side,this.square,this.count,this.passed,this.before,this.after);
}
void emit(List<Object> xs)=>stdout.writeln(xs.join(' '));
class Othello {
    String board=initial();
    var side='B';
    bool over=false;
    List<Move> history=[];
    List<Move> redo=[];
    void reset(){
        board=initial();
        side='B';
        over=false;
        history=[];
        redo=[];
    }
    Position snapshot()=>Position(board,side,over);
    void restore(Position p){
        board=p.board;
        side=p.side;
        over=p.over;
    }
    String status()=>over?gameOver(board):'$side to move';
    bool adjust([bool quiet=false]){
        if(legal(board,side).isNotEmpty)return false;
        if(legal(board,other(side)).isNotEmpty){
            if(!quiet)emit([side,'passes']);
            side=other(side);
            return true;
        }
        over=true;
        if(!quiet)emit([gameOver(board)]);
        return false;
    }
    bool move(int p,[bool quiet=false,int? value]){
        var before=snapshot();
        var s=side;
        var k=flips(board,side,p).length;
        board=place(board,s,p);
        if(!quiet)emit([s,name(p),'flips',k,if(value!=null)...['value',value]]);
        side=other(s);
        var passed=adjust(quiet);
        history.add(Move(s,p,k,passed,before,snapshot()));
        redo=[];
        return passed;
    }
    String reason(int p)=>over?'game over':board[p]!='.'?'occupied':flips(board,side,p).isEmpty?'no flips':'';
    void record(String text){
        var e=Othello();
        var ps=<int>[];
        var passes=0;
        for(var i=0;i<text.length;i+=2){
            var p=square(text.substring(i,i+2));
            var why=e.reason(p);
            if(why.isNotEmpty){
                emit(['ILLEGAL move',i~/2+1,name(p),why]);
                return;
            }
            ps.add(p);
            if(e.move(p,true))passes++;
        }
        restore(e.snapshot());
        history=e.history;
        redo=[];
        var op={
            'f5':'','e6':'diag','d3':'anti','c4':'rot180'
        }
        [name(ps[0])]!;
        emit(['record',ps.length,'moves',passes,'passes']);
        emit(['normal',ps.map((p)=>name(op.isEmpty?p:transform(p,op))).join()]);
        emit([status()]);
    }
    void sheet(){
        var fields=(history.isEmpty?board:history[0].before.board).split('');
        for(var i=0;i<history.length;i++)fields[history[i].square]='${i+1}';
        emit([' ${'abcdefgh'.split('').map((c)=>c.padLeft(3)).join()}']);
        for(var r=0;r<8;r++)emit(['${r+1}${fields.sublist(8*r,8*r+8).map((x)=>x.padLeft(3)).join()}']);
    }
    void stats(){
        var total=history.fold(0,(s,r)=>s+r.count);
        if(history.isEmpty){
            emit(['moves 0']);
        }else{
            emit(['moves',history.length,'flips',total,'avg',average(total,history.length),'passes',history.where((r)=>r.passed).length]);
        }
        for(var s in ['B','W']){
            var rows=history.where((r)=>r.side==s).toList();
            if(rows.isEmpty){
                emit([s,'moves 0']);
                continue;
            }
            var sum=rows.fold(0,(s,r)=>s+r.count);
            var maximum=rows.map((r)=>r.count).reduce(math.max);
            emit([s,'moves',rows.length,'flips',sum,'avg',average(sum,rows.length),'max',maximum,name(rows.firstWhere((r)=>r.count==maximum).square),'corners',rows.where((r)=>[0,7,56,63].contains(r.square)).length]);
        }
    }
    void autoplay(int black,int white,[int seed=0]){
        var rng=Minstd(seed);
        var ps=<String>[];
        var passes=0;
        while(!over){
            var moves=legal(board,side);
            var p=seed!=0?moves[rng.draw()%moves.length]:ranked(board,side,side=='B'?black:white)[0].$2;
            ps.add(name(p));
            if(move(p,true))passes++;
        }
        emit([seed!=0?'random':'autoplay',ps.length,'moves',passes,'passes']);
        emit(['moves',ps.join()]);
        emit([gameOver(board)]);
    }
    void monteCarlo(int k,int seed){
        var rng=Minstd(seed);
        var best=-1;
        var bp=-1;
        for(var p in legal(board,side)){
            var w=0;
            var d=0;
            var l=0;
            var start=place(board,side,p);
            for(var i=0;i<k;i++){
                var b=randomGame(start,other(side),rng);
                var diff=count(b,side)-count(b,other(side));
                if(diff>0){
                    w++;
                }else if(diff<0){
                    l++;
                }else{
                    d++;
                }
            }
            emit([name(p),w,d,l]);
            if(2*w+d>best){
                best=2*w+d;
                bp=p;
            }
        }
        emit(['best',name(bp),best]);
    }
    void execute(String text){
        var words=text.split(' ');
        var cmd=words[0];
        var a=words.sublist(1);
        var error='';
        if(!commands.contains(cmd)){
            error='unknown command';
        }else if(cmd=='LOAD'){
            if(a.length!=2||!RegExp(r'^[.BW]{64}$').hasMatch(a[0])||!['B','W'].contains(a[1]))error='bad board';
        }else if(['MOVE','FLIPS'].contains(cmd)){
            if(a.length!=1){
                error='bad arguments';
            }else if(!RegExp(r'^[a-h][1-8]$').hasMatch(a[0])){
                error='bad square';
            }
        }else if(['PLAY','RECORD'].contains(cmd)){
            if(a.length!=1){
                error='bad arguments';
            }else if(a[0].length>120||!RegExp(r'^([a-h][1-8])+$').hasMatch(a[0])){
                error='bad record';
            }
        }else if(zero.contains(cmd)){
            if(a.isNotEmpty)error='bad arguments';
        }else if(cmd=='TRANSFORM'){
            if(a.length!=1||!transforms.contains(a[0]))error='bad arguments';
        }else{
            var expected=['AUTOPLAY','MC'].contains(cmd)?2:1;
            var valid=a.length==expected&&a.every((s)=>RegExp(r'^[0-9]+$').hasMatch(s));
            if(valid){
                var ns=a.map(int.parse).toList();
                var n=ns[0];
                valid=switch(cmd){
                    'AUTOPLAY'=>ns.every((n)=>n>=1&&n<=4),'HINT'||'PV'||'AI'||'ANALYZE'=>n>=1&&n<=4,'PERFT'||'DIVIDE'=>n>=1&&n<=8,'MC'=>n>=1&&n<=100&&ns[1]>=1&&ns[1]<=2147483646,'RANDOM'=>n>=1&&n<=2147483646,_=>n>=1
                };
            }
            if(!valid)error='bad arguments';
        }
        if(error.isNotEmpty){
            emit(['ERROR',error]);
            return;
        }
        if(over&&active.contains(cmd)){
            emit(['ERROR game over']);
            return;
        }
        var n=a.isEmpty?0:int.tryParse(a[0])??0;
        switch(cmd){
            case 'NEW':{
                reset();
                emit(['OK']);
                break;
            }
            case 'LOAD':{
                board=a[0];
                side=a[1];
                over=false;
                history=[];
                redo=[];
                emit(['OK']);
                adjust();
                break;
            }
            case 'DUMP':{
                emit(['board',board,side]);
                break;
            }
            case 'SHOW':{
                emit(['  a b c d e f g h']);
                var ms=over?<int>[]:legal(board,side);
                for(var r=0;r<8;r++)emit([r+1,for(var c=0;c<8;c++)ms.contains(8*r+c)?'*':board[8*r+c]]);
                emit([status()]);
                break;
            }
            case 'SCORE':{
                emit(['score B',count(board,'B'),'W',count(board,'W'),'empty',count(board,'.')]);
                break;
            }
            case 'LEGAL':{
                var ms=over?<int>[]:legal(board,side);
                emit(['legal',ms.length,...ms.map(name)]);
                break;
            }
            case 'MOVE':case 'FLIPS':{
                var p=square(a[0]);
                var why=reason(p);
                if(why.isNotEmpty){
                    emit(['ILLEGAL',why]);
                }else if(cmd=='MOVE'){
                    move(p);
                }else{
                    var f=flips(board,side,p);
                    emit(['flips',a[0],f.length,...f.map(name)]);
                }
                break;
            }
            case 'PLAY':{
                for(var i=0;i<a[0].length;i+=2){
                    var p=square(a[0].substring(i,i+2));
                    var why=reason(p);
                    if(why.isNotEmpty){
                        emit(['ILLEGAL move',i~/2+1,name(p),why]);
                        break;
                    }
                    move(p);
                }
                break;
            }
            case 'RECORD':{
                record(a[0]);
                break;
            }
            case 'UNDO':{
                if(n>history.length){
                    emit(['ERROR cannot undo']);
                }else{
                    var removed=history.sublist(history.length-n);
                    restore(removed[0].before);
                    history.removeRange(history.length-n,history.length);
                    redo=[...removed,...redo];
                    emit([status()]);
                }
                break;
            }
            case 'REDO':{
                if(n>redo.length){
                    emit(['ERROR cannot redo']);
                }else{
                    var added=redo.sublist(0,n);
                    redo.removeRange(0,n);
                    history.addAll(added);
                    restore(added.last.after);
                    emit([status()]);
                }
                break;
            }
            case 'HISTORY':{
                emit(['history',history.length]);
                for(var i=0;i<history.length;i++){
                    var r=history[i];
                    emit([i+1,r.side,name(r.square),r.count,if(r.passed)'pass']);
                }
                break;
            }
            case 'SHEET':{
                sheet();
                break;
            }
            case 'STATS':{
                stats();
                break;
            }
            case 'TRANSFORM':{
                var op=a[0];
                board=transformBoard(board,op);
                Move tr(Move r)=>Move(r.side,transform(r.square,op),r.count,r.passed,Position(transformBoard(r.before.board,op),r.before.side,r.before.over),Position(transformBoard(r.after.board,op),r.after.side,r.after.over));
                history=history.map(tr).toList();
                redo=redo.map(tr).toList();
                emit(['OK']);
                break;
            }
            case 'EVAL':{
                var (v,w,x,y)=evaluate(board,side);
                emit(['eval',v,'weights',w,'mobility',x,y]);
                break;
            }
            case 'STABLE':{
                var (b,w)=stable(board);
                emit(['stable B',b,'W',w]);
                break;
            }
            case 'HINT':{
                for(var (v,p) in ranked(board,side,n))emit([name(p),v]);
                break;
            }
            case 'PV':{
                var (steps,_)=variation(board,side,n);
                emit(['pv',search(board,side,n),...steps]);
                break;
            }
            case 'AI':{
                var (v,p)=ranked(board,side,n)[0];
                move(p,false,v);
                break;
            }
            case 'ANALYZE':{
                var loss={
                    'B':0,'W':0
                };
                for(var i=0;i<history.length;i++){
                    var r=history[i];
                    var rows=ranked(history[i].before.board,history[i].side,n);
                    var (best,bp)=rows[0];
                    var value=rows.firstWhere((x)=>x.$2==r.square).$1;
                    loss[r.side]=loss[r.side]!+best-value;
                    emit([i+1,r.side,name(r.square),value,'best',name(bp),best]);
                }
                emit(['loss B',loss['B']!,'W',loss['W']!]);
                break;
            }
            case 'SOLVE':{
                if(count(board,'.')>=9){
                    emit(['ERROR too many empties']);
                }else{
                    for(var (v,p) in ranked(board,side,-1))emit([name(p),v]);
                    var (steps,b)=variation(board,side,-1);
                    emit(['line',...steps]);
                    emit(['final B',count(b,'B'),'W',count(b,'W')]);
                }
                break;
            }
            case 'AUTOPLAY':{
                autoplay(n,int.parse(a[1]));
                break;
            }
            case 'RANDOM':{
                autoplay(0,0,n);
                break;
            }
            case 'MC':{
                monteCarlo(n,int.parse(a[1]));
                break;
            }
            case 'PERFT':{
                emit(['perft',n,perft(board,side,n)]);
                break;
            }
            case 'DIVIDE':{
                var total=0;
                for(var p in legal(board,side)){
                    var value=perft(place(board,side,p),other(side),n-1);
                    emit([name(p),value]);
                    total+=value;
                }
                emit(['total',total]);
                break;
            }
        }
    }
}
void main(){
    var e=Othello();
    var n=int.parse(stdin.readLineSync()!);
    for(var i=0;i<n;i++)e.execute(stdin.readLineSync()!);
}
