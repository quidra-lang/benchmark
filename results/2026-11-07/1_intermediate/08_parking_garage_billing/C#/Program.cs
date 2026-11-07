using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

class Program {
    static readonly string[] TYPES={"MOTORCYCLE","CAR","ECAR","VAN","BUS"};
    static readonly string[] KINDS={"MOTO","COMPACT","LARGE","EV"};
    static readonly int[][] PREFS={new[]{0,1,2},new[]{1,2},new[]{3,1,2},new[]{2},new[]{2}};
    class Fault  : Exception { public Fault(string message) : base(message) {} }
    static void error(bool condition, string message) { if (condition) throw new Fault(message); }
    static string time(int n) => $"{n/1440+1}-{n/60%24:D2}:{n%60:D2}";
    static string duration(int n) => $"{n/60}:{n%60:D2}";
    static string tenths(int n) { return n/10+"."+n%10; }
    class Spot {
        public int level, number, kind, order;
        public bool closed;
        public Vehicle occupant;
        public Spot(int level, int number, int kind, int order) {
            this.level=level;
            this.number=number;
            this.kind=kind;
            this.order=order;
        }
        public string id() { return "L"+level+"-"+number; }
        public bool free() { return !closed && occupant==null; }
    }
    class Vehicle {
        public string plate;
        public int kind, entry, energy, charge, validation, paidAt=-1, paidParking, paidNight;
        public List<Spot> spots;
        public Vehicle(string plate, int kind, int entry, List<Spot> spots) {
            this.plate=plate;
            this.kind=kind;
            this.entry=entry;
            this.spots=spots;
        }
        public string location() { return spots[0].id()+(kind==4 ? ".."+spots[2].number : ""); }
    }
    record Waiting(string plate, int kind, int joined);
    record Visit(int entry, int exit, string location, int kind, int total, bool loss);
    class Garage {
        public int now, peak, peakAt;
        public List<List<Spot>> levels=new();
        public List<Spot> spots=new();
        public Dictionary<string,Vehicle> parked=new();
        public List<Waiting> queue=new();
        public SortedDictionary<string,int> passes=new(StringComparer.Ordinal);
        public Dictionary<string,List<Visit>> history=new();
        public int[][] rates={new[]{100,800},new[]{200,1600},new[]{200,1600},new[]{300,2400},new[]{600,4800}};
        public int night=300, lost=2000, kwh=30;
        public int[][] stats=Enumerable.Range(0,5).Select(_ => new int[9]).ToArray();
        public Dictionary<int,int[][]> days=new();
        public List<string> output;
        public int[][] daily(int date) {
            if (!days.TryGetValue(date,out int[][] data)) {
                data=Enumerable.Range(0,5).Select(_ => new int[4]).ToArray();
                days[date]=data;
            }
            return data;
        }
        List<Visit> visitsFor(string plate) {
            if (!history.TryGetValue(plate,out List<Visit> result)) {
                result=new();
                history[plate]=result;
            }
            return result;
        }
        public bool pass(string plate) { return passes.GetValueOrDefault(plate,0)>=now/1440+1; }
        public Vehicle vehicle(string plate) {
            Vehicle v=parked.GetValueOrDefault(plate);
            error(v==null,plate+" is not parked");
            return v;
        }
        public Spot spot(string id) {
            string[] p=id.Substring(1).Split('-');
            int l=int.Parse(p[0]), n=int.Parse(p[1]);
            error(l>levels.Count || n>levels[l-1].Count,"unknown spot "+id);
            return levels[l-1][n-1];
        }
        public List<Spot> assign(int kind) {
            if (kind==4) {
                foreach (List<Spot> level in levels) {
                    for (int i=0;i+2<level.Count;i++) {
                        List<Spot> triple=level.GetRange(i,3);
                        if (triple.All(s => s.kind==2 && s.free())) return triple;
                    }
                }
            } else {
                foreach (int wanted in PREFS[kind]) {
                    Spot first=spots.FirstOrDefault(s => s.kind==wanted && s.free());
                    if (first!=null) return new List<Spot>{first};
                }
            }
            return null;
        }
        public void occupy(Vehicle v) { foreach (Spot s in v.spots) s.occupant=v; }
        public void free(Vehicle v) { foreach (Spot s in v.spots) s.occupant=null; }
        public Vehicle park(string plate, int kind, List<Spot> assigned) {
            Vehicle v=new Vehicle(plate,kind,now,assigned);
            parked[plate]=v;
            occupy(v);
            stats[kind][0]++;
            daily(now/1440+1)[kind][0]++;
            if (parked.Count>peak) {
                peak=parked.Count;
                peakAt=now;
            }
            return v;
        }
        public void refuse(int kind, int at) {
            stats[kind][2]++;
            daily(at/1440+1)[kind][2]++;
        }
        public void giveup() {
            foreach (Waiting w in queue.ToList()) {
                if (now-w.joined>=30) {
                    queue.Remove(w);
                    refuse(w.kind,w.joined+30);
                    output.Add("GIVEUP "+w.plate+" "+TYPES[w.kind]+" "+time(w.joined+30));
                }
            }
        }
        public void admit() {
            foreach (Waiting w in queue.ToList()) {
                List<Spot> assigned=assign(w.kind);
                if (assigned!=null) {
                    queue.Remove(w);
                    Vehicle v=park(w.plate,w.kind,assigned);
                    output.Add("ADMIT "+v.plate+" "+TYPES[v.kind]+" "+v.location()+" waited "+duration(now-w.joined));
                }
            }
        }
        public int[] interval(Vehicle v, int start, int free) {
            int total=now-start;
            if (pass(v.plate) || total<=free) return new int[]{0,0};
            int parking=0;
            for (int offset=0;offset<total;offset+=1440) {
                int billable=Math.Min(total-offset,1440)-(offset==0 ? free : 0);
                parking+=Math.Min((billable+29)/30*rates[v.kind][0],rates[v.kind][1]);
            }
            return new int[]{parking,(now/1440-start/1440)*night};
        }
        public int[] fees(Vehicle v, bool loss) {
            int[] pair=interval(v,v.paidAt<0 ? v.entry : v.paidAt,v.paidAt<0 ? 15+v.validation : 15);
            int parking=pair[0]+(v.paidAt<0 ? 0 : v.paidParking);
            int surcharge=pair[1]+(v.paidAt<0 ? 0 : v.paidNight);
            int ticket=loss ? lost : 0;
            int total=parking+surcharge+ticket+v.charge;
            return new int[]{parking,surcharge,ticket,v.charge,total,v.paidAt<0 ? total : pair[0]+pair[1]};
        }
        public string feeLine(string label, Vehicle v, int[] f) {
            return label+" "+v.plate+" "+v.location()+" stay "+duration(now-v.entry)+" parking "+f[0]+
                " night "+f[1]+" lost "+f[2]+" charge "+f[3]+" total "+f[4]+" due "+f[5];
        }
        public string annotation(Vehicle v) {
            return (pass(v.plate) ? " PASS" : "")+(v.validation>0 ? " VAL "+v.validation : "")+
                (v.energy>0 ? " KWH "+v.energy : "")+(v.paidAt>=0 ? " PAID" : "");
        }
        public List<Vehicle> ordered() {
            return parked.Values.OrderBy(v => v.spots[0].order).ToList();
        }
        public void move(Vehicle v, List<Spot> target) {
            string old=v.location();
            free(v);
            v.spots=target;
            occupy(v);
            output.Add("MOVE "+v.plate+" "+old+" -> "+v.location());
        }
        public int[] occupancy(List<Spot> target) {
            int[] result=new int[9];
            foreach (Spot s in target) {
                if (s.closed) result[8]++;
                else result[4+s.kind]++;
                if (s.occupant!=null) result[s.kind]++;
            }
            return result;
        }
        public string occupancyLine(string label, int[] a) {
            string result=label;
            for (int k=0;k<4;k++) result+=" "+KINDS[k]+" "+a[k]+"/"+a[k+4];
            return result+" closed "+a[8];
        }
        public string revenueLine(string label, int[] a) {
            return label+" exits "+a[1]+" parking "+a[4]+" night "+a[5]+" lost "+a[6]+" charge "+a[7]+" total "+a[8];
        }
        public string statsLine(string label, int[] a) {
            return label+" entries "+a[0]+" exits "+a[1]+" refused "+a[2]+" avg_stay "+tenths(a[1]==0 ? 0 : a[3]*10/a[1]);
        }
        public string dailyLine(string label, int[] a) { return label+" entries "+a[0]+" exits "+a[1]+" refused "+a[2]+" revenue "+a[3]; }
        public int[] sum(int[][] a, int width) => Enumerable.Range(0,width).Select(i => a.Sum(row => row[i])).ToArray();
        public void execute(string[] t) {
            bool trigger=false;
            string command=t[2];
            switch (command) {
                case "LEVEL": {
                    List<Spot> added=new();
                    int[] counts=new int[4];
                    for (int k=0;k<4;k++) {
                        counts[k]=int.Parse(t[k+3]);
                        for (int i=0;i<counts[k];i++) {
                            Spot s=new Spot(levels.Count+1,added.Count+1,k,spots.Count);
                            added.Add(s);
                            spots.Add(s);
                        }
                    }
                    levels.Add(added);
                    output.Add("LEVEL "+levels.Count+" spots "+added.Count+" MOTO "+counts[0]+" COMPACT "+counts[1]+" LARGE "+counts[2]+" EV "+counts[3]);
                    trigger=true;
                    break;
                }
                case "CLOSE":
                case "OPEN": {
                    Spot s=spot(t[3]);
                    if (command.Equals("CLOSE")) {
                        error(s.closed,"spot "+t[3]+" is already closed");
                        error(s.occupant!=null,"spot "+t[3]+" is occupied by "+(s.occupant==null ? "" : s.occupant.plate));
                        s.closed=true;
                    } else {
                        error(!s.closed,"spot "+t[3]+" is not closed");
                        s.closed=false;
                        trigger=true;
                    }
                    output.Add(command+" "+s.id()+" "+KINDS[s.kind]);
                    break;
                }
                case "RATE": {
                    int k=Array.IndexOf(TYPES,t[3]);
                    error(k<0,"unknown type "+t[3]);
                    int rate=int.Parse(t[4]), cap=int.Parse(t[5]);
                    error(cap<rate,"cap below rate for "+t[3]);
                    rates[k]=new int[]{rate,cap};
                    output.Add("RATE "+t[3]+" "+rate+" "+cap);
                    break;
                }
                case "FEE": {
                    int amount=int.Parse(t[4]);
                    error(!new[]{"NIGHT","LOST","KWH"}.Contains(t[3]),"unknown fee "+t[3]);
                    switch (t[3]) {
                        case "NIGHT":
                            night=amount;
                            break;
                        case "LOST":
                            lost=amount;
                            break;
                        default:
                            kwh=amount;
                            break;
                    }
                    output.Add("FEE "+t[3]+" "+amount);
                    break;
                }
                case "ENTER": {
                    string plate=t[3];
                    int k=Array.IndexOf(TYPES,t[4]);
                    error(k<0,"unknown type "+t[4]);
                    Vehicle existing=parked.GetValueOrDefault(plate);
                    error(existing!=null,plate+" is already parked at "+(existing==null ? "" : existing.location()));
                    error(queue.Any(w => w.plate.Equals(plate)),plate+" is already waiting");
                    List<Spot> assigned=assign(k);
                    if (assigned!=null) output.Add("ENTER "+plate+" "+TYPES[k]+" "+park(plate,k,assigned).location());
                    else if (queue.Count<3) {
                        queue.Add(new Waiting(plate,k,now));
                        output.Add("WAIT "+plate+" "+TYPES[k]+" "+queue.Count);
                    } else {
                        refuse(k,now);
                        output.Add("FULL "+plate+" "+TYPES[k]);
                    }
                    break;
                }
                case "LEAVE": {
                    Waiting w=queue.FirstOrDefault(x => x.plate.Equals(t[3]));
                    error(w==null,t[3]+" is not waiting");
                    queue.Remove(w);
                    output.Add("LEAVE "+w.plate+" "+TYPES[w.kind]);
                    break;
                }
                case "EXIT":
                case "PAY":
                case "QUOTE": {
                    Vehicle v=vehicle(t[3]);
                    bool loss=t.Length==5;
                    error(v.paidAt>=0 && (command.Equals("PAY") || loss),v.plate+" has already paid");
                    int[] f=fees(v,loss);
                    if (command.Equals("PAY")) {
                        v.paidAt=now;
                        v.paidParking=f[0];
                        v.paidNight=f[1];
                        output.Add("PAY "+v.plate+" parking "+f[0]+" night "+f[1]+" charge "+f[3]+" total "+f[4]);
                    } else {
                        output.Add(feeLine(command,v,f));
                        if (command.Equals("EXIT")) {
                            visitsFor(v.plate).Add(new Visit(v.entry,now,v.location(),v.kind,f[4],loss));
                            stats[v.kind][1]++;
                            stats[v.kind][3]+=now-v.entry;
                            for (int i=0;i<5;i++) stats[v.kind][i+4]+=f[i];
                            int[] d=daily(now/1440+1)[v.kind];
                            d[1]++;
                            d[3]+=f[4];
                            free(v);
                            parked.Remove(v.plate);
                            trigger=true;
                        }
                    }
                    break;
                }
                case "CHARGE": {
                    Vehicle v=vehicle(t[3]);
                    error(v.kind!=2,v.plate+" is not an electric car");
                    error(v.spots[0].kind!=3,v.plate+" is not at a charger");
                    error(v.paidAt>=0,v.plate+" has already paid");
                    int energy=int.Parse(t[4]);
                    error(v.energy+energy>100,"charge limit exceeded for "+v.plate);
                    int cost=energy*kwh;
                    v.energy+=energy;
                    v.charge+=cost;
                    output.Add("CHARGE "+v.plate+" kwh "+energy+" cost "+cost+" stay_kwh "+v.energy+" stay_cost "+v.charge);
                    break;
                }
                case "VALIDATE": {
                    Vehicle v=vehicle(t[3]);
                    error(v.paidAt>=0,v.plate+" has already paid");
                    int minutes=int.Parse(t[4]);
                    error(v.validation+minutes>180,"validation limit exceeded for "+v.plate);
                    v.validation+=minutes;
                    output.Add("VALIDATE "+v.plate+" "+minutes+" total "+v.validation);
                    break;
                }
                case "PASS": {
                    int end=(pass(t[3]) ? passes[t[3]] : now/1440)+int.Parse(t[4]);
                    passes[t[3]]=end;
                    output.Add("PASS "+t[3]+" until "+end);
                    break;
                }
                case "UNPASS": {
                    error(!pass(t[3]),t[3]+" has no pass");
                    passes.Remove(t[3]);
                    output.Add("UNPASS "+t[3]);
                    break;
                }
                case "MOVE": {
                    Vehicle v=vehicle(t[3]);
                    error(v.kind==4,"bus "+v.plate+" cannot be moved");
                    Spot s=spot(t[4]);
                    error(v.spots[0]==s,v.plate+" is already at "+t[4]);
                    error(s.closed,"spot "+t[4]+" is closed");
                    error(s.occupant!=null,"spot "+t[4]+" is occupied by "+(s.occupant==null ? "" : s.occupant.plate));
                    error(!PREFS[v.kind].Contains(s.kind),TYPES[v.kind]+" cannot use "+KINDS[s.kind]+" spot "+t[4]);
                    move(v,new List<Spot>{s});
                    trigger=true;
                    break;
                }
                case "REBALANCE": {
                    int moved=0;
                    foreach (Vehicle v in ordered()) {
                        if (v.kind==4) continue;
                        List<Spot> target=assign(v.kind);
                        if (target!=null && Array.IndexOf(PREFS[v.kind],target[0].kind)<
                            Array.IndexOf(PREFS[v.kind],v.spots[0].kind)) {
                            move(v,target);
                            moved++;
                        }
                    }
                    output.Add("REBALANCE "+moved);
                    trigger=true;
                    break;
                }
                case "WHERE": {
                    Vehicle v=parked.GetValueOrDefault(t[3]);
                    int p=queue.FindIndex(w => w.plate == t[3]);
                    List<Visit> visits=history.GetValueOrDefault(t[3]);
                    error(v==null && p<0 && visits==null,"unknown plate "+t[3]);
                    if (v!=null) output.Add("WHERE "+v.plate+" "+v.location()+" "+TYPES[v.kind]+" "+time(v.entry)+" stay "+duration(now-v.entry)+annotation(v));
                    else if (p>=0) output.Add("WHERE "+t[3]+" waiting "+(p+1));
                    else output.Add("WHERE "+t[3]+" gone "+time(visits[visits.Count-1].exit));
                    break;
                }
                case "LIST": {
                    int l=t.Length==4 ? int.Parse(t[3]) : 0;
                    error(l>levels.Count,"unknown level "+l);
                    List<Vehicle> found=ordered().Where(v => l==0 || v.spots[0].level==l).ToList();
                    output.Add("LIST "+found.Count);
                    foreach (Vehicle v in found) output.Add(v.location()+" "+v.plate+" "+TYPES[v.kind]+" "+time(v.entry)+annotation(v));
                    break;
                }
                case "MAP": {
                    output.Add("MAP "+levels.Count);
                    for (int i=0;i<levels.Count;i++) {
                        var symbols=levels[i].Select(s => s.closed ? '#' : s.occupant!=null ? KINDS[s.kind][0] : char.ToLowerInvariant(KINDS[s.kind][0]));
                        var chunks=symbols.Chunk(10).Select(chars => new string(chars));
                        output.Add("L"+(i+1)+" "+string.Join(" ",chunks));
                    }
                    break;
                }
                case "OCCUPANCY": {
                    output.Add("OCCUPANCY vehicles "+parked.Count+" waiting "+queue.Count);
                    for (int i=0;i<levels.Count;i++) output.Add(occupancyLine("L"+(i+1),occupancy(levels[i])));
                    int[] a=occupancy(spots);
                    int used=a.Take(4).Sum(), available=a.Skip(4).Take(4).Sum();
                    output.Add(occupancyLine("TOTAL",a)+" rate "+tenths(available==0 ? 0 : used*1000/available)+"%");
                    break;
                }
                case "SIGN": {
                    string line="SIGN";
                    for (int k=0;k<5;k++) {
                        int count=0;
                        if (k==4) {
                            foreach (List<Spot> level in levels) {
                                int run=0;
                                foreach (Spot s in level) {
                                    if (s.kind==2 && s.free()) {
                                        run++;
                                        if (run==3) {
                                            count++;
                                            run=0;
                                        }
                                    } else run=0;
                                }
                            }
                        } else {
                            count=spots.Count(s => PREFS[k].Contains(s.kind) && s.free());
                        }
                        line+=" "+TYPES[k]+" "+(count==0 ? "FULL" : count.ToString());
                    }
                    output.Add(line);
                    break;
                }
                case "RATES": {
                    output.Add("RATES");
                    for (int k=0;k<5;k++) output.Add(TYPES[k]+" "+rates[k][0]+" "+rates[k][1]);
                    output.Add("NIGHT "+night+" LOST "+lost+" KWH "+kwh);
                    break;
                }
                case "PASSES": {
                    List<string> found=passes.Keys.Where(pass).ToList();
                    output.Add("PASSES "+found.Count);
                    foreach (string plate in found) output.Add(plate+" until "+passes[plate]+(parked.ContainsKey(plate) ? " IN" : ""));
                    break;
                }
                case "OVERSTAY": {
                    int hours=int.Parse(t[3]);
                    List<Vehicle> found=ordered().Where(v => now-v.entry>=hours*60).OrderBy(v => v.entry).ToList();
                    output.Add("OVERSTAY "+hours+" "+found.Count);
                    foreach (Vehicle v in found) output.Add(v.location()+" "+v.plate+" "+TYPES[v.kind]+" "+time(v.entry)+" stay "+duration(now-v.entry));
                    break;
                }
                case "HISTORY": {
                    List<Visit> visits=history.GetValueOrDefault(t[3]);
                    error(visits==null,"no history for "+t[3]);
                    output.Add("HISTORY "+t[3]+" visits "+visits.Count+" paid "+visits.Sum(v => v.total));
                    foreach (Visit v in visits) output.Add(time(v.entry)+" "+time(v.exit)+" "+v.location+" "+TYPES[v.kind]+" "+v.total+(v.loss ? " LOST" : ""));
                    break;
                }
                case "REVENUE": {
                    output.Add("REVENUE");
                    for (int k=0;k<5;k++) output.Add(revenueLine(TYPES[k],stats[k]));
                    output.Add(revenueLine("TOTAL",sum(stats,9)));
                    break;
                }
                case "DAILY": {
                    int d=int.Parse(t[3]);
                    int[][] a=daily(d);
                    output.Add(dailyLine("DAILY "+d,sum(a,4)));
                    for (int k=0;k<5;k++) output.Add(dailyLine(TYPES[k],a[k]));
                    break;
                }
                case "STATS": {
                    output.Add("STATS parked "+parked.Count+" peak "+peak+" at "+(peak==0 ? "-" : time(peakAt)));
                    for (int k=0;k<5;k++) output.Add(statsLine(TYPES[k],stats[k]));
                    output.Add(statsLine("ALL",sum(stats,9)));
                    break;
                }
            }
            if (trigger) admit();
        }
        public List<string> process(string line) {
            string[] t=line.Split(' '), hm=t[1].Split(':');
            now=(int.Parse(t[0])-1)*1440+int.Parse(hm[0])*60+int.Parse(hm[1]);
            output=new();
            giveup();
            try { execute(t); }
            catch (Fault f) { output.Add("ERROR "+f.Message); }
            return output;
        }
    }
    static void Main() {
        CultureInfo.CurrentCulture=CultureInfo.InvariantCulture;
        Garage garage=new();
        int n=int.Parse(Console.ReadLine()!);
        for (int i=0;i<n;i++) {
            foreach (string line in garage.process(Console.ReadLine()!)) Console.WriteLine(line);
        }
    }
}
