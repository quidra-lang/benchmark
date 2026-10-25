import 'dart:io';
import 'dart:math' as math;

const kinds = 'IOTSZJL';
const operations = ['L', 'R', 'LL', 'RR', 'SD', 'DD', 'CW', 'CCW', 'HD', 'LOCK', 'HOLD'];
const commands = ['NEW', 'PRINT', 'NEXT', 'PREVIEW', 'STATUS', 'ANALYZE', 'ROW', 'GARBAGE', 'ATTACK', 'TICK', 'UNDO', 'SAVE', 'LOAD', 'SPINS', 'HINT', 'AUTO'];
const afterEnd = ['PRINT', 'NEXT', 'PREVIEW', 'STATUS', 'ANALYZE', 'LOAD'];
const states = '0R2L';
const clearNames = ['SINGLE', 'DOUBLE', 'TRIPLE', 'TETRIS', 'TSPIN_MINI', 'TSPIN_MINI_SINGLE', 'TSPIN_MINI_DOUBLE', 'TSPIN', 'TSPIN_SINGLE', 'TSPIN_DOUBLE', 'TSPIN_TRIPLE'];
const frames = [
  ['....', '####', '....', '....'], ['##', '##'], ['.#.', '###', '...'],
  ['.##', '##.', '...'], ['##.', '.##', '...'], ['#..', '###', '...'], ['..#', '###', '...'],
];
const ordinaryKicks = [
  [[0,0],[-1,0],[-1,1],[0,-2],[-1,-2]],
  [[0,0],[1,0],[1,-1],[0,2],[1,2]],
  [[0,0],[1,0],[1,-1],[0,2],[1,2]],
  [[0,0],[-1,0],[-1,1],[0,-2],[-1,-2]],
  [[0,0],[1,0],[1,1],[0,-2],[1,-2]],
  [[0,0],[-1,0],[-1,-1],[0,2],[-1,2]],
  [[0,0],[-1,0],[-1,-1],[0,2],[-1,2]],
  [[0,0],[1,0],[1,1],[0,-2],[1,-2]],
];
const iKicks = [
  [[0,0],[-2,0],[1,0],[-2,-1],[1,2]],
  [[0,0],[2,0],[-1,0],[2,1],[-1,-2]],
  [[0,0],[-1,0],[2,0],[-1,2],[2,-1]],
  [[0,0],[1,0],[-2,0],[1,-2],[-2,1]],
  [[0,0],[2,0],[-1,0],[2,1],[-1,-2]],
  [[0,0],[-2,0],[1,0],[-2,-1],[1,2]],
  [[0,0],[1,0],[-2,0],[1,-2],[-2,1]],
  [[0,0],[-1,0],[2,0],[-1,2],[2,-1]],
];
const kickStates = [[0,1],[1,0],[1,2],[2,1],[2,3],[3,2],[3,0],[0,3]];

