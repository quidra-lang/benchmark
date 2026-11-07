import java.io.*;
import java.util.*;
public class Main {
    static final List<String> ALGOS=List.of("FCFS","SJF","SRTF","RR","PRIORITY","HRRN","EDF","LOTTERY","MLFQ");
    static final List<String> KEYS=List.of("cs","q","k","s","seed"), METRICS=List.of("turnaround","waiting","response"), EVENTS=List.of("PREEMPT","EXPIRE","DEMOTE","BOOST","AGE");
    static final long[] LOW={
        0,1,1,0,1
    },HIGH={
        5,20,50,500,2147483646L
    };
    static class Failure extends RuntimeException {
        Failure(String m) {
            super(m);
        }
    }
    static void check(boolean bad,String reason) {
        if(bad) throw new Failure(reason);
    }
    static String ratio(long u,long v) {
        long n=u*100/v;
        return n/100+"."+String.format(Locale.ROOT,"%02d",n%100);
    }
    static List<String> allowed(String a) {
        return switch(a) {
            case "RR" -> List.of("cs","q");
            case "PRIORITY" -> List.of("cs","k");
            case "MLFQ" -> List.of("cs","s");
            case "LOTTERY" -> List.of("cs","q","seed");
            default -> List.of("cs");
        };
    }
    static boolean valid(String k,long v) {
        int i=KEYS.indexOf(k);
        return v>=LOW[i]&&v<=HIGH[i];
    }
    static Map<String,Long> parameters(List<String> words,String algo,String preset) {
        Map<String,Long> p=new LinkedHashMap<>();
        p.put("cs",0L);
        p.put("q",4L);
        p.put("k",5L);
        p.put("s",0L);
        p.put("seed",1L);
        Set<String> seen=new HashSet<>();
        if(preset!=null) seen.add(preset);
        for(String word:words) {
            String[] parts=word.split("=");
            String k=parts[0];
            long v=Long.parseLong(parts[1]);
            check(!KEYS.contains(k),"unknown key "+k);
            check(algo!=null&&!allowed(algo).contains(k),"key "+k+" not allowed for "+algo);
            check(seen.contains(k),"duplicate key "+k);
            check(!valid(k,v),"invalid "+k);
            seen.add(k);
            p.put(k,v);
        }
        return p;
    }
    static String notation(Map<String,Long> p,String algo) {
        List<String> ks=algo==null?KEYS:allowed(algo);
        return String.join(" ",ks.stream().map(k -> k+"="+p.get(k)).toList());
    }
    static class RandomState {
        long x;
        RandomState(long x) {
            this.x=x;
        }
        int draw(int n) {
            x=48271*x%2147483647;
            return (int)(x%n);
        }
    }
    static class Process {
        String id;
        int arrival,priority,deadline;
        List<Integer> bursts;
        Process(String id,int arrival,int priority,List<Integer> bursts) {
            this.id=id;
            this.arrival=arrival;
            this.priority=priority;
            this.bursts=bursts;
        }
        int absolute() {
            return deadline==0?Integer.MAX_VALUE:arrival+deadline;
        }
        String describe() {
            List<String> bs=new ArrayList<>();
            for(int i=0;i<bursts.size();i++) bs.add((i%2==0?"C":"I")+bursts.get(i));
            return id+" arrival="+arrival+" priority="+priority+" deadline="+(deadline==0?"none":deadline)+" bursts="+String.join(",",bs);
        }
    }
    static class Burst {
        int length,ready,start=-1,end,slices;
        Burst(int l,int r) {
            length=l;
            ready=r;
        }
    }
    static class Job {
        Process p;
        String state="FUTURE";
        int burst,left,effective,wait,level,used,enqueued,start=-1,finish;
        List<Burst> records=new ArrayList<>();
        StringBuilder timeline=new StringBuilder();
        Job(Process p) {
            this.p=p;
            left=p.bursts.getFirst();
            effective=p.priority;
        }
        String id() {
            return p.id;
        }
        void advance() {
            left=p.bursts.get(++burst);
        }
        int slices() {
            return records.stream().mapToInt(b -> b.slices).sum();
        }
        long[] metrics() {
            int turn=finish-p.arrival;
            return new long[]{
                turn,turn-p.bursts.stream().mapToInt(Integer::intValue).sum(),start-p.arrival
            };
        }
        boolean missed() {
            return p.deadline>0&&finish>p.absolute();
        }
    }
    static class Simulation {
        String algo,cpu="IDLE";
        Map<String,Long> p;
        List<Job> jobs=new ArrayList<>();
        List<List<Job>> queues=new ArrayList<>();
        Job current,previous;
        int time,switchLeft,runLength,switches,snapshotTime;
        RandomState random;
        List<String> events=new ArrayList<>(),labels=new ArrayList<>(),cpuStates=new ArrayList<>(),snapshot;
        Map<String,Integer> counts=new HashMap<>();
        List<Integer> lengths=new ArrayList<>();
        Simulation(Collection<Process> processes,String algo,Map<String,Long> p,int snapshotTime) {
            this.algo=algo;
            this.p=p;
            this.snapshotTime=snapshotTime;
            for(Process process:processes) jobs.add(new Job(process));
            jobs.sort(Comparator.comparing(Job::id));
            for(int i=0;i<3;i++) queues.add(new ArrayList<>());
            random=new RandomState(p.get("seed"));
            run();
        }
        void event(String kind,Object... details) {
            String text=time+" "+kind;
            for(Object detail:details) text+=" "+detail;
            events.add(text);
            counts.merge(kind,1,Integer::sum);
        }
        void enqueue(Job j) {
            j.state="READY";
            j.enqueued=time;
            queues.get(algo.equals("MLFQ")?j.level:0).add(j);
        }
        void release() {
            cpu="IDLE";
            current=null;
        }
        void start(Job j) {
            current=j;
            cpu=j.state="RUN";
            runLength=0;
            if(j.start<0) j.start=time;
            if(j.records.getLast().start<0) j.records.getLast().start=time;
        }
        boolean preempts(Job j) {
            return switch(algo) {
                case "SRTF" -> queues.getFirst().stream().anyMatch(o -> o.left<j.left);
                case "PRIORITY" -> queues.getFirst().stream().anyMatch(o -> o.effective<j.effective);
                case "EDF" -> queues.getFirst().stream().anyMatch(o -> o.p.absolute()<j.p.absolute());
                case "MLFQ" -> queues.subList(0,j.level).stream().anyMatch(q -> !q.isEmpty());
                default -> false;
            };
        }
        Job choose(List<Job> q) {
            Job best=q.getFirst();
            if(algo.equals("LOTTERY")) {
                int r=random.draw(q.stream().mapToInt(j -> 10-j.p.priority).sum());
                for(Job j:q) {
                    r-=10-j.p.priority;
                    if(r<0) return j;
                }
            }
            for(Job j:q) {
                boolean better=switch(algo) {
                    case "SJF","SRTF" -> j.left<best.left;
                    case "PRIORITY" -> j.effective<best.effective;
                    case "EDF" -> j.p.absolute()<best.p.absolute();
                    case "HRRN" -> (long)(time-j.enqueued+j.left)*best.left>(long)(time-best.enqueued+best.left)*j.left;
                    default -> false;
                };
                if(better) best=j;
            }
            return best;
        }
        void run() {
            while(true) {
                if(algo.equals("PRIORITY")) for(Job j:queues.getFirst()) {
                    if(++j.wait==p.get("k")) {
                        j.wait=0;
                        if(j.effective>0) {
                            j.effective--;
                            event("AGE",j.id(),j.effective);
                        }
                    }
                }
                for(Job j:jobs) if(j.state.equals("IO")&&j.left==0) {
                    j.advance();
                    j.records.add(new Burst(j.left,time));
                    enqueue(j);
                    event("IODONE",j.id());
                }
                for(Job j:jobs) if(j.state.equals("FUTURE")&&j.p.arrival==time) {
                    j.records.add(new Burst(j.left,time));
                    enqueue(j);
                    event("ARRIVE",j.id());
                }
                if(cpu.equals("SWITCH")&&switchLeft==0) {
                    start(current);
                    event("START",current.id());
                }
                else if(cpu.equals("RUN")) {
                    Job j=current;
                    if(j.left==0&&j.burst==j.p.bursts.size()-1) {
                        j.state="DONE";
                        j.finish=time;
                        event("DONE",j.id());
                        release();
                    }
                    else {
                        boolean demoted=algo.equals("MLFQ")&&j.level<2&&j.used==(j.level==0?4:8);
                        if(demoted) {
                            j.level++;
                            j.used=0;
                            event("DEMOTE",j.id(),j.level);
                        }
                        if(j.left==0) {
                            j.advance();
                            j.state="IO";
                            event("IO",j.id(),j.left);
                            release();
                        }
                        else if(demoted) {
                            enqueue(j);
                            release();
                        }
                        else if((algo.equals("RR")||algo.equals("LOTTERY"))&&runLength==p.get("q")) {
                            enqueue(j);
                            event("EXPIRE",j.id());
                            release();
                        }
                        else if(preempts(j)) {
                            enqueue(j);
                            event("PREEMPT",j.id());
                            release();
                        }
                    }
                }
                if(jobs.stream().allMatch(j -> j.state.equals("DONE"))) break;
                if(algo.equals("MLFQ")&&p.get("s")>0&&time>0&&time%p.get("s")==0) {
                    queues.getFirst().addAll(queues.get(1));
                    queues.getFirst().addAll(queues.get(2));
                    queues.get(1).clear();
                    queues.get(2).clear();
                    for(Job j:jobs) {
                        j.level=0;
                        j.used=0;
                    }
                    event("BOOST");
                }
                if(cpu.equals("IDLE")) {
                    List<Job> q=queues.stream().filter(xs -> !xs.isEmpty()).findFirst().orElse(null);
                    if(q!=null) {
                        Job j=algo.equals("MLFQ")?q.getFirst():choose(q);
                        q.remove(j);
                        j.effective=j.p.priority;
                        j.wait=0;
                        j.records.getLast().slices++;
                        boolean switched=j!=previous;
                        if(switched) switches++;
                        if(switched&&p.get("cs")>0) {
                            current=j;
                            cpu=j.state="SWITCH";
                            switchLeft=p.get("cs").intValue();
                            event("SWITCH",j.id());
                        }
                        else {
                            start(j);
                            event("DISPATCH",j.id());
                        }
                    }
                }
                if(time==snapshotTime) capture();
                for(Job j:jobs) j.timeline.append(switch(j.state) {
                    case "READY" -> '.';
                    case "SWITCH" -> 's';
                    case "RUN" -> '#';
                    case "IO" -> 'i';
                    default -> '-';
                });
                lengths.add(queues.stream().mapToInt(List::size).sum());
                cpuStates.add(cpu);
                if(cpu.equals("RUN")) {
                    current.left--;
                    current.used++;
                    runLength++;
                    previous=current;
                    labels.add(current.id());
                    if(current.left==0) current.records.getLast().end=time+1;
                }
                else if(cpu.equals("SWITCH")) {
                    switchLeft--;
                    labels.add("CS");
                } else labels.add("IDLE");
                for(Job j:jobs) if(j.state.equals("IO")) j.left--;
                time++;
            }
            if(snapshot==null) capture();
        }
        void capture() {
            snapshot=new ArrayList<>();
            snapshot.add("CPU "+cpu+(current==null?"":" "+current.id()));
            for(int i=0;i<(algo.equals("MLFQ")?3:1);i++) {
                List<Job> q=queues.get(i);
                snapshot.add("QUEUE"+(algo.equals("MLFQ")?i:"")+" "+(q.isEmpty()?"none":String.join(" ",q.stream().map(Job::id).toList())));
            }
            for(Job j:jobs) {
                String s=j.id()+" "+j.state;
                if(j.state.equals("FUTURE")) s+=" at="+j.p.arrival;
                else if(j.state.equals("DONE")) s+=" at="+j.finish;
                else {
                    s+=" burst="+(j.burst+1)+" left="+j.left;
                    if(algo.equals("PRIORITY")) s+=" prio="+j.effective;
                    if(algo.equals("MLFQ")) s+=" level="+j.level+" used="+j.used;
                }
                snapshot.add(s);
            }
        }
        long[] totals() {
            long[] result=new long[3];
            for(Job j:jobs) {
                long[] m=j.metrics();
                for(int i=0;i<3;i++) result[i]+=m[i];
            }
            return result;
        }
        String averages() {
            long[] t=totals();
            return "turnaround="+ratio(t[0],jobs.size())+" waiting="+ratio(t[1],jobs.size())+" response="+ratio(t[2],jobs.size());
        }
        int[] ticks(int a,int b) {
            int[] counts=new int[3];
            for(String state:cpuStates.subList(a,b)) counts[state.equals("RUN")?0:state.equals("SWITCH")?1:2]++;
            return counts;
        }
        String util() {
            return ratio(ticks(0,time)[0]*100L,time);
        }
        int missed() {
            return (int)jobs.stream().filter(Job::missed).count();
        }
        int met() {
            return (int)jobs.stream().filter(j -> j.p.deadline>0&&!j.missed()).count();
        }
    }
    static class Scheduler {
        Map<String,Process> registry=new TreeMap<>();
        StringBuilder out=new StringBuilder();
        void emit(String s) {
            out.append(s).append('\n');
        }
        Process process(String id) {
            check(!registry.containsKey(id),"unknown process "+id);
            return registry.get(id);
        }
        void algorithm(String algo) {
            check(!ALGOS.contains(algo),"unknown algorithm "+algo);
        }
        Map<String,Long> prepare(List<String> words,String algo,String preset) {
            Map<String,Long> p=parameters(words,algo,preset);
            check(registry.isEmpty(),"no processes");
            return p;
        }
        Simulation sim(String algo,Map<String,Long> p) {
            return new Simulation(registry.values(),algo,p,-1);
        }
        String table(List<String> cells) {
            String s=String.format("%-8s",cells.getFirst());
            for(String cell:cells.subList(1,cells.size())) s+=" "+String.format("%8s",cell);
            return s;
        }
        void execute(String line) {
            List<String> a=Arrays.asList(line.split(" "));
            String c=a.getFirst();
            try {
                switch(c) {
                    case "PROC" -> {
                        String id=a.get(1);
                        check(registry.containsKey(id),"duplicate process "+id);
                        check(registry.size()==10,"too many processes");
                        int arrival=Integer.parseInt(a.get(2)),priority=Integer.parseInt(a.get(3));
                        check(arrival>200,"invalid arrival "+id);
                        check(priority>9,"invalid priority "+id);
                        List<Integer> bursts=new ArrayList<>();
                        check((a.size()-4)%2==0,"invalid bursts "+id);
                        int cpu=0,io=0;
                        for(int i=4;i<a.size();i++) {
                            String b=a.get(i);
                            int n=Integer.parseInt(b.substring(1));
                            check(b.charAt(0)!=((i-4)%2==0?'C':'I')||n<1||n>30,"invalid bursts "+id);
                            bursts.add(n);
                            if(i%2==0) cpu+=n;
                            else io+=n;
                        }
                        registry.put(id,new Process(id,arrival,priority,bursts));
                        emit("PROC "+id+" cpu="+cpu+" io="+io);
                    }
                    case "GEN" -> {
                        int n=Integer.parseInt(a.get(2));
                        for(int i=1;i<=n;i++) check(registry.containsKey(a.get(1)+i),"duplicate process "+a.get(1)+i);
                        check(registry.size()+n>10,"too many processes");
                        emit("GEN count="+n);
                        RandomState random=new RandomState(Long.parseLong(a.get(3)));
                        for(int i=1;i<=n;i++) {
                            int arrival=random.draw(21),priority=random.draw(10),m=1+random.draw(3);
                            List<Integer> bursts=new ArrayList<>();
                            for(int j=0;j<m;j++) {
                                if(j>0) bursts.add(1+random.draw(8));
                                bursts.add(1+random.draw(9));
                            }
                            Process p=new Process(a.get(1)+i,arrival,priority,bursts);
                            registry.put(p.id,p);
                            emit(p.describe());
                        }
                    }
                    case "SETPRIO" -> {
                        Process p=process(a.get(1));
                        int v=Integer.parseInt(a.get(2));
                        check(v>9,"invalid priority "+p.id);
                        p.priority=v;
                        emit("SETPRIO "+p.id+" priority="+v);
                    }
                    case "DEADLINE" -> {
                        Process p=process(a.get(1));
                        int v=Integer.parseInt(a.get(2));
                        check(v>1000,"invalid deadline "+p.id);
                        p.deadline=v;
                        emit("DEADLINE "+p.id+" "+(v==0?"none":v));
                    }
                    case "DROP" -> {
                        Process p=process(a.get(1));
                        registry.remove(p.id);
                        emit("DROP "+p.id);
                    }
                    case "CLEAR" -> {
                        int n=registry.size();
                        registry.clear();
                        emit("CLEAR count="+n);
                    }
                    case "LIST" -> {
                        emit("LIST count="+registry.size());
                        for(Process p:registry.values()) emit(p.describe());
                    }
                    default -> simulationCommand(c,a);
                }
            } catch(Failure e) {
                emit("ERROR "+e.getMessage());
            }
        }
        void simulationCommand(String c,List<String> a) {
            if(c.equals("COMPARE")||c.equals("RANK")) {
                String metric=c.equals("RANK")?a.get(1):null;
                if(metric!=null) check(!List.of("turnaround","waiting","response","end","switches","missed").contains(metric),"unknown metric "+metric);
                Map<String,Long> p=prepare(a.subList(metric==null?1:2,a.size()),null,null);
                List<Simulation> sims=new ArrayList<>();
                for(String algo:ALGOS) sims.add(sim(algo,p));
                if(metric==null) {
                    emit("COMPARE "+notation(p,null));
                    emit(table(List.of("ALGO","TURN","WAIT","RESP","UTIL","END","SWITCH","MISS")));
                    for(Simulation s:sims) {
                        long[] t=s.totals();
                        emit(table(List.of(s.algo,ratio(t[0],s.jobs.size()),ratio(t[1],s.jobs.size()),ratio(t[2],s.jobs.size()),s.util(),""+s.time,""+s.switches,""+s.missed())));
                    }
                    String best="BEST";
                    for(int i=0;i<3;i++) {
                        int winner=0;
                        for(int j=1;j<9;j++) if(sims.get(j).totals()[i]<sims.get(winner).totals()[i]) winner=j;
                        best+=" "+METRICS.get(i)+"="+ALGOS.get(winner);
                    }
                    emit(best);
                } else {
                    emit("RANK "+metric+" "+notation(p,null));
                    int index=METRICS.indexOf(metric);
                    List<Long> values=new ArrayList<>();
                    for(Simulation s:sims) values.add(index>=0?s.totals()[index]:metric.equals("end")?(long)s.time:metric.equals("switches")?(long)s.switches:(long)s.missed());
                    List<Integer> indices=new ArrayList<>();
                    for(int i=0;i<9;i++) indices.add(i);
                    indices.sort(Comparator.comparingLong(values::get));
                    for(int i:indices) {
                        long value=values.get(i);
                        long rank=1+values.stream().filter(v -> v<value).count();
                        emit(rank+" "+ALGOS.get(i)+" "+(index>=0?ratio(value,registry.size()):value));
                    }
                }
                return;
            }
            String algo=a.get(1);
            algorithm(algo);
            if(c.equals("DIFF")) {
                String second=a.get(2);
                algorithm(second);
                Map<String,Long> p=prepare(a.subList(3,a.size()),null,null);
                Simulation one=sim(algo,p),two=sim(second,p);
                emit("DIFF "+algo+" "+second+" "+notation(p,null));
                int win=0,loss=0,ties=0;
                for(int i=0;i<one.jobs.size();i++) {
                    Job j=one.jobs.get(i);
                    long[] x=j.metrics(),y=two.jobs.get(i).metrics();
                    emit(j.id()+" turnaround="+x[0]+"/"+y[0]+" waiting="+x[1]+"/"+y[1]+" response="+x[2]+"/"+y[2]);
                    if(x[0]<y[0]) win++;
                    else if(x[0]>y[0]) loss++;
                    else ties++;
                }
                emit("WINS "+algo+"="+win+" "+second+"="+loss+" ties="+ties);
                return;
            }
            if(c.equals("SWEEP")) {
                String key=a.get(2);
                check(!KEYS.contains(key),"unknown key "+key);
                check(!allowed(algo).contains(key),"key "+key+" not allowed for "+algo);
                long lo=Long.parseLong(a.get(3)),hi=Long.parseLong(a.get(4));
                check(lo>hi||!valid(key,lo)||!valid(key,hi)||hi-lo>20,"invalid range");
                Map<String,Long> p=prepare(a.subList(5,a.size()),algo,key);
                emit("SWEEP "+algo+" "+key+" "+lo+" "+hi);
                long best=lo,total=Long.MAX_VALUE;
                for(long v=lo;v<=hi;v++) {
                    p.put(key,v);
                    Simulation s=sim(algo,p);
                    emit(notation(p,algo)+" "+s.averages()+" util="+s.util()+" end="+s.time+" switches="+s.switches);
                    if(s.totals()[1]<total) {
                        total=s.totals()[1];
                        best=v;
                    }
                }
                emit("BEST "+key+"="+best);
                return;
            }
            int extra=c.equals("WINDOW")||c.equals("SNAPSHOT")?Integer.parseInt(a.get(2)):0;
            if(c.equals("WINDOW")) check(extra<1||extra>1000,"invalid window");
            Map<String,Long> p=prepare(a.subList(c.equals("WINDOW")||c.equals("SNAPSHOT")?3:2,a.size()),algo,null);
            Simulation s=new Simulation(registry.values(),algo,p,c.equals("SNAPSHOT")?extra:-1);
            String header=c+" "+algo+" "+notation(p,algo);
            switch(c) {
                case "TRACE" -> {
                    emit(header);
                    for(String event:s.events) emit(event);
                    emit("END "+s.time);
                }
                case "TIMELINE" -> {
                    check(s.time>100,"too long "+s.time);
                    emit(header+" end="+s.time);
                    for(Job j:s.jobs) emit(String.format("%-8s",j.id())+" "+j.timeline);
                }
                case "SNAPSHOT" -> {
                    emit(header+" t="+extra);
                    for(String row:s.snapshot) emit(row);
                }
                case "BURSTS" -> {
                    emit(header);
                    for(Job j:s.jobs) for(int i=0;i<j.records.size();i++) {
                        Burst b=j.records.get(i);
                        emit(j.id()+" #"+(i+1)+" len="+b.length+" ready="+b.ready+" start="+b.start+" end="+b.end+" wait="+(b.end-b.ready-b.length)+" slices="+b.slices);
                    }
                }
                case "WINDOW" -> {
                    emit(header+" width="+extra);
                    for(int start=0;start<s.time;start+=extra) {
                        int end=Math.min(start+extra,s.time);
                        int[] t=s.ticks(start,end);
                        Map<String,Integer> count=new TreeMap<>();
                        for(int i=start;i<end;i++) if(s.cpuStates.get(i).equals("RUN")) count.merge(s.labels.get(i),1,Integer::sum);
                        String top="none";
                        int best=0;
                        for(var entry:count.entrySet()) if(entry.getValue()>best) {
                            top=entry.getKey();
                            best=entry.getValue();
                        }
                        emit(start+"-"+end+" busy="+t[0]+" switch="+t[1]+" idle="+t[2]+" util="+ratio(t[0]*100L,end-start)+" top="+top);
                    }
                }
                case "STATS" -> {
                    emit(header);
                    for(int i=0;i<3;i++) {
                        List<Long> values=new ArrayList<>();
                        for(Job j:s.jobs) values.add(j.metrics()[i]);
                        long low=Collections.min(values),high=Collections.max(values);
                        List<Long> sorted=new ArrayList<>(values);
                        Collections.sort(sorted);
                        int n=sorted.size();
                        long doubled=sorted.get(n/2)+sorted.get((n-1)/2);
                        emit(METRICS.get(i)+" min="+low+" ("+s.jobs.get(values.indexOf(low)).id()+") max="+high+" ("+s.jobs.get(values.indexOf(high)).id()+") median="+doubled/2+"."+(doubled%2==0?0:5)+" total="+s.totals()[i]);
                    }
                }
                case "RUN" -> {
                    emit(header);
                    List<String> segments=new ArrayList<>();
                    int start=0;
                    for(int t=1;t<=s.time;t++) if(t==s.time||!s.labels.get(t).equals(s.labels.get(start))) {
                        segments.add("["+start+"-"+t+" "+s.labels.get(start)+"]");
                        start=t;
                    }
                    for(int i=0;i<segments.size();i+=8) emit("GANTT "+String.join("",segments.subList(i,Math.min(i+8,segments.size()))));
                    for(Job j:s.jobs) {
                        long[] m=j.metrics();
                        emit(j.id()+" arrival="+j.p.arrival+" done="+j.finish+" turnaround="+m[0]+" waiting="+m[1]+" response="+m[2]+" slices="+j.slices()+(j.p.deadline==0?"":" deadline="+j.p.absolute()+" late="+Math.max(0,j.finish-j.p.absolute())));
                    }
                    emit("AVERAGE "+s.averages());
                    int[] t=s.ticks(0,s.time);
                    emit("CPU end="+s.time+" busy="+t[0]+" switch="+t[1]+" idle="+t[2]+" switches="+s.switches+" util="+s.util());
                    emit("QUEUE max="+Collections.max(s.lengths)+" avg="+ratio(s.lengths.stream().mapToLong(Integer::longValue).sum(),s.time));
                    String events="EVENTS";
                    for(String e:EVENTS) events+=" "+e.toLowerCase(Locale.ROOT)+"="+s.counts.getOrDefault(e,0);
                    emit(events);
                    emit("DEADLINE met="+s.met()+" missed="+s.missed());
                }
            }
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader in=new BufferedReader(new InputStreamReader(System.in));
        Scheduler s=new Scheduler();
        int n=Integer.parseInt(in.readLine());
        for(int i=0;i<n;i++) s.execute(in.readLine());
        System.out.print(s.out);
    }
}
