import java.io.*;
import java.util.*;

public class Main {
    static final int P=0,G=2,W=4,L=6,R=8,GS=10,SERVE=11,LEG=12,DONE=13,WINNER=14,
        TC=15,TS=16,TV=17,TURN=18,LINEUP=21,SUBS=33,TIMEOUTS=35,POINTS=37,SERVED=39,
        SERVEWON=41,RUN=43,CURRENT=45,SERVICE=47,HOLDS=49,BREAKS=51,BPO=53,BPW=55,
        DARTS=57,SCORED=59,BUSTS=61,HIGH=63,TONS=65,MAXIMUMS=67,ATTEMPTS=69,HITS=71,
        FRAME=73,STANDING=74,ROLLCOUNT=75,ROLLS=76,FRAMEROLLS=97,FIRSTROLL=98,SECONDROLL=99;
    record Finished(int a, int b, int type, int loser) {}
    record Dart(String name, int value, boolean doubleOut) {}
    record BowlingFrame(String marks, Integer cumulative, boolean open) {}
    static class Problem extends RuntimeException {
        Problem(String message) { super(message); }
    }
    static void fail(String reason) { throw new Problem(reason); }
    final Map<String,Match> matches = new LinkedHashMap<>();
    final List<Dart> darts = new ArrayList<>(), doubles = new ArrayList<>();
    final Map<String,Integer> dartIndex = new HashMap<>();
    final Map<Integer,List<String>> checkoutCache = new HashMap<>();
    Main() {
        for (String prefix : List.of("S","T","D")) {
            for (int n = 20; n >= 1; n--) {
                Dart d = new Dart(prefix+n,n*(prefix.equals("S") ? 1 : prefix.equals("T") ? 3 : 2),prefix.equals("D"));
                darts.add(d);
                if (d.doubleOut()) doubles.add(d);
            }
        }
        darts.add(new Dart("25",25,false));
        Dart bull = new Dart("BULL",50,true);
        darts.add(bull);
        doubles.add(bull);
        darts.add(new Dart("MISS",0,false));
        for (int i = 0; i < darts.size(); i++) dartIndex.put(darts.get(i).name(),i);
    }
    List<String> checkout(int score, int maximum) {
        int key = score*4+maximum;
        if (checkoutCache.containsKey(key)) return checkoutCache.get(key);
        List<String> answer = List.of();
        search: {
            for (Dart c : doubles) {
                if (c.value() == score) {
                    answer = List.of(c.name());
                    break search;
                }
            }
            if (maximum >= 2) {
                for (int i = 0; i < 62; i++) {
                    Dart a = darts.get(i);
                    for (Dart b : doubles) {
                        if (a.value()+b.value() == score) {
                            answer = List.of(a.name(),b.name());
                            break search;
                        }
                    }
                }
            }
            if (maximum >= 3) {
                for (int i = 0; i < 62; i++) {
                    Dart a = darts.get(i);
                    for (int j = 0; j < 62; j++) {
                        Dart b = darts.get(j);
                        for (Dart c : doubles) {
                            if (a.value()+b.value()+c.value() == score) {
                                answer = List.of(a.name(),b.name(),c.name());
                                break search;
                            }
                        }
                    }
                }
            }
        }
        checkoutCache.put(key,answer);
        return answer;
    }
    class Match {
        final String id, sport;
        final String[] names;
        final Map<String,String> options = new HashMap<>();
        final int[][] initial = new int[2][6];
        int[] s = new int[100];
        final List<Finished> finished = new ArrayList<>();
        final Deque<int[]> history = new ArrayDeque<>();
        Match(String[] t) {
            id = t[1];
            sport = t[2];
            names = new String[]{t[3],sport.equals("BOWLING") ? "" : t[4]};
            Map<String,Set<String>> allowed = new HashMap<>();
            if (!sport.equals("BOWLING")) {
                allowed.put("FIRST",Set.of("A","B"));
                options.put("FIRST","A");
            }
            if (sport.equals("TENNIS")) {
                allowed.put("SETS",Set.of("3","5"));
                allowed.put("DEUCE",Set.of("AD","NOAD"));
                allowed.put("FINAL",Set.of("TB7","TB10","ADV","SUPER"));
                options.putAll(Map.of("SETS","3","DEUCE","AD","FINAL","TB7"));
            }
            if (sport.equals("TABLETENNIS")) {
                allowed.put("GAMES",Set.of("5","7"));
                options.put("GAMES","5");
            }
            if (sport.equals("DARTS")) {
                allowed.put("START",Set.of("301","501","701"));
                allowed.put("SETS",Set.of("1","2","3","4","5"));
                allowed.put("LEGS",Set.of("1","2","3","4","5"));
                options.putAll(Map.of("START","501","SETS","1","LEGS","1"));
            }
            int firstOption = sport.equals("BOWLING") ? 4 : sport.equals("VOLLEYBALL") ? 7 : 5;
            Set<String> seen = new HashSet<>();
            for (int i = firstOption; i < t.length; i++) {
                String[] p = t[i].split("=",-1);
                if (p.length != 2 || !allowed.containsKey(p[0]) || !allowed.get(p[0]).contains(p[1]) || !seen.add(p[0])) fail("invalid option");
                options.put(p[0],p[1]);
            }
            s[GS] = first();
            s[SERVE] = first();
            s[LEG] = 1;
            s[STANDING] = 10;
            if (sport.equals("DARTS")) {
                s[R] = option("START");
                s[R+1] = option("START");
                s[TS] = option("START");
            }
            if (sport.equals("VOLLEYBALL")) {
                for (int side = 0; side < 2; side++) {
                    String[] lineup = t[5+side].split(",");
                    for (int i = 0; i < 6; i++) {
                        initial[side][i] = Integer.parseInt(lineup[i]);
                        s[LINEUP+side*6+i] = initial[side][i];
                    }
                }
            }
        }
        int first() { return options.getOrDefault("FIRST","A").equals("A") ? 0 : 1; }
        int option(String name) { return Integer.parseInt(options.get(name)); }
        boolean over() { return s[DONE] != 0; }
        boolean tennis() { return sport.equals("TENNIS"); }
        boolean rally() { return !sport.equals("DARTS") && !sport.equals("BOWLING"); }
        boolean finalSet() { return tennis() && s[W] == option("SETS")/2 && s[W+1] == option("SETS")/2; }
        boolean superTie() { return finalSet() && options.get("FINAL").equals("SUPER"); }
        boolean tieBreak() { return superTie() || tennis() && s[G] == 6 && s[G+1] == 6 && !(finalSet() && options.get("FINAL").equals("ADV")); }
        int server() {
            if (tennis()) {
                int point = s[P]+s[P+1]+1;
                return s[GS] ^ (tieBreak() ? point/2%2 : 0);
            }
            if (sport.equals("TABLETENNIS")) {
                int played = s[P]+s[P+1];
                int alternate = played < 20 ? played/2%2 : played%2;
                return first() ^ (finished.size()%2) ^ alternate;
            }
            return s[SERVE];
        }
        boolean normalWin(int x, int extra) {
            int a = s[P+x]+extra, b = s[P+1-x];
            return a >= 4 && (options.get("DEUCE").equals("NOAD") || a-b >= 2);
        }
        void endSet(int x, Finished score) {
            finished.add(score);
            s[W+x]++;
            int target = tennis() ? option("SETS")/2+1 : sport.equals("TABLETENNIS") ? option("GAMES")/2+1 : sport.equals("VOLLEYBALL") ? 3 : 2;
            if (s[W+x] == target) {
                s[DONE] = 1;
                s[WINNER] = x;
            } else {
                s[P] = 0;
                s[P+1] = 0;
                s[G] = 0;
                s[G+1] = 0;
                if (sport.equals("VOLLEYBALL")) {
                    for (int side = 0; side < 2; side++) {
                        s[SUBS+side] = 0;
                        s[TIMEOUTS+side] = 0;
                        System.arraycopy(initial[side],0,s,LINEUP+side*6,6);
                    }
                    s[SERVE] = first() ^ (finished.size()%2);
                }
            }
        }
        void point(int x) {
            int serve = server();
            s[POINTS+x]++;
            s[SERVED+serve]++;
            if (serve == x) s[SERVEWON+x]++;
            s[CURRENT+1-x] = 0;
            s[CURRENT+x]++;
            s[RUN+x] = Math.max(s[RUN+x],s[CURRENT+x]);
            if (tennis()) {
                boolean tie = tieBreak(), superTie = superTie();
                if (!tie && normalWin(1-serve,1)) {
                    s[BPO+1-serve]++;
                    if (x != serve) s[BPW+x]++;
                }
                s[P+x]++;
                if (tie) {
                    int target = superTie || finalSet() && options.get("FINAL").equals("TB10") ? 10 : 7;
                    if (s[P+x] >= target && s[P+x]-s[P+1-x] >= 2) {
                        Finished score;
                        if (superTie) score = new Finished(s[P],s[P+1],2,0);
                        else {
                            s[G+x]++;
                            score = new Finished(s[G],s[G+1],1,s[P+1-x]);
                        }
                        s[GS] ^= 1;
                        endSet(x,score);
                    }
                } else if (normalWin(x,0)) {
                    s[SERVICE+s[GS]]++;
                    if (x == s[GS]) s[HOLDS+x]++;
                    else s[BREAKS+x]++;
                    s[G+x]++;
                    s[P] = 0;
                    s[P+1] = 0;
                    s[GS] ^= 1;
                    if (s[G+x] >= 6 && s[G+x]-s[G+1-x] >= 2) endSet(x,new Finished(s[G],s[G+1],0,0));
                }
                return;
            }
            s[P+x]++;
            if (sport.equals("BADMINTON")) s[SERVE] = x;
            if (sport.equals("VOLLEYBALL") && s[SERVE] != x) {
                int start = LINEUP+x*6, old = s[start];
                System.arraycopy(s,start+1,s,start,5);
                s[start+5] = old;
                s[SERVE] = x;
            }
            int target = sport.equals("TABLETENNIS") ? 11 : sport.equals("BADMINTON") ? 21 : finished.size() == 4 ? 15 : 25;
            if (s[P+x] >= target && s[P+x]-s[P+1-x] >= 2 || sport.equals("BADMINTON") && s[P+x] == 30) {
                endSet(x,new Finished(s[P],s[P+1],0,0));
            }
        }
        void completeTurn(int side) {
            int score = s[TV];
            s[HIGH+side] = Math.max(s[HIGH+side],score);
            if (score >= 100) s[TONS+side]++;
            if (score == 180) s[MAXIMUMS+side]++;
        }
        void nextTurn() {
            s[SERVE] ^= 1;
            s[TC] = 0;
            s[TV] = 0;
            s[TS] = s[R+s[SERVE]];
        }
        void dart(int code) {
            Dart d = darts.get(code);
            int x = s[SERVE], before = s[R+x];
            if (s[TC] == 0) s[TS] = before;
            if (before == 50 || before <= 40 && before%2 == 0) s[ATTEMPTS+x]++;
            s[DARTS+x]++;
            s[TURN+s[TC]] = code;
            s[TC]++;
            s[TV] += d.value();
            int remaining = before-d.value();
            if (remaining < 0 || remaining == 1 || remaining == 0 && !d.doubleOut()) {
                s[SCORED+x] -= s[TV]-d.value();
                s[BUSTS+x]++;
                s[R+x] = s[TS];
                nextTurn();
            } else {
                s[R+x] = remaining;
                s[SCORED+x] += d.value();
                if (remaining == 0) {
                    s[HITS+x]++;
                    completeTurn(x);
                    s[L+x]++;
                    if (s[L+x] == option("LEGS")) {
                        finished.add(new Finished(s[L],s[L+1],0,0));
                        s[W+x]++;
                        if (s[W+x] == option("SETS")) {
                            s[DONE] = 1;
                            s[WINNER] = x;
                            return;
                        }
                        s[L] = 0;
                        s[L+1] = 0;
                    }
                    s[LEG]++;
                    s[R] = option("START");
                    s[R+1] = option("START");
                    s[SERVE] = first() ^ ((s[LEG]-1)%2);
                    s[TC] = 0;
                    s[TV] = 0;
                    s[TS] = option("START");
                } else if (s[TC] == 3) {
                    completeTurn(x);
                    nextTurn();
                }
            }
        }
        void roll(int pins) {
            s[ROLLS+s[ROLLCOUNT]] = pins;
            s[ROLLCOUNT]++;
            int r = s[FRAMEROLLS], frame = s[FRAME];
            if (r == 0) s[FIRSTROLL] = pins;
            if (r == 1) s[SECONDROLL] = pins;
            s[STANDING] -= pins;
            boolean end;
            if (frame < 9) end = r == 1 || r == 0 && pins == 10;
            else end = r == 2 || r == 1 && s[FIRSTROLL] != 10 && s[FIRSTROLL]+pins < 10;
            if (end) {
                if (frame == 9) s[DONE] = 1;
                else {
                    s[FRAME]++;
                    s[FRAMEROLLS] = 0;
                    s[STANDING] = 10;
                }
            } else {
                s[FRAMEROLLS]++;
                if (frame == 9 && s[STANDING] == 0) s[STANDING] = 10;
            }
        }
        List<BowlingFrame> bowlingFrames() {
            List<BowlingFrame> result = new ArrayList<>();
            int cursor = 0, cumulative = 0;
            for (int frame = 0; frame < 10 && cursor < s[ROLLCOUNT]; frame++) {
                int first = s[ROLLS+cursor], count;
                if (frame < 9) count = first == 10 ? 1 : Math.min(2,s[ROLLCOUNT]-cursor);
                else count = Math.min(3,s[ROLLCOUNT]-cursor);
                StringBuilder marks = new StringBuilder();
                int standing = 10, sum = 0;
                boolean fresh = true;
                for (int i = 0; i < count; i++) {
                    int pins = s[ROLLS+cursor+i];
                    marks.append(pins == 10 && fresh ? "X" : pins == standing ? "/" : pins == 0 ? "-" : Integer.toString(pins));
                    sum += pins;
                    standing -= pins;
                    fresh = frame == 9 && standing == 0;
                    if (fresh) standing = 10;
                }
                Integer score = null;
                if (frame == 9) {
                    if (over()) score = sum;
                } else if (first == 10 && cursor+2 < s[ROLLCOUNT]) {
                    score = 10+s[ROLLS+cursor+1]+s[ROLLS+cursor+2];
                } else if (first != 10 && count == 2) {
                    if (sum < 10) score = sum;
                    else if (cursor+2 < s[ROLLCOUNT]) score = 10+s[ROLLS+cursor+2];
                }
                Integer total = null;
                if (score != null) {
                    cumulative += score;
                    total = cumulative;
                }
                boolean open = count >= 2 && first != 10 && first+s[ROLLS+cursor+1] < 10;
                result.add(new BowlingFrame(marks.toString(),total,open));
                cursor += count;
            }
            return result;
        }
        void event(String command, String value, String[] tokens) {
            if (over()) fail("match over");
            int code = 0, side = 0, position = -1;
            if (command.equals("ROLL")) {
                code = Integer.parseInt(value);
                if (code > s[STANDING]) fail("too many pins");
            }
            if (command.equals("THROW")) {
                Integer index = dartIndex.get(value);
                if (index == null) fail("invalid dart");
                code = index;
            }
            if (command.equals("SUB") || command.equals("TIMEOUT")) {
                side = tokens[2].equals("A") ? 0 : 1;
                if (command.equals("SUB")) {
                    int from = Integer.parseInt(tokens[3]), to = Integer.parseInt(tokens[4]);
                    for (int i = 0; i < 6; i++) {
                        if (s[LINEUP+side*6+i] == from) position = i;
                    }
                    if (position < 0) fail("player not on court");
                    for (int i = 0; i < 6; i++) {
                        if (s[LINEUP+side*6+i] == to) fail("player already on court");
                    }
                    if (s[SUBS+side] == 6) fail("no substitutions left");
                } else if (s[TIMEOUTS+side] == 2) fail("no timeouts left");
            }
            int[] before = s.clone();
            int count = finished.size();
            switch (command) {
                case "POINT" -> point(value.equals("A") ? 0 : 1);
                case "ROLL" -> roll(code);
                case "THROW" -> dart(code);
                case "SUB" -> {
                    s[LINEUP+side*6+position] = Integer.parseInt(tokens[4]);
                    s[SUBS+side]++;
                }
                case "TIMEOUT" -> s[TIMEOUTS+side]++;
            }
            int changed = 0;
            for (int i = 0; i < s.length; i++) {
                if (before[i] != s[i]) changed++;
            }
            int[] undo = new int[1+changed*2];
            undo[0] = count;
            int cursor = 1;
            for (int i = 0; i < s.length; i++) {
                if (before[i] != s[i]) {
                    undo[cursor++] = i;
                    undo[cursor++] = before[i];
                }
            }
            history.push(undo);
        }
        void undo() {
            if (history.isEmpty()) fail("nothing to undo");
            int[] undo = history.pop();
            for (int i = 1; i < undo.length; i += 2) s[undo[i]] = undo[i+1];
            finished.subList(undo[0],finished.size()).clear();
        }
        String situation(int x) {
            int[] old = s.clone();
            int count = finished.size(), games = s[G]+s[G+1];
            int serve = server();
            boolean normal = tennis() && !tieBreak();
            point(x);
            String result = over() ? "match point" : finished.size() > count ? (tennis() || sport.equals("VOLLEYBALL") ? "set point" : "game point") :
                normal && s[G]+s[G+1] > games ? (x == serve ? "game point" : "break point") : "";
            s = old;
            finished.subList(count,finished.size()).clear();
            return result;
        }
        String finishedScore(Finished f, int first) {
            String pair = (first == 0 ? f.a() : f.b())+"-"+(first == 0 ? f.b() : f.a());
            return f.type() == 2 ? "["+pair+"]" : pair+(f.type() == 1 ? "("+f.loser()+")" : "");
        }
        String pair(int offset) { return s[offset]+"-"+s[offset+1]; }
        String score() {
            if (sport.equals("BOWLING")) {
                List<String> frames = bowlingFrames().stream().map(f -> f.marks()+(f.cumulative() == null ? "" : "("+f.cumulative()+")")).toList();
                return id+": "+names[0]+(frames.isEmpty() ? "" : " "+String.join(" ",frames));
            }
            int serve = over() ? -1 : server();
            List<String> items = new ArrayList<>();
            if (sport.equals("DARTS")) {
                items.addAll(List.of("sets",pair(W),"legs",pair(L),"score",pair(R)));
                if (!over()) {
                    if (s[TC] > 0) {
                        items.add("turn");
                        for (int i = 0; i < s[TC]; i++) items.add(darts.get(s[TURN+i]).name());
                    }
                    List<String> check = checkout(s[R+s[SERVE]],3-s[TC]);
                    if (!check.isEmpty()) {
                        items.add("checkout");
                        items.addAll(check);
                    }
                }
            } else {
                for (Finished f : finished) items.add(finishedScore(f,0));
                if (!over()) {
                    if (tennis()) {
                        if (superTie()) items.add("["+pair(P)+"]");
                        else {
                            items.add(pair(G));
                            if (tieBreak()) items.add(pair(P));
                            else if (options.get("DEUCE").equals("AD") && s[P] >= 3 && s[P+1] >= 3) {
                                items.add(s[P] == s[P+1] ? "40-40" : s[P] > s[P+1] ? "AD-40" : "40-AD");
                            } else {
                                String[] points = {"0","15","30","40"};
                                items.add(points[s[P]]+"-"+points[s[P+1]]);
                            }
                        }
                    } else {
                        items.add(pair(P));
                        if (sport.equals("VOLLEYBALL")) items.addAll(List.of("server",Integer.toString(s[LINEUP+s[SERVE]*6])));
                    }
                    for (int x = 0; x < 2; x++) {
                        String situation = situation(x);
                        if (!situation.isEmpty()) items.add("("+situation+" "+names[x]+")");
                    }
                }
            }
            return id+": "+names[0]+(serve == 0 ? "*" : "")+" vs "+names[1]+(serve == 1 ? "*" : "")+" "+String.join(" ",items);
        }
        List<String> stats() {
            List<String> output = new ArrayList<>();
            if (sport.equals("BOWLING")) {
                List<BowlingFrame> frames = bowlingFrames();
                long strikes = frames.stream().mapToLong(f -> f.marks().chars().filter(c -> c == 'X').count()).sum();
                long spares = frames.stream().mapToLong(f -> f.marks().chars().filter(c -> c == '/').count()).sum();
                long open = frames.stream().filter(BowlingFrame::open).count();
                int[] old = s.clone();
                while (!over()) roll(s[STANDING]);
                int maximum = bowlingFrames().getLast().cumulative();
                s = old;
                output.add(id+" "+names[0]+": strikes "+strikes+" spares "+spares+" open "+open+" max "+maximum);
                return output;
            }
            for (int x = 0; x < 2; x++) {
                String line = id+" "+names[x]+": ";
                if (sport.equals("DARTS")) {
                    long average = s[DARTS+x] == 0 ? 0 : (long)s[SCORED+x]*300/s[DARTS+x];
                    line += "darts "+s[DARTS+x]+" average "+String.format(Locale.ROOT,"%d.%02d",average/100,average%100)+
                        " busts "+s[BUSTS+x]+" high "+s[HIGH+x]+" tons "+s[TONS+x]+" 180s "+s[MAXIMUMS+x]+" doubles "+s[HITS+x]+"/"+s[ATTEMPTS+x];
                } else {
                    line += "points "+s[POINTS+x]+" serve "+s[SERVEWON+x]+"/"+s[SERVED+x]+" run "+s[RUN+x];
                    if (tennis()) line += " holds "+s[HOLDS+x]+"/"+s[SERVICE+x]+" breaks "+s[BREAKS+x]+" break points "+s[BPW+x]+"/"+s[BPO+x];
                    if (sport.equals("VOLLEYBALL")) {
                        String lineup = String.join(",",Arrays.stream(s,LINEUP+x*6,LINEUP+x*6+6).mapToObj(String::valueOf).toList());
                        line += " subs "+s[SUBS+x]+" timeouts "+s[TIMEOUTS+x]+" lineup "+lineup;
                    }
                }
                output.add(line);
            }
            return output;
        }
        String result() {
            if (!over()) fail("match not finished");
            if (sport.equals("BOWLING")) return id+": "+names[0]+" "+bowlingFrames().getLast().cumulative();
            int winner = s[WINNER];
            List<String> scores = finished.stream().map(f -> finishedScore(f,winner)).toList();
            return id+": "+names[winner]+" def. "+names[1-winner]+" "+String.join(" ",scores);
        }
    }
    List<String> execute(String line) {
        String[] t = line.split(" ");
        String command = t[0];
        if (command.equals("MATCH")) {
            if (matches.containsKey(t[1])) fail("duplicate match");
            Match match = new Match(t);
            matches.put(t[1],match);
            return List.of();
        }
        if (command.equals("CHECKOUT")) {
            List<String> answer = checkout(Integer.parseInt(t[1]),3);
            return List.of("checkout "+t[1]+": "+(answer.isEmpty() ? "none" : String.join(" ",answer)));
        }
        if (command.equals("STANDINGS")) {
            Map<String,int[]> totals = new HashMap<>();
            for (Match match : matches.values()) {
                if (match.over() && !match.sport.equals("BOWLING")) {
                    int winner = match.s[WINNER];
                    totals.computeIfAbsent(match.names[winner],name -> new int[2])[0]++;
                    totals.computeIfAbsent(match.names[1-winner],name -> new int[2])[1]++;
                }
            }
            List<String> names = new ArrayList<>(totals.keySet());
            names.sort(Comparator.<String>comparingInt(name -> totals.get(name)[0]).reversed().thenComparingInt(name -> totals.get(name)[1]).thenComparing(name -> name));
            List<String> records = names.stream().map(name -> name+" "+totals.get(name)[0]+"-"+totals.get(name)[1]).toList();
            return List.of("standings: "+(records.isEmpty() ? "none" : String.join(", ",records)));
        }
        Match match = matches.get(t[1]);
        if (match == null) fail("unknown match");
        if (command.equals("UNDO")) {
            match.undo();
            return List.of();
        }
        if (command.equals("SCORE")) return List.of(match.score());
        if (command.equals("STATS")) return match.stats();
        if (command.equals("RESULT")) return List.of(match.result());
        boolean correct = switch (command) {
            case "POINT" -> match.rally();
            case "ROLL" -> match.sport.equals("BOWLING");
            case "THROW" -> match.sport.equals("DARTS");
            default -> match.sport.equals("VOLLEYBALL");
        };
        if (!correct) fail("wrong event");
        if (command.equals("POINT")) {
            for (char c : t[2].toCharArray()) match.event(command,String.valueOf(c),t);
        } else if (command.equals("ROLL") || command.equals("THROW")) {
            for (int i = 2; i < t.length; i++) match.event(command,t[i],t);
        } else match.event(command,"",t);
        return List.of();
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        Main app = new Main();
        int count = Integer.parseInt(input.readLine());
        for (int i = 0; i < count; i++) {
            try {
                app.execute(input.readLine()).forEach(output::println);
            } catch (Problem problem) {
                output.println("ERROR "+problem.getMessage());
            }
        }
        output.flush();
    }
}
