import java.io.*;
import java.util.*;

public class Main {
    static final String[] TYPES={"MOTORCYCLE","CAR","ECAR","VAN","BUS"};
    static final String[] KINDS={"MOTO","COMPACT","LARGE","EV"};
    static final int[][] PREFS={{0,1,2},{1,2},{3,1,2},{2},{2}};
    static class Fault extends RuntimeException { Fault(String message) { super(message); } }
    static void error(boolean condition, String message) { if (condition) throw new Fault(message); }
    static int index(String[] values, String value) { return Arrays.asList(values).indexOf(value); }
    static String two(int n) { return (n<10 ? "0" : "")+n; }
    static String time(int n) { return (n/1440+1)+"-"+two(n/60%24)+":"+two(n%60); }
    static String duration(int n) { return n/60+":"+two(n%60); }
    static String decimal(int n) { return n/10+"."+n%10; }
    static class Spot {
        int level, number, kind, order;
        boolean closed;
        Vehicle occupant;
        Spot(int level, int number, int kind, int order) {
            this.level=level;
            this.number=number;
            this.kind=kind;
            this.order=order;
        }
        String id() { return "L"+level+"-"+number; }
        boolean free() { return !closed && occupant==null; }
    }
    static class Vehicle {
        String plate;
        int kind, entry, energy, charge, validation, paidAt=-1, paidParking, paidNight;
        List<Spot> spots;
        Vehicle(String plate, int kind, int entry, List<Spot> spots) {
            this.plate=plate;
            this.kind=kind;
            this.entry=entry;
            this.spots=spots;
        }
        String location() { return spots.get(0).id()+(kind==4 ? ".."+spots.get(2).number : ""); }
    }
    record Waiting(String plate, int kind, int joined) {}
    record Visit(int entry, int exit, String location, int kind, int total, boolean loss) {}
    static class Garage {
        int now, peak, peakAt;
        List<List<Spot>> levels=new ArrayList<>();
        List<Spot> spots=new ArrayList<>();
        Map<String,Vehicle> parked=new HashMap<>();
        List<Waiting> queue=new ArrayList<>();
        TreeMap<String,Integer> passes=new TreeMap<>();
        Map<String,List<Visit>> history=new HashMap<>();
        int[][] rates={{100,800},{200,1600},{200,1600},{300,2400},{600,4800}};
        int night=300, lost=2000, kwh=30;
        int[][] stats=new int[5][9];
        Map<Integer,int[][]> days=new HashMap<>();
        List<String> output;
        void emit(String s) { output.add(s); }
        int[][] daily(int date) { return days.computeIfAbsent(date,d -> new int[5][4]); }
        boolean pass(String plate) { return passes.getOrDefault(plate,0)>=now/1440+1; }
        Vehicle vehicle(String plate) {
            Vehicle v=parked.get(plate);
            error(v==null,plate+" is not parked");
            return v;
        }
        Spot spot(String id) {
            String[] p=id.substring(1).split("-");
            int l=Integer.parseInt(p[0]), n=Integer.parseInt(p[1]);
            error(l>levels.size() || n>levels.get(l-1).size(),"unknown spot "+id);
            return levels.get(l-1).get(n-1);
        }
        List<Spot> assign(int kind) {
            if (kind==4) {
                for (List<Spot> level:levels) {
                    for (int i=0;i+2<level.size();i++) {
                        List<Spot> triple=level.subList(i,i+3);
                        if (triple.stream().allMatch(s -> s.kind==2 && s.free())) return new ArrayList<>(triple);
                    }
                }
            } else {
                for (int wanted:PREFS[kind]) {
                    for (Spot s:spots) if (s.kind==wanted && s.free()) return new ArrayList<>(List.of(s));
                }
            }
            return null;
        }
        void occupy(Vehicle v) { for (Spot s:v.spots) s.occupant=v; }
        void free(Vehicle v) { for (Spot s:v.spots) s.occupant=null; }
        Vehicle park(String plate, int kind, List<Spot> assigned) {
            Vehicle v=new Vehicle(plate,kind,now,assigned);
            parked.put(plate,v);
            occupy(v);
            stats[kind][0]++;
            daily(now/1440+1)[kind][0]++;
            if (parked.size()>peak) {
                peak=parked.size();
                peakAt=now;
            }
            return v;
        }
        void refuse(int kind, int at) {
            stats[kind][2]++;
            daily(at/1440+1)[kind][2]++;
        }
        void giveup() {
            for (Waiting w:new ArrayList<>(queue)) {
                if (now-w.joined()>=30) {
                    queue.remove(w);
                    refuse(w.kind(),w.joined()+30);
                    emit("GIVEUP "+w.plate()+" "+TYPES[w.kind()]+" "+time(w.joined()+30));
                }
            }
        }
        void admit() {
            for (Waiting w:new ArrayList<>(queue)) {
                List<Spot> assigned=assign(w.kind());
                if (assigned!=null) {
                    queue.remove(w);
                    Vehicle v=park(w.plate(),w.kind(),assigned);
                    emit("ADMIT "+v.plate+" "+TYPES[v.kind]+" "+v.location()+" waited "+duration(now-w.joined()));
                }
            }
        }
        int[] interval(Vehicle v, int start, int free) {
            int total=now-start;
            if (pass(v.plate) || total<=free) return new int[]{0,0};
            int parking=0;
            for (int offset=0;offset<total;offset+=1440) {
                int billable=Math.min(total-offset,1440)-(offset==0 ? free : 0);
                parking+=Math.min((billable+29)/30*rates[v.kind][0],rates[v.kind][1]);
            }
            return new int[]{parking,(now/1440-start/1440)*night};
        }
        int[] fees(Vehicle v, boolean loss) {
            int[] pair=interval(v,v.paidAt<0 ? v.entry : v.paidAt,v.paidAt<0 ? 15+v.validation : 15);
            int parking=pair[0]+(v.paidAt<0 ? 0 : v.paidParking);
            int surcharge=pair[1]+(v.paidAt<0 ? 0 : v.paidNight);
            int ticket=loss ? lost : 0;
            int total=parking+surcharge+ticket+v.charge;
            return new int[]{parking,surcharge,ticket,v.charge,total,v.paidAt<0 ? total : pair[0]+pair[1]};
        }
        String feeLine(String label, Vehicle v, int[] f) {
            return label+" "+v.plate+" "+v.location()+" stay "+duration(now-v.entry)+" parking "+f[0]+
                " night "+f[1]+" lost "+f[2]+" charge "+f[3]+" total "+f[4]+" due "+f[5];
        }
        String annotation(Vehicle v) {
            return (pass(v.plate) ? " PASS" : "")+(v.validation>0 ? " VAL "+v.validation : "")+
                (v.energy>0 ? " KWH "+v.energy : "")+(v.paidAt>=0 ? " PAID" : "");
        }
        List<Vehicle> ordered() {
            return parked.values().stream().sorted(Comparator.comparingInt(v -> v.spots.get(0).order)).toList();
        }
        void move(Vehicle v, List<Spot> target) {
            String old=v.location();
            free(v);
            v.spots=target;
            occupy(v);
            emit("MOVE "+v.plate+" "+old+" -> "+v.location());
        }
        int[] occupancy(List<Spot> target) {
            int[] result=new int[9];
            for (Spot s:target) {
                if (s.closed) result[8]++;
                else result[4+s.kind]++;
                if (s.occupant!=null) result[s.kind]++;
            }
            return result;
        }
        String occupancyLine(String label, int[] a) {
            String result=label;
            for (int k=0;k<4;k++) result+=" "+KINDS[k]+" "+a[k]+"/"+a[k+4];
            return result+" closed "+a[8];
        }
        String revenueLine(String label, int[] a) {
            return label+" exits "+a[1]+" parking "+a[4]+" night "+a[5]+" lost "+a[6]+" charge "+a[7]+" total "+a[8];
        }
        String statsLine(String label, int[] a) {
            return label+" entries "+a[0]+" exits "+a[1]+" refused "+a[2]+" avg_stay "+decimal(a[1]==0 ? 0 : a[3]*10/a[1]);
        }
        String dailyLine(String label, int[] a) { return label+" entries "+a[0]+" exits "+a[1]+" refused "+a[2]+" revenue "+a[3]; }
        int[] sum(int[][] a, int width) {
            int[] result=new int[width];
            for (int[] row:a) {
                for (int i=0;i<width;i++) result[i]+=row[i];
            }
            return result;
        }
        void execute(String[] t) {
            boolean trigger=false;
            String command=t[2];
            switch (command) {
                case "LEVEL": {
                    List<Spot> added=new ArrayList<>();
                    int[] counts=new int[4];
                    for (int k=0;k<4;k++) {
                        counts[k]=Integer.parseInt(t[k+3]);
                        for (int i=0;i<counts[k];i++) {
                            Spot s=new Spot(levels.size()+1,added.size()+1,k,spots.size());
                            added.add(s);
                            spots.add(s);
                        }
                    }
                    levels.add(added);
                    emit("LEVEL "+levels.size()+" spots "+added.size()+" MOTO "+counts[0]+" COMPACT "+counts[1]+" LARGE "+counts[2]+" EV "+counts[3]);
                    trigger=true;
                    break;
                }
                case "CLOSE", "OPEN": {
                    Spot s=spot(t[3]);
                    if (command.equals("CLOSE")) {
                        error(s.closed,"spot "+t[3]+" is already closed");
                        error(s.occupant!=null,"spot "+t[3]+" is occupied by "+(s.occupant==null ? "" : s.occupant.plate));
                        s.closed=true;
                    } else {
                        error(!s.closed,"spot "+t[3]+" is not closed");
                        s.closed=false;
                        trigger=true;
                    }
                    emit(command+" "+s.id()+" "+KINDS[s.kind]);
                    break;
                }
                case "RATE": {
                    int k=index(TYPES,t[3]);
                    error(k<0,"unknown type "+t[3]);
                    int rate=Integer.parseInt(t[4]), cap=Integer.parseInt(t[5]);
                    error(cap<rate,"cap below rate for "+t[3]);
                    rates[k]=new int[]{rate,cap};
                    emit("RATE "+t[3]+" "+rate+" "+cap);
                    break;
                }
                case "FEE": {
                    int amount=Integer.parseInt(t[4]);
                    error(!List.of("NIGHT","LOST","KWH").contains(t[3]),"unknown fee "+t[3]);
                    switch (t[3]) {
                        case "NIGHT":
                            night=amount;
                            break;
                        case "LOST":
                            lost=amount;
                            break;
                        default: kwh=amount;
                    }
                    emit("FEE "+t[3]+" "+amount);
                    break;
                }
                case "ENTER": {
                    String plate=t[3];
                    int k=index(TYPES,t[4]);
                    error(k<0,"unknown type "+t[4]);
                    Vehicle existing=parked.get(plate);
                    error(existing!=null,plate+" is already parked at "+(existing==null ? "" : existing.location()));
                    error(queue.stream().anyMatch(w -> w.plate().equals(plate)),plate+" is already waiting");
                    List<Spot> assigned=assign(k);
                    if (assigned!=null) emit("ENTER "+plate+" "+TYPES[k]+" "+park(plate,k,assigned).location());
                    else if (queue.size()<3) {
                        queue.add(new Waiting(plate,k,now));
                        emit("WAIT "+plate+" "+TYPES[k]+" "+queue.size());
                    } else {
                        refuse(k,now);
                        emit("FULL "+plate+" "+TYPES[k]);
                    }
                    break;
                }
                case "LEAVE": {
                    Waiting w=queue.stream().filter(x -> x.plate().equals(t[3])).findFirst().orElse(null);
                    error(w==null,t[3]+" is not waiting");
                    queue.remove(w);
                    emit("LEAVE "+w.plate()+" "+TYPES[w.kind()]);
                    break;
                }
                case "EXIT", "PAY", "QUOTE": {
                    Vehicle v=vehicle(t[3]);
                    boolean loss=t.length==5;
                    error(v.paidAt>=0 && (command.equals("PAY") || loss),v.plate+" has already paid");
                    int[] f=fees(v,loss);
                    if (command.equals("PAY")) {
                        v.paidAt=now;
                        v.paidParking=f[0];
                        v.paidNight=f[1];
                        emit("PAY "+v.plate+" parking "+f[0]+" night "+f[1]+" charge "+f[3]+" total "+f[4]);
                    } else {
                        emit(feeLine(command,v,f));
                        if (command.equals("EXIT")) {
                            history.computeIfAbsent(v.plate,p -> new ArrayList<>()).add(new Visit(v.entry,now,v.location(),v.kind,f[4],loss));
                            stats[v.kind][1]++;
                            stats[v.kind][3]+=now-v.entry;
                            for (int i=0;i<5;i++) stats[v.kind][i+4]+=f[i];
                            int[] d=daily(now/1440+1)[v.kind];
                            d[1]++;
                            d[3]+=f[4];
                            free(v);
                            parked.remove(v.plate);
                            trigger=true;
                        }
                    }
                    break;
                }
                case "CHARGE": {
                    Vehicle v=vehicle(t[3]);
                    error(v.kind!=2,v.plate+" is not an electric car");
                    error(v.spots.get(0).kind!=3,v.plate+" is not at a charger");
                    error(v.paidAt>=0,v.plate+" has already paid");
                    int energy=Integer.parseInt(t[4]);
                    error(v.energy+energy>100,"charge limit exceeded for "+v.plate);
                    int cost=energy*kwh;
                    v.energy+=energy;
                    v.charge+=cost;
                    emit("CHARGE "+v.plate+" kwh "+energy+" cost "+cost+" stay_kwh "+v.energy+" stay_cost "+v.charge);
                    break;
                }
                case "VALIDATE": {
                    Vehicle v=vehicle(t[3]);
                    error(v.paidAt>=0,v.plate+" has already paid");
                    int minutes=Integer.parseInt(t[4]);
                    error(v.validation+minutes>180,"validation limit exceeded for "+v.plate);
                    v.validation+=minutes;
                    emit("VALIDATE "+v.plate+" "+minutes+" total "+v.validation);
                    break;
                }
                case "PASS": {
                    int end=(pass(t[3]) ? passes.get(t[3]) : now/1440)+Integer.parseInt(t[4]);
                    passes.put(t[3],end);
                    emit("PASS "+t[3]+" until "+end);
                    break;
                }
                case "UNPASS": {
                    error(!pass(t[3]),t[3]+" has no pass");
                    passes.remove(t[3]);
                    emit("UNPASS "+t[3]);
                    break;
                }
                case "MOVE": {
                    Vehicle v=vehicle(t[3]);
                    error(v.kind==4,"bus "+v.plate+" cannot be moved");
                    Spot s=spot(t[4]);
                    error(v.spots.get(0)==s,v.plate+" is already at "+t[4]);
                    error(s.closed,"spot "+t[4]+" is closed");
                    error(s.occupant!=null,"spot "+t[4]+" is occupied by "+(s.occupant==null ? "" : s.occupant.plate));
                    error(Arrays.stream(PREFS[v.kind]).noneMatch(k -> k==s.kind),TYPES[v.kind]+" cannot use "+KINDS[s.kind]+" spot "+t[4]);
                    move(v,new ArrayList<>(List.of(s)));
                    trigger=true;
                    break;
                }
                case "REBALANCE": {
                    int moved=0;
                    for (Vehicle v:ordered()) {
                        if (v.kind==4) continue;
                        List<Spot> target=assign(v.kind);
                        if (target!=null && Arrays.stream(PREFS[v.kind]).boxed().toList().indexOf(target.get(0).kind)<
                            Arrays.stream(PREFS[v.kind]).boxed().toList().indexOf(v.spots.get(0).kind)) {
                            move(v,target);
                            moved++;
                        }
                    }
                    emit("REBALANCE "+moved);
                    trigger=true;
                    break;
                }
                case "WHERE": {
                    Vehicle v=parked.get(t[3]);
                    int p=-1;
                    for (int i=0;i<queue.size();i++) if (queue.get(i).plate().equals(t[3])) p=i;
                    List<Visit> visits=history.get(t[3]);
                    error(v==null && p<0 && visits==null,"unknown plate "+t[3]);
                    if (v!=null) emit("WHERE "+v.plate+" "+v.location()+" "+TYPES[v.kind]+" "+time(v.entry)+" stay "+duration(now-v.entry)+annotation(v));
                    else if (p>=0) emit("WHERE "+t[3]+" waiting "+(p+1));
                    else emit("WHERE "+t[3]+" gone "+time(visits.get(visits.size()-1).exit()));
                    break;
                }
                case "LIST": {
                    int l=t.length==4 ? Integer.parseInt(t[3]) : 0;
                    error(l>levels.size(),"unknown level "+l);
                    List<Vehicle> found=ordered().stream().filter(v -> l==0 || v.spots.get(0).level==l).toList();
                    emit("LIST "+found.size());
                    for (Vehicle v:found) emit(v.location()+" "+v.plate+" "+TYPES[v.kind]+" "+time(v.entry)+annotation(v));
                    break;
                }
                case "MAP": {
                    emit("MAP "+levels.size());
                    for (int i=0;i<levels.size();i++) {
                        List<String> chunks=new ArrayList<>();
                        StringBuilder symbols=new StringBuilder();
                        for (Spot s:levels.get(i)) symbols.append(s.closed ? '#' : s.occupant!=null ? KINDS[s.kind].charAt(0) : Character.toLowerCase(KINDS[s.kind].charAt(0)));
                        for (int j=0;j<symbols.length();j+=10) chunks.add(symbols.substring(j,Math.min(j+10,symbols.length())));
                        emit("L"+(i+1)+" "+String.join(" ",chunks));
                    }
                    break;
                }
                case "OCCUPANCY": {
                    emit("OCCUPANCY vehicles "+parked.size()+" waiting "+queue.size());
                    for (int i=0;i<levels.size();i++) emit(occupancyLine("L"+(i+1),occupancy(levels.get(i))));
                    int[] a=occupancy(spots);
                    int used=0, available=0;
                    for (int i=0;i<4;i++) {
                        used+=a[i];
                        available+=a[i+4];
                    }
                    emit(occupancyLine("TOTAL",a)+" rate "+decimal(available==0 ? 0 : used*1000/available)+"%");
                    break;
                }
                case "SIGN": {
                    String line="SIGN";
                    for (int k=0;k<5;k++) {
                        int count=0;
                        if (k==4) {
                            for (List<Spot> level:levels) {
                                int run=0;
                                for (Spot s:level) {
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
                            for (int wanted:PREFS[k]) {
                                for (Spot s:spots) if (s.kind==wanted && s.free()) count++;
                            }
                        }
                        line+=" "+TYPES[k]+" "+(count==0 ? "FULL" : Integer.toString(count));
                    }
                    emit(line);
                    break;
                }
                case "RATES": {
                    emit("RATES");
                    for (int k=0;k<5;k++) emit(TYPES[k]+" "+rates[k][0]+" "+rates[k][1]);
                    emit("NIGHT "+night+" LOST "+lost+" KWH "+kwh);
                    break;
                }
                case "PASSES": {
                    List<String> found=passes.keySet().stream().filter(this::pass).toList();
                    emit("PASSES "+found.size());
                    for (String plate:found) emit(plate+" until "+passes.get(plate)+(parked.containsKey(plate) ? " IN" : ""));
                    break;
                }
                case "OVERSTAY": {
                    int hours=Integer.parseInt(t[3]);
                    List<Vehicle> found=ordered().stream().filter(v -> now-v.entry>=hours*60).sorted(Comparator.comparingInt(v -> v.entry)).toList();
                    emit("OVERSTAY "+hours+" "+found.size());
                    for (Vehicle v:found) emit(v.location()+" "+v.plate+" "+TYPES[v.kind]+" "+time(v.entry)+" stay "+duration(now-v.entry));
                    break;
                }
                case "HISTORY": {
                    List<Visit> visits=history.get(t[3]);
                    error(visits==null,"no history for "+t[3]);
                    emit("HISTORY "+t[3]+" visits "+visits.size()+" paid "+visits.stream().mapToInt(Visit::total).sum());
                    for (Visit v:visits) emit(time(v.entry())+" "+time(v.exit())+" "+v.location()+" "+TYPES[v.kind()]+" "+v.total()+(v.loss() ? " LOST" : ""));
                    break;
                }
                case "REVENUE": {
                    emit("REVENUE");
                    for (int k=0;k<5;k++) emit(revenueLine(TYPES[k],stats[k]));
                    emit(revenueLine("TOTAL",sum(stats,9)));
                    break;
                }
                case "DAILY": {
                    int d=Integer.parseInt(t[3]);
                    int[][] a=daily(d);
                    emit(dailyLine("DAILY "+d,sum(a,4)));
                    for (int k=0;k<5;k++) emit(dailyLine(TYPES[k],a[k]));
                    break;
                }
                case "STATS": {
                    emit("STATS parked "+parked.size()+" peak "+peak+" at "+(peak==0 ? "-" : time(peakAt)));
                    for (int k=0;k<5;k++) emit(statsLine(TYPES[k],stats[k]));
                    emit(statsLine("ALL",sum(stats,9)));
                    break;
                }
            }
            if (trigger) admit();
        }
        List<String> process(String line) {
            String[] t=line.split(" "), hm=t[1].split(":");
            now=(Integer.parseInt(t[0])-1)*1440+Integer.parseInt(hm[0])*60+Integer.parseInt(hm[1]);
            output=new ArrayList<>();
            giveup();
            try { execute(t); }
            catch (Fault f) { emit("ERROR "+f.getMessage()); }
            return output;
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input=new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output=new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        Garage garage=new Garage();
        int n=Integer.parseInt(input.readLine());
        for (int i=0;i<n;i++) {
            for (String line:garage.process(input.readLine())) output.println(line);
        }
        output.flush();
    }
}
