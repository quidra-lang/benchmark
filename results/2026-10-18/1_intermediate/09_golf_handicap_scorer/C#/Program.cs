using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

class Program {
    static readonly int NO_NET=1000000;
    class Fault : Exception { public Fault(string reason) : base(reason) {} }
    static void error(bool condition, string reason) { if (condition) throw new Fault(reason); }
    static int away(long n, long d) { return (int)(n<0 ? -((2*(-n)+d)/(2*d)) : (2*n+d)/(2*d)); }
    static int up(long n, long d) { return (int)Floor(2*n+d,2*d); }
    static string signed(int n) { return (n<0 ? "-" : "")+Math.Abs(n)/10+"."+Math.Abs(n)%10; }
    static string index(int? n) { return n==null ? "none" : n.Value<0 ? "+"+signed(-n.Value) : signed(n.Value); }
    static string handicap(int? n) { return n==null ? "none" : n.Value<0 ? "+"+(-n.Value) : n.Value.ToString(); }
    static string cents(int n) { return n/100+"."+(n%100<10 ? "0" : "")+n%100; }
    static string average(int total, int count) { return count==0 ? "-" : cents(total*100/count); }
    static string numbers(int[] a) { return string.Join(" ",a.Select(n => n.ToString())); }
    static int sum(int[] a, int from, int to) {
        int result=0;
        for (int i=from;i<to;i++) result+=a[i];
        return result;
    }
    record Tee(string id, int rating, int slope);
    class Course {
        public string id;
        public int[] par, si;
        public int total;
        public Dictionary<string,Tee> tees=new();
        public Course(string id, int[] par, int[] si) {
            this.id=id;
            this.par=par;
            this.si=si;
            total=sum(par,0,18);
        }
    }
    record IndexRecord(int day, int value);
    record Calculation(int k, int average, int adjustment, int? low, bool hard, bool soft, bool maximum);
    class Round {
        public Course course;
        public Tee tee;
        public int day, ags, diff, exceptional, oldRecords;
        public int? handicap, oldIndex;
        public Calculation oldCalculation;
        public string[] raw;
        public int[] scores, adjusted;
    }
    class Player {
        public string id, name;
        public int? index;
        public Calculation calculation;
        public List<Round> rounds=new();
        public List<IndexRecord> records=new();
        public Player(string id, string name, int? index) { this.id=id; this.name=name; this.index=index; }
    }
    record Event(string id, string format, Course course, Tee tee, int day, int allowance, List<Player> players);
    record Eligible(int start, int[] adjusted, List<int> counting, int k, int adjustment);
    record EventData(Event e, List<Round> rounds, int[] ph, int[] strokes, int[][] nets, int[][] points, int[][] par);
    record Match(List<string> statuses, string result);
    static int[] allocate(Course c, int h) {
        int[] a=new int[18];
        for (int i=0;i<18;i++) a[i]=h>=0 ? h/18+(c.si[i]<=h%18 ? 1 : 0) : -((-h)/18)-(c.si[i]>=19-(-h)%18 ? 1 : 0);
        return a;
    }
    static int courseHandicap(Course c, Tee t, int i) { return up((long)i*t.slope+113L*(t.rating-10*c.total),1130); }
    class Scorer {
        public SortedDictionary<string,Course> courses=new(StringComparer.Ordinal);
        public SortedDictionary<string,Player> players=new(StringComparer.Ordinal);
        public Dictionary<string,Event> events=new();
        public List<Event> eventOrder=new();
        public List<string> output;
        public void emit(string s) { output.Add(s); }
        public Player player(string id) {
            Player p=players.GetValueOrDefault(id);
            error(p==null,"unknown player");
            return p;
        }
        public Course course(string id) {
            Course c=courses.GetValueOrDefault(id);
            error(c==null,"unknown course");
            return c;
        }
        public Tee findTee(Course c, string id) {
            Tee t=c.tees.GetValueOrDefault(id);
            error(t==null,"unknown tee");
            return t;
        }
        public IndexRecord low(Player p, int day) {
            return p.records.Where(r => r.day>=day-365 && r.day<day).OrderBy(r => r.value).ThenBy(r => r.day).FirstOrDefault();
        }
        public Eligible eligible(Player p) {
            int start=Math.Max(0,p.rounds.Count-20), n=p.rounds.Count-start, reduction=0;
            int[] adjusted=new int[n];
            for (int i=n-1;i>=0;i--) {
                Round r=p.rounds[start+i];
                reduction+=r.exceptional;
                adjusted[i]=r.diff-reduction;
            }
            int k=n<3 ? 0 : n<=5 ? 1 : n<=8 ? 2 : n<=11 ? 3 : n<=14 ? 4 : n<=16 ? 5 : n<=18 ? 6 : n==19 ? 7 : 8;
            int adjustment=n==3 ? -20 : n==4 || n==6 ? -10 : 0;
            List<int> order=new();
            for (int i=0;i<n;i++) order.Add(i);
            order=order.OrderBy(i => adjusted[i]).ThenByDescending(i => i).ToList();
            return new Eligible(start,adjusted,order.GetRange(0,k),k,adjustment);
        }
        public void update(Player p, int day) {
            Eligible e=eligible(p);
            if (e.k==0) {
                p.calculation=null;
                return;
            }
            int total=0;
            foreach (int i in e.counting) total+=e.adjusted[i];
            int a=away(total,e.k), c=a+e.adjustment;
            IndexRecord record=low(p,day);
            int? l=record==null ? null : record.value;
            bool soft=false,hard=false,maximum=false;
            if (l!=null && c-l.Value>30) {
                int next=l.Value+30+(c-l.Value-30)/2;
                soft=next!=c;
                c=next;
            }
            if (l!=null && c-l.Value>50) {
                c=l.Value+50;
                hard=true;
            }
            if (c>540) {
                c=540;
                maximum=true;
            }
            p.index=c;
            p.calculation=new Calculation(e.k,a,e.adjustment,l,hard,soft,maximum);
        }
        public EventData data(Event e) {
            List<Round> rounds=new();
            int n=e.players.Count;
            int[] ph=new int[n], strokes=new int[n];
            for (int i=0;i<n;i++) {
                Round r=e.players[i].rounds.FirstOrDefault(x => x.course==e.course && x.tee==e.tee && x.day==e.day);
                error(r==null,"missing round");
                error(r.handicap==null,"no index");
                rounds.Add(r);
                ph[i]=up((long)r.handicap.Value*e.allowance,100);
            }
            int minimum=ph.Min();
            bool relative=new[]{"MATCH","NASSAU","FOURBALL"}.Contains(e.format);
            int[][] nets=Matrix(n), points=Matrix(n), par=Matrix(n);
            for (int i=0;i<n;i++) {
                strokes[i]=ph[i]-(relative ? minimum : 0);
                int[] allocation=allocate(e.course,strokes[i]);
                for (int h=0;h<18;h++) {
                    nets[i][h]=rounds[i].scores[h]==NO_NET ? NO_NET : rounds[i].scores[h]-allocation[h];
                    points[i][h]=nets[i][h]==NO_NET ? 0 : Math.Max(0,e.course.par[h]+2-nets[i][h]);
                    par[i][h]=nets[i][h]==NO_NET || nets[i][h]>e.course.par[h] ? -1 : nets[i][h]<e.course.par[h] ? 1 : 0;
                }
            }
            return new EventData(e,rounds,ph,strokes,nets,points,par);
        }
        public List<int> rank(int[][] values, List<int> candidates, bool high, List<string> ids) {
            List<int> result=new(candidates);
            result.Sort((a,b) => {
                foreach (int start in new int[]{0,9,12,15,17}) {
                    int cmp=CompareInt(sum(values[a],start,18),sum(values[b],start,18));
                    if (cmp!=0) return high ? -cmp : cmp;
                }
                return StringComparer.Ordinal.Compare(ids[a],ids[b]);
            });
            return result;
        }
        public List<int> all(int n) {
            List<int> a=new();
            for (int i=0;i<n;i++) a.Add(i);
            return a;
        }
        public List<int> ranked(EventData d) {
            List<int> candidates=all(d.ph.Length);
            if (d.e.format.Equals("STROKE")) candidates.RemoveAll(i => d.rounds[i].scores.Any(s => s==NO_NET));
            int[][] values=d.e.format.Equals("STROKE") ? d.nets : d.e.format.Equals("PAR") ? d.par : d.points;
            return rank(values,candidates,!d.e.format.Equals("STROKE"),d.e.players.Select(p => p.id).ToList());
        }
        public string status(int lead) { return lead==0 ? "AS" : lead>0 ? lead+" UP" : (-lead)+" DN"; }
        public Match match(int[] wins, int first, int last, string a, string b) {
            int lead=0,remaining=0;
            List<string> statuses=new();
            for (int h=first;h<=last;h++) {
                lead+=wins[h];
                remaining=last-h;
                statuses.Add(status(lead));
                if (Math.Abs(lead)>remaining) break;
            }
            string result=lead==0 ? "AS" : (lead>0 ? a : b)+" "+Math.Abs(lead)+(remaining>0 ? "&"+remaining : " UP");
            return new Match(statuses,result);
        }
        public void results(Event e, EventData d) {
            emit("results "+e.id+": "+e.format+" "+e.course.id+" "+e.tee.id+" day "+e.day+" allowance "+e.allowance);
            int n=e.players.Count;
            List<string> ids=e.players.Select(p => p.id).ToList();
            if (new[]{"STROKE","STABLEFORD","PAR"}.Contains(e.format)) {
                List<int> order=ranked(d);
                for (int r=0;r<order.Count;r++) {
                    int i=order[r];
                    string value=e.format.Equals("STROKE") ? "net "+sum(d.nets[i],0,18)+" gross "+sum(d.rounds[i].scores,0,18) :
                        e.format.Equals("STABLEFORD") ? "points "+sum(d.points[i],0,18) : status(sum(d.par[i],0,18));
                    emit((r+1)+" "+ids[i]+" "+value+" hcp "+handicap(d.ph[i]));
                }
                if (e.format.Equals("STROKE")) {
                    List<int> nr=all(n);
                    nr.RemoveAll(i => order.Contains(i));
                    nr=nr.OrderBy(i => ids[i],StringComparer.Ordinal).ToList();
                    foreach (int i in nr) emit("NR "+ids[i]+" hcp "+handicap(d.ph[i]));
                    if (order.Count!=0) {
                        int[][] gross=new int[n][];
                        for (int i=0;i<n;i++) gross[i]=d.rounds[i].scores;
                        int winner=rank(gross,order,false,ids)[0];
                        emit("gross "+ids[winner]+" "+sum(gross[winner],0,18));
                    }
                }
            } else if (new[]{"MATCH","NASSAU","FOURBALL"}.Contains(e.format)) {
                string line="strokes";
                for (int i=0;i<n;i++) line+=" "+ids[i]+" "+d.strokes[i];
                emit(line);
                int size=n/2;
                string a=string.Join("+",ids.Take(size)), b=string.Join("+",ids.Skip(size));
                int[] wins=new int[18];
                for (int h=0;h<18;h++) {
                    int left=NO_NET,right=NO_NET;
                    for (int i=0;i<size;i++) left=Math.Min(left,d.nets[i][h]);
                    for (int i=size;i<n;i++) right=Math.Min(right,d.nets[i][h]);
                    wins[h]=CompareInt(right,left);
                }
                if (e.format.Equals("NASSAU")) {
                    emit("front "+match(wins,0,8,a,b).result);
                    emit("back "+match(wins,9,17,a,b).result);
                    emit("total "+match(wins,0,17,a,b).result);
                } else {
                    Match m=match(wins,0,17,a,b);
                    emit("status "+string.Join(", ",m.statuses));
                    emit("result "+m.result);
                }
            } else if (e.format.Equals("BETTERBALL")) {
                int[][] values=Matrix(n/2);
                List<string> keys=new();
                for (int i=0;i<n/2;i++) {
                    keys.Add(ids[2*i]);
                    for (int h=0;h<18;h++) values[i][h]=Math.Max(d.points[2*i][h],d.points[2*i+1][h]);
                }
                List<int> order=rank(values,all(n/2),true,keys);
                for (int r=0;r<order.Count;r++) {
                    int i=order[r];
                    emit((r+1)+" "+ids[2*i]+"+"+ids[2*i+1]+" points "+sum(values[i],0,18)+" hcp "+handicap(d.ph[2*i])+" "+handicap(d.ph[2*i+1]));
                }
            } else {
                int carry=0;
                int[] totals=new int[n];
                List<int> tied=all(n);
                for (int h=0;h<18;h++) {
                    carry++;
                    int minimum=NO_NET;
                    for (int i=0;i<n;i++) minimum=Math.Min(minimum,d.nets[i][h]);
                    tied=new();
                    for (int i=0;i<n;i++) if (d.nets[i][h]==minimum) tied.Add(i);
                    if (minimum!=NO_NET && tied.Count==1) {
                        int i=tied[0];
                        emit("hole "+(h+1)+" "+ids[i]+" "+carry);
                        totals[i]+=carry*100;
                        carry=0;
                    }
                }
                if (carry>0) {
                    tied=tied.OrderBy(i => ids[i],StringComparer.Ordinal).ToList();
                    string line="carry "+carry;
                    foreach (int i in tied) {
                        line+=" "+ids[i];
                        totals[i]+=carry*100/tied.Count;
                    }
                    emit(line);
                }
                List<int> order=all(n);
                order=order.OrderByDescending(i => totals[i]).ThenBy(i => ids[i],StringComparer.Ordinal).ToList();
                foreach (int i in order) emit(ids[i]+" "+cents(totals[i]));
            }
        }
        public void card(Player p, int number, Round r) {
            emit("card "+p.id+" "+number+": "+r.course.id+" "+r.tee.id+" day "+r.day+" handicap "+handicap(r.handicap));
            int[] strokes=allocate(r.course,r.handicap ?? 0), nets=new int[18], points=new int[18];
            for (int h=0;h<18;h++) {
                nets[h]=r.scores[h]==NO_NET ? NO_NET : r.scores[h]-strokes[h];
                points[h]=nets[h]==NO_NET ? 0 : Math.Max(0,r.course.par[h]+2-nets[h]);
                emit((h+1)+" "+r.course.par[h]+" "+r.course.si[h]+" "+r.raw[h]+" "+r.adjusted[h]+" "+strokes[h]+" "+(nets[h]==NO_NET ? "-" : Convert.ToString(nets[h]))+" "+points[h]);
                if (h==8) cardTotal("OUT",r,strokes,nets,points,0,9);
                if (h==17) {
                    cardTotal("IN",r,strokes,nets,points,9,18);
                    cardTotal("TOTAL",r,strokes,nets,points,0,18);
                }
            }
            emit("ags "+r.ags+" diff "+signed(r.diff));
        }
        public void cardTotal(string label, Round r, int[] strokes, int[] nets, int[] points, int from, int to) {
            bool complete=true;
            for (int h=from;h<to;h++) if (r.scores[h]==NO_NET) complete=false;
            emit(label+" "+sum(r.course.par,from,to)+" "+(complete ? Convert.ToString(sum(r.scores,from,to)) : "-")+" "+sum(r.adjusted,from,to)+
                " "+sum(strokes,from,to)+" "+(complete ? Convert.ToString(sum(nets,from,to)) : "-")+" "+sum(points,from,to));
        }
        public void statistics(Player p) {
            int[] category=new int[7], totals=new int[3], counts=new int[3];
            List<int> complete=new();
            foreach (Round r in p.rounds) {
                bool full=true;
                for (int h=0;h<18;h++) {
                    if (r.raw[h].Equals("X")) category[6]++;
                    if (r.scores[h]==NO_NET) {
                        full=false;
                        continue;
                    }
                    int relative=r.scores[h]-r.course.par[h];
                    category[relative<=-2 ? 0 : relative==-1 ? 1 : relative==0 ? 2 : relative==1 ? 3 : relative==2 ? 4 : 5]++;
                    int i=r.course.par[h]-3;
                    totals[i]+=r.scores[h];
                    counts[i]++;
                }
                if (full) complete.Add(sum(r.scores,0,18));
            }
            string line="stats "+p.id+": rounds "+p.rounds.Count+" best "+(complete.Count==0 ? "-" : complete.Min().ToString())+" average "+
                average(complete.Sum(),complete.Count);
            string[] labels={"eagles","birdies","pars","bogeys","doubles","others","pickups"};
            for (int i=0;i<7;i++) line+=" "+labels[i]+" "+category[i];
            for (int i=0;i<3;i++) line+=" par"+(i+3)+" "+average(totals[i],counts[i]);
            emit(line);
        }
        public void execute(string[] t) {
            switch (t[0]) {
                case "COURSE": {
                    error(courses.ContainsKey(t[1]),"duplicate course");
                    int[] par=new int[18],si=new int[18];
                    for (int i=0;i<18;i++) {
                        par[i]=int.Parse(t[i+2]);
                        si[i]=int.Parse(t[i+20]);
                    }
                    error(par.Any(x => x<3 || x>5) || si.Distinct().Count()!=18 || si.Any(x => x<1 || x>18),"invalid course");
                    courses[t[1]]=new Course(t[1],par,si);
                    break;
                }
                case "TEE": {
                    Course c=course(t[1]);
                    error(c.tees.ContainsKey(t[2]),"duplicate tee");
                    int rating=int.Parse(t[3]),slope=int.Parse(t[4]);
                    error(rating<500 || rating>900 || slope<55 || slope>155,"invalid tee");
                    c.tees[t[2]]=new Tee(t[2],rating,slope);
                    break;
                }
                case "PLAYER": {
                    error(players.ContainsKey(t[1]),"duplicate player");
                    int? i=t.Length==4 ? int.Parse(t[3]) : null;
                    error(i!=null && (i< -100 || i>540),"invalid index");
                    players[t[1]]=new Player(t[1],t[2],i);
                    break;
                }
                case "ROUND": {
                    Player p=player(t[1]);
                    Course c=course(t[2]);
                    Tee tee=findTee(c,t[3]);
                    int day=int.Parse(t[4]);
                    error(p.rounds.Count!=0 && day<p.rounds[p.rounds.Count-1].day,"invalid day");
                    string[] raw=t.Skip(5).Take(18).ToArray();
                    error(raw.Count(s => s.Equals("-"))>=5,"too few holes");
                    Round r=new Round();
                    r.course=c;
                    r.tee=tee;
                    r.day=day;
                    r.raw=raw;
                    r.oldIndex=p.index;
                    r.oldCalculation=p.calculation;
                    r.oldRecords=p.records.Count;
                    r.handicap=p.index==null ? null : courseHandicap(c,tee,p.index.Value);
                    int[] strokes=allocate(c,r.handicap ?? 0);
                    r.scores=new int[18];
                    r.adjusted=new int[18];
                    for (int h=0;h<18;h++) {
                        int limit=c.par[h]+(p.index==null ? 5 : 2+strokes[h]);
                        r.scores[h]=raw[h].Equals("X") || raw[h].Equals("-") ? NO_NET : int.Parse(raw[h]);
                        r.adjusted[h]=raw[h].Equals("-") ? c.par[h]+strokes[h] : raw[h].Equals("X") ? limit : Math.Min(r.scores[h],limit);
                    }
                    r.ags=sum(r.adjusted,0,18);
                    r.diff=away(113L*(10*r.ags-tee.rating),tee.slope);
                    r.exceptional=p.index!=null && p.index.Value-r.diff>=70 ? (p.index.Value-r.diff>=100 ? 20 : 10) : 0;
                    p.rounds.Add(r);
                    update(p,day);
                    if (p.index!=null) p.records.Add(new IndexRecord(day,p.index.Value));
                    emit("round "+p.id+" "+p.rounds.Count+": ags "+r.ags+" diff "+signed(r.diff)+(r.exceptional==0 ? "" : " exceptional "+signed(-r.exceptional))+" index "+index(p.index));
                    break;
                }
                case "REMOVE": {
                    Player p=player(t[1]);
                    error(p.rounds.Count==0,"no rounds");
                    int number=p.rounds.Count;
                    Round r=RemoveLast(p.rounds);
                    p.index=r.oldIndex;
                    p.calculation=r.oldCalculation;
                    p.records.RemoveRange(r.oldRecords,p.records.Count-r.oldRecords);
                    emit("removed "+p.id+" "+number+": index "+index(p.index));
                    break;
                }
                case "INDEX": {
                    Player p=player(t[1]);
                    string line="index "+p.id+": "+index(p.index)+" rounds "+p.rounds.Count;
                    Calculation c=p.calculation;
                    if (c!=null) line+=" lowest "+c.k+" average "+signed(c.average)+" adjustment "+signed(c.adjustment)+
                        (c.low==null ? "" : " low "+index(c.low))+(c.hard ? " hard cap" : c.soft ? " soft cap" : "")+(c.maximum ? " maximum" : "");
                    emit(line);
                    break;
                }
                case "HISTORY": {
                    Player p=player(t[1]);
                    Eligible e=eligible(p);
                    emit("history "+p.id+": rounds "+p.rounds.Count);
                    for (int i=0;i<e.adjusted.Length;i++) {
                        Round r=p.rounds[e.start+i];
                        emit((e.start+i+1)+" day "+r.day+" "+r.course.id+" "+r.tee.id+" ags "+r.ags+" diff "+signed(r.diff)+
                            (r.diff==e.adjusted[i] ? "" : " adjusted "+signed(e.adjusted[i]))+(e.counting.Contains(i) ? " *" : ""));
                    }
                    break;
                }
                case "LOWINDEX": {
                    Player p=player(t[1]);
                    int day=int.Parse(t[2]);
                    IndexRecord r=low(p,day);
                    emit("lowindex "+p.id+" "+day+": "+(r==null ? "none" : index(r.value)+" day "+r.day));
                    break;
                }
                case "COURSEHCP": {
                    Player p=player(t[1]);
                    Course c=course(t[2]);
                    Tee tee=findTee(c,t[3]);
                    error(p.index==null,"no index");
                    int h=courseHandicap(c,tee,p.index.Value);
                    emit("coursehcp "+p.id+" "+c.id+" "+tee.id+": "+handicap(h)+" strokes "+numbers(allocate(c,h)));
                    break;
                }
                case "HCPTABLE": {
                    Course c=course(t[1]);
                    Tee tee=findTee(c,t[2]);
                    int first=int.Parse(t[3]),last=int.Parse(t[4]);
                    error(first< -100 || first>last || last>540,"invalid index");
                    emit("hcptable "+c.id+" "+tee.id+": "+index(first)+" to "+index(last));
                    int start=first,h=courseHandicap(c,tee,first);
                    for (int i=first+1;i<=last+1;i++) {
                        int next=i<=last ? courseHandicap(c,tee,i) : h+1;
                        if (next!=h) {
                            emit(index(start)+" to "+index(i-1)+": "+handicap(h));
                            start=i;
                            h=next;
                        }
                    }
                    break;
                }
                case "CARD": {
                    Player p=player(t[1]);
                    int n=int.Parse(t[2]);
                    error(n>p.rounds.Count,"unknown round");
                    card(p,n,p.rounds[n-1]);
                    break;
                }
                case "STATS":
                    statistics(player(t[1]));
                    break;
                case "HOLESTATS": {
                    Course c=course(t[1]);
                    List<Round> rounds=players.Values.SelectMany(p => p.rounds).Where(r => r.course==c).ToList();
                    int[] totals=new int[18],counts=new int[18],ranks=new int[18];
                    foreach (Round r in rounds) {
                        for (int h=0;h<18;h++) {
                            if (r.scores[h]!=NO_NET) {
                                totals[h]+=r.scores[h];
                                counts[h]++;
                            }
                        }
                    }
                    List<int> order=all(18);
                    order.Sort((a,b) => {
                        if (counts[a]==0 || counts[b]==0) return counts[a]==counts[b] ? CompareInt(a,b) : counts[a]==0 ? 1 : -1;
                        int cmp=CompareLong((long)(totals[b]-c.par[b]*counts[b])*counts[a],(long)(totals[a]-c.par[a]*counts[a])*counts[b]);
                        return cmp==0 ? CompareInt(a,b) : cmp;
                    });
                    for (int i=0;i<18;i++) ranks[order[i]]=i+1;
                    emit("holestats "+c.id+": rounds "+rounds.Count);
                    for (int h=0;h<18;h++) emit((h+1)+" par "+c.par[h]+" si "+c.si[h]+" scores "+counts[h]+" avg "+average(totals[h],counts[h])+" rank "+ranks[h]);
                    break;
                }
                case "PLAYERS": {
                    List<Player> order=new(players.Values);
                    order=order.OrderBy(p => p.index==null).ThenBy(p => p.index).ThenBy(p => p.id,StringComparer.Ordinal).ToList();
                    emit("players "+order.Count);
                    foreach (Player p in order) emit(p.id+" "+p.name+" "+index(p.index)+" rounds "+p.rounds.Count);
                    break;
                }
                case "EVENT": {
                    error(events.ContainsKey(t[1]),"duplicate event");
                    Course c=course(t[3]);
                    Tee tee=findTee(c,t[4]);
                    int allowance=int.Parse(t[6]);
                    error(allowance<1 || allowance>100,"invalid allowance");
                    List<Player> list=new();
                    for (int i=7;i<t.Length;i++) list.Add(player(t[i]));
                    int n=list.Count;
                    bool valid=t[2] switch { "MATCH" or "NASSAU" => n==2, "FOURBALL" => n==4, "BETTERBALL" => n==4 || n==6 || n==8, _ => n>=2 && n<=8 };
                    error(new HashSet<Player>(list).Count!=n || !valid,"invalid players");
                    events[t[1]]=new Event(t[1],t[2],c,tee,int.Parse(t[5]),allowance,list);
                    eventOrder.Add(events[t[1]]);
                    break;
                }
                case "RESULTS": {
                    Event e=events.GetValueOrDefault(t[1]);
                    error(e==null,"unknown event");
                    EventData d=data(e);
                    results(e,d);
                    break;
                }
                case "MERIT": {
                    Dictionary<string,int[]> merit=new();
                    int count=0;
                    int[] awards={10,8,6,5,4,3,2,1};
                    foreach (Event e in eventOrder) {
                        if (!new[]{"STROKE","STABLEFORD","PAR"}.Contains(e.format)) continue;
                        EventData d;
                        try { d=data(e); }
                        catch (Fault f) { continue; }
                        count++;
                        foreach (Player p in e.players) MeritRow(merit,p.id)[2]++;
                        List<int> placing=ranked(d);
                        for (int i=0;i<placing.Count;i++) {
                            string id=e.players[placing[i]].id;
                            merit[id][0]+=awards[i];
                            if (i==0) merit[id][1]++;
                        }
                    }
                    List<string> order=new(merit.Keys);
                    order=order.OrderByDescending(id => merit[id][0]).ThenByDescending(id => merit[id][1]).ThenBy(id => id,StringComparer.Ordinal).ToList();
                    emit("merit: events "+count);
                    for (int i=0;i<order.Count;i++) {
                        string id=order[i];
                        int[] a=merit[id];
                        emit((i+1)+" "+id+" "+a[0]+" wins "+a[1]+" played "+a[2]);
                    }
                    break;
                }
            }
        }
        public List<string> process(string line) {
            output=new();
            try { execute(line.Split(' ')); }
            catch (Fault f) { emit("ERROR "+f.Message); }
            return output;
        }
    }
    static long Floor(long n, long d) => n/d-(n%d<0 ? 1 : 0);
    static int CompareLong(long a, long b) => a.CompareTo(b);
    static int CompareInt(int a, int b) => a.CompareTo(b);
    static int[][] Matrix(int n) => Enumerable.Range(0,n).Select(_ => new int[18]).ToArray();
    static Round RemoveLast(List<Round> rounds) {
        Round r=rounds[^1];
        rounds.RemoveAt(rounds.Count-1);
        return r;
    }
    static int[] MeritRow(Dictionary<string,int[]> merit, string id) {
        if (!merit.TryGetValue(id,out int[] row)) {
            row=new int[3];
            merit[id]=row;
        }
        return row;
    }
    static void Main() {
        CultureInfo.CurrentCulture=CultureInfo.InvariantCulture;
        Scorer scorer=new();
        int n=int.Parse(Console.ReadLine()!);
        for (int i=0;i<n;i++) {
            foreach (string line in scorer.process(Console.ReadLine()!)) Console.WriteLine(line);
        }
    }
}
