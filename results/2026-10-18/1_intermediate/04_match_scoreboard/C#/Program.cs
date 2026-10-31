using System;
using System.Linq;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

class Program {
    const int P=0,G=2,W=4,L=6,R=8,GS=10,SERVE=11,LEG=12,DONE=13,WINNER=14,
        TC=15,TS=16,TV=17,TURN=18,LINEUP=21,SUBS=33,TIMEOUTS=35,POINTS=37,SERVED=39,
        SERVEWON=41,RUN=43,CURRENT=45,SERVICE=47,HOLDS=49,BREAKS=51,BPO=53,BPW=55,
        DARTS=57,SCORED=59,BUSTS=61,HIGH=63,TONS=65,MAXIMUMS=67,ATTEMPTS=69,HITS=71,
        FRAME=73,STANDING=74,ROLLCOUNT=75,ROLLS=76,FRAMEROLLS=97,FIRSTROLL=98,SECONDROLL=99;
    record Finished(int A, int B, int Type, int Loser);
    record Dart(string Name, int Value, bool DoubleOut);
    record BowlingFrame(string Marks, int? Cumulative, bool Open);
    class Problem : Exception {
        public Problem(string message) : base(message) {}
    }
    static void Fail(string reason) { throw new Problem(reason); }
    readonly Dictionary<string,Match> matches = new(StringComparer.Ordinal);
    readonly List<Dart> darts = new(), doubles = new();
    readonly Dictionary<string,int> dartIndex = new(StringComparer.Ordinal);
    readonly Dictionary<int,List<string>> checkoutCache = new();
    Program() {
        foreach (string prefix in new List<string> { "S","T","D" }) {
            for (int n = 20; n >= 1; n--) {
                Dart d = new Dart(prefix+n,n*(prefix.Equals("S") ? 1 : prefix.Equals("T") ? 3 : 2),prefix.Equals("D"));
                darts.Add(d);
                if (d.DoubleOut) doubles.Add(d);
            }
        }
        darts.Add(new Dart("25",25,false));
        Dart bull = new Dart("BULL",50,true);
        darts.Add(bull);
        doubles.Add(bull);
        darts.Add(new Dart("MISS",0,false));
        for (int i = 0; i < darts.Count; i++) dartIndex[darts[i].Name] = i;
    }
    List<string> Checkout(int score, int maximum) {
        int key = score*4+maximum;
        if (checkoutCache.ContainsKey(key)) return checkoutCache[key];
        List<string> answer = new List<string> {  };
        {
            foreach (Dart c in doubles) {
                if (c.Value == score) {
                    answer = new List<string> { c.Name };
                    goto Found;
                }
            }
            if (maximum >= 2) {
                for (int i = 0; i < 62; i++) {
                    Dart a = darts[i];
                    foreach (Dart b in doubles) {
                        if (a.Value+b.Value == score) {
                            answer = new List<string> { a.Name,b.Name };
                            goto Found;
                        }
                    }
                }
            }
            if (maximum >= 3) {
                for (int i = 0; i < 62; i++) {
                    Dart a = darts[i];
                    for (int j = 0; j < 62; j++) {
                        Dart b = darts[j];
                        foreach (Dart c in doubles) {
                            if (a.Value+b.Value+c.Value == score) {
                                answer = new List<string> { a.Name,b.Name,c.Name };
                                goto Found;
                            }
                        }
                    }
                }
            }
        }
        Found:
        checkoutCache[key] = answer;
        return answer;
    }
    class Match {
        readonly Program app;
        public string id, sport;
        public string[] names;
        Dictionary<string,string> options = new(StringComparer.Ordinal);
        int[][] initial = { new int[6], new int[6] };
        public int[] s = new int[100];
        List<Finished> finished = new();
        Stack<int[]> history = new();
        public Match(Program owner, string[] t) {
            app = owner;
            id = t[1];
            sport = t[2];
            names = new string[]{t[3],sport.Equals("BOWLING") ? "" : t[4]};
            Dictionary<string,HashSet<string>> allowed = new(StringComparer.Ordinal);
            if (!sport.Equals("BOWLING")) {
                allowed["FIRST"] = new HashSet<string> { "A","B" };
                options["FIRST"] = "A";
            }
            if (sport.Equals("TENNIS")) {
                allowed["SETS"] = new HashSet<string> { "3","5" };
                allowed["DEUCE"] = new HashSet<string> { "AD","NOAD" };
                allowed["FINAL"] = new HashSet<string> { "TB7","TB10","ADV","SUPER" };
                options["SETS"] = "3";
                options["DEUCE"] = "AD";
                options["FINAL"] = "TB7";
            }
            if (sport.Equals("TABLETENNIS")) {
                allowed["GAMES"] = new HashSet<string> { "5","7" };
                options["GAMES"] = "5";
            }
            if (sport.Equals("DARTS")) {
                allowed["START"] = new HashSet<string> { "301","501","701" };
                allowed["SETS"] = new HashSet<string> { "1","2","3","4","5" };
                allowed["LEGS"] = new HashSet<string> { "1","2","3","4","5" };
                options["START"] = "501";
                options["SETS"] = "1";
                options["LEGS"] = "1";
            }
            int firstOption = sport.Equals("BOWLING") ? 4 : sport.Equals("VOLLEYBALL") ? 7 : 5;
            HashSet<string> seen = new(StringComparer.Ordinal);
            for (int i = firstOption; i < t.Length; i++) {
                string[] p = t[i].Split('=');
                if (p.Length != 2 || !allowed.ContainsKey(p[0]) || !allowed[p[0]].Contains(p[1]) || !seen.Add(p[0])) Fail("invalid option");
                options[p[0]] = p[1];
            }
            s[GS] = First();
            s[SERVE] = First();
            s[LEG] = 1;
            s[STANDING] = 10;
            if (sport.Equals("DARTS")) {
                s[R] = Option("START");
                s[R+1] = Option("START");
                s[TS] = Option("START");
            }
            if (sport.Equals("VOLLEYBALL")) {
                for (int side = 0; side < 2; side++) {
                    string[] lineup = t[5+side].Split(',');
                    for (int i = 0; i < 6; i++) {
                        initial[side][i] = int.Parse(lineup[i]);
                        s[LINEUP+side*6+i] = initial[side][i];
                    }
                }
            }
        }
        public int First() { return options.GetValueOrDefault("FIRST","A").Equals("A") ? 0 : 1; }
        public int Option(string name) { return int.Parse(options[name]); }
        public bool Over() { return s[DONE] != 0; }
        public bool Tennis() { return sport.Equals("TENNIS"); }
        public bool Rally() { return !sport.Equals("DARTS") && !sport.Equals("BOWLING"); }
        public bool FinalSet() { return Tennis() && s[W] == Option("SETS")/2 && s[W+1] == Option("SETS")/2; }
        public bool SuperTie() { return FinalSet() && options["FINAL"].Equals("SUPER"); }
        public bool TieBreak() { return SuperTie() || Tennis() && s[G] == 6 && s[G+1] == 6 && !(FinalSet() && options["FINAL"].Equals("ADV")); }
        public int Server() {
            if (Tennis()) {
                int point = s[P]+s[P+1]+1;
                return s[GS] ^ (TieBreak() ? point/2%2 : 0);
            }
            if (sport.Equals("TABLETENNIS")) {
                int played = s[P]+s[P+1];
                int alternate = played < 20 ? played/2%2 : played%2;
                return First() ^ (finished.Count%2) ^ alternate;
            }
            return s[SERVE];
        }
        public bool NormalWin(int x, int extra) {
            int a = s[P+x]+extra, b = s[P+1-x];
            return a >= 4 && (options["DEUCE"].Equals("NOAD") || a-b >= 2);
        }
        public void EndSet(int x, Finished score) {
            finished.Add(score);
            s[W+x]++;
            int target = Tennis() ? Option("SETS")/2+1 : sport.Equals("TABLETENNIS") ? Option("GAMES")/2+1 : sport.Equals("VOLLEYBALL") ? 3 : 2;
            if (s[W+x] == target) {
                s[DONE] = 1;
                s[WINNER] = x;
            } else {
                s[P] = 0;
                s[P+1] = 0;
                s[G] = 0;
                s[G+1] = 0;
                if (sport.Equals("VOLLEYBALL")) {
                    for (int side = 0; side < 2; side++) {
                        s[SUBS+side] = 0;
                        s[TIMEOUTS+side] = 0;
                        Array.Copy(initial[side],0,s,LINEUP+side*6,6);
                    }
                    s[SERVE] = First() ^ (finished.Count%2);
                }
            }
        }
        public void Point(int x) {
            int serve = Server();
            s[POINTS+x]++;
            s[SERVED+serve]++;
            if (serve == x) s[SERVEWON+x]++;
            s[CURRENT+1-x] = 0;
            s[CURRENT+x]++;
            s[RUN+x] = Math.Max(s[RUN+x],s[CURRENT+x]);
            if (Tennis()) {
                bool tie = TieBreak(), superTie = SuperTie();
                if (!tie && NormalWin(1-serve,1)) {
                    s[BPO+1-serve]++;
                    if (x != serve) s[BPW+x]++;
                }
                s[P+x]++;
                if (tie) {
                    int target = superTie || FinalSet() && options["FINAL"].Equals("TB10") ? 10 : 7;
                    if (s[P+x] >= target && s[P+x]-s[P+1-x] >= 2) {
                        Finished score;
                        if (superTie) score = new Finished(s[P],s[P+1],2,0);
                        else {
                            s[G+x]++;
                            score = new Finished(s[G],s[G+1],1,s[P+1-x]);
                        }
                        s[GS] ^= 1;
                        EndSet(x,score);
                    }
                } else if (NormalWin(x,0)) {
                    s[SERVICE+s[GS]]++;
                    if (x == s[GS]) s[HOLDS+x]++;
                    else s[BREAKS+x]++;
                    s[G+x]++;
                    s[P] = 0;
                    s[P+1] = 0;
                    s[GS] ^= 1;
                    if (s[G+x] >= 6 && s[G+x]-s[G+1-x] >= 2) EndSet(x,new Finished(s[G],s[G+1],0,0));
                }
                return;
            }
            s[P+x]++;
            if (sport.Equals("BADMINTON")) s[SERVE] = x;
            if (sport.Equals("VOLLEYBALL") && s[SERVE] != x) {
                int start = LINEUP+x*6, old = s[start];
                Array.Copy(s,start+1,s,start,5);
                s[start+5] = old;
                s[SERVE] = x;
            }
            int target = sport.Equals("TABLETENNIS") ? 11 : sport.Equals("BADMINTON") ? 21 : finished.Count == 4 ? 15 : 25;
            if (s[P+x] >= target && s[P+x]-s[P+1-x] >= 2 || sport.Equals("BADMINTON") && s[P+x] == 30) {
                EndSet(x,new Finished(s[P],s[P+1],0,0));
            }
        }
        public void CompleteTurn(int side) {
            int score = s[TV];
            s[HIGH+side] = Math.Max(s[HIGH+side],score);
            if (score >= 100) s[TONS+side]++;
            if (score == 180) s[MAXIMUMS+side]++;
        }
        public void NextTurn() {
            s[SERVE] ^= 1;
            s[TC] = 0;
            s[TV] = 0;
            s[TS] = s[R+s[SERVE]];
        }
        public void ApplyDart(int code) {
            Dart d = app.darts[code];
            int x = s[SERVE], before = s[R+x];
            if (s[TC] == 0) s[TS] = before;
            if (before == 50 || before <= 40 && before%2 == 0) s[ATTEMPTS+x]++;
            s[DARTS+x]++;
            s[TURN+s[TC]] = code;
            s[TC]++;
            s[TV] += d.Value;
            int remaining = before-d.Value;
            if (remaining < 0 || remaining == 1 || remaining == 0 && !d.DoubleOut) {
                s[SCORED+x] -= s[TV]-d.Value;
                s[BUSTS+x]++;
                s[R+x] = s[TS];
                NextTurn();
            } else {
                s[R+x] = remaining;
                s[SCORED+x] += d.Value;
                if (remaining == 0) {
                    s[HITS+x]++;
                    CompleteTurn(x);
                    s[L+x]++;
                    if (s[L+x] == Option("LEGS")) {
                        finished.Add(new Finished(s[L],s[L+1],0,0));
                        s[W+x]++;
                        if (s[W+x] == Option("SETS")) {
                            s[DONE] = 1;
                            s[WINNER] = x;
                            return;
                        }
                        s[L] = 0;
                        s[L+1] = 0;
                    }
                    s[LEG]++;
                    s[R] = Option("START");
                    s[R+1] = Option("START");
                    s[SERVE] = First() ^ ((s[LEG]-1)%2);
                    s[TC] = 0;
                    s[TV] = 0;
                    s[TS] = Option("START");
                } else if (s[TC] == 3) {
                    CompleteTurn(x);
                    NextTurn();
                }
            }
        }
        public void Roll(int pins) {
            s[ROLLS+s[ROLLCOUNT]] = pins;
            s[ROLLCOUNT]++;
            int r = s[FRAMEROLLS], frame = s[FRAME];
            if (r == 0) s[FIRSTROLL] = pins;
            if (r == 1) s[SECONDROLL] = pins;
            s[STANDING] -= pins;
            bool end;
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
        public List<BowlingFrame> BowlingFrames() {
            List<BowlingFrame> result = new();
            int cursor = 0, cumulative = 0;
            for (int frame = 0; frame < 10 && cursor < s[ROLLCOUNT]; frame++) {
                int first = s[ROLLS+cursor], count;
                if (frame < 9) count = first == 10 ? 1 : Math.Min(2,s[ROLLCOUNT]-cursor);
                else count = Math.Min(3,s[ROLLCOUNT]-cursor);
                StringBuilder marks = new StringBuilder();
                int standing = 10, sum = 0;
                bool fresh = true;
                for (int i = 0; i < count; i++) {
                    int pins = s[ROLLS+cursor+i];
                    marks.Append(pins == 10 && fresh ? "X" : pins == standing ? "/" : pins == 0 ? "-" : Convert.ToString(pins));
                    sum += pins;
                    standing -= pins;
                    fresh = frame == 9 && standing == 0;
                    if (fresh) standing = 10;
                }
                int? score = null;
                if (frame == 9) {
                    if (Over()) score = sum;
                } else if (first == 10 && cursor+2 < s[ROLLCOUNT]) {
                    score = 10+s[ROLLS+cursor+1]+s[ROLLS+cursor+2];
                } else if (first != 10 && count == 2) {
                    if (sum < 10) score = sum;
                    else if (cursor+2 < s[ROLLCOUNT]) score = 10+s[ROLLS+cursor+2];
                }
                int? total = null;
                if (score != null) {
                    cumulative += score.Value;
                    total = cumulative;
                }
                bool open = count >= 2 && first != 10 && first+s[ROLLS+cursor+1] < 10;
                result.Add(new BowlingFrame(marks.ToString(),total,open));
                cursor += count;
            }
            return result;
        }
        public void Event(string command, string value, string[] tokens) {
            if (Over()) Fail("match over");
            int code = 0, side = 0, position = -1;
            if (command.Equals("ROLL")) {
                code = int.Parse(value);
                if (code > s[STANDING]) Fail("too many pins");
            }
            if (command.Equals("THROW")) {
                if (!app.dartIndex.TryGetValue(value,out code)) Fail("invalid dart");
            }
            if (command.Equals("SUB") || command.Equals("TIMEOUT")) {
                side = tokens[2].Equals("A") ? 0 : 1;
                if (command.Equals("SUB")) {
                    int from = int.Parse(tokens[3]), to = int.Parse(tokens[4]);
                    int start = LINEUP+side*6;
                    position = Array.IndexOf(s,from,start,6)-start;
                    if (position < 0) Fail("player not on court");
                    if (Array.IndexOf(s,to,start,6) >= 0) Fail("player already on court");
                    if (s[SUBS+side] == 6) Fail("no substitutions left");
                } else if (s[TIMEOUTS+side] == 2) Fail("no timeouts left");
            }
            int[] before = (int[])s.Clone();
            int count = finished.Count;
            switch (command) {
                case "POINT":
                    Point(value.Equals("A") ? 0 : 1);
                    break;
                case "ROLL":
                    Roll(code);
                    break;
                case "THROW":
                    ApplyDart(code);
                    break;
                case "SUB":
                    s[LINEUP+side*6+position] = int.Parse(tokens[4]);
                    s[SUBS+side]++;
                    break;
                case "TIMEOUT":
                    s[TIMEOUTS+side]++;
                    break;
            }
            int changed = 0;
            for (int i = 0; i < s.Length; i++) {
                if (before[i] != s[i]) changed++;
            }
            int[] undo = new int[1+changed*2];
            undo[0] = count;
            int cursor = 1;
            for (int i = 0; i < s.Length; i++) {
                if (before[i] != s[i]) {
                    undo[cursor++] = i;
                    undo[cursor++] = before[i];
                }
            }
            history.Push(undo);
        }
        public void Undo() {
            if (history.Count == 0) Fail("nothing to undo");
            int[] undo = history.Pop();
            for (int i = 1; i < undo.Length; i += 2) s[undo[i]] = undo[i+1];
            finished.RemoveRange(undo[0],finished.Count-undo[0]);
        }
        public string Situation(int x) {
            int[] old = (int[])s.Clone();
            int count = finished.Count, games = s[G]+s[G+1];
            int serve = Server();
            bool normal = Tennis() && !TieBreak();
            Point(x);
            string result = Over() ? "match point" : finished.Count > count ? (Tennis() || sport.Equals("VOLLEYBALL") ? "set point" : "game point") :
                normal && s[G]+s[G+1] > games ? (x == serve ? "game point" : "break point") : "";
            s = old;
            finished.RemoveRange(count,finished.Count-count);
            return result;
        }
        public string FinishedScore(Finished f, int first) {
            string pair = (first == 0 ? f.A : f.B)+"-"+(first == 0 ? f.B : f.A);
            return f.Type == 2 ? "["+pair+"]" : pair+(f.Type == 1 ? "("+f.Loser+")" : "");
        }
        public string Pair(int offset) { return s[offset]+"-"+s[offset+1]; }
        public string Score() {
            if (sport.Equals("BOWLING")) {
                var frames = BowlingFrames().Select(f => f.Marks+(f.Cumulative == null ? "" : "("+f.Cumulative+")")).ToList();
                return id+": "+names[0]+(frames.Count == 0 ? "" : " "+string.Join(" ",frames));
            }
            int serve = Over() ? -1 : Server();
            List<string> items = new();
            if (sport.Equals("DARTS")) {
                items.AddRange(new List<string> { "sets",Pair(W),"legs",Pair(L),"score",Pair(R) });
                if (!Over()) {
                    if (s[TC] > 0) {
                        items.Add("turn");
                        for (int i = 0; i < s[TC]; i++) items.Add(app.darts[s[TURN+i]].Name);
                    }
                    List<string> check = app.Checkout(s[R+s[SERVE]],3-s[TC]);
                    if (check.Count != 0) {
                        items.Add("checkout");
                        items.AddRange(check);
                    }
                }
            } else {
                foreach (Finished f in finished) items.Add(FinishedScore(f,0));
                if (!Over()) {
                    if (Tennis()) {
                        if (SuperTie()) items.Add("["+Pair(P)+"]");
                        else {
                            items.Add(Pair(G));
                            if (TieBreak()) items.Add(Pair(P));
                            else if (options["DEUCE"].Equals("AD") && s[P] >= 3 && s[P+1] >= 3) {
                                items.Add(s[P] == s[P+1] ? "40-40" : s[P] > s[P+1] ? "AD-40" : "40-AD");
                            } else {
                                string[] points = {"0","15","30","40"};
                                items.Add(points[s[P]]+"-"+points[s[P+1]]);
                            }
                        }
                    } else {
                        items.Add(Pair(P));
                        if (sport.Equals("VOLLEYBALL")) items.AddRange(new List<string> { "server",Convert.ToString(s[LINEUP+s[SERVE]*6]) });
                    }
                    for (int x = 0; x < 2; x++) {
                        string situation = Situation(x);
                        if (situation.Length != 0) items.Add("("+situation+" "+names[x]+")");
                    }
                }
            }
            return id+": "+names[0]+(serve == 0 ? "*" : "")+" vs "+names[1]+(serve == 1 ? "*" : "")+" "+string.Join(" ",items);
        }
        public List<string> Stats() {
            List<string> output = new();
            if (sport.Equals("BOWLING")) {
                List<BowlingFrame> frames = BowlingFrames();
                int strikes = frames.Sum(f => f.Marks.Count(c => c == 'X'));
                int spares = frames.Sum(f => f.Marks.Count(c => c == '/'));
                int open = frames.Count(f => f.Open);
                int[] old = (int[])s.Clone();
                while (!Over()) Roll(s[STANDING]);
                int maximum = BowlingFrames().Last().Cumulative!.Value;
                s = old;
                output.Add(id+" "+names[0]+": strikes "+strikes+" spares "+spares+" open "+open+" max "+maximum);
                return output;
            }
            for (int x = 0; x < 2; x++) {
                string line = id+" "+names[x]+": ";
                if (sport.Equals("DARTS")) {
                    long average = s[DARTS+x] == 0 ? 0 : (long)s[SCORED+x]*300/s[DARTS+x];
                    line += "darts "+s[DARTS+x]+" average "+$"{average/100}.{average%100:D2}"+
                        " busts "+s[BUSTS+x]+" high "+s[HIGH+x]+" tons "+s[TONS+x]+" 180s "+s[MAXIMUMS+x]+" doubles "+s[HITS+x]+"/"+s[ATTEMPTS+x];
                } else {
                    line += "points "+s[POINTS+x]+" serve "+s[SERVEWON+x]+"/"+s[SERVED+x]+" run "+s[RUN+x];
                    if (Tennis()) line += " holds "+s[HOLDS+x]+"/"+s[SERVICE+x]+" breaks "+s[BREAKS+x]+" break points "+s[BPW+x]+"/"+s[BPO+x];
                    if (sport.Equals("VOLLEYBALL")) {
                        line += " subs "+s[SUBS+x]+" timeouts "+s[TIMEOUTS+x]+" lineup "+
                            string.Join(",",s.Skip(LINEUP+x*6).Take(6));
                    }
                }
                output.Add(line);
            }
            return output;
        }
        public string Result() {
            if (!Over()) Fail("match not finished");
            if (sport.Equals("BOWLING")) return id+": "+names[0]+" "+BowlingFrames().Last().Cumulative;
            int winner = s[WINNER];
            var scores = finished.Select(f => FinishedScore(f,winner));
            return id+": "+names[winner]+" def. "+names[1-winner]+" "+string.Join(" ",scores);
        }
    }
    List<string> Execute(string line) {
        string[] t = line.Split(' ');
        string command = t[0];
        if (command.Equals("MATCH")) {
            if (matches.ContainsKey(t[1])) Fail("duplicate match");
            Match match = new Match(this,t);
            matches[t[1]] = match;
            return new List<string> {  };
        }
        if (command.Equals("CHECKOUT")) {
            List<string> answer = Checkout(int.Parse(t[1]),3);
            return new List<string> { "checkout "+t[1]+": "+(answer.Count == 0 ? "none" : string.Join(" ",answer)) };
        }
        if (command.Equals("STANDINGS")) {
            Dictionary<string,int[]> totals = new(StringComparer.Ordinal);
            foreach (Match match in matches.Values) {
                if (match.Over() && !match.sport.Equals("BOWLING")) {
                    int winner = match.s[WINNER];
                    if (!totals.ContainsKey(match.names[winner])) totals[match.names[winner]] = new int[2];
                    totals[match.names[winner]][0]++;
                    if (!totals.ContainsKey(match.names[1-winner])) totals[match.names[1-winner]] = new int[2];
                    totals[match.names[1-winner]][1]++;
                }
            }
            List<string> names = totals.Keys.ToList();
            names = names.OrderByDescending(name => totals[name][0]).ThenBy(name => totals[name][1]).ThenBy(name => name,StringComparer.Ordinal).ToList();
            var records = names.Select(name => name+" "+totals[name][0]+"-"+totals[name][1]).ToList();
            return new List<string> { "standings: "+(records.Count == 0 ? "none" : string.Join(", ",records)) };
        }
        Match target = matches.GetValueOrDefault(t[1]);
        if (target == null) Fail("unknown match");
        if (command.Equals("UNDO")) {
            target.Undo();
            return new List<string> {  };
        }
        if (command.Equals("SCORE")) return new List<string> { target.Score() };
        if (command.Equals("STATS")) return target.Stats();
        if (command.Equals("RESULT")) return new List<string> { target.Result() };
        bool correct = command switch {
            "POINT" => target.Rally(),
            "ROLL" => target.sport.Equals("BOWLING"),
            "THROW" => target.sport.Equals("DARTS"),
            _ => target.sport.Equals("VOLLEYBALL")
        };
        if (!correct) Fail("wrong event");
        if (command.Equals("POINT")) {
            foreach (char c in t[2].ToCharArray()) target.Event(command,Convert.ToString(c),t);
        } else if (command.Equals("ROLL") || command.Equals("THROW")) {
            for (int i = 2; i < t.Length; i++) target.Event(command,t[i],t);
        } else target.Event(command,"",t);
        return new List<string> {  };
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var app = new Program();
        int count = int.Parse(Console.ReadLine()!,CultureInfo.InvariantCulture);
        for (int i = 0; i < count; i++) {
            try {
                foreach (string line in app.Execute(Console.ReadLine()!)) Console.WriteLine(line);
            } catch (Problem problem) {
                Console.WriteLine("ERROR "+problem.Message);
            }
        }
    }
}
