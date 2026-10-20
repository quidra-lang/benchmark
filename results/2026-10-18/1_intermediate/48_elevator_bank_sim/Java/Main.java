import java.io.*;
import java.util.*;
public class Main {
    static final List<String> POLICIES=List.of("COST","NEAREST","ROUND","ETA");
    static final List<String> KEYS=List.of("FLOORS","CARS","CAPACITY","DOOR","START","POLICY","ZONES","PARK","PATIENCE","BYPASS","PERIOD","LIMIT","COMPARE");
    static final Map<String,Integer> ARGS=Map.of("CALL",3,"CANCEL",1,"OUT",1,"IN",1,"HOLD",2,"FIRE",1,"RESET",0,"WHERE",1,"STATUS",0);
    static class Invalid extends RuntimeException {
        Invalid(String message) {
            super(message);
        }
    }
    static void require(boolean ok,String message) {
        if(!ok) throw new Invalid(message);
    }
    static String join(Collection<?> xs) {
        return xs.isEmpty()?"-":String.join(",",xs.stream().map(Object::toString).toList());
    }
    static String avg(long total,long count) {
        long n=count==0?0:total*100/count;
        return count==0?"-":n/100+"."+String.format(Locale.ROOT,"%02d",n%100);
    }
    static int bound(String key,String text,int low,int high) {
        int n=Integer.parseInt(text);
        require(n>=low&&n<=high,"bad value for "+key);
        return n;
    }
    static class Config {
        int floors,cars,capacity,door,park=-1,patience=-1,bypass=100,period=-1,limit=1000;
        int[] starts,homes,low,high;
        String policy="COST";
        List<String> compare=List.of();
        Config(List<String[]> lines) {
            Map<String,List<String>> entries=new HashMap<>();
            for(String[] a:lines) {
                String k=a[0];
                require(KEYS.contains(k),"unknown key "+k);
                require(!entries.containsKey(k),"duplicate key "+k);
                entries.put(k,Arrays.asList(a).subList(1,a.length));
            }
            for(String k:KEYS.subList(0,5)) require(entries.containsKey(k),"missing key "+k);
            for(String k:KEYS) {
                if(!entries.containsKey(k)) continue;
                List<String> v=entries.get(k);
                int n=v.size();
                require(k.equals("START")||k.equals("ZONES")?n==cars:k.equals("PARK")?n==cars+1:k.equals("COMPARE")?n>=1&&n<=4:n==1,"wrong number of values for "+k);
                switch(k) {
                    case "FLOORS" -> floors=bound(k,v.getFirst(),2,50);
                    case "CARS" -> {
                        cars=bound(k,v.getFirst(),1,8);
                        starts=new int[cars];
                        homes=new int[cars];
                        low=new int[cars];
                        high=new int[cars];
                    }
                    case "CAPACITY" -> capacity=bound(k,v.getFirst(),1,20);
                    case "DOOR" -> door=bound(k,v.getFirst(),1,9);
                    case "START" -> {
                        for(int i=0;i<cars;i++) starts[i]=bound(k,v.get(i),1,floors);
                    }
                    case "POLICY" -> {
                        require(POLICIES.contains(v.getFirst()),"bad value for "+k);
                        policy=v.getFirst();
                    }
                    case "ZONES" -> {
                        for(int i=0;i<cars;i++) {
                            String[] z=v.get(i).split(":");
                            low[i]=Integer.parseInt(z[0]);
                            high[i]=Integer.parseInt(z[1]);
                            require(low[i]>=1&&low[i]<high[i]&&high[i]<=floors,"bad value for "+k);
                        }
                    }
                    case "PARK" -> {
                        park=bound(k,v.getFirst(),0,100);
                        for(int i=0;i<cars;i++) homes[i]=bound(k,v.get(i+1),1,floors);
                    }
                    case "PATIENCE" -> patience=bound(k,v.getFirst(),1,1000);
                    case "BYPASS" -> bypass=bound(k,v.getFirst(),50,100);
                    case "PERIOD" -> period=bound(k,v.getFirst(),1,1000);
                    case "LIMIT" -> limit=bound(k,v.getFirst(),1,5000);
                    case "COMPARE" -> {
                        require(v.stream().allMatch(POLICIES::contains)&&new HashSet<>(v).size()==v.size(),"bad value for "+k);
                        compare=v;
                    }
                }
            }
            if(!entries.containsKey("ZONES")) {
                Arrays.fill(low,1);
                Arrays.fill(high,floors);
            }
            for(int i=0;i<cars;i++) {
                require(starts[i]>=low[i]&&starts[i]<=high[i],"car "+(i+1)+" starts outside its zone");
                require(park<0||homes[i]>=low[i]&&homes[i]<=high[i],"car "+(i+1)+" home outside its zone");
            }
        }
        boolean serves(int i,int a,int b) {
            return low[i]<=a&&a<=high[i]&&low[i]<=b&&b<=high[i];
        }
        void header(List<String> out) {
            out.add("config: floors="+floors+" cars="+cars+" capacity="+capacity+" door="+door+" policy="+policy+" park="+(park<0?"off":park)+" patience="+(patience<0?"off":patience)+" bypass="+bypass+" period="+(period<0?"off":period)+" limit="+limit+" compare="+join(compare));
            for(int i=0;i<cars;i++) out.add("E"+(i+1)+": start="+starts[i]+" zone="+low[i]+"-"+high[i]+" home="+(park<0?"-":homes[i]));
        }
    }
    record Raw(int line,String[] words) {
    }
    record Event(int time,String command,int[] values) {
    }
    static List<Event> validate(Config c,List<Raw> raw,List<String> out) {
        List<Event> events=new ArrayList<>();
        int last=0,groups=0;
        boolean fire=false;
        Set<Integer> gone=new HashSet<>();
        for(Raw r:raw) {
            String[] a=r.words;
            int t=Integer.parseInt(a[0]);
            String cmd=a[1],problem=null;
            int[] v=new int[0];
            if(!ARGS.containsKey(cmd)) problem="unknown command "+cmd;
            else if(a.length-2!=ARGS.get(cmd)) problem="wrong number of arguments for "+cmd;
            else if(t<last) problem="time goes backwards";
            else {
                v=Arrays.stream(a).skip(2).mapToInt(Integer::parseInt).toArray();
                int x=v.length==0?0:v[0];
                switch(cmd) {
                    case "CALL" -> {
                        boolean served=false;
                        for(int i=0;i<c.cars;i++) served|=c.serves(i,x,v[1]);
                        if(x<1||x>c.floors||v[1]<1||v[1]>c.floors) problem="bad floor";
                        else if(x==v[1]) problem="same floor";
                        else if(v[2]<1||v[2]>99) problem="bad count";
                        else if(!served) problem="no car serves "+x+"->"+v[1];
                        else if(fire) problem="fire service active";
                    }
                    case "CANCEL","WHERE" -> {
                        if(x<1||x>groups) problem="unknown group";
                    }
                    case "OUT","IN" -> {
                        if(x<1||x>c.cars) problem="bad car";
                        else if(cmd.equals("OUT")&&gone.contains(x)) problem="car "+x+" already out";
                        else if(cmd.equals("IN")&&!gone.contains(x)) problem="car "+x+" already in";
                    }
                    case "HOLD" -> {
                        if(x<1||x>c.cars) problem="bad car";
                        else if(v[1]<1||v[1]>9) problem="bad ticks";
                    }
                    case "FIRE" -> {
                        if(x<1||x>c.floors) problem="bad floor";
                        else if(fire) problem="fire already active";
                    }
                    case "RESET" -> {
                        if(!fire) problem="fire not active";
                    }
                }
            }
            if(problem!=null) {
                out.add("line "+r.line+": "+problem);
                continue;
            }
            last=t;
            switch(cmd) {
                case "CALL" -> groups++;
                case "OUT" -> gone.add(v[0]);
                case "IN" -> gone.remove(v[0]);
                case "FIRE" -> fire=true;
                case "RESET" -> fire=false;
            }
            events.add(new Event(t,cmd,v));
        }
        return events;
    }
    static class Group {
        int number,landing,destination,count,time,direction,waiting,boarded,delivered,lost,lastBoard,lastAlight;
        long waitTotal,travelTotal;
        Car car;
        Set<Integer> cars=new TreeSet<>();
        Group(int n,int a,int b,int count,int time) {
            number=n;
            landing=a;
            destination=b;
            this.count=waiting=count;
            this.time=time;
            direction=Integer.signum(b-a);
        }
        String label() {
            return "G"+number;
        }
    }
    record Passenger(Group group,int count,int boarded) {
    }
    static class Car {
        int number,floor,direction,door,idleStart,distance,stops,boarded,busy;
        long energy;
        boolean service=true;
        List<Group> calls=new ArrayList<>();
        List<Passenger> passengers=new ArrayList<>();
        Car(int n,int f) {
            number=n;
            floor=f;
        }
        String label() {
            return "E"+number;
        }
        int load() {
            return passengers.stream().mapToInt(Passenger::count).sum();
        }
        Set<Integer> targets() {
            Set<Integer> s=new HashSet<>();
            for(Passenger p:passengers) s.add(p.group.destination);
            for(Group g:calls) s.add(g.landing);
            return s;
        }
    }
    static class Simulation {
        Config c;
        String policy,status;
        List<Event> events;
        List<Car> cars=new ArrayList<>();
        List<Group> groups=new ArrayList<>(),pending=new ArrayList<>();
        List<String> log=new ArrayList<>();
        int time,fireFloor,lastRound,abandoned,evacuated,delivered,maxWait;
        long waitTotal,travelTotal;
        Simulation(Config c,List<Event> events,String policy) {
            this.c=c;
            this.events=events;
            this.policy=policy;
            for(int i=0;i<c.cars;i++) cars.add(new Car(i+1,c.starts[i]));
        }
        void emit(String s) {
            log.add(time+" "+s);
        }
        boolean bypass(Car e) {
            return e.load()*100>=c.capacity*c.bypass;
        }
        int cost(Car e,Group g) {
            int f=e.floor,d=e.direction,x=g.landing;
            if(policy.equals("NEAREST")||d==0) return Math.abs(f-x);
            Set<Integer> targets=e.targets();
            int distance,via=0;
            if(g.direction==d&&(x-f)*d>=0) {
                distance=Math.abs(x-f);
                for(int y:targets) if((y-f)*d>0&&(x-y)*d>0) via++;
            }
            else {
                int m=f;
                for(int y:targets) m=d>0?Math.max(m,y):Math.min(m,y);
                distance=Math.abs(f-m)+Math.abs(m-x);
                for(int y:targets) if((y-f)*d>0) via++;
            }
            return policy.equals("COST")?distance:distance+c.door*via+e.door;
        }
        boolean assign(Group g,Car excluded) {
            List<Car> candidates=cars.stream().filter(e -> e.service&&e!=excluded&&c.serves(e.number-1,g.landing,g.destination)).toList();
            if(candidates.isEmpty()) return false;
            Car chosen=candidates.getFirst();
            int best=0;
            if(policy.equals("ROUND")) {
                for(Car e:candidates) if(e.number>lastRound) {
                    chosen=e;
                    break;
                }
                lastRound=chosen.number;
            }
            else {
                best=cost(chosen,g);
                for(Car e:candidates) {
                    int value=cost(e,g);
                    if(value<best) {
                        chosen=e;
                        best=value;
                    }
                }
            }
            emit(chosen.label()+" ASSIGN "+g.label()+(policy.equals("ROUND")?"":" cost="+best));
            if(g.car!=null) g.car.calls.remove(g);
            chosen.calls.add(g);
            g.car=chosen;
            return true;
        }
        void dispatch(Group g) {
            if(!assign(g,null)) {
                pending.add(g);
                emit("PENDING "+g.label());
            }
        }
        void walk(Group g,String word) {
            if(g.car==null) pending.remove(g);
            else {
                g.car.calls.remove(g);
                g.car=null;
            }
            emit(word+" "+g.label()+" x"+g.waiting);
            g.lost+=g.waiting;
            abandoned+=g.waiting;
            g.waiting=0;
        }
        void event(Event event) {
            int[] v=event.values;
            int x=v.length==0?0:v[0];
            switch(event.command) {
                case "CALL" -> {
                    Group g=new Group(groups.size()+1,x,v[1],v[2],time);
                    groups.add(g);
                    emit("CALL "+g.label()+" "+x+"->"+v[1]+" x"+v[2]);
                    dispatch(g);
                }
                case "CANCEL" -> {
                    Group g=groups.get(x-1);
                    if(g.waiting>0) walk(g,"CANCEL");
                    else emit("CANCEL "+g.label()+" ignored");
                }
                case "OUT" -> {
                    Car e=cars.get(x-1);
                    e.service=false;
                    emit(e.label()+" OUT");
                    List<Group> old=new ArrayList<>(e.calls);
                    e.calls.clear();
                    for(Group g:old) {
                        g.car=null;
                        dispatch(g);
                    }
                }
                case "IN" -> {
                    Car e=cars.get(x-1);
                    e.service=true;
                    e.idleStart=time;
                    emit(e.label()+" IN");
                    List<Group> old=new ArrayList<>(pending);
                    pending.clear();
                    for(Group g:old) if(!assign(g,null)) pending.add(g);
                }
                case "HOLD" -> {
                    Car e=cars.get(x-1);
                    if(e.door>0) {
                        e.door+=v[1];
                        emit(e.label()+" HOLD "+e.door);
                    } else emit(e.label()+" HOLD ignored");
                }
                case "FIRE" -> {
                    fireFloor=x;
                    emit("FIRE "+x);
                    for(Group g:groups) if(g.waiting>0) walk(g,"ABANDON");
                }
                case "RESET" -> {
                    fireFloor=0;
                    emit("RESET");
                    for(Car e:cars) e.idleStart=time;
                }
                case "WHERE" -> {
                    Group g=groups.get(x-1);
                    List<String> riding=new ArrayList<>();
                    for(Car e:cars) {
                        int n=e.passengers.stream().filter(p -> p.group==g).mapToInt(Passenger::count).sum();
                        if(n>0) riding.add(e.label()+"x"+n);
                    }
                    emit("WHERE "+g.label()+" waiting="+g.waiting+" car="+(g.waiting==0?"-":g.car==null?"pending":g.car.label())+" riding="+join(riding)+" delivered="+g.delivered+" lost="+g.lost);
                }
                case "STATUS" -> {
                    for(Car e:cars) {
                        Set<Integer> stops=new TreeSet<>();
                        for(Passenger p:e.passengers) stops.add(p.group.destination);
                        emit("STATUS "+e.label()+" floor="+e.floor+" dir="+(e.direction==0?"idle":e.direction>0?"up":"down")+" door="+e.door+" load="+e.load()+" stops="+join(stops)+" calls="+join(e.calls.stream().map(Group::label).toList())+" service="+(e.service?"in":"out"));
                    }
                    emit("STATUS pending="+join(pending.stream().map(Group::label).toList()));
                }
            }
        }
        int direction(Car e) {
            int f=e.floor,d=e.direction;
            List<Group> here=bypass(e)?List.of():e.calls.stream().filter(g -> g.landing==f).toList();
            Set<Integer> targets=e.targets();
            if(d!=0&&(targets.stream().anyMatch(y -> (y-f)*d>0)||here.stream().anyMatch(g -> g.direction==d))) return d;
            if(!here.isEmpty()) return here.getFirst().direction;
            if(d!=0&&targets.stream().anyMatch(y -> (y-f)*d<0)) return -d;
            if(d==0&&!e.calls.isEmpty()) return Integer.signum(e.calls.getFirst().landing-f);
            return 0;
        }
        void deliver(Passenger p) {
            Group g=p.group;
            int wait=p.boarded-g.time,travel=time-g.time;
            g.delivered+=p.count;
            g.lastAlight=time;
            g.waitTotal+=(long)wait*p.count;
            g.travelTotal+=(long)travel*p.count;
            delivered+=p.count;
            waitTotal+=(long)wait*p.count;
            travelTotal+=(long)travel*p.count;
            maxWait=Math.max(maxWait,wait);
        }
        void open(Car e) {
            emit(e.label()+" OPEN "+e.floor);
            e.door=c.door;
            e.stops++;
            e.energy+=2;
            List<Passenger> keep=new ArrayList<>();
            for(Passenger p:e.passengers) {
                if(p.group.destination==e.floor) {
                    emit(e.label()+" ALIGHT "+p.group.label()+" x"+p.count);
                    deliver(p);
                }
                else if(fireFloor!=0) {
                    emit(e.label()+" EVACUATE "+p.group.label()+" x"+p.count);
                    p.group.lost+=p.count;
                    evacuated+=p.count;
                }
                else keep.add(p);
            }
            e.passengers=keep;
            if(fireFloor!=0) return;
            int n=direction(e);
            if(n!=0) e.direction=n;
            List<Group> boarding=e.calls.stream().filter(g -> g.landing==e.floor&&g.direction==n).toList();
            for(Group g:boarding) {
                int k=Math.min(c.capacity-e.load(),g.waiting);
                if(k>0) {
                    e.passengers.add(new Passenger(g,k,time));
                    e.boarded+=k;
                    g.waiting-=k;
                    g.boarded+=k;
                    g.lastBoard=time;
                    g.cars.add(e.number);
                    emit(e.label()+" BOARD "+g.label()+" x"+k);
                }
                if(g.waiting==0) {
                    e.calls.remove(g);
                    g.car=null;
                }
                else {
                    emit(e.label()+" LEFT "+g.label()+" x"+g.waiting);
                    assign(g,e);
                }
            }
        }
        void move(Car e,int d) {
            e.energy+=d>0?3+e.load():1;
            e.distance++;
            e.floor+=d;
        }
        void advance(Car e) {
            int old=e.floor;
            if(e.door>0) e.door--;
            if(e.door==0) {
                int n=fireFloor==0?direction(e):Integer.signum(fireFloor-e.floor);
                boolean stop=fireFloor!=0?n==0&&!e.passengers.isEmpty():e.passengers.stream().anyMatch(p -> p.group.destination==e.floor)||!bypass(e)&&e.calls.stream().anyMatch(g -> g.landing==e.floor&&g.direction==n);
                if(stop) open(e);
                else if(n!=0) {
                    e.direction=n;
                    move(e,n);
                }
                else {
                    if(e.direction!=0) {
                        emit(e.label()+" IDLE "+e.floor);
                        e.direction=0;
                        e.idleStart=time;
                    }
                    if(fireFloor==0&&e.service&&c.park>=0&&e.floor!=c.homes[e.number-1]&&time-e.idleStart>=c.park) {
                        move(e,Integer.signum(c.homes[e.number-1]-e.floor));
                        if(e.floor==c.homes[e.number-1]) emit(e.label()+" PARK "+e.floor);
                    }
                }
            }
            if(e.door>0||e.floor!=old) e.busy++;
        }
        boolean settled(Car e) {
            return e.door==0&&e.passengers.isEmpty()&&e.calls.isEmpty()&&(fireFloor!=0?e.floor==fireFloor:!e.service||c.park<0||e.floor==c.homes[e.number-1]);
        }
        void run() {
            int index=0;
            while(true) {
                if(c.patience>=0) for(Group g:groups) if(g.waiting>0&&time==g.time+c.patience) walk(g,"ABANDON");
                while(index<events.size()&&events.get(index).time==time) event(events.get(index++));
                for(Car e:cars) advance(e);
                if(index==events.size()&&cars.stream().allMatch(this::settled)) {
                    status="end";
                    emit("END");
                    return;
                }
                if(time==c.limit) {
                    status="abort";
                    emit("ABORT");
                    return;
                }
                time++;
            }
        }
        String averages() {
            return "avg_wait="+avg(waitTotal,delivered)+" avg_travel="+avg(travelTotal,delivered)+" max_wait="+(delivered==0?"-":maxWait);
        }
        String breakdown(String label,List<Group> gs) {
            return label+": groups="+gs.size()+" passengers="+gs.stream().mapToInt(g -> g.count).sum()+" delivered="+gs.stream().mapToInt(g -> g.delivered).sum()+" avg_wait="+avg(gs.stream().mapToLong(g -> g.waitTotal).sum(),gs.stream().mapToInt(g -> g.delivered).sum());
        }
        void report(List<String> out) {
            for(Group g:groups) out.add(g.label()+" t="+g.time+" "+g.landing+"->"+g.destination+" n="+g.count+" delivered="+g.delivered+" lost="+g.lost+" wait="+(g.boarded==g.count?g.lastBoard-g.time:"-")+" travel="+(g.delivered==g.count?g.lastAlight-g.time:"-")+" cars="+join(g.cars));
            for(Car e:cars) {
                long u=(long)e.busy*1000/(time+1);
                out.add(e.label()+" distance="+e.distance+" stops="+e.stops+" boarded="+e.boarded+" busy="+e.busy+" util="+u/10+"."+u%10+"% energy="+e.energy);
            }
            Set<Integer> floors=new TreeSet<>(),periods=new TreeSet<>();
            for(Group g:groups) {
                floors.add(g.landing);
                if(c.period>0) periods.add(g.time/c.period);
            }
            for(int f:floors) out.add(breakdown("F"+f,groups.stream().filter(g -> g.landing==f).toList()));
            for(int p:periods) out.add(breakdown("P"+p+" "+p*c.period+"-"+(p*c.period+c.period-1),groups.stream().filter(g -> g.time/c.period==p).toList()));
            out.add("summary: groups="+groups.size()+" passengers="+groups.stream().mapToInt(g -> g.count).sum()+" delivered="+delivered+" abandoned="+abandoned+" evacuated="+evacuated+" "+averages()+" end="+time);
        }
    }
    static class Scenario {
        String name;
        Config c;
        Simulation sim;
        Scenario(String name) {
            this.name=name;
        }
        String outcome() {
            return sim==null?"invalid":sim.status.equals("abort")?"aborted":sim.delivered==0?"empty":"ranked";
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader in=new BufferedReader(new InputStreamReader(System.in));
        int q=Integer.parseInt(in.readLine()),lineNo=1;
        List<Scenario> scenarios=new ArrayList<>();
        List<String> out=new ArrayList<>();
        for(int i=0;i<q;i++) {
            Scenario s=new Scenario(in.readLine().split(" ")[1]);
            lineNo++;
            scenarios.add(s);
            List<String[]> settings=new ArrayList<>();
            List<Raw> raw=new ArrayList<>();
            while(true) {
                String line=in.readLine();
                lineNo++;
                if(line.equals("END")) break;
                String[] a=line.split(" ");
                if(Character.isDigit(a[0].charAt(0))) raw.add(new Raw(lineNo,a));
                else settings.add(a);
            }
            out.add("== "+s.name+" ==");
            try {
                s.c=new Config(settings);
            } catch(Invalid e) {
                out.add("error: "+e.getMessage());
                continue;
            }
            s.c.header(out);
            List<Event> events=validate(s.c,raw,out);
            s.sim=new Simulation(s.c,events,s.c.policy);
            s.sim.run();
            out.addAll(s.sim.log);
            s.sim.report(out);
            for(String p:s.c.compare) {
                Simulation rerun=new Simulation(s.c,events,p);
                rerun.run();
                out.add("compare "+p+": delivered="+rerun.delivered+" "+rerun.averages()+" end="+rerun.time+" status="+rerun.status);
            }
        }
        out.add("== ranking ==");
        List<Scenario> ranked=new ArrayList<>(scenarios.stream().filter(s -> s.outcome().equals("ranked")).toList());
        ranked.sort((a,b) -> {
            long aw=a.sim.waitTotal*b.sim.delivered,bw=b.sim.waitTotal*a.sim.delivered;
            int r=Long.compare(aw,bw);
            return r!=0?r:Long.compare(a.sim.travelTotal*b.sim.delivered,b.sim.travelTotal*a.sim.delivered);
        });
        for(int i=0;i<ranked.size();i++) {
            Scenario s=ranked.get(i);
            out.add((i+1)+". "+s.name+" policy="+s.c.policy+" "+s.sim.averages());
        }
        for(Scenario s:scenarios) if(!s.outcome().equals("ranked")) out.add("- "+s.name+" "+s.outcome());
        out.add("== policies ==");
        for(String p:POLICIES) {
            List<Scenario> runs=ranked.stream().filter(s -> s.c.policy.equals(p)).toList();
            if(runs.isEmpty()) continue;
            long n=0,w=0,t=0;
            for(Scenario s:runs) {
                n+=s.sim.delivered;
                w+=s.sim.waitTotal;
                t+=s.sim.travelTotal;
            }
            out.add(p+": runs="+runs.size()+" avg_wait="+avg(w,n)+" avg_travel="+avg(t,n));
        }
        System.out.println(String.join("\n",out));
    }
}