class Position {
  final int s;
  final int x;
  final int y;
  const Position(this.s, this.x, this.y);
  String get key => '$s,$x,$y';
  Position translate(int dx, int dy) => Position(s,x+dx,y+dy);
}
class Cell {
  final int x;
  final int y;
  const Cell(this.x,this.y);
}
class Movement {
  final Position position;
  final int test;
  const Movement(this.position,this.test);
}
class Metrics {
  final List<int> heights;
  final int holes;
  final int bumpiness;
  final int value;
  Metrics(this.heights,this.holes,this.bumpiness,this.value);
}
class ClearInfo {
  final int name;
  final int points;
  final int sent;
  ClearInfo(this.name,this.points,this.sent);
}
class Statistics {
  int drops=0,holds=0,operationCount=0,faults=0,perfect=0,sent=0,cancelled=0,received=0,combo=0,chain=0;
  List<int> kinds=List.filled(7,0),clears=List.filled(11,0);
  Statistics copy() {
    final result=Statistics();
    result.drops=drops;result.holds=holds;result.operationCount=operationCount;result.faults=faults;
    result.perfect=perfect;result.sent=sent;result.cancelled=cancelled;result.received=received;
    result.combo=combo;result.chain=chain;result.kinds=List.of(kinds);result.clears=List.of(clears);
    return result;
  }
}
class GameState {
  List<int> board=List.filled(22,0);
  int random;
  List<int> queue=[];
  int? hold;
  bool usedHold=false;
  int kind=0;
  Position position=const Position(0,4,22);
  int last=0,test=0,keys=0,drop=0,fall=0,ground=0,resets=0,lowest=0;
  int initialLevel,level,score=0,lines=0,pieces=0,streak=0,chain=0;
  List<int> pending=[];
  bool ended=false;
  Statistics stats=Statistics();
  GameState(this.random,this.initialLevel,this.level);
  GameState copy() {
    final r=GameState(random,initialLevel,level);
    r.board=List.of(board);r.queue=List.of(queue);r.hold=hold;r.usedHold=usedHold;r.kind=kind;
    r.position=position;r.last=last;r.test=test;r.keys=keys;r.drop=drop;r.fall=fall;
    r.ground=ground;r.resets=resets;r.lowest=lowest;
    r.score=score;r.lines=lines;r.pieces=pieces;r.streak=streak;r.chain=chain;
    r.pending=List.of(pending);r.ended=ended;r.stats=stats.copy();
    return r;
  }
}
class SavedGame {
  final GameState state;
  final List<GameState> history;
  final GameState start;
  SavedGame(this.state,this.history,this.start);
}
class Route {
  final Position position;
  final int parent;
  final int operation;
  Route(this.position,this.parent,this.operation);
}
class Routes {
  final List<Route> entries;
  final int? index;
  Routes(this.entries,this.index);
}
class Candidate {
  final int kind;
  final int value;
  final List<int> operations;
  final String occupied;
  int order=0;
  Candidate(this.kind,this.value,this.operations,this.occupied);
}
class SpinCandidate {
  final Position position;
  final int spin;
  SpinCandidate(this.position,this.spin);
}
class GameOver implements Exception {}

