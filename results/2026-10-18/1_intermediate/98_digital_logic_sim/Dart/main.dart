import 'dart:io';

const types=['AND','OR','NAND','NOR','XOR','XNOR','NOT','BUF','MUX2','DFF'];
const counts={'BUILD':1,'RESET':0,'SET':3,'APPLY':2,'PULSE':3,'CLOCK':4,'RUN':1,'WATCH':1,'UNWATCH':1,'SHOW':0,'CHECK':2,'PROBE':1,'WAVE':2,'HISTORY':1,'ACTIVITY':1,'STATUS':0,'MODULES':0,'NETLIST':1,'HIERARCHY':1,'STATS':1,'TRUTHTABLE':1,'EQUIV':2,'FAULTS':1,'CRITICAL':1,'PERIOD':1};
final simulationCommands='RESET SET APPLY PULSE CLOCK RUN WATCH UNWATCH SHOW CHECK PROBE WAVE HISTORY ACTIVITY STATUS'.split(' ').toSet();
class InputError implements Exception {final String reason;const InputError(this.reason);}
Never fail(String s)=>throw InputError(s);
void emit(String s)=>stdout.writeln(s);
bool nameOk(String s)=>RegExp(r'^[a-z][a-z0-9_]{0,15}$').hasMatch(s);
bool numberOk(String s)=>RegExp(r'^(0|[1-9][0-9]{0,8})$').hasMatch(s);
int number(String s,[bool positive=false]){if(!numberOk(s)||positive&&s=='0')fail('bad number $s');return int.parse(s);}
String value(String s){if(!['0','1','X'].contains(s))fail('bad value $s');return s;}
String bits(int r,int n)=>[for(var i=0;i<n;i++)(r>>(n-1-i))&1].join();
String logic(String k,List<String>a){
  String y;
  if(k=='AND'||k=='NAND')y=a.contains('0')?'0':a.contains('X')?'X':'1';
  else if(k=='OR'||k=='NOR')y=a.contains('1')?'1':a.contains('X')?'X':'0';
  else if(k=='XOR'||k=='XNOR')y=a.contains('X')?'X':(a.where((x)=>x=='1').length%2).toString();
  else if(k=='MUX2')y=a[0]=='X'?(a[1]==a[2]?a[1]:'X'):a[a[0]=='0'?1:2];
  else y=a[0];
  return ['NAND','NOR','XNOR','NOT'].contains(k)?{'0':'1','1':'0','X':'X'}[y]!:y;
}
sealed class Item {}
class Gate extends Item {final String name,kind,output;final List<String> inputs;final int delay;Gate(this.name,this.kind,this.inputs,this.output,this.delay);}
class Instance extends Item {final String name;final LogicModule module;final List<(String,String)> connections;Instance(this.name,this.module,this.connections);}
class LogicModule {final String name;final List<String> inputs,outputs;final List<Item> body;LogicModule(this.name,this.inputs,this.outputs,this.body);}
class Arrival {final Map<String,int> late,early;final Map<String,String> previous;Arrival(this.late,this.early,this.previous);}
class Circuit {
  final String name;final List<String> inputs,outputs;final gates=<Gate>[],flops=<Gate>[],order=<Gate>[];
  final driver=<String,Gate>{},readers=<String,List<Gate>>{};late final List<String> signals;late final bool loop;
  Circuit(LogicModule m):name=m.name,inputs=m.inputs,outputs=m.outputs{
    expand(m,'',{});signals=[...inputs,...gates.map((g)=>g.output)];for(final s in signals)readers[s]=[];
    for(final g in gates){driver[g.output]=g;if(g.kind=='DFF')flops.add(g);for(final s in g.inputs.toSet())readers[s]!.add(g);}
    final waiting=<Gate,int>{},ready=<Gate>[];
    for(final g in gates){if(g.kind=='DFF')continue;final n=g.inputs.toSet().where((s)=>driver.containsKey(s)&&driver[s]!.kind!='DFF').length;waiting[g]=n;if(n==0)ready.add(g);}
    while(ready.isNotEmpty){final g=ready.removeLast();order.add(g);for(final r in readers[g.output]!)if(r.kind!='DFF'){waiting[r]=waiting[r]!-1;if(waiting[r]==0)ready.add(r);}}
    loop=order.length!=waiting.length;
  }
  void expand(LogicModule m,String prefix,Map<String,String>ports){
    String actual(String s)=>ports[s]??prefix+s;
    for(final x in m.body){if(x is Gate)gates.add(Gate(prefix+x.name,x.kind,x.inputs.map(actual).toList(),actual(x.output),x.delay));else if(x is Instance)expand(x.module,prefix+x.name+'.',{for(final (p,s)in x.connections)p:actual(s)});}
  }
  void combinational(){if(flops.isNotEmpty)fail('$name is not combinational');if(loop)fail('$name has a combinational loop');if(inputs.length>8)fail('too many inputs ${inputs.length}');}
  String evaluate(String b,[String stuck='',String v='X']){
    final values={for(var i=0;i<inputs.length;i++)inputs[i]:inputs[i]==stuck?v:b[i]};
    for(final g in order)values[g.output]=g.output==stuck?v:logic(g.kind,g.inputs.map((s)=>values[s]!).toList());
    return outputs.map((s)=>values[s]!).join();
  }
  Arrival arrivals(bool period){
    final late=<String,int>{},early=<String,int>{},previous=<String,String>{};
    if(period){for(final g in flops){late[g.output]=g.delay;early[g.output]=g.delay;}}else{for(final s in inputs){late[s]=0;early[s]=0;}}
    for(final g in order){final a=g.inputs.where(late.containsKey).toList();if(a.isEmpty)continue;var best=a[0];for(final s in a)if(late[s]!>late[best]!)best=s;late[g.output]=late[best]!+g.delay;early[g.output]=a.map((s)=>early[s]!).reduce((a,b)=>a<b?a:b)+g.delay;previous[g.output]=best;}
    return Arrival(late,early,previous);
  }
}
class Event {final int time,sequence;final String signal,value;Event(this.time,this.sequence,this.signal,this.value);}
class Change {final int time;final String value;Change(this.time,this.value);}
class Simulation {
  final Circuit c;final watch=<String>[];late Map<String,String> values;late Map<String,List<Change>> history;
  final queue=<Event>[];int time=0,sequence=0,processed=0;bool halted=false;
  Simulation(this.c){reset();}
  void reset(){values={for(final s in c.signals)s:'X'};history={for(final s in c.signals)s:[]};queue.clear();time=0;sequence=0;processed=0;halted=false;}
  bool before(Event a,Event b)=>a.time<b.time||a.time==b.time&&a.sequence<b.sequence;
  void schedule(int t,String s,String v){final e=Event(t,sequence++,s,v);var i=queue.length;queue.add(e);while(i>0){final p=(i-1)~/2;if(!before(e,queue[p]))break;queue[i]=queue[p];i=p;}queue[i]=e;}
  Event pop(){
    final result=queue[0],last=queue.removeLast();if(queue.isNotEmpty){var i=0;while(2*i+1<queue.length){var j=2*i+1;if(j+1<queue.length&&before(queue[j+1],queue[j]))j++;if(!before(queue[j],last))break;queue[i]=queue[j];i=j;}queue[i]=last;}return result;
  }
  List<String> describe(Iterable<String>a)=>a.map((s)=>'$s=${values[s]}').toList();
  void run(int end){
    var total=0,glitches=0;
    while(queue.isNotEmpty&&queue[0].time<end){final t=queue[0].time,original=<String,String>{};var count=0;
      while(queue.isNotEmpty&&queue[0].time==t){
        if(count==1000){emit('halted: oscillation at time $t');queue.clear();time=t;halted=true;return;}
        final e=pop();count++;processed++;final old=values[e.signal]!;if(old==e.value)continue;original.putIfAbsent(e.signal,()=>old);values[e.signal]=e.value;
        for(final g in c.readers[e.signal]!)if(g.kind!='DFF')schedule(t+g.delay,g.output,logic(g.kind,g.inputs.map((s)=>values[s]!).toList()));else if(e.signal==g.inputs[0]&&old=='0'&&e.value=='1')schedule(t+g.delay,g.output,values[g.inputs[1]]!);
      }
      total+=count;for(final entry in original.entries){final s=entry.key;if(values[s]==entry.value)glitches++;else history[s]!.add(Change(t,values[s]!));}
      for(final s in watch)if(original.containsKey(s)&&values[s]!=original[s])emit('$t $s ${values[s]}');
    }
    time=end;emit('run $end events $total glitches $glitches pending ${queue.length}');
  }
}
class Simulator {
  final modules=<String,LogicModule>{};Simulation? simulation;
  LogicModule lookup(String s)=>modules[s]??fail('unknown module $s');
  void signal(String s){if(!simulation!.values.containsKey(s))fail('unknown signal $s');}
  void input(String s){if(!simulation!.c.inputs.contains(s))fail('not an input $s');}
  int parseTime(String w){final t=number(w);if(t<simulation!.time)fail('time $t is in the past');return t;}
  void define(int header,List<String>lines){
    var line=header;
    try{
      final w=lines[0].split(' ');if(w.length<5||w[2]!='IN'||w.skip(3).where((s)=>s=='OUT').length!=1||w.last=='OUT')fail('bad module header');final name=w[1];if(!RegExp(r'^[A-Z][A-Z0-9_]{0,15}$').hasMatch(name))fail('bad module name $name');if(modules.containsKey(name))fail('duplicate module $name');
      final ins=w.sublist(3,w.indexOf('OUT',3)),outs=w.sublist(w.indexOf('OUT',3)+1),seen=<String>{};
      for(final p in [...ins,...outs]){if(!nameOk(p))fail('bad name $p');if(!seen.add(p))fail('duplicate port $p');}
      final driven=ins.toSet(),used=<String>{},body=<Item>[],reads=<(int,String)>[];var gates=0;
      for(var i=1;i<lines.length;i++){line=header+i;final a=lines[i].split(' '),kind=a[0];
        if(types.contains(kind)){
          if(a.length<5||a[a.length-3]!='->'||a.where((s)=>s=='->').length!=1)fail('bad gate syntax');final n=a[1];if(!nameOk(n))fail('bad name $n');final inputs=a.sublist(2,a.length-3),output=a[a.length-2],delay=a.last,lo=['NOT','BUF'].contains(kind)?1:kind=='MUX2'?3:2;final hi=types.indexOf(kind)<6?8:lo;
          if(inputs.length<lo||inputs.length>hi)fail('bad input count ${inputs.length} for $kind');for(final s in [...inputs,output])if(!nameOk(s))fail('bad name $s');if(!numberOk(delay)||int.parse(delay)>1000)fail('bad delay $delay');if(used.contains(n))fail('duplicate name $n');if(driven.contains(output))fail('multiple drivers for $output');
          used.add(n);driven.add(output);body.add(Gate(n,kind,inputs,output,int.parse(delay)));gates++;reads.addAll(inputs.map((s)=>(line,s)));
        }else if(kind=='INST'){
          if(a.length<3)fail('bad instance syntax');final n=a[1];if(!nameOk(n))fail('bad name $n');final m=lookup(a[2]),connections=<(String,String)>[],ports=<String>{};
          for(final word in a.skip(3)){final p=word.split('=');if(p.length!=2||p[0].isEmpty||p[1].isEmpty)fail('bad connection $word');if(!m.inputs.contains(p[0])&&!m.outputs.contains(p[0]))fail('unknown port ${p[0]}');if(ports.contains(p[0]))fail('duplicate connection ${p[0]}');if(!nameOk(p[1]))fail('bad name ${p[1]}');ports.add(p[0]);connections.add((p[0],p[1]));}
          for(final p in m.inputs)if(!ports.contains(p))fail('unconnected input $p');if(used.contains(n))fail('duplicate name $n');for(final (p,s)in connections)if(m.outputs.contains(p)&&!driven.add(s))fail('multiple drivers for $s');
          used.add(n);body.add(Instance(n,m,connections));reads.addAll(connections.where((v)=>m.inputs.contains(v.$1)).map((v)=>(line,v.$2)));
        }else fail('unknown statement $kind');
      }
      reads.addAll(outs.map((s)=>(header,s)));for(final (n,s) in reads)if(!driven.contains(s)){line=n;fail('undriven signal $s');}
      modules[name]=LogicModule(name,ins,outs,body);emit('defined $name inputs ${ins.length} outputs ${outs.length} gates $gates instances ${body.length-gates}');
    }on InputError catch(e){emit('error: line $line: ${e.reason}');}
  }
  void hierarchy(LogicModule m,int depth){for(final x in m.body)if(x is Instance){emit('${'  '*depth}${x.name} ${x.module.name}');hierarchy(x.module,depth+1);}}
  void execute(int line,List<String>w){
    try{
      final cmd=w[0],a=w.sublist(1),n=counts[w[0]];if(n==null)fail('unknown command $cmd');if(a.length<n||!['WATCH','UNWATCH','SHOW'].contains(cmd)&&a.length!=n)fail('wrong argument count');if(simulationCommands.contains(cmd)&&simulation==null)fail('no circuit');final s=simulation;
      if(['SET','APPLY','PULSE','CLOCK','RUN'].contains(cmd)&&s!.halted)fail('simulation halted');
      if(cmd=='MODULES'){emit('modules ${modules.length}');for(final m in modules.values)emit('${m.name} inputs ${m.inputs.length} outputs ${m.outputs.length} gates ${Circuit(m).gates.length}');return;}
      if(['BUILD','NETLIST','HIERARCHY','STATS','TRUTHTABLE','EQUIV','FAULTS','CRITICAL','PERIOD'].contains(cmd)){
        final m=lookup(a[0]),m2=cmd=='EQUIV'?lookup(a[1]):null,c=Circuit(m);
        if(cmd=='BUILD'){simulation=Simulation(c);emit('built ${c.name} signals ${c.signals.length} gates ${c.gates.length}');}
        else if(cmd=='NETLIST'){emit('netlist ${c.name} gates ${c.gates.length} signals ${c.signals.length}');for(final g in c.gates)emit('${g.name} ${g.kind} ${g.inputs.join(' ')} -> ${g.output} ${g.delay}');}
        else if(cmd=='HIERARCHY'){emit(c.name);hierarchy(m,1);}
        else if(cmd=='STATS'){
          final levels={for(final x in c.signals)x:0};var depth=0;for(final g in c.order){final v=g.inputs.map((x)=>levels[x]!).reduce((a,b)=>a>b?a:b)+1;levels[g.output]=v;if(v>depth)depth=v;}
          emit('stats ${c.name} gates ${c.gates.length} signals ${c.signals.length} depth ${c.loop?'-':depth}');final row=<Object>['types'];for(final t in types){final count=c.gates.where((g)=>g.kind==t).length;if(count>0)row.addAll([t,count]);}emit(row.join(' '));var best=c.signals[0];for(final x in c.signals)if(c.readers[x]!.length>c.readers[best]!.length)best=x;emit('max fanout $best ${c.readers[best]!.length}');
        }else if(cmd=='CRITICAL'||cmd=='PERIOD'){
          final period=cmd=='PERIOD';if(period&&c.flops.isEmpty)fail('${c.name} has no flip-flops');if(c.loop)fail('${c.name} has a combinational loop');final arr=c.arrivals(period),ends=period?c.flops.map((g)=>g.inputs[1]).toList():c.outputs,heading=period?'flip-flops ${c.flops.length} period':'critical';String? best;
          for(final x in ends){if(!period)emit(arr.late.containsKey(x)?'$x min ${arr.early[x]} max ${arr.late[x]}':'$x unreachable');if(arr.late.containsKey(x)&&(best==null||arr.late[x]!>arr.late[best]!))best=x;}
          if(best==null)emit('$heading none');else{final endpoint=best,path=[best];while(arr.previous.containsKey(path.last))path.add(arr.previous[path.last]!);emit('$heading ${arr.late[endpoint]}: ${path.reversed.join(' -> ')}');}
        }else{
          c.combinational();final rows=[for(var r=0;r<(1<<c.inputs.length);r++)bits(r,c.inputs.length)],expected=rows.map(c.evaluate).toList();
          if(cmd=='TRUTHTABLE'){emit([...c.inputs,'|',...c.outputs].join(' '));for(var r=0;r<rows.length;r++)emit([...rows[r].split(''),'|',...expected[r].split('')].join(' '));}
          else if(cmd=='EQUIV'){final d=Circuit(m2!);d.combinational();if(c.inputs.length!=d.inputs.length||c.outputs.length!=d.outputs.length)fail('port mismatch');for(var r=0;r<rows.length;r++){final v=d.evaluate(rows[r]);if(v!=expected[r]){emit('not equivalent at ${rows[r]}: ${expected[r]} vs $v');return;}}emit('equivalent');}
          else{final undetected=<String>[],tests=<int>{};for(final x in c.signals)for(final v in ['0','1']){var found=-1;for(var r=0;r<rows.length;r++)if(c.evaluate(rows[r],x,v)!=expected[r]){found=r;break;}if(found<0)undetected.add('$x/$v');else tests.add(found);}final total=2*c.signals.length;emit('faults $total detected ${total-undetected.length}');for(final f in undetected)emit('undetected $f');final sorted=tests.toList()..sort();emit(['tests',...sorted.map((r)=>rows[r])].join(' '));}
        }return;
      }
      final sim=s!;
      if(cmd=='RESET'){sim.reset();emit('reset');}
      else if(cmd=='SET'){final t=parseTime(a[0]);input(a[1]);value(a[2]);sim.schedule(t,a[1],a[2]);emit('set ${a[1]} ${a[2]} at $t');}
      else if(cmd=='APPLY'){final t=parseTime(a[0]),b=a[1];if(b.length!=sim.c.inputs.length||!RegExp(r'^[01X]*$').hasMatch(b))fail('bad vector $b');for(var i=0;i<b.length;i++)sim.schedule(t,sim.c.inputs[i],b[i]);emit('apply $b at $t');}
      else if(cmd=='PULSE'||cmd=='CLOCK'){input(a[0]);final t=parseTime(a[1]),width=number(a[2],true);if(cmd=='PULSE'){sim.schedule(t,a[0],'1');sim.schedule(t+width,a[0],'0');emit('pulse ${a[0]} $t ${t+width}');}else{final count=number(a[3],true);for(var i=0;i<count;i++)sim.schedule(t+i*width,a[0],(i%2).toString());emit('clock ${a[0]} events $count last ${t+(count-1)*width}');}}
      else if(cmd=='RUN'){final t=number(a[0]);if(t<=sim.time)fail('time $t is not after ${sim.time}');sim.run(t);}
      else if(cmd=='WATCH'||cmd=='UNWATCH'){final seen=<String>{};for(final x in a){signal(x);final watched=sim.watch.contains(x);if(cmd=='WATCH'?(watched||seen.contains(x)):(!watched||seen.contains(x)))fail('${cmd=='WATCH'?'already watched':'not watched'} $x');seen.add(x);}if(cmd=='WATCH')sim.watch.addAll(a);else sim.watch.removeWhere(seen.contains);emit('watching ${sim.watch.isEmpty?'nothing':sim.watch.join(' ')}');}
      else if(cmd=='SHOW'){for(final x in a)signal(x);emit((a.isNotEmpty?sim.describe(a):[...sim.describe(sim.c.inputs),'|',...sim.describe(sim.c.outputs)]).join(' '));}
      else if(cmd=='CHECK'){signal(a[0]);value(a[1]);emit('check ${a[0]}=${a[1]} ${sim.values[a[0]]==a[1]?'ok':'failed (${sim.values[a[0]]})'}');}
      else if(cmd=='PROBE'){final x=a[0];signal(x);final g=sim.c.driver[x];emit('$x=${sim.values[x]} driven by ${g==null?'input':'${g.name} ${g.kind} ${sim.describe(g.inputs).join(' ')} delay ${g.delay}'}');final readers=sim.c.readers[x]!;emit(['fanout',readers.length,...readers.map((g)=>g.name)].join(' '));}
      else if(cmd=='WAVE'){final first=number(a[0]),last=number(a[1]);if(!(first<last&&last<=sim.time))fail('bad range $first $last');if(sim.watch.isEmpty)fail('nothing watched');for(final x in sim.watch){final h=sim.history[x]!,wave=StringBuffer();var i=0,v='X';for(var t=first;t<last;t++){while(i<h.length&&h[i].time<=t)v=h[i++].value;wave.write(v);}emit('$x $wave');}}
      else if(cmd=='HISTORY'){final x=a[0];signal(x);final h=sim.history[x]!;emit(['history',x,'changes',h.length,...h.map((v)=>'${v.time}:${v.value}')].join(' '));}
      else if(cmd=='ACTIVITY'){final k=number(a[0],true),ranked=[...sim.c.signals]..sort((x,y){final d=sim.history[y]!.length-sim.history[x]!.length;return d!=0?d:x.compareTo(y);});for(final x in ranked.take(k))emit('$x ${sim.history[x]!.length}');}
      else if(cmd=='STATUS'){emit('circuit ${sim.c.name} time ${sim.time} pending ${sim.queue.length} events ${sim.processed} halted ${sim.halted?'yes':'no'}');emit('values 0:${sim.values.values.where((v)=>v=='0').length} 1:${sim.values.values.where((v)=>v=='1').length} X:${sim.values.values.where((v)=>v=='X').length}');}
    }on InputError catch(e){emit('error: line $line: ${e.reason}');}
  }
}
void main(){final lines=<String>[];for(String? line;(line=stdin.readLineSync())!=null;)lines.add(line!);final simulator=Simulator();for(var i=0;i<lines.length&&lines[i]!='END';i++){final w=lines[i].split(' ');if(w[0]=='MODULE'){var end=i+1;while(lines[end]!='ENDMODULE')end++;simulator.define(i+1,lines.sublist(i,end));i=end;}else simulator.execute(i+1,w);}}
