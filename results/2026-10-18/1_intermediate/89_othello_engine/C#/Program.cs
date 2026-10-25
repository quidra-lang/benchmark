using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
class Program
{
    static readonly int[] Weights={
        100,-20,10,5,5,10,-20,100,-20,-50,-2,-2,-2,-2,-50,-20,10,-2,-1,-1,-1,-1,-2,10,5,-2,-1,-1,-1,-1,-2,5,5,-2,-1,-1,-1,-1,-2,5,10,-2,-1,-1,-1,-1,-2,10,-20,-50,-2,-2,-2,-2,-50,-20,100,-20,10,5,5,10,-20,100
    };
    static readonly string[] Transforms={
        "rot90","rot180","rot270","mirror","flip","diag","anti"
    };
    static readonly string[] Zero="NEW DUMP SHOW SCORE LEGAL HISTORY SHEET STATS EVAL STABLE SOLVE".Split(' ');
    static readonly string[] Numeric="UNDO REDO HINT PV AI ANALYZE RANDOM PERFT DIVIDE".Split(' ');
    static readonly string[] Active="FLIPS MOVE PLAY HINT PV AI SOLVE AUTOPLAY RANDOM MC DIVIDE".Split(' ');
    static readonly HashSet<string> Commands=new(Zero.Concat(Numeric).Concat("LOAD TRANSFORM AUTOPLAY MC FLIPS MOVE PLAY RECORD".Split(' ')));
    static char Other(char s)=>s=='B'?'W':'B';
    static string Name(int p)=>"abcdefgh"[p%8].ToString()+(p/8+1);
    static int Square(string s)=>(s[1]-'1')*8+s[0]-'a';
    static bool Inside(int r,int c)=>r>=0&&r<8&&c>=0&&c<8;
    static string Initial(){
        char[] b=Enumerable.Repeat('.',64).ToArray();
        b[27]=b[36]='W';
        b[28]=b[35]='B';
        return new(b);
    }
    static List<int> Flips(string b,char s,int p){
        List<int> output=new();
        if(b[p]!='.')return output;
        int row=p/8,col=p%8;
        for(int dr=-1;dr<=1;dr++)for(int dc=-1;dc<=1;dc++){
            if(dr==0&&dc==0)continue;
            int r=row+dr,c=col+dc;
            List<int> line=new();
            while(Inside(r,c)&&b[8*r+c]==Other(s)){
                line.Add(8*r+c);
                r+=dr;
                c+=dc;
            }
            if(line.Count>0&&Inside(r,c)&&b[8*r+c]==s)output.AddRange(line);
        }
        output.Sort();
        return output;
    }
    static List<int> Legal(string b,char s)=>Enumerable.Range(0,64).Where(p=>b[p]=='.'&&Flips(b,s,p).Count>0).ToList();
    static string Place(string b,char s,int p){
        char[] a=b.ToCharArray();
        foreach(int q in Flips(b,s,p))a[q]=s;
        a[p]=s;
        return new(a);
    }
    static int Count(string b,char s)=>b.Count(x=>x==s);
    static bool Terminal(string b)=>Legal(b,'B').Count==0&&Legal(b,'W').Count==0;
    static string GameOver(string b){
        int x=Count(b,'B'),y=Count(b,'W');
        return $"game over B {x} W {y} "+(x>y?"winner B":x<y?"winner W":"draw");
    }
    static (int Value,int Weight,int Own,int Enemy) Evaluate(string b,char s){
        int w=Enumerable.Range(0,64).Sum(i=>b[i]==s?Weights[i]:b[i]==Other(s)?-Weights[i]:0),own=Legal(b,s).Count,enemy=Legal(b,Other(s)).Count;
        return(w+10*(own-enemy),w,own,enemy);
    }
    static readonly Dictionary<(string,char,int),int> SearchCache=new(),PerftCache=new();
    static int Search(string b,char s,int d){
        var key=(b,s,d);
        if(SearchCache.TryGetValue(key,out int found))return found;
        List<int> moves=Legal(b,s);
        char o=Other(s);
        int v;
        if(moves.Count==0&&Legal(b,o).Count==0)v=(d<0?1:1000)*(Count(b,s)-Count(b,o));
        else if(d==0)v=Evaluate(b,s).Value;
        else if(moves.Count==0)v=-Search(b,o,d<0?-1:d-1);
        else v=moves.Max(p=>-Search(Place(b,s,p),o,d<0?-1:d-1));
        if(SearchCache.Count>300000)SearchCache.Clear();
        SearchCache[key]=v;
        return v;
    }
    static List<(int Value,int Square)> Ranked(string b,char s,int d)=>Legal(b,s).Select(p=>(Value:-Search(Place(b,s,p),Other(s),d<0?-1:d-1),Square:p)).OrderByDescending(x=>x.Value).ThenBy(x=>x.Square).ToList();
    static (List<string> Steps,string Board) Variation(string b,char s,int d){
        List<string> steps=new();
        while(d!=0&&!Terminal(b)){
            var moves=Ranked(b,s,d);
            if(moves.Count==0)steps.Add("pass");
            else{
                int p=moves[0].Square;
                steps.Add(Name(p));
                b=Place(b,s,p);
            }
            s=Other(s);
            if(d>0)d--;
        }
        return(steps,b);
    }
    static int Perft(string b,char s,int d){
        if(d==0)return 1;
        var key=(b,s,d);
        if(PerftCache.TryGetValue(key,out int found))return found;
        List<int> moves=Legal(b,s);
        char o=Other(s);
        int n=moves.Count>0?moves.Sum(p=>Perft(Place(b,s,p),o,d-1)):Legal(b,o).Count==0?1:Perft(b,o,d-1);
        if(PerftCache.Count>200000)PerftCache.Clear();
        PerftCache[key]=n;
        return n;
    }
    static (int Black,int White) Stable(string b){
        bool[] stable=new bool[64];
        (int,int)[] axes={
            (0,1),(1,0),(1,1),(1,-1)
        };
        while(true){
            List<int> found=new();
            for(int p=0;p<64;p++){
                if(b[p]=='.'||stable[p])continue;
                bool ok=true;
                foreach(var (dr,dc) in axes){
                    bool full=true,anchor=false;
                    foreach(int sign in new[]{
                        -1,1
                    }){
                        int r=p/8+dr*sign,c=p%8+dc*sign;
                        if(!Inside(r,c)||(stable[8*r+c]&&b[8*r+c]==b[p]))anchor=true;
                        while(Inside(r,c)){
                            if(b[8*r+c]=='.')full=false;
                            r+=dr*sign;
                            c+=dc*sign;
                        }
                    }
                    if(!full&&!anchor){
                        ok=false;
                        break;
                    }
                }
                if(ok)found.Add(p);
            }
            if(found.Count==0)break;
            foreach(int p in found)stable[p]=true;
        }
        return(Enumerable.Range(0,64).Count(i=>stable[i]&&b[i]=='B'),Enumerable.Range(0,64).Count(i=>stable[i]&&b[i]=='W'));
    }
    static int Transform(int p,string op){
        int r=p/8,c=p%8;
        return op switch{
            "rot90"=>8*c+7-r,"rot180"=>63-p,"rot270"=>8*(7-c)+r,"mirror"=>8*r+7-c,"flip"=>8*(7-r)+c,"diag"=>8*c+r,_=>8*(7-c)+7-r
        };
    }
    static string TransformBoard(string b,string op){
        char[] a=new char[64];
        for(int p=0;p<64;p++)a[Transform(p,op)]=b[p];
        return new(a);
    }
    class Minstd{
        long value;
        public Minstd(long seed){
            value=seed;
        }
        public long Draw()=>value=value*48271%2147483647;
    }
    static string RandomGame(string b,char s,Minstd rng){
        while(true){
            List<int> moves=Legal(b,s);
            if(moves.Count>0)b=Place(b,s,moves[(int)(rng.Draw()%moves.Count)]);
            else if(Legal(b,Other(s)).Count==0)return b;
            s=Other(s);
        }
    }
    static string Average(int f,int n){
        int v=100*f/n;
        return $"{v/100}.{v%100:00}";
    }
    record Position(string Board,char Side,bool Over);
    record Move(char Side,int Square,int Count,bool Passed,Position Before,Position After);
    class Othello
    {
        string board=Initial();
        char side='B';
        bool over;
        List<Move> history=new(),redo=new();
        static void Emit(params object[] xs)=>Console.WriteLine(string.Join(" ",xs));
        Position Snapshot()=>new(board,side,over);
        void Restore(Position p){
            board=p.Board;
            side=p.Side;
            over=p.Over;
        }
        string Status()=>over?GameOver(board):side+" to move";
        void Reset(){
            board=Initial();
            side='B';
            over=false;
            history.Clear();
            redo.Clear();
        }
        bool Adjust(bool quiet=false){
            if(Legal(board,side).Count>0)return false;
            if(Legal(board,Other(side)).Count>0){
                if(!quiet)Emit(side,"passes");
                side=Other(side);
                return true;
            }
            over=true;
            if(!quiet)Emit(GameOver(board));
            return false;
        }
        bool PlayMove(int p,bool quiet=false,int? value=null){
            Position before=Snapshot();
            char s=side;
            int k=Flips(board,s,p).Count;
            board=Place(board,s,p);
            if(!quiet){
                if(value.HasValue)Emit(s,Name(p),"flips",k,"value",value.Value);
                else Emit(s,Name(p),"flips",k);
            }
            side=Other(s);
            bool passed=Adjust(quiet);
            history.Add(new(s,p,k,passed,before,Snapshot()));
            redo.Clear();
            return passed;
        }
        string Reason(int p)=>over?"game over":board[p]!='.'?"occupied":Flips(board,side,p).Count==0?"no flips":"";
        void Record(string text){
            Othello e=new();
            List<int> ps=new();
            int passes=0;
            for(int i=0;i<text.Length;i+=2){
                int p=Square(text.Substring(i,2));
                string why=e.Reason(p);
                if(why!=""){
                    Emit("ILLEGAL move",i/2+1,Name(p),why);
                    return;
                }
                ps.Add(p);
                if(e.PlayMove(p,true))passes++;
            }
            Restore(e.Snapshot());
            history=e.history;
            redo.Clear();
            string op=Name(ps[0]) switch{
                "e6"=>"diag","d3"=>"anti","c4"=>"rot180",_=>""
            };
            string normal=string.Concat(ps.Select(p=>Name(op==""?p:Transform(p,op))));
            Emit("record",ps.Count,"moves",passes,"passes");
            Emit("normal",normal);
            Emit(Status());
        }
        void Sheet(){
            string b=history.Count==0?board:history[0].Before.Board;
            string[] fields=b.Select(c=>c.ToString()).ToArray();
            for(int i=0;i<history.Count;i++)fields[history[i].Square]=(i+1).ToString();
            Emit(" "+string.Concat("abcdefgh".Select(c=>c.ToString().PadLeft(3))));
            for(int r=0;r<8;r++)Emit((r+1)+string.Concat(fields.Skip(8*r).Take(8).Select(x=>x.PadLeft(3))));
        }
        void Stats(){
            int total=history.Sum(r=>r.Count);
            if(history.Count==0)Emit("moves 0");
            else Emit("moves",history.Count,"flips",total,"avg",Average(total,history.Count),"passes",history.Count(r=>r.Passed));
            foreach(char s in new[]{
                'B','W'
            }){
                List<Move> rows=history.Where(r=>r.Side==s).ToList();
                if(rows.Count==0){
                    Emit(s,"moves 0");
                    continue;
                }
                int sum=rows.Sum(r=>r.Count),max=rows.Max(r=>r.Count);
                Emit(s,"moves",rows.Count,"flips",sum,"avg",Average(sum,rows.Count),"max",max,Name(rows.First(r=>r.Count==max).Square),"corners",rows.Count(r=>new[]{
                    0,7,56,63
                }.Contains(r.Square)));
            }
        }
        void AutoPlay(int black,int white,long seed=0){
            Minstd rng=new(seed);
            List<string> ps=new();
            int passes=0;
            while(!over){
                List<int> moves=Legal(board,side);
                int p=seed!=0?moves[(int)(rng.Draw()%moves.Count)]:Ranked(board,side,side=='B'?black:white)[0].Square;
                ps.Add(Name(p));
                if(PlayMove(p,true))passes++;
            }
            Emit(seed!=0?"random":"autoplay",ps.Count,"moves",passes,"passes");
            Emit("moves",string.Concat(ps));
            Emit(GameOver(board));
        }
        void MonteCarlo(int k,long seed){
            Minstd rng=new(seed);
            int best=-1,bp=-1;
            foreach(int p in Legal(board,side)){
                int w=0,d=0,l=0;
                string start=Place(board,side,p);
                for(int i=0;i<k;i++){
                    string end=RandomGame(start,Other(side),rng);
                    int diff=Count(end,side)-Count(end,Other(side));
                    if(diff>0)w++;
                    else if(diff<0)l++;
                    else d++;
                }
                Emit(Name(p),w,d,l);
                if(2*w+d>best){
                    best=2*w+d;
                    bp=p;
                }
            }
            Emit("best",Name(bp),best);
        }
        public void Execute(string text){
            string[] words=text.Split(' ');
            string cmd=words[0];
            string[] a=words.Skip(1).ToArray();
            string error="";
            if(!Commands.Contains(cmd))error="unknown command";
            else if(cmd=="LOAD"){
                if(a.Length!=2||!Regex.IsMatch(a[0],@"\A[.BW]{64}\z")||!new[]{
                    "B","W"
                }.Contains(a[1]))error="bad board";
            }
            else if(cmd=="MOVE"||cmd=="FLIPS"){
                if(a.Length!=1)error="bad arguments";
                else if(!Regex.IsMatch(a[0],@"\A[a-h][1-8]\z"))error="bad square";
            }
            else if(cmd=="PLAY"||cmd=="RECORD"){
                if(a.Length!=1)error="bad arguments";
                else if(a[0].Length>120||!Regex.IsMatch(a[0],@"\A([a-h][1-8])+\z"))error="bad record";
            }
            else if(Zero.Contains(cmd)){
                if(a.Length!=0)error="bad arguments";
            }
            else if(cmd=="TRANSFORM"){
                if(a.Length!=1||!Transforms.Contains(a[0]))error="bad arguments";
            }
            else{
                int expected=cmd=="AUTOPLAY"||cmd=="MC"?2:1;
                bool valid=a.Length==expected&&a.All(s=>Regex.IsMatch(s,@"\A[0-9]+\z"));
                if(valid){
                    long[] nums=a.Select(long.Parse).ToArray();
                    long n0=nums[0];
                    valid=cmd switch{
                        "AUTOPLAY"=>nums.All(n=>n>=1&&n<=4),"HINT" or "PV" or "AI" or "ANALYZE"=>n0>=1&&n0<=4,"PERFT" or "DIVIDE"=>n0>=1&&n0<=8,"MC"=>n0>=1&&n0<=100&&nums[1]>=1&&nums[1]<=2147483646,"RANDOM"=>n0>=1&&n0<=2147483646,_=>n0>=1
                    };
                }
                if(!valid)error="bad arguments";
            }
            if(error!=""){
                Emit("ERROR",error);
                return;
            }
            if(over&&Active.Contains(cmd)){
                Emit("ERROR game over");
                return;
            }
            int n=a.Length>0&&int.TryParse(a[0],out int numeric)?numeric:0;
            switch(cmd){
                case "NEW":Reset();
                Emit("OK");
                break;
                case "LOAD":board=a[0];
                side=a[1][0];
                over=false;
                history.Clear();
                redo.Clear();
                Emit("OK");
                Adjust();
                break;
                case "DUMP":Emit("board",board,side);
                break;
                case "SHOW":Emit("  a b c d e f g h");
                var legal=over?new List<int>():Legal(board,side);
                for(int r=0;r<8;r++)Emit((r+1)+" "+string.Join(" ",Enumerable.Range(0,8).Select(c=>legal.Contains(8*r+c)?'*':board[8*r+c])));
                Emit(Status());
                break;
                case "SCORE":Emit("score B",Count(board,'B'),"W",Count(board,'W'),"empty",Count(board,'.'));
                break;
                case "LEGAL":var moves=over?new List<int>():Legal(board,side);
                Emit(string.Join(" ",new[]{
                    "legal",moves.Count.ToString()
                }.Concat(moves.Select(Name))));
                break;
                case "MOVE":case "FLIPS":{
                    int p=Square(a[0]);
                    string why=Reason(p);
                    if(why!="")Emit("ILLEGAL",why);
                    else if(cmd=="MOVE")PlayMove(p);
                    else{
                        List<int> f=Flips(board,side,p);
                        Emit(string.Join(" ",new[]{
                            "flips",a[0],f.Count.ToString()
                        }.Concat(f.Select(Name))));
                    }
                    break;
                }
                case "PLAY":for(int i=0;i<a[0].Length;i+=2){
                    int p=Square(a[0].Substring(i,2));
                    string why=Reason(p);
                    if(why!=""){
                        Emit("ILLEGAL move",i/2+1,Name(p),why);
                        break;
                    }
                    PlayMove(p);
                }
                break;
                case "RECORD":Record(a[0]);
                break;
                case "UNDO":if(n>history.Count)Emit("ERROR cannot undo");
                else{
                    List<Move> removed=history.GetRange(history.Count-n,n);
                    Restore(removed[0].Before);
                    history.RemoveRange(history.Count-n,n);
                    redo.InsertRange(0,removed);
                    Emit(Status());
                }
                break;
                case "REDO":if(n>redo.Count)Emit("ERROR cannot redo");
                else{
                    List<Move> added=redo.GetRange(0,n);
                    redo.RemoveRange(0,n);
                    history.AddRange(added);
                    Restore(added[^1].After);
                    Emit(Status());
                }
                break;
                case "HISTORY":Emit("history",history.Count);
                for(int i=0;i<history.Count;i++){
                    Move r=history[i];
                    Emit($"{i+1} {r.Side} {Name(r.Square)} {r.Count}"+(r.Passed?" pass":""));
                }
                break;
                case "SHEET":Sheet();
                break;
                case "STATS":Stats();
                break;
                case "TRANSFORM":{
                    string op=a[0];
                    board=TransformBoard(board,op);
                    Move Tr(Move r)=>r with{
                        Square=Transform(r.Square,op),Before=r.Before with{
                            Board=TransformBoard(r.Before.Board,op)
                        },After=r.After with{
                            Board=TransformBoard(r.After.Board,op)
                        }
                    };
                    history=history.Select(Tr).ToList();
                    redo=redo.Select(Tr).ToList();
                    Emit("OK");
                    break;
                }
                case "EVAL":{
                    var (v,w,x,y)=Evaluate(board,side);
                    Emit("eval",v,"weights",w,"mobility",x,y);
                    break;
                }
                case "STABLE":{
                    var (b,w)=Stable(board);
                    Emit("stable B",b,"W",w);
                    break;
                }
                case "HINT":foreach(var (v,p) in Ranked(board,side,n))Emit(Name(p),v);
                break;
                case "PV":var pv=Variation(board,side,n);
                Emit(string.Join(" ",new[]{
                    "pv",Search(board,side,n).ToString()
                }.Concat(pv.Steps)));
                break;
                case "AI":{
                    var (v,p)=Ranked(board,side,n)[0];
                    PlayMove(p,false,v);
                    break;
                }
                case "ANALYZE":{
                    Dictionary<char,int> loss=new(){
                        {
                            'B',0
                        },{
                            'W',0
                        }
                    };
                    for(int i=0;i<history.Count;i++){
                        Move r=history[i];
                        var rows=Ranked(r.Before.Board,r.Side,n);
                        var (best,bp)=rows[0];
                        int v=rows.First(x=>x.Square==r.Square).Value;
                        loss[r.Side]+=best-v;
                        Emit(i+1,r.Side,Name(r.Square),v,"best",Name(bp),best);
                    }
                    Emit("loss B",loss['B'],"W",loss['W']);
                    break;
                }
                case "SOLVE":if(Count(board,'.')>=9)Emit("ERROR too many empties");
                else{
                    foreach(var (v,p) in Ranked(board,side,-1))Emit(Name(p),v);
                    var line=Variation(board,side,-1);
                    Emit(string.Join(" ",new[]{
                        "line"
                    }.Concat(line.Steps)));
                    Emit("final B",Count(line.Board,'B'),"W",Count(line.Board,'W'));
                }
                break;
                case "AUTOPLAY":AutoPlay(n,int.Parse(a[1]));
                break;
                case "RANDOM":AutoPlay(0,0,n);
                break;
                case "MC":MonteCarlo(n,long.Parse(a[1]));
                break;
                case "PERFT":Emit("perft",n,Perft(board,side,n));
                break;
                case "DIVIDE":int total=0;
                foreach(int p in Legal(board,side)){
                    int v=Perft(Place(board,side,p),Other(side),n-1);
                    Emit(Name(p),v);
                    total+=v;
                }
                Emit("total",total);
                break;
            }
        }
    }
    static void Main(){
        int n=int.Parse(Console.ReadLine()!);
        Othello e=new();
        for(int i=0;i<n;i++)e.Execute(Console.ReadLine()!);
    }
}