final shapes = List.generate(7,(kind) {
  final pattern=frames[kind];
  final n=pattern.length;
  var blocks=<Cell>[];
  for(var row=0;row<n;row++) {
    for(var col=0;col<n;col++) if(pattern[row][col]=='#') blocks.add(Cell(col,row));
  }
  final rotations=<List<Cell>>[blocks];
  for(var i=0;i<3;i++) {
    blocks=blocks.map((b)=>Cell(n-1-b.y,b.x)).toList();
    rotations.add(blocks);
  }
  return rotations;
});
int seedStep(int x)=>(48271*x)%2147483647;
Position spawn(int kind)=>Position(0,kind==1?5:4,22);
List<Cell> cells(int kind,Position p)=>shapes[kind][p.s].map((c)=>Cell(p.x+c.x,p.y-c.y)).toList();
int lowest(int kind,Position p)=>cells(kind,p).map((c)=>c.y).reduce(math.min);
(int,List<int>) bag(int random) {
  final pieces=List<int>.generate(7,(i)=>i);
  for(var i=6;i>=1;i--) {
    random=seedStep(random);
    final j=random%(i+1);
    final temp=pieces[i];pieces[i]=pieces[j];pieces[j]=temp;
  }
  return (random,pieces);
}
bool fits(List<int> board,int kind,Position p) {
  for(final c in cells(kind,p)) {
    if(c.x<1||c.x>10||c.y<1||c.y>22) return false;
    if((board[c.y-1]&(1<<(c.x-1)))!=0)return false;
  }
  return true;
}
Movement? move(List<int> board,int kind,Position p,int op) {
  if(op==6||op==7) {
    final b=(p.s+(op==6?1:3))%4;
    final row=kickStates.indexWhere((s)=>s[0]==p.s&&s[1]==b);
    final offsets=kind==1?[[0,0]]:(kind==0?iKicks:ordinaryKicks)[row];
    for(var i=0;i<offsets.length;i++) {
      final q=Position(b,p.x+offsets[i][0],p.y+offsets[i][1]);
      if(fits(board,kind,q))return Movement(q,i+1);
    }
    return null;
  }
  final dx=(op==0||op==2)?-1:(op==1||op==3)?1:0;
  final dy=dx==0?-1:0;
  final repeatMove=op==2||op==3||op==5;
  var q=p;
  var changed=false;
  do {
    final next=q.translate(dx,dy);
    if(!fits(board,kind,next))break;
    q=next;changed=true;
  }while(repeatMove);
  return changed?Movement(q,0):null;
}
Position landing(List<int> board,int kind,Position p)=>move(board,kind,p,5)?.position??p;
(List<int>,int) placed(List<int> board,int kind,Position p) {
  final result=List<int>.of(board);
  for(final c in cells(kind,p))result[c.y-1]|=1<<(c.x-1);
  final remaining=result.where((r)=>r!=1023).toList();
  final n=22-remaining.length;
  return (remaining..addAll(List.filled(n,0)),n);
}
Metrics evaluate(List<int> board,int cleared) {
  final heights=List<int>.filled(10,0);
  var holes=0,bump=0;
  for(var c=0;c<10;c++) {
    for(var r=21;r>=0;r--)if((board[r]&(1<<c))!=0){heights[c]=r+1;break;}
    for(var r=0;r<heights[c];r++)if((board[r]&(1<<c))==0)holes++;
  }
  for(var c=0;c<9;c++)bump+=(heights[c]-heights[c+1]).abs();
  final value=76*cleared-51*heights.fold<int>(0,(a,b)=>a+b)-36*holes-18*bump;
  return Metrics(heights,holes,bump,value);
}
Routes routes(List<int> board,int kind,Position start,[Position? target]) {
  if(!fits(board,kind,start))return Routes([],null);
  final entries=<Route>[Route(start,-1,-1)];
  final seen=<String>{start.key};
  for(var i=0;i<entries.length;i++) {
    final entry=entries[i];
    if(target!=null&&landing(board,kind,entry.position).key==target.key)return Routes(entries,i);
    for(var op=0;op<8;op++) {
      final next=move(board,kind,entry.position,op);
      if(next!=null&&seen.add(next.position.key))entries.add(Route(next.position,i,op));
    }
  }
  return Routes(target==null?entries:[],null);
}
List<int> shortest(List<Route> entries,int index) {
  final ops=<int>[];
  while(entries[index].parent>=0) {
    ops.add(entries[index].operation);
    index=entries[index].parent;
  }
  return ops.reversed.toList();
}
int tSpin(List<int> board,Position p,int test) {
  final corners=[Cell(p.x,p.y),Cell(p.x+2,p.y),Cell(p.x+2,p.y-2),Cell(p.x,p.y-2)];
  final blocked=corners.map((c)=>c.x<1||c.x>10||c.y<1||c.y>22||(board[c.y-1]&(1<<(c.x-1)))!=0).toList();
  if(blocked.where((b)=>b).length<3)return 0;
  return (blocked[p.s]&&blocked[(p.s+1)%4])||test==5?2:1;
}
ClearInfo clearInfo(int spin,int n) {
  if(spin==2)return ClearInfo(7+n,[400,800,1200,1600][n],[0,2,4,6][n]);
  if(spin==1)return ClearInfo(4+n,[100,200,400][n],[0,0,1][n]);
  return ClearInfo(n==0?-1:n-1,[0,100,300,500,800][n],[0,0,1,2,4][n]);
}
String operationText(List<int> ops)=>ops.map((i)=>operations[i]).join(' ');

