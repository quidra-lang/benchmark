using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

static class Program
{
    const string Files="abcdefgh", Ranks="12345678", Initial="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
    static readonly (int X,int Y)[] Rook=[(0,1),(0,-1),(-1,0),(1,0)], Bishop=[(1,1),(-1,1),(1,-1),(-1,-1)], Knight=[(1,2),(2,1),(2,-1),(1,-2),(-1,-2),(-2,-1),(-2,1),(-1,2)];
    static readonly (int X,int Y)[] King=[..Rook,..Bishop];
    sealed record Rule(int King,int Rook,int Target,int RookTarget,int[] Path);
    readonly record struct Move(int Source,int Target,char Promotion='\0');
    readonly record struct Record(string San,string Uci,char Captured);
    static readonly Dictionary<char,Rule> Rules=new()
    {
        ['K']=new(4,7,6,5,[5,6]),['Q']=new(4,0,2,3,[1,2,3]),['k']=new(60,63,62,61,[61,62]),['q']=new(60,56,58,59,[57,58,59])
    };
    static void Fail(string reason)=>throw new ArgumentException(reason);
    static char Color(char p)=>char.IsUpper(p)?'w':'b';
    static char Opposite(char c)=>c=='w'?'b':'w';
    static char Colored(char p,char c)=>c=='w'?p:char.ToLowerInvariant(p);
    static int Step(char c)=>c=='w'?8:-8;
    static int Square(string s)=>Regex.IsMatch(s,"\\A[a-h][1-8]\\z")?s[0]-'a'+8*(s[1]-'1'):-1;
    static string Name(int s)=>$"{Files[s%8]}{Ranks[s/8]}";
    static int Number(string s,int lo,int hi)=>Regex.IsMatch(s,"\\A(?:0|[1-9][0-9]{0,8})\\z")&&int.TryParse(s,out int n)&&n>=lo&&n<=hi?n:-1;
    static int Shift(int s,int dx,int dy){int x=s%8+dx,y=s/8+dy;return x>=0&&x<8&&y>=0&&y<8?8*y+x:-1;}
    static IEnumerable<int> Targets(char[] board,int s)
    {
        char p=board[s],kind=char.ToUpperInvariant(p);
        if("PNK".Contains(kind))
        {
            (int X,int Y)[] dirs=kind=='P'?[(-1,Color(p)=='w'?1:-1),(1,Color(p)=='w'?1:-1)]:kind=='N'?Knight:King;
            foreach(var (dx,dy) in dirs){int t=Shift(s,dx,dy);if(t>=0)yield return t;}
        }
        else foreach(var (dx,dy) in kind=='Q'?King:kind=='R'?Rook:Bishop)
            for(int t=Shift(s,dx,dy);t>=0;t=Shift(t,dx,dy)){yield return t;if(board[t]!='.')break;}
    }
    static List<int> Attackers(char[] b,int t,char c)=>Enumerable.Range(0,64).Where(s=>b[s]!='.'&&Color(b[s])==c&&Targets(b,s).Contains(t)).ToList();
    sealed class Position
    {
        public readonly char[] Board;public readonly char Side;public readonly string Rights;public readonly int Ep,Half,Full;List<Move>? cached;
        public Position(char[] b,char side,string rights,int ep,int half,int full){Board=b;Side=side;Rights=rights;Ep=ep;Half=half;Full=full;}
        public bool Check(char? c=null){char side=c??Side;return Attackers(Board,Array.IndexOf(Board,Colored('K',side)),Opposite(side)).Count>0;}
        public bool Castle(Move m)=>char.ToUpperInvariant(Board[m.Source])=='K'&&Math.Abs(m.Target-m.Source)==2;
        public bool EnPassant(Move m)=>char.ToUpperInvariant(Board[m.Source])=='P'&&m.Source%8!=m.Target%8&&Board[m.Target]=='.';
        public bool Capture(Move m)=>Board[m.Target]!='.'||EnPassant(m);
        public char Captured(Move m)=>Board[m.Target]!='.'?char.ToLowerInvariant(Board[m.Target]):EnPassant(m)?'p':'-';
        public Position Play(Move m)
        {
            char[] b=(char[])Board.Clone();char piece=b[m.Source],kind=char.ToUpperInvariant(piece);
            if(EnPassant(m))b[m.Target-Step(Side)]='.';
            if(Castle(m)){Rule r=Rules[Colored(m.Target>m.Source?'K':'Q',Side)];b[r.RookTarget]=b[r.Rook];b[r.Rook]='.';}
            b[m.Target]=m.Promotion=='\0'?piece:Colored(m.Promotion,Side);b[m.Source]='.';
            string rights=new(Rights.Where(r=>(kind!='K'||Color(r)!=Side)&&Rules[r].Rook!=m.Source&&Rules[r].Rook!=m.Target).ToArray());
            return new(b,Opposite(Side),rights,kind=='P'&&Math.Abs(m.Target-m.Source)==16?(m.Source+m.Target)/2:-1,kind=='P'||Capture(m)?0:Half+1,Full+(Side=='b'?1:0));
        }
        public List<Move> Pseudo()
        {
            List<Move> result=[];
            for(int s=0;s<64;s++)
            {
                char p=Board[s];if(p=='.'||Color(p)!=Side)continue;bool pawn=char.ToUpperInvariant(p)=='P';List<int> a=[];
                if(pawn){int d=Step(Side);if(Board[s+d]=='.'){a.Add(s+d);if(s/8==(Side=='w'?1:6)&&Board[s+2*d]=='.')a.Add(s+2*d);}a.AddRange(Targets(Board,s).Where(t=>(Board[t]!='.'&&Color(Board[t])!=Side)||t==Ep));}
                else a.AddRange(Targets(Board,s).Where(t=>Board[t]=='.'||Color(Board[t])!=Side));
                foreach(int t in a)if(pawn&&t/8==(Side=='w'?7:0)){foreach(char promotion in "QRBN")result.Add(new(s,t,promotion));}else result.Add(new(s,t));
            }
            return result;
        }
        public Move CastlingMove(bool kingside){Rule r=Rules[Colored(kingside?'K':'Q',Side)];return new(r.King,r.Target);}
        public string CastlingProblem(bool kingside)
        {
            char right=Colored(kingside?'K':'Q',Side);Rule r=Rules[right];
            if(!Rights.Contains(right))return "no castling right";
            if(r.Path.Any(s=>Board[s]!='.'))return "path blocked";
            if(Check())return "in check";
            if(Attackers(Board,r.RookTarget,Opposite(Side)).Count>0)return "through check";
            if(Play(CastlingMove(kingside)).Check(Side))return "into check";
            return "";
        }
        public List<Move> Legal()
        {
            if(cached is not null)return cached;List<Move>a=Pseudo().Where(m=>!Play(m).Check(Side)).ToList();
            foreach(bool k in new[]{true,false})if(CastlingProblem(k)=="")a.Add(CastlingMove(k));return cached=a;
        }
        public string Mark(Move m){Position q=Play(m);return q.Check()?(q.Legal().Count==0?"#":"+"):"";}
        public string Disambiguation(Move m)
        {
            List<Move>a=Legal().Where(x=>!Castle(x)&&x.Target==m.Target&&x.Source!=m.Source&&Board[x.Source]==Board[m.Source]).ToList();
            return a.Count==0?"":a.All(x=>x.Source%8!=m.Source%8)?Files[m.Source%8].ToString():a.All(x=>x.Source/8!=m.Source/8)?Ranks[m.Source/8].ToString():Name(m.Source);
        }
        public string San(Move m)
        {
            char kind=char.ToUpperInvariant(Board[m.Source]);string text;
            if(Castle(m))text=m.Target>m.Source?"O-O":"O-O-O";
            else if(kind=='P')text=(Capture(m)?Files[m.Source%8]+"x":"")+Name(m.Target)+(m.Promotion!='\0'?"="+m.Promotion:"");
            else text=kind+Disambiguation(m)+(Capture(m)?"x":"")+Name(m.Target);
            return text+Mark(m);
        }
        public string Key()=>new string(Board)+$" {Side} {Rights} "+(Ep>=0&&Legal().Any(EnPassant)?Ep:-1);
        public string State()=>Check()?(Legal().Count==0?"checkmate":"check"):(Legal().Count==0?"stalemate":"normal");
        public bool Insufficient()
        {
            int[]a=Enumerable.Range(0,64).Where(s=>Board[s]!='.'&&char.ToUpperInvariant(Board[s])!='K').ToArray();
            if(a.Any(s=>"PRQ".Contains(char.ToUpperInvariant(Board[s]))))return false;
            return a.Length<=1||a.All(s=>char.ToUpperInvariant(Board[s])=='B')&&a.Select(s=>(s%8+s/8)%2).Distinct().Count()==1;
        }
        public List<(int,int)> Pins()
        {
            int king=Array.IndexOf(Board,Colored('K',Side));List<(int,int)>a=[];
            foreach(var (dx,dy) in King){int first=-1;for(int t=Shift(king,dx,dy);t>=0;t=Shift(t,dx,dy)){char p=Board[t];if(p=='.')continue;if(first<0){if(Color(p)!=Side)break;first=t;}else{if(Color(p)!=Side&&(char.ToUpperInvariant(p)=='Q'||char.ToUpperInvariant(p)==(dx==0||dy==0?'R':'B')))a.Add((first,t));break;}}}
            a.Sort((x,y)=>x.Item1.CompareTo(y.Item1));return a;
        }
        public string Fen()
        {
            List<string>rows=[];
            for(int r=7;r>=0;r--){StringBuilder row=new();int empty=0;for(int f=0;f<8;f++){char p=Board[r*8+f];if(p=='.')empty++;else{if(empty>0)row.Append(empty);empty=0;row.Append(p);}}if(empty>0)row.Append(empty);rows.Add(row.ToString());}
            return string.Join('/',rows)+$" {Side} "+(Rights==""?"-":Rights)+" "+(Ep<0?"-":Name(Ep))+$" {Half} {Full}";
        }
    }
    static Position ParseFen(string[]a)
    {
        if(a.Length!=6)Fail("fields");string[]rows=a[0].Split('/');if(rows.Length!=8)Fail("placement");char[]b=Enumerable.Repeat('.',64).ToArray();
        for(int i=0;i<8;i++){int f=0;bool digit=false;foreach(char c in rows[i])if(c>='1'&&c<='8'){if(digit)Fail("placement");f+=c-'0';digit=true;}else{if(!"KQRBNPkqrbnp".Contains(c)||f>=8)Fail("placement");b[(7-i)*8+f++]=c;digit=false;}if(f!=8)Fail("placement");}
        if(b.Count(c=>c=='K')!=1||b.Count(c=>c=='k')!=1)Fail("kings");
        if(b.Take(8).Concat(b.Skip(56)).Any(c=>c=='P'||c=='p'))Fail("pawns");
        if(a[1]!="w"&&a[1]!="b")Fail("side");char side=a[1][0];
        if(a[2]!="-"&&(a[2]==""||!Regex.IsMatch(a[2],"\\AK?Q?k?q?\\z")))Fail("castling");string rights=a[2]=="-"?"":a[2];
        foreach(char r in rights){Rule rule=Rules[r];if(b[rule.King]!=Colored('K',Color(r))||b[rule.Rook]!=Colored('R',Color(r)))Fail("castling");}
        int ep=-1;if(a[3]!="-"){ep=Square(a[3]);int d=Step(side);if(ep<0||ep/8!=(side=='w'?5:2)||b[ep]!='.'||b[ep+d]!='.'||b[ep-d]!=Colored('P',Opposite(side)))Fail("en passant");}
        int half=Number(a[4],0,999),full=Number(a[5],1,999);if(half<0||full<0||(ep>=0&&half!=0))Fail("clocks");Position p=new(b,side,rights,ep,half,full);if(p.Check(Opposite(side)))Fail("check");return p;
    }
    static Move ReadSan(Position p,string text)
    {
        string mark=text.EndsWith('+')||text.EndsWith('#')?text[^1..]:"",body=mark==""?text:text[..^1];bool castling=body is "O-O" or "O-O-O",capture=false;char promotion='\0',kind='P';string file="",rank="";int target=-1;
        if(!castling)
        {
            if(body.Length>=2&&body[^2]=='='){promotion=body[^1];if(!"QRBN".Contains(promotion))Fail("syntax");body=body[..^2];}
            if(body.Length<2)Fail("syntax");target=Square(body[^2..]);if(target<0)Fail("syntax");body=body[..^2];capture=body.EndsWith('x');if(capture)body=body[..^1];
            if(body.Length>0&&"KQRBN".Contains(body[0])){kind=body[0];Match h=Regex.Match(body[1..],"\\A([a-h]?)([1-8]?)\\z");if(!h.Success||promotion!='\0')Fail("syntax");file=h.Groups[1].Value;rank=h.Groups[2].Value;}
            else{if(!Regex.IsMatch(body,capture?"\\A[a-h]\\z":"\\A\\z"))Fail("syntax");file=body;}
        }
        List<Move>legal=p.Legal();if(legal.Count==0)Fail("game over");Move move;
        if(castling){bool k=body=="O-O";string problem=p.CastlingProblem(k);if(problem!="")Fail(problem);move=p.CastlingMove(k);}
        else
        {
            bool Matches(Move m)=>char.ToUpperInvariant(p.Board[m.Source])==kind&&m.Target==target&&!p.Castle(m)&&(file==""||Files[m.Source%8]==file[0])&&(rank==""||Ranks[m.Source/8]==rank[0])&&(kind!='P'||(m.Source%8!=m.Target%8)==capture);
            List<Move>a=legal.Where(Matches).ToList();if(a.Count==0)Fail(p.Pseudo().Any(Matches)?"leaves king in check":"no such move");
            if(a.Select(m=>m.Source).Distinct().Count()>1)Fail("ambiguous");move=a[0];if(p.Capture(move)!=capture)Fail("capture mark");if(move.Promotion!='\0'&&promotion=='\0')Fail("missing promotion");if(promotion!='\0'&&move.Promotion=='\0')Fail("invalid promotion");if(kind!='P'&&file+rank!=p.Disambiguation(move))Fail("disambiguation");move=move with{Promotion=promotion};
        }
        if(p.Mark(move)!=mark)Fail("check mark");return move;
    }
    static Move ReadUci(Position p,string text)
    {
        if(!Regex.IsMatch(text,"\\A[a-h][1-8][a-h][1-8][qrbn]?\\z"))Fail("syntax");int s=Square(text[..2]),t=Square(text[2..4]);char promotion=text.Length==5?char.ToUpperInvariant(text[4]):'\0';List<Move>legal=p.Legal();
        if(legal.Count==0)Fail("game over");if(p.Board[s]=='.'||Color(p.Board[s])!=p.Side)Fail("no piece");List<Move>a=legal.Where(m=>m.Source==s&&m.Target==t).ToList();if(a.Count==0)Fail(p.Pseudo().Any(m=>m.Source==s&&m.Target==t)?"leaves king in check":"no such move");
        if(a[0].Promotion!='\0'&&promotion=='\0')Fail("missing promotion");if(promotion!='\0'&&a[0].Promotion=='\0')Fail("invalid promotion");return new(s,t,promotion);
    }
    static long Perft(Position p,int d,long[]? stats=null)
    {
        if(d==0)return 1;long total=0;
        foreach(Move m in p.Legal()){Position q=p.Play(m);total+=Perft(q,d-1,stats);if(d==1&&stats is not null){stats[0]++;if(p.Capture(m))stats[1]++;if(p.EnPassant(m))stats[2]++;if(p.Castle(m))stats[3]++;if(m.Promotion!='\0')stats[4]++;if(q.Check()){stats[5]++;if(q.Legal().Count==0)stats[6]++;}}}
        return total;
    }
    sealed class Game
    {
        public List<Position> Positions;public List<Record> Records=[];public bool Loaded;
        public Game(Position? start=null,bool loaded=false){Positions=[start??ParseFen(Initial.Split(' '))];Loaded=loaded;}
        public Position Current=>Positions[^1];
        public void Play(Move m){Position p=Current;Records.Add(new(p.San(m),Name(m.Source)+Name(m.Target)+(m.Promotion=='\0'?"":char.ToLowerInvariant(m.Promotion).ToString()),p.Captured(m)));Positions.Add(p.Play(m));}
        public int Repetition(){string key=Current.Key();return Positions.Count(p=>p.Key()==key);}
        public List<string> Draws(){List<string>a=[];if(Current.Half>=100)a.Add("fifty");if(Repetition()>=3)a.Add("threefold");if(Current.Insufficient())a.Add("insufficient");return a;}
        public string Result(){string s=Current.State();return s=="checkmate"?(Current.Side=='b'?"1-0":"0-1"):s=="stalemate"||Draws().Count>0?"1/2-1/2":"*";}
    }
    static Game game=new();
    static void Execute(string line)
    {
        string[]w=line.Split(' '),a=w.Skip(1).ToArray();string cmd=w[0];
        if(!new[]{"NEW","LOAD","FEN","BOARD","MOVE","UCI","LEGAL","STATUS","UNDO","PERFT","DIVIDE","ATTACKS","PINS","HISTORY","PGN"}.Contains(cmd)){Console.WriteLine("ERROR unknown command");return;}
        bool bad=new[]{"NEW","FEN","BOARD","STATUS","PINS","HISTORY","PGN"}.Contains(cmd)&&a.Length!=0;
        if(cmd is "MOVE" or "UCI")bad=a.Length==0;if(cmd=="LEGAL")bad=a.Length>1||(a.Length==1&&Square(a[0])<0);if(cmd=="ATTACKS")bad=a.Length!=1||(a.Length==1&&Square(a[0])<0);int n=-1;if(cmd is "UNDO" or "PERFT" or "DIVIDE"){n=a.Length==1?Number(a[0],1,cmd=="UNDO"?9999:3):-1;bad=n<0;}if(bad){Console.WriteLine("ERROR bad arguments");return;}
        Position p=game.Current;
        switch(cmd)
        {
        case "NEW":game=new();Console.WriteLine("OK");break;
        case "LOAD":try{Position q=ParseFen(a);game=new(q,true);Console.WriteLine("OK");}catch(ArgumentException e){Console.WriteLine($"ERROR bad fen ({e.Message})");}break;
        case "FEN":Console.WriteLine(p.Fen());break;
        case "BOARD":for(int r=7;r>=0;r--)Console.WriteLine(string.Join(' ',new[]{(r+1).ToString()}.Concat(p.Board.Skip(8*r).Take(8).Select(c=>c.ToString()))));Console.WriteLine("  a b c d e f g h");break;
        case "MOVE":case "UCI":
            List<string>played=[];string failure="";for(int i=0;i<a.Length;i++){try{Move m=cmd=="MOVE"?ReadSan(game.Current,a[i]):ReadUci(game.Current,a[i]);game.Play(m);played.Add(game.Records[^1].San);}catch(ArgumentException e){failure=$"ILLEGAL move {i+1}: {a[i]} ({e.Message})";break;}}
            if(cmd=="UCI"&&played.Count>0)Console.WriteLine("san "+string.Join(' ',played));if(failure!="")Console.WriteLine(failure);else if(cmd=="MOVE")Console.WriteLine("OK");break;
        case "LEGAL":string[]list=p.Legal().Where(m=>a.Length==0||m.Source==Square(a[0])).Select(p.San).Order(StringComparer.Ordinal).ToArray();Console.WriteLine(string.Join(' ',new[]{"legal",list.Length.ToString()}.Concat(list)));break;
        case "STATUS":Console.WriteLine(string.Join(' ',new[]{"status",p.Side=='w'?"white":"black",p.State(),"rep",game.Repetition().ToString()}.Concat(game.Draws())));break;
        case "UNDO":if(n>game.Records.Count)Console.WriteLine("ERROR cannot undo");else{game.Records.RemoveRange(game.Records.Count-n,n);game.Positions.RemoveRange(game.Positions.Count-n,n);Console.WriteLine("OK");}break;
        case "PERFT":long[]stats=new long[7];Perft(p,n,stats);string[]fields=["nodes","captures","ep","castles","promotions","checks","mates"];Console.WriteLine($"perft {n} "+string.Join(' ',fields.Select((f,i)=>$"{f} {stats[i]}")));break;
        case "DIVIDE":var rows=p.Legal().Select(m=>(San:p.San(m),Count:Perft(p.Play(m),n-1))).OrderBy(r=>r.San,StringComparer.Ordinal).ToList();foreach(var row in rows)Console.WriteLine($"{row.San} {row.Count}");Console.WriteLine($"total {rows.Sum(r=>r.Count)}");break;
        case "ATTACKS":List<string>words=["attacks",a[0]];foreach(char c in new[]{'w','b'}){List<int>found=Attackers(p.Board,Square(a[0]),c);words.Add(c=='w'?"white":"black");words.Add(found.Count.ToString());words.AddRange(found.Select(Name));}Console.WriteLine(string.Join(' ',words));break;
        case "PINS":var pins=p.Pins();Console.WriteLine(string.Join(' ',new[]{"pins",pins.Count.ToString()}.Concat(pins.Select(pair=>Name(pair.Item1)+"-"+Name(pair.Item2)))));break;
        case "HISTORY":Console.WriteLine($"history {game.Records.Count}");for(int i=0;i<game.Records.Count;i++){Record r=game.Records[i];Console.WriteLine($"{i+1} {r.Uci} {r.San} {r.Captured}");}break;
        case "PGN":string result=game.Result();Console.WriteLine($"[Result \"{result}\"]");if(game.Loaded){Console.WriteLine("[SetUp \"1\"]");Console.WriteLine($"[FEN \"{game.Positions[0].Fen()}\"]");}List<string>text=[];for(int i=0;i<game.Records.Count;i++){Position q=game.Positions[i];if(q.Side=='w')text.Add($"{q.Full}.");else if(i==0)text.Add($"{q.Full}...");text.Add(game.Records[i].San);}text.Add(result);Console.WriteLine(string.Join(' ',text));break;
        }
    }
    static void Main(){int n=int.Parse(Console.ReadLine()!);for(int i=0;i<n;i++)Execute(Console.ReadLine()!);}
}
