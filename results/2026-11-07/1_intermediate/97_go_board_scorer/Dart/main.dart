import 'dart:io';
const columns='ABCDEFGHJKLMNOPQRST';
const handicapPoints={
    9:['C3','G7','C7','G3','C5','G5','E3','E7','E5'],13:['D4','K10','D10','K4','D7','K7','G4','G10','G7'],19:['D4','Q16','D16','Q4','D10','Q10','K4','K16','K10']
};
const arity={
    'BOARD':2,'KOMI':1,'SUPERKO':1,'HANDICAP':1,'PLAY':2,'PASS':1,'REPLAY':1,'UNDO':0,'SHOW':0,'MAP':0,'STATUS':0,'CAPTURES':0,'HISTORY':0,'MOVES':0,'GROUP':1,'GROUPS':0,'ATARI':0,'LEGAL':1,'EYES':1,'SAFE':1,'LADDER':1,'DEAD':1,'REGIONS':0,'SCORE':1
};
String other(String c)=>c=='B'?'W':'B';
String half(int x)=>(x<0?'-':'')+'${x.abs()~/2}'+(x.abs().isOdd?'.5':'.0');
void emit(List<Object>a)=>stdout.writeln(a.join(' '));
List<int> ordered(Set<int>s)=>s.toList()..sort();
int? komi(String s){
    if(!RegExp(r'^-?(0|[1-9][0-9]*)(?:\.[05])?$').hasMatch(s))return null;
    final negative=s.startsWith('-'),parts=(negative?s.substring(1):s).split('.');
    final whole=int.tryParse(parts[0]);
    if(whole==null||whole>100)return null;
    final x=2*whole+(parts.length==2&&parts[1]=='5'?1:0);
    return negative&&x==0?null:negative?-x:x;
}
List<int> adjacent(int p,int n,[bool diagonal=false]){
    final r=p~/n,c=p%n;
    final steps=diagonal?[(-1,-1),(-1,1),(1,-1),(1,1)]:[(-1,0),(1,0),(0,-1),(0,1)];
    return[for(final(dr,dc) in steps)if(r+dr>=0&&r+dr<n&&c+dc>=0&&c+dc<n)(r+dr)*n+c+dc];
}
Set<int> flood(List<String>b,int n,int p,Set<String>allowed){
    final seen={
        p
    },todo=[p];
    while(todo.isNotEmpty){
        for(final q in adjacent(todo.removeLast(),n)){
            if(!seen.contains(q)&&allowed.contains(b[q])){
                seen.add(q);
                todo.add(q);
            }
        }
    }
    return seen;
}
final class Group {
    final String color;
    final int first;
    final Set<int>stones,liberties;
    Group(this.color,this.first,this.stones,this.liberties);
}
Group group(List<String>b,int n,int p){
    final s=flood(b,n,p,{
        b[p]
    }),l=<int>{
    };
    for(final q in s){
        for(final t in adjacent(q,n)){
            if(b[t]=='.')l.add(t);
        }
    }
    return Group(b[p],ordered(s).first,s,l);
}
List<Group> groups(List<String>b,int n,[String? color]){
    final out=<Group>[],seen=<int>{
    };
    for(var p=0;p<b.length;p++){
        if(b[p]!='.'&&!seen.contains(p)&&(color==null||b[p]==color)){
            final g=group(b,n,p);
            seen.addAll(g.stones);
            out.add(g);
        }
    }
    return out;
}
final class Placement {
    final List<String>board;
    final int captured;
    final String reason;
    Placement(this.board,this.captured,this.reason);
}
Placement placement(List<String>b,int n,String c,int p){
    if(b[p]!='.')return Placement(b,0,'occupied');
    final next=List<String>.of(b);
    next[p]=c;
    var captured=0;
    final seen=<int>{
    };
    for(final q in adjacent(p,n)){
        if(next[q]==other(c)&&!seen.contains(q)){
            final g=group(next,n,q);
            seen.addAll(g.stones);
            if(g.liberties.isEmpty){
                for(final t in g.stones){
                    next[t]='.';
                }
                captured+=g.stones.length;
            }
        }
    }
    return Placement(next,captured,group(next,n,p).liberties.isEmpty?'suicide':'');
}
final class Region {
    final int first;
    final Set<int>points;
    final String owner;
    Region(this.first,this.points,this.owner);
}
List<Region> regions(List<String>b,int n){
    final out=<Region>[],seen=<int>{
    };
    for(var p=0;p<b.length;p++){
        if(b[p]=='.'&&!seen.contains(p)){
            final points=flood(b,n,p,{
                '.'
            }),border=<String>{
            };
            seen.addAll(points);
            for(final q in points){
                for(final t in adjacent(q,n)){
                    if(b[t]!='.')border.add(b[t]);
                }
            }
            out.add(Region(p,points,border.length==1?border.first:'neutral'));
        }
    }
    return out;
}
List<Group> safeGroups(List<String>b,int n,String c){
    final own=groups(b,n,c),touch=<Set<int>>[],vital=<Set<int>>[],seen=<int>{
    };
    for(var p=0;p<b.length;p++){
        if(b[p]!=c&&!seen.contains(p)){
            final area=flood(b,n,p,{
                '.',other(c)
            }),empty=<int>{
            };
            seen.addAll(area);
            for(final q in area){
                if(b[q]=='.')empty.add(q);
            }
            final t=<int>{
            },v=<int>{
            };
            for(var i=0;i<own.length;i++){
                if(area.any((q)=>adjacent(q,n).any(own[i].stones.contains)))t.add(i);
                if(empty.every(own[i].liberties.contains))v.add(i);
            }
            touch.add(t);
            vital.add(v);
        }
    }
    final s=Set<int>.from(List.generate(own.length,(i)=>i)),a=Set<int>.from(List.generate(touch.length,(i)=>i));
    while(true){
        final before=s.length+a.length;
        s.removeWhere((i)=>a.where((j)=>vital[j].contains(i)).length<2);
        a.removeWhere((j)=>!touch[j].every(s.contains));
        if(before==s.length+a.length)break;
    }
    return ordered(s).map((i)=>own[i]).toList();
}
(String,int) ladder(List<String>b,int n,int p){
    final defender=b[p],attacker=other(defender),memo=<(String,int,bool),(bool,int)>{
    };
    (bool,int) read(List<String>current,int depth,bool defending){
        if(depth>=40)return(defending,-1);
        final key=(current.join(),depth,defending),known=memo[key];
        if(known!=null)return known;
        final g=group(current,n,p),candidates=Set<int>.of(g.liberties),seen=<int>{
        };
        if(defending){
            for(final q in g.stones){
                for(final t in adjacent(q,n)){
                    if(current[t]==attacker&&!seen.contains(t)){
                        final e=group(current,n,t);
                        seen.addAll(e.stones);
                        if(e.liberties.length==1)candidates.addAll(e.liberties);
                    }
                }
            }
        }
        for(final q in ordered(candidates)){
            final next=placement(current,n,defending?defender:attacker,q);
            if(next.reason.isNotEmpty)continue;
            bool success;
            if(defending){
                final m=group(next.board,n,p).liberties.length;
                success=m>=3||(m==2&&!read(next.board,depth+1,false).$1);
            }else{
                success=!read(next.board,depth+1,true).$1;
            }
            if(success)return memo[key]=(true,q);
        }
        return memo[key]=(false,-1);
    }
    final count=group(b,n,p).liberties.length;
    if(count>=3)return('safe',-1);
    final(success,move)=read(b,0,count==1);
    return((count==1?success:!success)?'escapes':'captured',move);
}
final class Snapshot {
    final List<String>board;
    final String turn;
    final Map<String,int>captures;
    final int passes;
    final bool over;
    Snapshot(this.board,this.turn,this.captures,this.passes,this.over);
}
final class Move {
    final String color;
    final int point,captured;
    final Snapshot before;
    Move(this.color,this.point,this.captured,this.before);
}
final class Game {
    int n=19,komi2=13,passes=0;
    List<String>board=List.filled(361,'.');
    String turn='B';
    Map<String,int>captures={
        'B':0,'W':0
    };
    bool over=false,superko=false;
    List<int>handicap=[];
    List<Move>history=[];
    late List<List<String>>positions=[board];
    Set<int>dead={
    };
    void reset(int size,int k){
        n=size;
        komi2=k;
        board=List.filled(n*n,'.');
        turn='B';
        captures={
            'B':0,'W':0
        };
        passes=0;
        over=false;
        handicap=[];
        history=[];
        positions=[board];
        dead.clear();
    }
    int point(String s){
        if(!RegExp(r'^[A-HJ-T](?:[1-9]|1[0-9])$').hasMatch(s))return -1;
        final c=columns.indexOf(s[0]),r=int.parse(s.substring(1));
        return c<n&&r<=n?(r-1)*n+c:-1;
    }
    String name(int p)=>columns[p%n]+'${p~/n+1}';
    String sgf(int p)=>String.fromCharCodes([97+p%n,97+n-1-p~/n]);
    Placement check(String c,int p){
        final r=placement(board,n,c,p);
        var reason=r.reason;
        final text=r.board.join();
        if(reason.isEmpty&&positions.length>=2&&text==positions[positions.length-2].join())reason='ko';
        if(reason.isEmpty&&superko&&positions.any((b)=>text==b.join()))reason='superko';
        return Placement(r.board,r.captured,reason);
    }
    int move(String c,int p,[Placement? checked]){
        final before=Snapshot(board,turn,Map.of(captures),passes,over);
        var captured=0;
        if(p<0){
            passes++;
            if(passes==2)over=true;
        }else{
            final r=checked??check(c,p);
            board=r.board;
            captured=r.captured;
            captures[c]=captures[c]!+captured;
            passes=0;
        }
        turn=other(c);
        history.add(Move(c,p,captured,before));
        positions.add(board);
        dead.clear();
        return captured;
    }
    List<String> clean()=>[for(var p=0;p<board.length;p++)dead.contains(p)?'.':board[p]];
    void show([bool map=false]){
        final b=map?clean():board,chars=List<String>.of(map?clean():board),stars=<int>{
        };
        for(var i=0;i<9;i++){
            if(n==19||i<4||i==8)stars.add(point(handicapPoints[n]![i]));
        }
        if(map){
            for(final r in regions(b,n)){
                for(final p in r.points){
                    chars[p]=r.owner=='B'?'x':r.owner=='W'?'o':'.';
                }
            }
        }
        for(var p=0;p<b.length;p++){
            if(b[p]!='.'){
                final c=b[p]=='B'?'X':'O';
                chars[p]=!map&&dead.contains(p)?c.toLowerCase():c;
            }else if(!map){
                chars[p]=stars.contains(p)?'+':'.';
            }
        }
        final header='   '+columns.substring(0,n).split('').join(' ');
        emit([header]);
        for(var r=n;r>=1;r--){
            emit(['$r'.padLeft(2),chars.sublist((r-1)*n,r*n).join(' '),r]);
        }
        emit([header]);
    }
    void score(String method){
        final b=clean(),territory={
            'B':0,'W':0
        },total=<String,int>{
        };
        for(final r in regions(b,n)){
            if(r.owner!='neutral')territory[r.owner]=territory[r.owner]!+r.points.length;
        }
        for(final c in ['B','W']){
            List<Object>fields;
            if(method=='AREA'){
                final stones=b.where((s)=>s==c).length;
                total[c]=2*(stones+territory[c]!)+(c=='W'?komi2:0);
                fields=[c,'stones',stones,'territory',territory[c]!];
            }else{
                final prisoners=captures[c]!+dead.where((p)=>board[p]==other(c)).length;
                total[c]=2*(territory[c]!+prisoners)+(c=='W'?komi2:0);
                fields=[c,'territory',territory[c]!,'prisoners',prisoners];
            }
            if(c=='W')fields.addAll(['komi',half(komi2)]);
            fields.addAll(['total',half(total[c]!)]);
            emit(fields);
        }
        final d=total['B']!-total['W']!;
        emit(['result',d>0?'B+'+half(d):d<0?'W+'+half(-d):'Draw']);
    }
    void execute(String line){
        final words=line.split(' '),c=words[0],a=words.sublist(1);
        if(!arity.containsKey(c)){
            emit(['ERROR unknown command']);
            return;
        }
        if(a.length!=arity[c]){
            emit(['ERROR bad arguments']);
            return;
        }
        final valid=switch(c){
            'BOARD'=>{
                '9','13','19'
            }.contains(a[0])&&komi(a[1])!=null,'KOMI'=>komi(a[0])!=null,'SUPERKO'=>{
                'ON','OFF'
            }.contains(a[0]),'HANDICAP'=>RegExp(r'^[2-9]$').hasMatch(a[0]),'PLAY'||'PASS'||'LEGAL'||'EYES'||'SAFE'=>{
                'B','W'
            }.contains(a[0]),'SCORE'=>{
                'AREA','TERRITORY'
            }.contains(a[0]),_=>true
        };
        if(!valid){
            emit(['ERROR bad arguments']);
            return;
        }
        var p=-1;
        if({
            'PLAY','GROUP','LADDER','DEAD'
        }.contains(c)){
            p=point(a[c=='PLAY'?1:0]);
            if(p<0){
                emit(['ERROR bad point']);
                return;
            }
        }
        final records=<(String,int)>[];
        if(c=='REPLAY'){
            if(!RegExp(r'^(?:;[BW]\[[a-z]{0,2}\])+$').hasMatch(a[0])){
                emit(['ERROR bad sequence']);
                return;
            }
            for(final m in RegExp(r';([BW])\[([a-z]*)\]').allMatches(a[0])){
                final text=m[2]!;
                if(text.isNotEmpty&&(text.length!=2||text.codeUnits.any((ch)=>ch-97>=n))){
                    emit(['ERROR bad sequence']);
                    return;
                }
                records.add((m[1]!,text.isEmpty?-1:(n-1-(text.codeUnitAt(1)-97))*n+text.codeUnitAt(0)-97));
            }
        }
        if({
            'PLAY','PASS','REPLAY'
        }.contains(c)&&over){
            emit(['ERROR game over']);
            return;
        }
        switch(c){
            case 'BOARD': {
                reset(int.parse(a[0]),komi(a[1])!);
                emit(['board',n,'komi',half(komi2)]);
                break;
            }
            case 'KOMI': {
                komi2=komi(a[0])!;
                emit(['komi',half(komi2)]);
                break;
            }
            case 'SUPERKO': {
                superko=a[0]=='ON';
                emit(['superko',superko?'on':'off']);
                break;
            }
            case 'HANDICAP': {
                if(history.isNotEmpty||board.any((s)=>s!='.')){
                    emit(['ERROR handicap not allowed']);
                    return;
                }
                final k=int.parse(a[0]),ix=k==5?[0,1,2,3,8]:k==7?[0,1,2,3,4,5,8]:List.generate(k,(i)=>i);
                handicap=ix.map((i)=>point(handicapPoints[n]![i])).toList();
                board=List.of(board);
                for(final q in handicap){
                    board[q]='B';
                }
                turn='W';
                positions=[board];
                dead.clear();
                emit(['handicap',k,...handicap.map(name)]);
                break;
            }
            case 'PLAY': {
                final color=a[0],r=check(a[0],p),reason=color!=turn?'turn':r.reason;
                if(reason.isNotEmpty){
                    emit(['ILLEGAL',color,a[1],reason]);
                }else{
                    final count=move(color,p,r);
                    emit([color,a[1],if(count>0)...['captures',count]]);
                }
                break;
            }
            case 'PASS': {
                if(a[0]!=turn){
                    emit(['ILLEGAL',a[0],'pass turn']);
                }else{
                    move(a[0],-1);
                    emit([a[0],'pass']);
                    if(over)emit(['game over']);
                }
                break;
            }
            case 'REPLAY': {
                var played=0;
                List<Object>stop=[];
                for(final(color,q) in records){
                    final next=q<0?null:check(color,q),reason=over?'game over':color!=turn?'turn':next?.reason??'';
                    if(reason.isNotEmpty){
                        stop=['stopped',color,q<0?'pass':name(q),reason];
                        break;
                    }
                    move(color,q,next);
                    played++;
                }
                emit(['replay',played,'moves',...stop]);
                if(over)emit(['game over']);
                break;
            }
            case 'UNDO': {
                if(history.isEmpty){
                    emit(['ERROR nothing to undo']);
                    return;
                }
                final m=history.removeLast(),s=m.before;
                board=s.board;
                turn=s.turn;
                captures=Map.of(s.captures);
                passes=s.passes;
                over=s.over;
                positions.removeLast();
                dead.clear();
                emit(['undo',m.color,m.point<0?'pass':name(m.point)]);
                break;
            }
            case 'SHOW': {
                show();
                break;
            }
            case 'MAP': {
                show(true);
                break;
            }
            case 'STATUS': {
                emit(['size',n,'komi',half(komi2),'handicap',handicap.length,'superko',superko?'on':'off']);
                emit(['moves',history.length,...(over?['game over']:['next',turn,'passes',passes])]);
                break;
            }
            case 'CAPTURES': {
                emit(['captures B',captures['B']!,'W',captures['W']!]);
                break;
            }
            case 'HISTORY': {
                emit(['history',history.length]);
                for(var i=0;i<history.length;i++){
                    final m=history[i];
                    emit([i+1,m.color,m.point<0?'pass':name(m.point),if(m.captured>0)...['captures',m.captured]]);
                }
                break;
            }
            case 'MOVES': {
                var record='(;GM[1]FF[4]SZ[$n]KM[${half(komi2)}]';
                if(handicap.isNotEmpty)record+='HA[${handicap.length}]AB'+handicap.map((q)=>'[${sgf(q)}]').join();
                record+=history.map((m)=>';${m.color}[${m.point<0?'':sgf(m.point)}]').join();
                emit([record+')']);
                break;
            }
            case 'GROUP'||'DEAD'||'LADDER': {
                if(board[p]=='.'){
                    emit(['ERROR no stone']);
                    return;
                }
                final g=group(board,n,p);
                if(c=='GROUP'){
                    emit(['group',g.color,name(g.first),'size',g.stones.length,'liberties',g.liberties.length]);
                    emit(['stones',...ordered(g.stones).map(name)]);
                    emit(['liberties',...ordered(g.liberties).map(name)]);
                }else if(c=='DEAD'){
                    final alive=dead.contains(p);
                    if(alive){
                        dead.removeAll(g.stones);
                    }else{
                        dead.addAll(g.stones);
                    }
                    emit([alive?'alive':'dead',g.color,name(g.first),'size',g.stones.length]);
                }else{
                    final(status,q)=ladder(board,n,p);
                    emit(['ladder',a[0],status,if(q>=0)name(q)]);
                }
                break;
            }
            case 'GROUPS': {
                final gs=groups(board,n);
                emit(['groups',gs.length]);
                for(final g in gs){
                    emit([g.color,name(g.first),'size',g.stones.length,'liberties',g.liberties.length,if(dead.contains(g.first))'dead']);
                }
                break;
            }
            case 'ATARI': {
                final gs=groups(board,n).where((g)=>g.liberties.length==1).toList();
                if(gs.isEmpty)emit(['atari none']);
                for(final g in gs){
                    emit(['atari',g.color,name(g.first),'size',g.stones.length,'at',name(g.liberties.first)]);
                }
                break;
            }
            case 'LEGAL': {
                final rejected=<(String,String)>[];
                var legal=0;
                for(var q=0;q<board.length;q++){
                    if(board[q]=='.'){
                        final reason=check(a[0],q).reason;
                        if(reason.isEmpty){
                            legal++;
                        }else{
                            rejected.add((name(q),reason));
                        }
                    }
                }
                emit(['legal',a[0],legal]);
                for(final(q,reason) in rejected){
                    emit([q,reason]);
                }
                break;
            }
            case 'EYES': {
                final found=<(String,String)>[];
                for(var q=0;q<board.length;q++){
                    if(board[q]=='.'){
                        final ns=adjacent(q,n);
                        if(ns.every((t)=>board[t]==a[0])){
                            final enemies=adjacent(q,n,true).where((t)=>board[t]==other(a[0])).length;
                            found.add((name(q),enemies<=(ns.length==4?1:0)?'real':'false'));
                        }
                    }
                }
                emit(['eyes',a[0],found.length]);
                for(final(q,kind) in found){
                    emit([q,kind]);
                }
                break;
            }
            case 'SAFE': {
                final gs=safeGroups(board,n,a[0]);
                emit(['safe',a[0],gs.length]);
                for(final g in gs){
                    emit([name(g.first),'size',g.stones.length]);
                }
                break;
            }
            case 'REGIONS': {
                final rs=regions(clean(),n);
                emit(['regions',rs.length]);
                for(final r in rs){
                    emit([name(r.first),'size',r.points.length,r.owner]);
                }
                break;
            }
            case 'SCORE': {
                score(a[0]);
                break;
            }
        }
    }
}
void main(){
    final g=Game();
    final count=int.parse(stdin.readLineSync()!);
    for(var i=0;i<count;i++){
        g.execute(stdin.readLineSync()!);
    }
}
