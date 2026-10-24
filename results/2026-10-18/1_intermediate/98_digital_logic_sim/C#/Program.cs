using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

static class Program
{
    static readonly string[] Types=["AND","OR","NAND","NOR","XOR","XNOR","NOT","BUF","MUX2","DFF"];
    static readonly Dictionary<string,int> Counts="BUILD:1 RESET:0 SET:3 APPLY:2 PULSE:3 CLOCK:4 RUN:1 WATCH:1 UNWATCH:1 SHOW:0 CHECK:2 PROBE:1 WAVE:2 HISTORY:1 ACTIVITY:1 STATUS:0 MODULES:0 NETLIST:1 HIERARCHY:1 STATS:1 TRUTHTABLE:1 EQUIV:2 FAULTS:1 CRITICAL:1 PERIOD:1".Split(' ').Select(s=>s.Split(':')).ToDictionary(p=>p[0],p=>int.Parse(p[1]));
    static readonly HashSet<string> SimulationCommands=[.."RESET SET APPLY PULSE CLOCK RUN WATCH UNWATCH SHOW CHECK PROBE WAVE HISTORY ACTIVITY STATUS".Split(' ')];
    static void Emit(string s)=>Console.WriteLine(s);
    static void Fail(string s)=>throw new ArgumentException(s);
    static bool NameOk(string s)=>Regex.IsMatch(s,"\\A[a-z][a-z0-9_]{0,15}\\z");
    static bool NumberOk(string s)=>Regex.IsMatch(s,"\\A(?:0|[1-9][0-9]{0,8})\\z");
    static int Number(string s,bool positive=false){if(!NumberOk(s)||(positive&&s=="0"))Fail("bad number "+s);return int.Parse(s);}
    static char Value(string s){if(s is not ("0" or "1" or "X"))Fail("bad value "+s);return s[0];}
    static string Bits(int r,int n)=>string.Concat(Enumerable.Range(0,n).Select(i=>(char)('0'+((r>>(n-1-i))&1))));
    static char Logic(string kind,List<char> a)
    {
        char y=kind switch
        {
            "AND" or "NAND"=>a.Contains('0')?'0':a.Contains('X')?'X':'1',
            "OR" or "NOR"=>a.Contains('1')?'1':a.Contains('X')?'X':'0',
            "XOR" or "XNOR"=>a.Contains('X')?'X':(char)('0'+a.Count(x=>x=='1')%2),
            "MUX2"=>a[0]=='X'?(a[1]==a[2]?a[1]:'X'):a[a[0]=='0'?1:2],_=>a[0]
        };
        return kind is "NAND" or "NOR" or "XNOR" or "NOT"?y=='0'?'1':y=='1'?'0':'X':y;
    }
    abstract record Item;
    sealed record Gate(string Name,string Kind,List<string> Inputs,string Output,int Delay):Item;
    sealed record Connection(string Port,string Signal);
    sealed record Instance(string Name,Module Module,List<Connection> Connections):Item;
    sealed record Module(string Name,List<string> Inputs,List<string> Outputs,List<Item> Body);
    sealed record Arrival(Dictionary<string,int> Late,Dictionary<string,int> Early,Dictionary<string,string> Previous);
    sealed class Circuit
    {
        public readonly string Name;public readonly List<string> Inputs,Outputs,Signals;public readonly List<Gate>Gates=[],Flops=[],Order=[];
        public readonly Dictionary<string,Gate>Driver=[];public readonly Dictionary<string,List<Gate>>Readers=[];public readonly bool Loop;
        public Circuit(Module m)
        {
            Name=m.Name;Inputs=m.Inputs;Outputs=m.Outputs;Expand(m,"",[]);Signals=[..Inputs,..Gates.Select(g=>g.Output)];
            foreach(string s in Signals)Readers[s]=[];
            foreach(Gate g in Gates){Driver[g.Output]=g;if(g.Kind=="DFF")Flops.Add(g);foreach(string s in g.Inputs.Distinct())Readers[s].Add(g);}
            Dictionary<Gate,int>waiting=[];Stack<Gate>ready=new();
            foreach(Gate g in Gates){if(g.Kind=="DFF")continue;int n=g.Inputs.Distinct().Count(s=>Driver.TryGetValue(s,out Gate? d)&&d.Kind!="DFF");waiting[g]=n;if(n==0)ready.Push(g);}
            while(ready.Count>0){Gate g=ready.Pop();Order.Add(g);foreach(Gate r in Readers[g.Output])if(r.Kind!="DFF"&&--waiting[r]==0)ready.Push(r);}
            Loop=Order.Count!=waiting.Count;
        }
        void Expand(Module m,string prefix,Dictionary<string,string> ports)
        {
            string Actual(string s)=>ports.GetValueOrDefault(s,prefix+s);
            foreach(Item item in m.Body)
                if(item is Gate g)Gates.Add(new(prefix+g.Name,g.Kind,g.Inputs.Select(Actual).ToList(),Actual(g.Output),g.Delay));
                else{Instance x=(Instance)item;Expand(x.Module,prefix+x.Name+".",x.Connections.ToDictionary(c=>c.Port,c=>Actual(c.Signal)));}
        }
        public void Combinational(){if(Flops.Count>0)Fail(Name+" is not combinational");if(Loop)Fail(Name+" has a combinational loop");if(Inputs.Count>8)Fail("too many inputs "+Inputs.Count);}
        public string Evaluate(string bits,string stuck="",char v='X')
        {
            Dictionary<string,char>values=Inputs.Select((s,i)=>(s,v:s==stuck?v:bits[i])).ToDictionary(x=>x.s,x=>x.v);
            foreach(Gate g in Order)values[g.Output]=g.Output==stuck?v:Logic(g.Kind,g.Inputs.Select(s=>values[s]).ToList());
            return string.Concat(Outputs.Select(s=>values[s]));
        }
        public Arrival Arrivals(bool period)
        {
            Dictionary<string,int>late=[],early=[];Dictionary<string,string>previous=[];
            if(period){foreach(Gate g in Flops)late[g.Output]=early[g.Output]=g.Delay;}else foreach(string s in Inputs)late[s]=early[s]=0;
            foreach(Gate g in Order){List<string>a=g.Inputs.Where(late.ContainsKey).ToList();if(a.Count==0)continue;string best=a[0];foreach(string s in a)if(late[s]>late[best])best=s;late[g.Output]=late[best]+g.Delay;early[g.Output]=a.Min(s=>early[s])+g.Delay;previous[g.Output]=best;}
            return new(late,early,previous);
        }
    }
    readonly record struct Event(int Time,string Signal,char Value);
    readonly record struct Change(int Time,char Value);
    sealed class Simulation
    {
        public Circuit Circuit;public List<string>Watch=[];public Dictionary<string,char>Values=[];public Dictionary<string,List<Change>>History=[];
        public PriorityQueue<Event,(int,long)>Queue=new();public int Time;public long Sequence,Processed;public bool Halted;
        public Simulation(Circuit c){Circuit=c;Reset();}
        public void Reset(){Values=Circuit.Signals.ToDictionary(s=>s,_=>'X');History=Circuit.Signals.ToDictionary(s=>s,_=>new List<Change>());Queue.Clear();Time=0;Sequence=Processed=0;Halted=false;}
        public void Schedule(int t,string s,char v)=>Queue.Enqueue(new(t,s,v),(t,Sequence++));
        public List<string>Describe(IEnumerable<string>a)=>a.Select(s=>$"{s}={Values[s]}").ToList();
        public void Run(int end)
        {
            int total=0,glitches=0;
            while(Queue.TryPeek(out Event first,out _)&&first.Time<end)
            {
                int t=first.Time,count=0;Dictionary<string,char>original=[];
                while(Queue.TryPeek(out Event next,out _)&&next.Time==t)
                {
                    if(count==1000){Emit($"halted: oscillation at time {t}");Queue.Clear();Time=t;Halted=true;return;}
                    Event e=Queue.Dequeue();count++;Processed++;char old=Values[e.Signal];if(old==e.Value)continue;original.TryAdd(e.Signal,old);Values[e.Signal]=e.Value;
                    foreach(Gate g in Circuit.Readers[e.Signal])if(g.Kind!="DFF")Schedule(t+g.Delay,g.Output,Logic(g.Kind,g.Inputs.Select(s=>Values[s]).ToList()));else if(e.Signal==g.Inputs[0]&&old=='0'&&e.Value=='1')Schedule(t+g.Delay,g.Output,Values[g.Inputs[1]]);
                }
                total+=count;foreach(var (s,v) in original)if(Values[s]==v)glitches++;else History[s].Add(new(t,Values[s]));
                foreach(string s in Watch)if(original.TryGetValue(s,out char v)&&Values[s]!=v)Emit($"{t} {s} {Values[s]}");
            }
            Time=end;Emit($"run {end} events {total} glitches {glitches} pending {Queue.Count}");
        }
    }
    sealed class Simulator
    {
        readonly Dictionary<string,Module>modules=[];readonly List<Module>moduleOrder=[];Simulation? sim;
        Module Lookup(string s)=>modules.TryGetValue(s,out Module? m)?m:throw new ArgumentException("unknown module "+s);
        void RequireSignal(string s){if(!sim!.Values.ContainsKey(s))Fail("unknown signal "+s);}
        void RequireInput(string s){if(!sim!.Circuit.Inputs.Contains(s))Fail("not an input "+s);}
        int ParseTime(string w){int t=Number(w);if(t<sim!.Time)Fail($"time {t} is in the past");return t;}
        public void Define(int header,List<string>lines)
        {
            int line=header;
            try
            {
                string[]w=lines[0].Split(' ');if(w.Length<5||w[2]!="IN"||w.Skip(3).Count(s=>s=="OUT")!=1||w[^1]=="OUT")Fail("bad module header");string name=w[1];if(!Regex.IsMatch(name,"\\A[A-Z][A-Z0-9_]{0,15}\\z"))Fail("bad module name "+name);if(modules.ContainsKey(name))Fail("duplicate module "+name);
                int split=Array.IndexOf(w,"OUT",3);List<string>inputs=w.Skip(3).Take(split-3).ToList(),outputs=w.Skip(split+1).ToList();HashSet<string>seen=[];
                foreach(string p in inputs.Concat(outputs)){if(!NameOk(p))Fail("bad name "+p);if(!seen.Add(p))Fail("duplicate port "+p);}
                HashSet<string>driven=[..inputs],used=[];List<Item>body=[];List<(int Line,string Signal)>reads=[];int gates=0;
                for(int i=1;i<lines.Count;i++)
                {
                    line=header+i;string[]a=lines[i].Split(' ');string kind=a[0];
                    if(Types.Contains(kind))
                    {
                        if(a.Length<5||a[^3]!="->"||a.Count(s=>s=="->")!=1)Fail("bad gate syntax");string n=a[1];if(!NameOk(n))Fail("bad name "+n);List<string>ins=a.Skip(2).Take(a.Length-5).ToList();string output=a[^2],delay=a[^1];int lo=kind is "NOT" or "BUF"?1:kind=="MUX2"?3:2,hi=Array.IndexOf(Types,kind)<6?8:lo;
                        if(ins.Count<lo||ins.Count>hi)Fail($"bad input count {ins.Count} for {kind}");foreach(string s in ins.Append(output))if(!NameOk(s))Fail("bad name "+s);if(!NumberOk(delay)||int.Parse(delay)>1000)Fail("bad delay "+delay);if(used.Contains(n))Fail("duplicate name "+n);if(driven.Contains(output))Fail("multiple drivers for "+output);
                        used.Add(n);driven.Add(output);body.Add(new Gate(n,kind,ins,output,int.Parse(delay)));gates++;reads.AddRange(ins.Select(s=>(line,s)));
                    }
                    else if(kind=="INST")
                    {
                        if(a.Length<3)Fail("bad instance syntax");string n=a[1];if(!NameOk(n))Fail("bad name "+n);Module m=Lookup(a[2]);List<Connection>connections=[];HashSet<string>ports=[];
                        foreach(string word in a.Skip(3)){string[]p=word.Split('=');if(p.Length!=2||p[0]==""||p[1]=="")Fail("bad connection "+word);if(!m.Inputs.Contains(p[0])&&!m.Outputs.Contains(p[0]))Fail("unknown port "+p[0]);if(ports.Contains(p[0]))Fail("duplicate connection "+p[0]);if(!NameOk(p[1]))Fail("bad name "+p[1]);ports.Add(p[0]);connections.Add(new(p[0],p[1]));}
                        foreach(string p in m.Inputs)if(!ports.Contains(p))Fail("unconnected input "+p);if(used.Contains(n))Fail("duplicate name "+n);foreach(Connection c in connections)if(m.Outputs.Contains(c.Port)&&!driven.Add(c.Signal))Fail("multiple drivers for "+c.Signal);
                        used.Add(n);body.Add(new Instance(n,m,connections));reads.AddRange(connections.Where(c=>m.Inputs.Contains(c.Port)).Select(c=>(line,c.Signal)));
                    }
                    else Fail("unknown statement "+kind);
                }
                reads.AddRange(outputs.Select(s=>(header,s)));foreach(var (n,s) in reads)if(!driven.Contains(s)){line=n;Fail("undriven signal "+s);}
                Module module=new(name,inputs,outputs,body);modules.Add(name,module);moduleOrder.Add(module);Emit($"defined {name} inputs {inputs.Count} outputs {outputs.Count} gates {gates} instances {body.Count-gates}");
            }
            catch(ArgumentException e){Emit($"error: line {line}: {e.Message}");}
        }
        void Hierarchy(Module m,int depth){foreach(Instance x in m.Body.OfType<Instance>()){Emit(new string(' ',2*depth)+x.Name+" "+x.Module.Name);Hierarchy(x.Module,depth+1);}}
        public void Execute(int line,string[]w)
        {
            try
            {
                string cmd=w[0];List<string>a=w.Skip(1).ToList();if(!Counts.TryGetValue(cmd,out int n))Fail("unknown command "+cmd);if(a.Count<n||(!(cmd is "WATCH" or "UNWATCH" or "SHOW")&&a.Count!=n))Fail("wrong argument count");if(SimulationCommands.Contains(cmd)&&sim is null)Fail("no circuit");if((cmd is "SET" or "APPLY" or "PULSE" or "CLOCK" or "RUN")&&sim!.Halted)Fail("simulation halted");
                if(cmd=="MODULES"){Emit($"modules {modules.Count}");foreach(Module m in moduleOrder)Emit($"{m.Name} inputs {m.Inputs.Count} outputs {m.Outputs.Count} gates {new Circuit(m).Gates.Count}");return;}
                if(cmd is "BUILD" or "NETLIST" or "HIERARCHY" or "STATS" or "TRUTHTABLE" or "EQUIV" or "FAULTS" or "CRITICAL" or "PERIOD")
                {
                    Module m=Lookup(a[0]);Module? m2=cmd=="EQUIV"?Lookup(a[1]):null;Circuit c=new(m);
                    switch(cmd)
                    {
                    case "BUILD":sim=new(c);Emit($"built {c.Name} signals {c.Signals.Count} gates {c.Gates.Count}");break;
                    case "NETLIST":Emit($"netlist {c.Name} gates {c.Gates.Count} signals {c.Signals.Count}");foreach(Gate g in c.Gates)Emit($"{g.Name} {g.Kind} {string.Join(' ',g.Inputs)} -> {g.Output} {g.Delay}");break;
                    case "HIERARCHY":Emit(c.Name);Hierarchy(m,1);break;
                    case "STATS":
                        Dictionary<string,int>levels=c.Signals.ToDictionary(x=>x,_=>0);int depth=0;foreach(Gate g in c.Order){levels[g.Output]=g.Inputs.Max(x=>levels[x])+1;depth=Math.Max(depth,levels[g.Output]);}Emit($"stats {c.Name} gates {c.Gates.Count} signals {c.Signals.Count} depth {(c.Loop?"-":depth.ToString())}");List<string>text=["types"];foreach(string t in Types){int count=c.Gates.Count(g=>g.Kind==t);if(count>0){text.Add(t);text.Add(count.ToString());}}Emit(string.Join(' ',text));string best=c.Signals[0];foreach(string x in c.Signals)if(c.Readers[x].Count>c.Readers[best].Count)best=x;Emit($"max fanout {best} {c.Readers[best].Count}");break;
                    case "CRITICAL":case "PERIOD":
                        bool period=cmd=="PERIOD";if(period&&c.Flops.Count==0)Fail(c.Name+" has no flip-flops");if(c.Loop)Fail(c.Name+" has a combinational loop");Arrival arr=c.Arrivals(period);List<string>ends=period?c.Flops.Select(g=>g.Inputs[1]).ToList():c.Outputs;string heading=period?$"flip-flops {c.Flops.Count} period":"critical";string? endpoint=null;
                        foreach(string x in ends){if(!period)Emit(arr.Late.ContainsKey(x)?$"{x} min {arr.Early[x]} max {arr.Late[x]}":x+" unreachable");if(arr.Late.ContainsKey(x)&&(endpoint is null||arr.Late[x]>arr.Late[endpoint]))endpoint=x;}
                        if(endpoint is null)Emit(heading+" none");else{List<string>path=[endpoint];while(arr.Previous.TryGetValue(path[^1],out string? previous))path.Add(previous);path.Reverse();Emit($"{heading} {arr.Late[endpoint]}: {string.Join(" -> ",path)}");}break;
                    default:
                        c.Combinational();List<string>rows=Enumerable.Range(0,1<<c.Inputs.Count).Select(r=>Bits(r,c.Inputs.Count)).ToList(),expected=rows.Select(b=>c.Evaluate(b)).ToList();
                        if(cmd=="TRUTHTABLE"){Emit(string.Join(' ',c.Inputs.Append("|").Concat(c.Outputs)));for(int r=0;r<rows.Count;r++)Emit(string.Join(' ',rows[r].Select(x=>x.ToString()).Append("|").Concat(expected[r].Select(x=>x.ToString()))));}
                        else if(cmd=="EQUIV"){Circuit d=new(m2!);d.Combinational();if(c.Inputs.Count!=d.Inputs.Count||c.Outputs.Count!=d.Outputs.Count)Fail("port mismatch");for(int r=0;r<rows.Count;r++){string v=d.Evaluate(rows[r]);if(v!=expected[r]){Emit($"not equivalent at {rows[r]}: {expected[r]} vs {v}");return;}}Emit("equivalent");}
                        else{List<string>undetected=[];SortedSet<int>tests=[];foreach(string x in c.Signals)foreach(char v in "01"){int found=-1;for(int r=0;r<rows.Count;r++)if(c.Evaluate(rows[r],x,v)!=expected[r]){found=r;break;}if(found<0)undetected.Add($"{x}/{v}");else tests.Add(found);}int total=2*c.Signals.Count;Emit($"faults {total} detected {total-undetected.Count}");foreach(string f in undetected)Emit("undetected "+f);Emit(string.Join(' ',new[]{"tests"}.Concat(tests.Select(r=>rows[r]))));}break;
                    }
                    return;
                }
                Simulation s=sim!;
                switch(cmd)
                {
                case "RESET":s.Reset();Emit("reset");break;
                case "SET":int t=ParseTime(a[0]);RequireInput(a[1]);char v=Value(a[2]);s.Schedule(t,a[1],v);Emit($"set {a[1]} {v} at {t}");break;
                case "APPLY":int applyTime=ParseTime(a[0]);string b=a[1];if(b.Length!=s.Circuit.Inputs.Count||b.Any(x=>!"01X".Contains(x)))Fail("bad vector "+b);for(int i=0;i<b.Length;i++)s.Schedule(applyTime,s.Circuit.Inputs[i],b[i]);Emit($"apply {b} at {applyTime}");break;
                case "PULSE":case "CLOCK":RequireInput(a[0]);int start=ParseTime(a[1]),width=Number(a[2],true);if(cmd=="PULSE"){s.Schedule(start,a[0],'1');s.Schedule(start+width,a[0],'0');Emit($"pulse {a[0]} {start} {start+width}");}else{int count=Number(a[3],true);for(int i=0;i<count;i++)s.Schedule(start+i*width,a[0],i%2==0?'0':'1');Emit($"clock {a[0]} events {count} last {start+(count-1)*width}");}break;
                case "RUN":int end=Number(a[0]);if(end<=s.Time)Fail($"time {end} is not after {s.Time}");s.Run(end);break;
                case "WATCH":case "UNWATCH":HashSet<string>seen=[];foreach(string x in a){RequireSignal(x);bool watched=s.Watch.Contains(x);if(cmd=="WATCH"?(watched||seen.Contains(x)):(!watched||seen.Contains(x)))Fail((cmd=="WATCH"?"already watched ":"not watched ")+x);seen.Add(x);}if(cmd=="WATCH")s.Watch.AddRange(a);else s.Watch.RemoveAll(seen.Contains);Emit("watching "+(s.Watch.Count==0?"nothing":string.Join(' ',s.Watch)));break;
                case "SHOW":foreach(string x in a)RequireSignal(x);Emit(string.Join(' ',a.Count>0?s.Describe(a):s.Describe(s.Circuit.Inputs).Append("|").Concat(s.Describe(s.Circuit.Outputs))));break;
                case "CHECK":RequireSignal(a[0]);char expectedValue=Value(a[1]);Emit($"check {a[0]}={expectedValue} "+(s.Values[a[0]]==expectedValue?"ok":$"failed ({s.Values[a[0]]})"));break;
                case "PROBE":string signal=a[0];RequireSignal(signal);string driver="input";if(s.Circuit.Driver.TryGetValue(signal,out Gate? gate))driver=$"{gate.Name} {gate.Kind} {string.Join(' ',s.Describe(gate.Inputs))} delay {gate.Delay}";Emit($"{signal}={s.Values[signal]} driven by {driver}");List<Gate>readers=s.Circuit.Readers[signal];Emit(string.Join(' ',new[]{"fanout",readers.Count.ToString()}.Concat(readers.Select(g=>g.Name))));break;
                case "WAVE":int first=Number(a[0]),last=Number(a[1]);if(!(first<last&&last<=s.Time))Fail($"bad range {first} {last}");if(s.Watch.Count==0)Fail("nothing watched");foreach(string x in s.Watch){List<Change>h=s.History[x];int i=0;char val='X';StringBuilder wave=new();for(int time=first;time<last;time++){while(i<h.Count&&h[i].Time<=time)val=h[i++].Value;wave.Append(val);}Emit(x+" "+wave);}break;
                case "HISTORY":string name=a[0];RequireSignal(name);List<Change>history=s.History[name];Emit(string.Join(' ',new[]{"history",name,"changes",history.Count.ToString()}.Concat(history.Select(h=>$"{h.Time}:{h.Value}"))));break;
                case "ACTIVITY":int k=Number(a[0],true);foreach(string x in s.Circuit.Signals.OrderByDescending(x=>s.History[x].Count).ThenBy(x=>x,StringComparer.Ordinal).Take(k))Emit($"{x} {s.History[x].Count}");break;
                case "STATUS":Emit($"circuit {s.Circuit.Name} time {s.Time} pending {s.Queue.Count} events {s.Processed} halted {(s.Halted?"yes":"no")}");Emit($"values 0:{s.Values.Values.Count(x=>x=='0')} 1:{s.Values.Values.Count(x=>x=='1')} X:{s.Values.Values.Count(x=>x=='X')}");break;
                }
            }
            catch(ArgumentException e){Emit($"error: line {line}: {e.Message}");}
        }
    }
    static void Main(){List<string>lines=[];for(string? line;(line=Console.ReadLine())is not null;)lines.Add(line);Simulator simulator=new();for(int i=0;i<lines.Count&&lines[i]!="END";i++){string[]w=lines[i].Split(' ');if(w[0]=="MODULE"){int end=i+1;while(lines[end]!="ENDMODULE")end++;simulator.Define(i+1,lines.GetRange(i,end-i));i=end;}else simulator.Execute(i+1,w);}}
}
