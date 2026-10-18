import java.io.*;
import java.util.*;

public class Main {
    static final int NO_NET=1000000;
    static class Fault extends RuntimeException { Fault(String reason) { super(reason); } }
    static void error(boolean condition, String reason) { if (condition) throw new Fault(reason); }
    static int away(long n, long d) { return (int)(n<0 ? -((2*(-n)+d)/(2*d)) : (2*n+d)/(2*d)); }
    static int up(long n, long d) { return (int)Math.floorDiv(2*n+d,2*d); }
    static String signed(int n) { return (n<0 ? "-" : "")+Math.abs(n)/10+"."+Math.abs(n)%10; }
    static String index(Integer n) { return n==null ? "none" : n<0 ? "+"+signed(-n) : signed(n); }
    static String handicap(Integer n) { return n==null ? "none" : n<0 ? "+"+(-n) : n.toString(); }
    static String cents(int n) { return n/100+"."+(n%100<10 ? "0" : "")+n%100; }
    static String average(int total, int count) { return count==0 ? "-" : cents(total*100/count); }
    static String numbers(int[] a) { return String.join(" ",Arrays.stream(a).mapToObj(Integer::toString).toList()); }
    static int sum(int[] a, int from, int to) {
        int result=0;
        for (int i=from;i<to;i++) result+=a[i];
        return result;
    }
    record Tee(String id, int rating, int slope) {}
    static class Course {
        String id;
        int[] par, si;
        int total;
        Map<String,Tee> tees=new HashMap<>();
        Course(String id, int[] par, int[] si) {
            this.id=id;
            this.par=par;
            this.si=si;
            total=sum(par,0,18);
        }
    }
    record IndexRecord(int day, int value) {}
    record Calculation(int k, int average, int adjustment, Integer low, boolean hard, boolean soft, boolean maximum) {}
    static class Round {
        Course course;
        Tee tee;
        int day, ags, diff, exceptional, oldRecords;
        Integer handicap, oldIndex;
        Calculation oldCalculation;
        String[] raw;
        int[] scores, adjusted;
    }
    static class Player {
        String id, name;
        Integer index;
        Calculation calculation;
        List<Round> rounds=new ArrayList<>();
        List<IndexRecord> records=new ArrayList<>();
        Player(String id, String name, Integer index) { this.id=id; this.name=name; this.index=index; }
    }
    record Event(String id, String format, Course course, Tee tee, int day, int allowance, List<Player> players) {}
    record Eligible(int start, int[] adjusted, List<Integer> counting, int k, int adjustment) {}
    record EventData(Event event, List<Round> rounds, int[] ph, int[] strokes, int[][] nets, int[][] points, int[][] par) {}
    record Match(List<String> statuses, String result) {}
    static int[] allocate(Course c, int h) {
        int[] a=new int[18];
        for (int i=0;i<18;i++) a[i]=h>=0 ? h/18+(c.si[i]<=h%18 ? 1 : 0) : -((-h)/18)-(c.si[i]>=19-(-h)%18 ? 1 : 0);
        return a;
    }
    static int courseHandicap(Course c, Tee t, int i) { return up((long)i*t.slope()+113L*(t.rating()-10*c.total),1130); }
    static class Scorer {
        TreeMap<String,Course> courses=new TreeMap<>();
        TreeMap<String,Player> players=new TreeMap<>();
        LinkedHashMap<String,Event> events=new LinkedHashMap<>();
        List<String> output;
        void emit(String s) { output.add(s); }
        Player player(String id) {
            Player p=players.get(id);
            error(p==null,"unknown player");
            return p;
        }
        Course course(String id) {
            Course c=courses.get(id);
            error(c==null,"unknown course");
            return c;
        }
        Tee tee(Course c, String id) {
            Tee t=c.tees.get(id);
            error(t==null,"unknown tee");
            return t;
        }
        IndexRecord low(Player p, int day) {
            return p.records.stream().filter(r -> r.day()>=day-365 && r.day()<day)
                .min(Comparator.comparingInt(IndexRecord::value).thenComparingInt(IndexRecord::day)).orElse(null);
        }
        Eligible eligible(Player p) {
            int start=Math.max(0,p.rounds.size()-20), n=p.rounds.size()-start, reduction=0;
            int[] adjusted=new int[n];
            for (int i=n-1;i>=0;i--) {
                Round r=p.rounds.get(start+i);
                reduction+=r.exceptional;
                adjusted[i]=r.diff-reduction;
            }
            int k=n<3 ? 0 : n<=5 ? 1 : n<=8 ? 2 : n<=11 ? 3 : n<=14 ? 4 : n<=16 ? 5 : n<=18 ? 6 : n==19 ? 7 : 8;
            int adjustment=n==3 ? -20 : n==4 || n==6 ? -10 : 0;
            List<Integer> order=new ArrayList<>();
            for (int i=0;i<n;i++) order.add(i);
            order.sort(Comparator.comparingInt((Integer i) -> adjusted[i]).thenComparing(Comparator.reverseOrder()));
            return new Eligible(start,adjusted,new ArrayList<>(order.subList(0,k)),k,adjustment);
        }
        void update(Player p, int day) {
            Eligible e=eligible(p);
            if (e.k()==0) {
                p.calculation=null;
                return;
            }
            int total=0;
            for (int i:e.counting()) total+=e.adjusted()[i];
            int a=away(total,e.k()), c=a+e.adjustment();
            IndexRecord record=low(p,day);
            Integer l=record==null ? null : record.value();
            boolean soft=false,hard=false,maximum=false;
            if (l!=null && c-l>30) {
                int next=l+30+(c-l-30)/2;
                soft=next!=c;
                c=next;
            }
            if (l!=null && c-l>50) {
                c=l+50;
                hard=true;
            }
            if (c>540) {
                c=540;
                maximum=true;
            }
            p.index=c;
            p.calculation=new Calculation(e.k(),a,e.adjustment(),l,hard,soft,maximum);
        }
        EventData data(Event e) {
            List<Round> rounds=new ArrayList<>();
            int n=e.players().size();
            int[] ph=new int[n], strokes=new int[n];
            for (int i=0;i<n;i++) {
                Round r=e.players().get(i).rounds.stream().filter(x -> x.course==e.course() && x.tee==e.tee() && x.day==e.day()).findFirst().orElse(null);
                error(r==null,"missing round");
                error(r.handicap==null,"no index");
                rounds.add(r);
                ph[i]=up((long)r.handicap*e.allowance(),100);
            }
            int minimum=Arrays.stream(ph).min().orElse(0);
            boolean relative=List.of("MATCH","NASSAU","FOURBALL").contains(e.format());
            int[][] nets=new int[n][18], points=new int[n][18], par=new int[n][18];
            for (int i=0;i<n;i++) {
                strokes[i]=ph[i]-(relative ? minimum : 0);
                int[] allocation=allocate(e.course(),strokes[i]);
                for (int h=0;h<18;h++) {
                    nets[i][h]=rounds.get(i).scores[h]==NO_NET ? NO_NET : rounds.get(i).scores[h]-allocation[h];
                    points[i][h]=nets[i][h]==NO_NET ? 0 : Math.max(0,e.course().par[h]+2-nets[i][h]);
                    par[i][h]=nets[i][h]==NO_NET || nets[i][h]>e.course().par[h] ? -1 : nets[i][h]<e.course().par[h] ? 1 : 0;
                }
            }
            return new EventData(e,rounds,ph,strokes,nets,points,par);
        }
        List<Integer> rank(int[][] values, List<Integer> candidates, boolean high, List<String> ids) {
            List<Integer> result=new ArrayList<>(candidates);
            result.sort((a,b) -> {
                for (int start:new int[]{0,9,12,15,17}) {
                    int cmp=Integer.compare(sum(values[a],start,18),sum(values[b],start,18));
                    if (cmp!=0) return high ? -cmp : cmp;
                }
                return ids.get(a).compareTo(ids.get(b));
            });
            return result;
        }
        List<Integer> all(int n) {
            List<Integer> a=new ArrayList<>();
            for (int i=0;i<n;i++) a.add(i);
            return a;
        }
        List<Integer> ranked(EventData d) {
            List<Integer> candidates=all(d.ph().length);
            if (d.event().format().equals("STROKE")) candidates.removeIf(i -> Arrays.stream(d.rounds().get(i).scores).anyMatch(s -> s==NO_NET));
            int[][] values=d.event().format().equals("STROKE") ? d.nets() : d.event().format().equals("PAR") ? d.par() : d.points();
            return rank(values,candidates,!d.event().format().equals("STROKE"),d.event().players().stream().map(p -> p.id).toList());
        }
        String status(int lead) { return lead==0 ? "AS" : lead>0 ? lead+" UP" : (-lead)+" DN"; }
        Match match(int[] wins, int first, int last, String a, String b) {
            int lead=0,remaining=0;
            List<String> statuses=new ArrayList<>();
            for (int h=first;h<=last;h++) {
                lead+=wins[h];
                remaining=last-h;
                statuses.add(status(lead));
                if (Math.abs(lead)>remaining) break;
            }
            String result=lead==0 ? "AS" : (lead>0 ? a : b)+" "+Math.abs(lead)+(remaining>0 ? "&"+remaining : " UP");
            return new Match(statuses,result);
        }
        void results(Event e, EventData d) {
            emit("results "+e.id()+": "+e.format()+" "+e.course().id+" "+e.tee().id()+" day "+e.day()+" allowance "+e.allowance());
            int n=e.players().size();
            List<String> ids=e.players().stream().map(p -> p.id).toList();
            if (List.of("STROKE","STABLEFORD","PAR").contains(e.format())) {
                List<Integer> order=ranked(d);
                for (int r=0;r<order.size();r++) {
                    int i=order.get(r);
                    String value=e.format().equals("STROKE") ? "net "+sum(d.nets()[i],0,18)+" gross "+sum(d.rounds().get(i).scores,0,18) :
                        e.format().equals("STABLEFORD") ? "points "+sum(d.points()[i],0,18) : status(sum(d.par()[i],0,18));
                    emit((r+1)+" "+ids.get(i)+" "+value+" hcp "+handicap(d.ph()[i]));
                }
                if (e.format().equals("STROKE")) {
                    List<Integer> nr=all(n);
                    nr.removeAll(order);
                    nr.sort(Comparator.comparing(ids::get));
                    for (int i:nr) emit("NR "+ids.get(i)+" hcp "+handicap(d.ph()[i]));
                    if (!order.isEmpty()) {
                        int[][] gross=new int[n][];
                        for (int i=0;i<n;i++) gross[i]=d.rounds().get(i).scores;
                        int winner=rank(gross,order,false,ids).get(0);
                        emit("gross "+ids.get(winner)+" "+sum(gross[winner],0,18));
                    }
                }
            } else if (List.of("MATCH","NASSAU","FOURBALL").contains(e.format())) {
                String line="strokes";
                for (int i=0;i<n;i++) line+=" "+ids.get(i)+" "+d.strokes()[i];
                emit(line);
                int size=n/2;
                String a=String.join("+",ids.subList(0,size)), b=String.join("+",ids.subList(size,n));
                int[] wins=new int[18];
                for (int h=0;h<18;h++) {
                    int left=NO_NET,right=NO_NET;
                    for (int i=0;i<size;i++) left=Math.min(left,d.nets()[i][h]);
                    for (int i=size;i<n;i++) right=Math.min(right,d.nets()[i][h]);
                    wins[h]=Integer.compare(right,left);
                }
                if (e.format().equals("NASSAU")) {
                    emit("front "+match(wins,0,8,a,b).result());
                    emit("back "+match(wins,9,17,a,b).result());
                    emit("total "+match(wins,0,17,a,b).result());
                } else {
                    Match m=match(wins,0,17,a,b);
                    emit("status "+String.join(", ",m.statuses()));
                    emit("result "+m.result());
                }
            } else if (e.format().equals("BETTERBALL")) {
                int[][] values=new int[n/2][18];
                List<String> keys=new ArrayList<>();
                for (int i=0;i<n/2;i++) {
                    keys.add(ids.get(2*i));
                    for (int h=0;h<18;h++) values[i][h]=Math.max(d.points()[2*i][h],d.points()[2*i+1][h]);
                }
                List<Integer> order=rank(values,all(n/2),true,keys);
                for (int r=0;r<order.size();r++) {
                    int i=order.get(r);
                    emit((r+1)+" "+ids.get(2*i)+"+"+ids.get(2*i+1)+" points "+sum(values[i],0,18)+" hcp "+handicap(d.ph()[2*i])+" "+handicap(d.ph()[2*i+1]));
                }
            } else {
                int carry=0;
                int[] totals=new int[n];
                List<Integer> tied=all(n);
                for (int h=0;h<18;h++) {
                    carry++;
                    int minimum=NO_NET;
                    for (int i=0;i<n;i++) minimum=Math.min(minimum,d.nets()[i][h]);
                    tied=new ArrayList<>();
                    for (int i=0;i<n;i++) if (d.nets()[i][h]==minimum) tied.add(i);
                    if (minimum!=NO_NET && tied.size()==1) {
                        int i=tied.get(0);
                        emit("hole "+(h+1)+" "+ids.get(i)+" "+carry);
                        totals[i]+=carry*100;
                        carry=0;
                    }
                }
                if (carry>0) {
                    tied.sort(Comparator.comparing(ids::get));
                    String line="carry "+carry;
                    for (int i:tied) {
                        line+=" "+ids.get(i);
                        totals[i]+=carry*100/tied.size();
                    }
                    emit(line);
                }
                List<Integer> order=all(n);
                order.sort(Comparator.comparingInt((Integer i) -> -totals[i]).thenComparing(ids::get));
                for (int i:order) emit(ids.get(i)+" "+cents(totals[i]));
            }
        }
        void card(Player p, int number, Round r) {
            emit("card "+p.id+" "+number+": "+r.course.id+" "+r.tee.id()+" day "+r.day+" handicap "+handicap(r.handicap));
            int[] strokes=allocate(r.course,r.handicap==null ? 0 : r.handicap), nets=new int[18], points=new int[18];
            for (int h=0;h<18;h++) {
                nets[h]=r.scores[h]==NO_NET ? NO_NET : r.scores[h]-strokes[h];
                points[h]=nets[h]==NO_NET ? 0 : Math.max(0,r.course.par[h]+2-nets[h]);
                emit((h+1)+" "+r.course.par[h]+" "+r.course.si[h]+" "+r.raw[h]+" "+r.adjusted[h]+" "+strokes[h]+" "+(nets[h]==NO_NET ? "-" : Integer.toString(nets[h]))+" "+points[h]);
                if (h==8) cardTotal("OUT",r,strokes,nets,points,0,9);
                if (h==17) {
                    cardTotal("IN",r,strokes,nets,points,9,18);
                    cardTotal("TOTAL",r,strokes,nets,points,0,18);
                }
            }
            emit("ags "+r.ags+" diff "+signed(r.diff));
        }
        void cardTotal(String label, Round r, int[] strokes, int[] nets, int[] points, int from, int to) {
            boolean complete=true;
            for (int h=from;h<to;h++) if (r.scores[h]==NO_NET) complete=false;
            emit(label+" "+sum(r.course.par,from,to)+" "+(complete ? Integer.toString(sum(r.scores,from,to)) : "-")+" "+sum(r.adjusted,from,to)+
                " "+sum(strokes,from,to)+" "+(complete ? Integer.toString(sum(nets,from,to)) : "-")+" "+sum(points,from,to));
        }
        void statistics(Player p) {
            int[] category=new int[7], totals=new int[3], counts=new int[3];
            List<Integer> complete=new ArrayList<>();
            for (Round r:p.rounds) {
                boolean full=true;
                for (int h=0;h<18;h++) {
                    if (r.raw[h].equals("X")) category[6]++;
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
                if (full) complete.add(sum(r.scores,0,18));
            }
            String line="stats "+p.id+": rounds "+p.rounds.size()+" best "+(complete.isEmpty() ? "-" : Collections.min(complete))+" average "+
                average(complete.stream().mapToInt(Integer::intValue).sum(),complete.size());
            String[] labels={"eagles","birdies","pars","bogeys","doubles","others","pickups"};
            for (int i=0;i<7;i++) line+=" "+labels[i]+" "+category[i];
            for (int i=0;i<3;i++) line+=" par"+(i+3)+" "+average(totals[i],counts[i]);
            emit(line);
        }
        void execute(String[] t) {
            switch (t[0]) {
                case "COURSE": {
                    error(courses.containsKey(t[1]),"duplicate course");
                    int[] par=new int[18],si=new int[18];
                    for (int i=0;i<18;i++) {
                        par[i]=Integer.parseInt(t[i+2]);
                        si[i]=Integer.parseInt(t[i+20]);
                    }
                    error(Arrays.stream(par).anyMatch(x -> x<3 || x>5) || Arrays.stream(si).distinct().count()!=18 || Arrays.stream(si).anyMatch(x -> x<1 || x>18),"invalid course");
                    courses.put(t[1],new Course(t[1],par,si));
                    break;
                }
                case "TEE": {
                    Course c=course(t[1]);
                    error(c.tees.containsKey(t[2]),"duplicate tee");
                    int rating=Integer.parseInt(t[3]),slope=Integer.parseInt(t[4]);
                    error(rating<500 || rating>900 || slope<55 || slope>155,"invalid tee");
                    c.tees.put(t[2],new Tee(t[2],rating,slope));
                    break;
                }
                case "PLAYER": {
                    error(players.containsKey(t[1]),"duplicate player");
                    Integer i=t.length==4 ? Integer.parseInt(t[3]) : null;
                    error(i!=null && (i< -100 || i>540),"invalid index");
                    players.put(t[1],new Player(t[1],t[2],i));
                    break;
                }
                case "ROUND": {
                    Player p=player(t[1]);
                    Course c=course(t[2]);
                    Tee tee=tee(c,t[3]);
                    int day=Integer.parseInt(t[4]);
                    error(!p.rounds.isEmpty() && day<p.rounds.get(p.rounds.size()-1).day,"invalid day");
                    String[] raw=Arrays.copyOfRange(t,5,23);
                    error(Arrays.stream(raw).filter(s -> s.equals("-")).count()>=5,"too few holes");
                    Round r=new Round();
                    r.course=c;
                    r.tee=tee;
                    r.day=day;
                    r.raw=raw;
                    r.oldIndex=p.index;
                    r.oldCalculation=p.calculation;
                    r.oldRecords=p.records.size();
                    r.handicap=p.index==null ? null : courseHandicap(c,tee,p.index);
                    int[] strokes=allocate(c,r.handicap==null ? 0 : r.handicap);
                    r.scores=new int[18];
                    r.adjusted=new int[18];
                    for (int h=0;h<18;h++) {
                        int limit=c.par[h]+(p.index==null ? 5 : 2+strokes[h]);
                        r.scores[h]=raw[h].equals("X") || raw[h].equals("-") ? NO_NET : Integer.parseInt(raw[h]);
                        r.adjusted[h]=raw[h].equals("-") ? c.par[h]+strokes[h] : raw[h].equals("X") ? limit : Math.min(r.scores[h],limit);
                    }
                    r.ags=sum(r.adjusted,0,18);
                    r.diff=away(113L*(10*r.ags-tee.rating()),tee.slope());
                    r.exceptional=p.index!=null && p.index-r.diff>=70 ? (p.index-r.diff>=100 ? 20 : 10) : 0;
                    p.rounds.add(r);
                    update(p,day);
                    if (p.index!=null) p.records.add(new IndexRecord(day,p.index));
                    emit("round "+p.id+" "+p.rounds.size()+": ags "+r.ags+" diff "+signed(r.diff)+(r.exceptional==0 ? "" : " exceptional "+signed(-r.exceptional))+" index "+index(p.index));
                    break;
                }
                case "REMOVE": {
                    Player p=player(t[1]);
                    error(p.rounds.isEmpty(),"no rounds");
                    int number=p.rounds.size();
                    Round r=p.rounds.remove(number-1);
                    p.index=r.oldIndex;
                    p.calculation=r.oldCalculation;
                    p.records.subList(r.oldRecords,p.records.size()).clear();
                    emit("removed "+p.id+" "+number+": index "+index(p.index));
                    break;
                }
                case "INDEX": {
                    Player p=player(t[1]);
                    String line="index "+p.id+": "+index(p.index)+" rounds "+p.rounds.size();
                    Calculation c=p.calculation;
                    if (c!=null) line+=" lowest "+c.k()+" average "+signed(c.average())+" adjustment "+signed(c.adjustment())+
                        (c.low()==null ? "" : " low "+index(c.low()))+(c.hard() ? " hard cap" : c.soft() ? " soft cap" : "")+(c.maximum() ? " maximum" : "");
                    emit(line);
                    break;
                }
                case "HISTORY": {
                    Player p=player(t[1]);
                    Eligible e=eligible(p);
                    emit("history "+p.id+": rounds "+p.rounds.size());
                    for (int i=0;i<e.adjusted().length;i++) {
                        Round r=p.rounds.get(e.start()+i);
                        emit((e.start()+i+1)+" day "+r.day+" "+r.course.id+" "+r.tee.id()+" ags "+r.ags+" diff "+signed(r.diff)+
                            (r.diff==e.adjusted()[i] ? "" : " adjusted "+signed(e.adjusted()[i]))+(e.counting().contains(i) ? " *" : ""));
                    }
                    break;
                }
                case "LOWINDEX": {
                    Player p=player(t[1]);
                    int day=Integer.parseInt(t[2]);
                    IndexRecord r=low(p,day);
                    emit("lowindex "+p.id+" "+day+": "+(r==null ? "none" : index(r.value())+" day "+r.day()));
                    break;
                }
                case "COURSEHCP": {
                    Player p=player(t[1]);
                    Course c=course(t[2]);
                    Tee tee=tee(c,t[3]);
                    error(p.index==null,"no index");
                    int h=courseHandicap(c,tee,p.index);
                    emit("coursehcp "+p.id+" "+c.id+" "+tee.id()+": "+handicap(h)+" strokes "+numbers(allocate(c,h)));
                    break;
                }
                case "HCPTABLE": {
                    Course c=course(t[1]);
                    Tee tee=tee(c,t[2]);
                    int first=Integer.parseInt(t[3]),last=Integer.parseInt(t[4]);
                    error(first< -100 || first>last || last>540,"invalid index");
                    emit("hcptable "+c.id+" "+tee.id()+": "+index(first)+" to "+index(last));
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
                    int n=Integer.parseInt(t[2]);
                    error(n>p.rounds.size(),"unknown round");
                    card(p,n,p.rounds.get(n-1));
                    break;
                }
                case "STATS":
                    statistics(player(t[1]));
                    break;
                case "HOLESTATS": {
                    Course c=course(t[1]);
                    List<Round> rounds=players.values().stream().flatMap(p -> p.rounds.stream()).filter(r -> r.course==c).toList();
                    int[] totals=new int[18],counts=new int[18],ranks=new int[18];
                    for (Round r:rounds) {
                        for (int h=0;h<18;h++) {
                            if (r.scores[h]!=NO_NET) {
                                totals[h]+=r.scores[h];
                                counts[h]++;
                            }
                        }
                    }
                    List<Integer> order=all(18);
                    order.sort((a,b) -> {
                        if (counts[a]==0 || counts[b]==0) return counts[a]==counts[b] ? Integer.compare(a,b) : counts[a]==0 ? 1 : -1;
                        int cmp=Long.compare((long)(totals[b]-c.par[b]*counts[b])*counts[a],(long)(totals[a]-c.par[a]*counts[a])*counts[b]);
                        return cmp==0 ? Integer.compare(a,b) : cmp;
                    });
                    for (int i=0;i<18;i++) ranks[order.get(i)]=i+1;
                    emit("holestats "+c.id+": rounds "+rounds.size());
                    for (int h=0;h<18;h++) emit((h+1)+" par "+c.par[h]+" si "+c.si[h]+" scores "+counts[h]+" avg "+average(totals[h],counts[h])+" rank "+ranks[h]);
                    break;
                }
                case "PLAYERS": {
                    List<Player> order=new ArrayList<>(players.values());
                    order.sort(Comparator.comparing((Player p) -> p.index,Comparator.nullsLast(Comparator.naturalOrder())).thenComparing(p -> p.id));
                    emit("players "+order.size());
                    for (Player p:order) emit(p.id+" "+p.name+" "+index(p.index)+" rounds "+p.rounds.size());
                    break;
                }
                case "EVENT": {
                    error(events.containsKey(t[1]),"duplicate event");
                    Course c=course(t[3]);
                    Tee tee=tee(c,t[4]);
                    int allowance=Integer.parseInt(t[6]);
                    error(allowance<1 || allowance>100,"invalid allowance");
                    List<Player> list=new ArrayList<>();
                    for (int i=7;i<t.length;i++) list.add(player(t[i]));
                    int n=list.size();
                    boolean valid=switch(t[2]) { case "MATCH","NASSAU" -> n==2; case "FOURBALL" -> n==4; case "BETTERBALL" -> n==4 || n==6 || n==8; default -> n>=2 && n<=8; };
                    error(new HashSet<>(list).size()!=n || !valid,"invalid players");
                    events.put(t[1],new Event(t[1],t[2],c,tee,Integer.parseInt(t[5]),allowance,list));
                    break;
                }
                case "RESULTS": {
                    Event e=events.get(t[1]);
                    error(e==null,"unknown event");
                    EventData d=data(e);
                    results(e,d);
                    break;
                }
                case "MERIT": {
                    Map<String,int[]> merit=new HashMap<>();
                    int count=0;
                    int[] awards={10,8,6,5,4,3,2,1};
                    for (Event e:events.values()) {
                        if (!List.of("STROKE","STABLEFORD","PAR").contains(e.format())) continue;
                        EventData d;
                        try { d=data(e); }
                        catch (Fault f) { continue; }
                        count++;
                        for (Player p:e.players()) merit.computeIfAbsent(p.id,id -> new int[3])[2]++;
                        List<Integer> order=ranked(d);
                        for (int i=0;i<order.size();i++) {
                            String id=e.players().get(order.get(i)).id;
                            merit.get(id)[0]+=awards[i];
                            if (i==0) merit.get(id)[1]++;
                        }
                    }
                    List<String> order=new ArrayList<>(merit.keySet());
                    order.sort(Comparator.comparingInt((String id) -> -merit.get(id)[0]).thenComparingInt(id -> -merit.get(id)[1]).thenComparing(Comparator.naturalOrder()));
                    emit("merit: events "+count);
                    for (int i=0;i<order.size();i++) {
                        String id=order.get(i);
                        int[] a=merit.get(id);
                        emit((i+1)+" "+id+" "+a[0]+" wins "+a[1]+" played "+a[2]);
                    }
                    break;
                }
            }
        }
        List<String> process(String line) {
            output=new ArrayList<>();
            try { execute(line.split(" ")); }
            catch (Fault f) { emit("ERROR "+f.getMessage()); }
            return output;
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input=new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output=new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        Scorer scorer=new Scorer();
        int n=Integer.parseInt(input.readLine());
        for (int i=0;i<n;i++) {
            for (String line:scorer.process(input.readLine())) output.println(line);
        }
        output.flush();
    }
}