class Game {
  final int number;
  late GameState state;
  List<GameState> history=[];
  late GameState start;
  final Map<String,SavedGame> saves={};
  Game(this.number,int seed,int level) {
    state=GameState(seed,level,level);
    addBag();
    spawnPiece(takeNext());
    start=state.copy();
  }
  void addBag() {
    final result=bag(state.random);
    state.random=result.$1;
    state.queue.addAll(result.$2);
  }
  int takeNext() {
    final kind=state.queue.removeAt(0);
    if(state.queue.length<5)addBag();
    return kind;
  }
  void spawnPiece(int kind) {
    state.kind=kind;state.position=spawn(kind);
    state.last=0;state.test=0;state.keys=0;state.drop=0;state.fall=0;state.ground=0;state.resets=0;
    state.lowest=lowest(kind,state.position);
    if(!fits(state.board,kind,state.position))gameOver('block out');
  }
  Never gameOver(String reason) {
    print('game over $reason');
    summary();
    state.ended=true;
    throw GameOver();
  }
  void update(Position p,int last,[int test=0]) {
    state.position=p;state.last=last;state.test=test;
    final row=lowest(state.kind,p);
    if(row<state.lowest){state.lowest=row;state.resets=0;}
  }
  bool grounded()=>move(state.board,state.kind,state.position,4)==null;
  void drops(int points){state.score+=points;state.drop+=points;state.stats.drops+=points;}
  void insertGarbage(int count,int hole) {
    if(state.board.skip(22-count).any((r)=>r!=0))gameOver('top out');
    state.board=[...List.filled(count,1023^(1<<(hole-1))),...state.board.take(22-count)];
  }
  void operation(int op) {
    if(op<8) {
      state.keys++;
      final next=move(state.board,state.kind,state.position,op);
      if(next==null){print('fail ${operations[op]}');return;}
      if(op==4||op==5) {
        drops(state.position.y-next.position.y);update(next.position,1);state.fall=0;state.ground=0;
      }else{
        update(next.position,op>=6?2:1,next.test);
        if(state.ground>0&&state.resets<15){state.ground=0;state.resets++;}
      }
    }else if(op==8) {
      final p=landing(state.board,state.kind,state.position);
      final rows=state.position.y-p.y;
      drops(2*rows);
      if(rows>0)update(p,1);
      lock();
    }else if(op==9){if(grounded())lock();else print('fail LOCK');}
    else {
      if(state.usedHold){print('fail HOLD');return;}
      state.usedHold=true;state.stats.holds++;
      final previous=state.hold;
      state.hold=state.kind;
      spawnPiece(previous??takeNext());
    }
  }
  void tick() {
    if(!grounded()) {
      state.ground=0;state.fall++;
      final interval=state.level>=13?1:[60,48,37,28,21,16,11,8,6,4,3,2][state.level-1];
      if(state.fall>=interval){update(state.position.translate(0,-1),1);state.fall=0;}
    }else{state.ground++;if(state.ground>=30)lock();}
  }
  void lock() {
    final kind=state.kind,p=state.position;
    final oldCells=cells(kind,p);
    final route=routes(state.board,kind,spawn(kind),p);
    final shortestOps=route.index==null?null:shortest(route.entries,route.index!);
    final spin=kind==2&&state.last==2?tSpin(state.board,p,state.test):0;
    final placement=placed(state.board,kind,p);
    final n=placement.$2;
    state.board=placement.$1;
    history.add(start.copy());
    state.pieces++;state.stats.kinds[kind]++;state.stats.operationCount+=state.keys;
    final info=clearInfo(spin,n);
    final level=state.level;
    var points=info.points*level,sent=info.sent,back=false;
    if(n>0){state.streak++;if(n==4||spin!=0){state.chain++;back=state.chain>=2;}else state.chain=0;}
    else state.streak=0;
    if(back){points=points*3~/2;sent++;}
    final combo=state.streak-1;
    final comboPoints=combo>=1?50*combo*level:0;
    if(combo>=0)sent+=[0,1,1,2,2,3,3,4,4,4,5][math.min(combo,10)];
    final perfect=n>0&&state.board.every((r)=>r==0);
    final perfectPoints=perfect?(n==4&&back?3200:[800,1200,1800,2000][n-1])*level:0;
    if(perfect){sent+=10;state.stats.perfect++;}
    final gained=points+comboPoints+perfectPoints;
    state.score+=gained;state.lines+=n;state.stats.sent+=sent;
    state.stats.combo=math.max(state.stats.combo,combo);
    state.stats.chain=math.max(state.stats.chain,state.chain);
    print('lock ${state.pieces} ${kinds[kind]} ${states[p.s]} ${p.x} ${p.y} keys ${state.keys} ${shortestOps?.length??'-'} drop ${state.drop} lines $n sent $sent +$gained total ${state.score}');
    if(shortestOps!=null&&state.keys>shortestOps.length){state.stats.faults++;print('finesse ${shortestOps.isEmpty?'none':operationText(shortestOps)}');}
    if(info.name>=0){
      state.stats.clears[info.name]++;
      var line='clear ${clearNames[info.name]} $points';
      if(back)line+=' b2b';
      if(combo>=1)line+=' combo $combo $comboPoints';
      if(perfect)line+=' perfect $perfectPoints';
      print(line);
    }
    final nextLevel=state.initialLevel+state.lines~/10;
    if(nextLevel>level){state.level=nextLevel;print('level ${state.level}');}
    if(oldCells.every((c)=>c.y>=21))gameOver('lock out');
    final cancelled=math.min(sent,state.pending.fold<int>(0,(a,b)=>a+b));
    var remaining=cancelled;
    while(remaining>0){
      final used=math.min(remaining,state.pending[0]);remaining-=used;state.pending[0]-=used;
      if(state.pending[0]==0)state.pending.removeAt(0);
    }
    if(cancelled>0){state.stats.cancelled+=cancelled;print('cancel $cancelled pending ${state.pending.fold<int>(0,(a,b)=>a+b)}');}
    if(n==0){
      var risen=0;
      while(state.pending.isNotEmpty&&risen<8){
        final count=math.min(state.pending[0],8-risen);
        state.random=seedStep(state.random);
        final hole=state.random%10+1;
        insertGarbage(count,hole);
        state.stats.received+=count;risen+=count;state.pending[0]-=count;
        if(state.pending[0]==0)state.pending.removeAt(0);
        print('rise $count hole $hole pending ${state.pending.fold<int>(0,(a,b)=>a+b)}');
      }
    }
    state.usedHold=false;
    spawnPiece(takeNext());
    start=state.copy();
  }
  List<Candidate> candidates(int kind,Position start,List<int> prefix) {
    final result=<Candidate>[];
    final seen=<String>{};
    for(final turns in <List<int>>[[],[6],[6,6],[7]]){
      var p=start;
      var valid=true;
      for(final op in turns){final next=move(state.board,kind,p,op);if(next==null){valid=false;break;}p=next.position;}
      if(!valid)continue;
      void add(Position q,List<int> shifts){
        final landed=landing(state.board,kind,q);
        final occupied=cells(kind,landed).map((c)=>(c.y-1)*10+c.x-1).toList()..sort();
        final id=occupied.join(',');
        if(!seen.add(id))return;
        final r=placed(state.board,kind,landed);
        final value=evaluate(r.$1,r.$2).value;
        result.add(Candidate(kind,value,[...prefix,...turns,...shifts,8],id));
      }
      add(p,[]);
      for(final direction in [0,1]){
        var q=p;
        final shifts=<int>[];
        while(true){
          final next=move(state.board,kind,q,direction);
          if(next==null)break;
          q=next.position;shifts.add(direction);add(q,shifts);
        }
      }
    }
    return result;
  }
  List<Candidate> ranked(){
    final result=candidates(state.kind,state.position,[]);
    final held=state.hold??state.queue[0];
    if(!state.usedHold&&fits(state.board,held,spawn(held)))result.addAll(candidates(held,spawn(held),[10]));
    for(var i=0;i<result.length;i++)result[i].order=i;
    result.sort((a,b){final diff=b.value.compareTo(a.value);return diff!=0?diff:a.order.compareTo(b.order);});
    return result;
  }
  void spins(){
    if(state.kind!=2){print('spins 0');return;}
    final found=<String,SpinCandidate>{};
    for(final route in routes(state.board,2,state.position).entries){
      for(final op in [6,7]){
        final next=move(state.board,2,route.position,op);
        if(next==null||move(state.board,2,next.position,4)!=null)continue;
        final spin=tSpin(state.board,next.position,next.test);
        if(spin!=0){
          final existing=found[next.position.key];
          if(existing==null||spin>existing.spin)found[next.position.key]=SpinCandidate(next.position,spin);
        }
      }
    }
    final list=found.values.toList()..sort((a,b){
      final dy=a.position.y.compareTo(b.position.y);
      if(dy!=0)return dy;
      final dx=a.position.x.compareTo(b.position.x);
      return dx!=0?dx:a.position.s.compareTo(b.position.s);
    });
    for(final c in list){
      final n=placed(state.board,2,c.position).$2;
      final info=clearInfo(c.spin,n);
      print('spin ${states[c.position.s]} ${c.position.x} ${c.position.y} ${clearNames[info.name]}');
    }
    print('spins ${list.length}');
  }
  void summary(){
    final s=state,a=state.stats,c=a.clears;
    String ratio(int x,int y){final q=y==0?0:100*x~/y;return '${q~/100}.${(q%100).toString().padLeft(2,'0')}';}
    print('summary game $number score ${s.score} level ${s.level} lines ${s.lines} pieces ${s.pieces}');
    print('clears single ${c[0]} double ${c[1]} triple ${c[2]} tetris ${c[3]} perfect ${a.perfect}');
    print('tspins mini ${c[4]} mini_single ${c[5]} mini_double ${c[6]} zero ${c[7]} single ${c[8]} double ${c[9]} triple ${c[10]}');
    print('pieces ${List.generate(7,(i)=>'${kinds[i]} ${a.kinds[i]}').join(' ')}');
    print('best combo ${a.combo} chain ${a.chain} holds ${a.holds} drops ${a.drops} faults ${a.faults}');
    print('garbage sent ${a.sent} cancelled ${a.cancelled} received ${a.received}');
    print('rates app ${ratio(a.sent,s.pieces)} apl ${ratio(a.sent,s.lines)} kpp ${ratio(a.operationCount,s.pieces)}');
  }
  void command(String cmd,List<String> args){
    switch(cmd){
      case 'PRINT':
        final current=state.ended?<String>{}:cells(state.kind,state.position).map((c)=>'${c.x},${c.y}').toSet();
        final ghost=state.ended?<String>{}:cells(state.kind,landing(state.board,state.kind,state.position)).map((c)=>'${c.x},${c.y}').toSet();
        for(var r=22;r>=1;r--){
          var line='${r.toString().padLeft(2)} ';
          for(var c=1;c<=10;c++){
            line+=(state.board[r-1]&(1<<(c-1)))!=0?'#':current.contains('$c,$r')?'@':ghost.contains('$c,$r')?'+':'.';
          }
          print(line);
        }
        break;
      case 'NEXT':print('hold ${state.hold==null?'-':kinds[state.hold!]} next ${state.queue.take(5).map((i)=>kinds[i]).join()}');break;
      case 'PREVIEW':
        final n=int.parse(args[0]);
        final queue=List<int>.of(state.queue);
        var random=state.random;
        while(queue.length<n){final b=bag(random);random=b.$1;queue.addAll(b.$2);}
        print('preview ${queue.take(n).map((i)=>kinds[i]).join()}');
        break;
      case 'STATUS':
        print('score ${state.score} level ${state.level} lines ${state.lines} pieces ${state.pieces}');
        final piece=state.ended?'-':'${kinds[state.kind]} ${states[state.position.s]} ${state.position.x} ${state.position.y}';
        print('piece $piece streak ${state.streak} chain ${state.chain} pending ${state.pending.fold<int>(0,(a,b)=>a+b)}');
        break;
      case 'ANALYZE':
        final e=evaluate(state.board,0);
        print('heights ${e.heights.join(' ')}');
        print('holes ${e.holes} bumpiness ${e.bumpiness} value ${e.value}');
        break;
      case 'ROW':
        final row=int.parse(args[0]);final pattern=args[1];
        if(cells(state.kind,state.position).any((c)=>c.y==row&&pattern[c.x-1]=='#')){print('ERROR overlap');break;}
        var mask=0;for(var i=0;i<10;i++)if(pattern[i]=='#')mask|=1<<i;
        state.board[row-1]=mask;
        print('OK');break;
      case 'GARBAGE':
        final n=int.parse(args[0]),hole=int.parse(args[1]);insertGarbage(n,hole);
        var success=false;
        for(var j=0;j<=n;j++){
          final p=state.position.translate(0,j);
          if(fits(state.board,state.kind,p)){state.position=p;success=true;print('OK');break;}
        }
        if(!success)gameOver('top out');
        break;
      case 'ATTACK':state.pending.add(int.parse(args[0]));print('pending ${state.pending.fold<int>(0,(a,b)=>a+b)}');break;
      case 'TICK':for(var i=0;i<int.parse(args[0]);i++)tick();break;
      case 'UNDO':
        if(history.isEmpty)print('ERROR nothing to undo');
        else{state=history.removeLast().copy();start=state.copy();print('undo ${state.pieces} ${kinds[state.kind]}');}
        break;
      case 'SAVE':saves[args[0]]=SavedGame(state.copy(),history.map((s)=>s.copy()).toList(),start.copy());print('OK');break;
      case 'LOAD':
        final saved=saves[args[0]];
        if(saved==null)print('ERROR unknown save');
        else{state=saved.state.copy();history=saved.history.map((s)=>s.copy()).toList();start=saved.start.copy();print('load ${state.pieces} ${kinds[state.kind]}');}
        break;
      case 'SPINS':spins();break;
      case 'HINT':
        final list=ranked().take(int.parse(args[0])).toList();
        for(var i=0;i<list.length;i++)print('hint ${i+1} ${kinds[list[i].kind]} ${operationText(list[i].operations)} value ${list[i].value}');
        break;
      case 'AUTO':
        for(var i=0;i<int.parse(args[0]);i++){
          final c=ranked()[0];print('auto ${kinds[c.kind]} ${operationText(c.operations)}');
          for(final op in c.operations)operation(op);
        }
        break;
    }
  }
}
bool validNumber(String text,int minValue,int maxValue){
  if(text.isEmpty||(text.length>1&&text[0]=='0')||!RegExp(r'^[0-9]+$').hasMatch(text))return false;
  final n=int.tryParse(text);
  return n!=null&&n>=minValue&&n<=maxValue;
}
bool validArgs(String command,List<String> args){
  if(command=='NEW')return args.length==2&&validNumber(args[0],1,2147483646)&&validNumber(args[1],1,15);
  if(command=='ROW')return args.length==2&&validNumber(args[0],1,22)&&args[1].length==10&&RegExp(r'^[#.]{10}$').hasMatch(args[1])&&args[1].contains('.');
  if(command=='GARBAGE')return args.length==2&&validNumber(args[0],1,10)&&validNumber(args[1],1,10);
  if(command=='SAVE'||command=='LOAD')return args.length==1&&RegExp(r'^[a-z]{1,8}$').hasMatch(args[0]);
  final limits={'PREVIEW':14,'ATTACK':20,'TICK':1000,'HINT':10,'AUTO':50};
  if(limits.containsKey(command))return args.length==1&&validNumber(args[0],1,limits[command]!);
  return args.isEmpty;
}
void main(){
  final count=int.parse(stdin.readLineSync()!);
  Game? game;
  var serial=0;
  for(var i=0;i<count;i++){
    final line=stdin.readLineSync()!;
    final words=line.split(' ');
    final command=words[0],args=words.sublist(1);
    try{
      if(commands.contains(command)){
        if(!validArgs(command,args))print('ERROR bad arguments');
        else if(command=='NEW'){
          if(game!=null&&!game.state.ended){print('game stopped');game.summary();}
          serial++;
          print('game $serial seed ${int.parse(args[0])} level ${int.parse(args[1])}');
          game=Game(serial,int.parse(args[0]),int.parse(args[1]));
        }else if(game==null)print('ERROR no game');
        else if(game.state.ended&&!afterEnd.contains(command))print('ERROR game over');
        else game.command(command,args);
      }else{
        final invalid=words.where((w)=>!operations.contains(w)).firstOrNull;
        if(invalid!=null)print('ERROR unknown $invalid');
        else if(game==null)print('ERROR no game');
        else if(game.state.ended)print('ERROR game over');
        else for(final word in words)game.operation(operations.indexOf(word));
      }
    }on GameOver catch(_){ }
  }
  if(game!=null&&!game.state.ended){print('game stopped');game.summary();}
}
