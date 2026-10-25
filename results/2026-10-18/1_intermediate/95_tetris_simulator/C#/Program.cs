using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

internal readonly record struct Position(int State, int X, int Y);
internal readonly record struct Cell(int X, int Y);
internal readonly record struct Movement(Position Position, int Test);
internal readonly record struct ClearInfo(int Name, int Points, int Sent);
internal readonly record struct WellMetrics(int[] Heights, int Holes, int Bumpiness, int Value);
internal readonly record struct Route(Position Position, int Parent, int Operation);
internal record Candidate(int Kind, int Value, List<int> Operations, string Occupied, int Order = 0);
internal readonly record struct SpinCandidate(Position Position, int Spin);

internal sealed class Statistics
{
    public int Drops;
    public int Holds;
    public int Operations;
    public int Faults;
    public int Perfect;
    public int Sent;
    public int Cancelled;
    public int Received;
    public int Combo;
    public int Chain;
    public int[] Kinds = new int[7];
    public int[] Clears = new int[11];
    public Statistics Copy() => new Statistics
    {
        Drops=Drops, Holds=Holds, Operations=Operations, Faults=Faults, Perfect=Perfect,
        Sent=Sent, Cancelled=Cancelled, Received=Received, Combo=Combo, Chain=Chain,
        Kinds=(int[])Kinds.Clone(), Clears=(int[])Clears.Clone()
    };
}
internal sealed class GameState
{
    public int[] Board = new int[22];
    public long Random;
    public List<int> Queue = new();
    public int? Hold;
    public bool UsedHold;
    public int Kind;
    public Position Position;
    public int Last, Test, Keys, Drop, Fall, Ground, Resets, Lowest;
    public int InitialLevel, Level, Score, Lines, Pieces, Streak, Chain;
    public List<int> Pending = new();
    public bool Ended;
    public Statistics Stats = new();
    public GameState Copy() => new GameState
    {
        Board=(int[])Board.Clone(), Random=Random, Queue=new List<int>(Queue), Hold=Hold,
        UsedHold=UsedHold, Kind=Kind, Position=Position, Last=Last, Test=Test, Keys=Keys,
        Drop=Drop, Fall=Fall, Ground=Ground, Resets=Resets, Lowest=Lowest,
        InitialLevel=InitialLevel, Level=Level, Score=Score, Lines=Lines, Pieces=Pieces,
        Streak=Streak, Chain=Chain, Pending=new List<int>(Pending), Ended=Ended, Stats=Stats.Copy()
    };
}
internal sealed class SavedGame
{
    public required GameState State { get; init; }
    public required List<GameState> History { get; init; }
    public required GameState Start { get; init; }
}
internal sealed class GameOverException : Exception { }
internal static class Tetris
{
    internal const string Kinds = "IOTSZJL";
    internal const string States = "0R2L";
    internal static readonly string[] Operations = {"L", "R", "LL", "RR", "SD", "DD", "CW", "CCW", "HD", "LOCK", "HOLD"};
    internal static readonly HashSet<string> Commands = new("NEW PRINT NEXT PREVIEW STATUS ANALYZE ROW GARBAGE ATTACK TICK UNDO SAVE LOAD SPINS HINT AUTO".Split(' '));
    internal static readonly HashSet<string> AfterEnd = new("PRINT NEXT PREVIEW STATUS ANALYZE LOAD".Split(' '));
    internal static readonly string[] ClearNames = {"SINGLE", "DOUBLE", "TRIPLE", "TETRIS", "TSPIN_MINI", "TSPIN_MINI_SINGLE", "TSPIN_MINI_DOUBLE", "TSPIN", "TSPIN_SINGLE", "TSPIN_DOUBLE", "TSPIN_TRIPLE"};
    private static readonly string[][] Frames =
    {
        new[] {"....","####","....","...."},new[] {"##","##"},new[] {".#.","###","..."},
        new[] {".##","##.","..."},new[] {"##.",".##","..."},new[] {"#..","###","..."},new[] {"..#","###","..."}
    };
    private static readonly (int X,int Y)[][] OrdinaryKicks =
    {
        new[] {(0,0),(-1,0),(-1,1),(0,-2),(-1,-2)},
        new[] {(0,0),(1,0),(1,-1),(0,2),(1,2)},
        new[] {(0,0),(1,0),(1,-1),(0,2),(1,2)},
        new[] {(0,0),(-1,0),(-1,1),(0,-2),(-1,-2)},
        new[] {(0,0),(1,0),(1,1),(0,-2),(1,-2)},
        new[] {(0,0),(-1,0),(-1,-1),(0,2),(-1,2)},
        new[] {(0,0),(-1,0),(-1,-1),(0,2),(-1,2)},
        new[] {(0,0),(1,0),(1,1),(0,-2),(1,-2)}
    };
    private static readonly (int X,int Y)[][] IKicks =
    {
        new[] {(0,0),(-2,0),(1,0),(-2,-1),(1,2)},
        new[] {(0,0),(2,0),(-1,0),(2,1),(-1,-2)},
        new[] {(0,0),(-1,0),(2,0),(-1,2),(2,-1)},
        new[] {(0,0),(1,0),(-2,0),(1,-2),(-2,1)},
        new[] {(0,0),(2,0),(-1,0),(2,1),(-1,-2)},
        new[] {(0,0),(-2,0),(1,0),(-2,-1),(1,2)},
        new[] {(0,0),(1,0),(-2,0),(1,-2),(-2,1)},
        new[] {(0,0),(-1,0),(2,0),(-1,2),(2,-1)}
    };
    private static readonly (int From,int To)[] KickStates = {(0,1),(1,0),(1,2),(2,1),(2,3),(3,2),(3,0),(0,3)};
    private static readonly Cell[][][] Shapes = InitializeShapes();
    internal static Cell[][][] InitializeShapes()
    {
        var result = new Cell[7][][];
        for(int kind=0;kind<7;kind++)
        {
            int size=Frames[kind].Length;
            var blocks=new List<Cell>();
            for(int row=0;row<size;row++)for(int col=0;col<size;col++)
                if(Frames[kind][row][col]=='#')blocks.Add(new Cell(col,row));
            result[kind]=new Cell[4][];
            result[kind][0]=blocks.ToArray();
            for(int rotation=1;rotation<4;rotation++)
            {
                blocks=blocks.Select(cell=>new Cell(size-1-cell.Y,cell.X)).ToList();
                result[kind][rotation]=blocks.ToArray();
            }
        }
        return result;
    }
    internal static Position Spawn(int kind) => new(0,kind==1?5:4,22);
    internal static long SeedStep(long value) => 48271*value%2147483647;
    internal static Cell[] Cells(int kind,Position pos) => Shapes[kind][pos.State].Select(c=>new Cell(pos.X+c.X,pos.Y-c.Y)).ToArray();
    internal static int Lowest(int kind,Position pos) => Cells(kind,pos).Min(c=>c.Y);
    internal static (long,List<int>) Bag(long value)
    {
        var pieces=Enumerable.Range(0,7).ToList();
        for(int i=6;i>=1;i--)
        {
            value=SeedStep(value);
            int j=(int)(value%(i+1));
            (pieces[i],pieces[j])=(pieces[j],pieces[i]);
        }
        return (value,pieces);
    }
    internal static bool Fits(int[] board,int kind,Position pos)
    {
        foreach(var cell in Cells(kind,pos))
        {
            if(cell.X<1||cell.X>10||cell.Y<1||cell.Y>22)return false;
            if((board[cell.Y-1]&(1<<(cell.X-1)))!=0)return false;
        }
        return true;
    }
    internal static Movement? Move(int[] board,int kind,Position pos,int op)
    {
        if(op==6||op==7)
        {
            int next=(pos.State+(op==6?1:3))%4;
            int row=Array.FindIndex(KickStates,k=>k.From==pos.State&&k.To==next);
            var offsets=kind==1?new[] {(0,0)}:(kind==0?IKicks:OrdinaryKicks)[row];
            for(int i=0;i<offsets.Length;i++)
            {
                var p=new Position(next,pos.X+offsets[i].Item1,pos.Y+offsets[i].Item2);
                if(Fits(board,kind,p))return new Movement(p,i+1);
            }
            return null;
        }
        int dx=(op==0||op==2)?-1:(op==1||op==3)?1:0;
        int dy=dx==0?-1:0;
        bool repeated=op==2||op==3||op==5;
        var current=pos;
        bool changed=false;
        do
        {
            var p=new Position(pos.State,current.X+dx,current.Y+dy);
            if(!Fits(board,kind,p))break;
            current=p;
            changed=true;
        }while(repeated);
        return changed?new Movement(current,0):null;
    }
    internal static Position Landing(int[] board,int kind,Position pos)=>Move(board,kind,pos,5)?.Position??pos;
    internal static (int[],int) Placed(int[] board,int kind,Position pos)
    {
        var result=(int[])board.Clone();
        foreach(var cell in Cells(kind,pos))result[cell.Y-1]|=1<<(cell.X-1);
        var remaining=result.Where(row=>row!=1023).ToList();
        int count=22-remaining.Count;
        remaining.AddRange(Enumerable.Repeat(0,count));
        return (remaining.ToArray(),count);
    }
    internal static WellMetrics Evaluate(int[] board,int cleared)
    {
        var heights=new int[10];
        int holes=0,bump=0;
        for(int col=0;col<10;col++)
        {
            for(int row=21;row>=0;row--)if((board[row]&(1<<col))!=0){heights[col]=row+1;break;}
            for(int row=0;row<heights[col];row++)if((board[row]&(1<<col))==0)holes++;
        }
        for(int col=0;col<9;col++)bump+=Math.Abs(heights[col]-heights[col+1]);
        return new WellMetrics(heights,holes,bump,76*cleared-51*heights.Sum()-36*holes-18*bump);
    }
    internal static (List<Route>,int?) Routes(int[] board,int kind,Position start,Position? target=null)
    {
        if(!Fits(board,kind,start))return (new List<Route>(),null);
        var entries=new List<Route>{new(start,-1,-1)};
        var seen=new HashSet<Position>{start};
        for(int i=0;i<entries.Count;i++)
        {
            var entry=entries[i];
            if(target.HasValue&&Landing(board,kind,entry.Position)==target.Value)return (entries,i);
            for(int op=0;op<8;op++)
            {
                var next=Move(board,kind,entry.Position,op);
                if(next.HasValue&&seen.Add(next.Value.Position))entries.Add(new Route(next.Value.Position,i,op));
            }
        }
        return (target.HasValue?new List<Route>():entries,null);
    }
    internal static List<int> Shortest(List<Route> nodes,int index)
    {
        var result=new List<int>();
        while(nodes[index].Parent>=0){result.Add(nodes[index].Operation);index=nodes[index].Parent;}
        result.Reverse();return result;
    }
    internal static int TSpin(int[] board,Position p,int test)
    {
        var corners=new[]{new Cell(p.X,p.Y),new Cell(p.X+2,p.Y),new Cell(p.X+2,p.Y-2),new Cell(p.X,p.Y-2)};
        var blocked=corners.Select(c=>c.X<1||c.X>10||c.Y<1||c.Y>22||(board[c.Y-1]&(1<<(c.X-1)))!=0).ToArray();
        if(blocked.Count(x=>x)<3)return 0;
        return (blocked[p.State]&&blocked[(p.State+1)%4])||test==5?2:1;
    }
    internal static ClearInfo Clearance(int spin,int n)
    {
        if(spin==2)return new ClearInfo(7+n,new[]{400,800,1200,1600}[n],new[]{0,2,4,6}[n]);
        if(spin==1)return new ClearInfo(4+n,new[]{100,200,400}[n],new[]{0,0,1}[n]);
        return new ClearInfo(n==0?-1:n-1,new[]{0,100,300,500,800}[n],new[]{0,0,1,2,4}[n]);
    }
    internal static string OperationText(IEnumerable<int> list)=>string.Join(" ",list.Select(i=>Operations[i]));
    internal static bool ValidNumber(string text,int min,int max)
    {
        if(text.Length==0||(text.Length>1&&text[0]=='0')||!text.All(ch=>ch>='0'&&ch<='9'))return false;
        return long.TryParse(text,out long value)&&value>=min&&value<=max;
    }
    internal static bool ValidArguments(string command,string[] args)
    {
        if(command=="NEW")return args.Length==2&&ValidNumber(args[0],1,2147483646)&&ValidNumber(args[1],1,15);
        if(command=="ROW")return args.Length==2&&ValidNumber(args[0],1,22)&&args[1].Length==10&&args[1].All(ch=>ch=='#'||ch=='.')&&args[1].Contains('.');
        if(command=="GARBAGE")return args.Length==2&&ValidNumber(args[0],1,10)&&ValidNumber(args[1],1,10);
        if(command=="SAVE"||command=="LOAD")return args.Length==1&&args[0].Length>=1&&args[0].Length<=8&&args[0].All(ch=>ch>='a'&&ch<='z');
        int limit=command switch{"PREVIEW"=>14,"ATTACK"=>20,"TICK"=>1000,"HINT"=>10,"AUTO"=>50,_=>0};
        return limit!=0?args.Length==1&&ValidNumber(args[0],1,limit):args.Length==0;
    }
    internal static void Main()
    {
        int count=int.Parse(Console.ReadLine()!);
        Game? game=null;
        int serial=0;
        for(int i=0;i<count;i++)
        {
            var words=Console.ReadLine()!.Split(' ');
            string command=words[0];
            var args=words.Skip(1).ToArray();
            try
            {
                if(Commands.Contains(command))
                {
                    if(!ValidArguments(command,args)){Console.WriteLine("ERROR bad arguments");continue;}
                    if(command=="NEW")
                    {
                        if(game!=null&&!game.State.Ended){Console.WriteLine("game stopped");game.Summary();}
                        serial++;
                        Console.WriteLine($"game {serial} seed {int.Parse(args[0])} level {int.Parse(args[1])}");
                        game=new Game(serial,int.Parse(args[0]),int.Parse(args[1]));
                    }
                    else if(game==null)Console.WriteLine("ERROR no game");
                    else if(game.State.Ended&&!AfterEnd.Contains(command))Console.WriteLine("ERROR game over");
                    else game.Command(command,args);
                }
                else
                {
                    var invalid=words.FirstOrDefault(word=>!Operations.Contains(word));
                    if(invalid!=null)Console.WriteLine($"ERROR unknown {invalid}");
                    else if(game==null)Console.WriteLine("ERROR no game");
                    else if(game.State.Ended)Console.WriteLine("ERROR game over");
                    else foreach(var word in words)game.Operation(Array.IndexOf(Operations,word));
                }
            }
            catch(GameOverException){}
        }
        if(game!=null&&!game.State.Ended){Console.WriteLine("game stopped");game.Summary();}
    }
}
internal sealed class Game
{
    private readonly int number;
    public GameState State { get; private set; }
    private List<GameState> history=new();
    private GameState start;
    private readonly Dictionary<string,SavedGame> saves=new();
    public Game(int number,int seed,int level)
    {
        this.number=number;
        State=new GameState{Random=seed,InitialLevel=level,Level=level};
        AddBag();
        SpawnPiece(TakeNext());
        start=State.Copy();
    }
    private void AddBag()
    {
        var (next,pieces)=Tetris.Bag(State.Random);
        State.Random=next;
        State.Queue.AddRange(pieces);
    }
    private int TakeNext()
    {
        int kind=State.Queue[0];State.Queue.RemoveAt(0);
        if(State.Queue.Count<5)AddBag();
        return kind;
    }
    private void SpawnPiece(int kind)
    {
        State.Kind=kind;
        State.Position=Tetris.Spawn(kind);
        State.Last=0;State.Test=0;State.Keys=0;State.Drop=0;State.Fall=0;State.Ground=0;State.Resets=0;
        State.Lowest=Tetris.Lowest(kind,State.Position);
        if(!Tetris.Fits(State.Board,kind,State.Position))GameOver("block out");
    }
    private void GameOver(string reason)
    {
        Console.WriteLine($"game over {reason}");
        Summary();
        State.Ended=true;
        throw new GameOverException();
    }
    private void Update(Position p,int last,int test=0)
    {
        State.Position=p;State.Last=last;State.Test=test;
        int row=Tetris.Lowest(State.Kind,p);
        if(row<State.Lowest){State.Lowest=row;State.Resets=0;}
    }
    private bool Grounded()=>Tetris.Move(State.Board,State.Kind,State.Position,4)==null;
    private void Drops(int points)
    {
        State.Score+=points;State.Drop+=points;State.Stats.Drops+=points;
    }
    private void InsertGarbage(int count,int hole)
    {
        if(State.Board.Skip(22-count).Any(row=>row!=0))GameOver("top out");
        State.Board=Enumerable.Repeat(1023^(1<<(hole-1)),count).Concat(State.Board.Take(22-count)).ToArray();
    }
    public void Operation(int op)
    {
        if(op<8)
        {
            State.Keys++;
            var next=Tetris.Move(State.Board,State.Kind,State.Position,op);
            if(!next.HasValue){Console.WriteLine($"fail {Tetris.Operations[op]}");return;}
            if(op==4||op==5)
            {
                Drops(State.Position.Y-next.Value.Position.Y);
                Update(next.Value.Position,1);
                State.Fall=0;State.Ground=0;
            }
            else
            {
                Update(next.Value.Position,op>=6?2:1,next.Value.Test);
                if(State.Ground>0&&State.Resets<15){State.Ground=0;State.Resets++;}
            }
        }
        else if(op==8)
        {
            var p=Tetris.Landing(State.Board,State.Kind,State.Position);
            int rows=State.Position.Y-p.Y;
            Drops(2*rows);
            if(rows>0)Update(p,1);
            Lock();
        }
        else if(op==9)
        {
            if(Grounded())Lock();else Console.WriteLine("fail LOCK");
        }
        else
        {
            if(State.UsedHold){Console.WriteLine("fail HOLD");return;}
            State.UsedHold=true;State.Stats.Holds++;
            int? previous=State.Hold;
            State.Hold=State.Kind;
            SpawnPiece(previous??TakeNext());
        }
    }
    private void Tick()
    {
        if(!Grounded())
        {
            State.Ground=0;State.Fall++;
            int interval=State.Level>=13?1:new[]{60,48,37,28,21,16,11,8,6,4,3,2}[State.Level-1];
            if(State.Fall>=interval){Update(State.Position with {Y=State.Position.Y-1},1);State.Fall=0;}
        }
        else
        {
            State.Ground++;
            if(State.Ground>=30)Lock();
        }
    }
    private void Lock()
    {
        int kind=State.Kind;
        var p=State.Position;
        var oldCells=Tetris.Cells(kind,p);
        var route=Tetris.Routes(State.Board,kind,Tetris.Spawn(kind),p);
        var shortest=route.Item2.HasValue?Tetris.Shortest(route.Item1,route.Item2.Value):null;
        int spin=kind==2&&State.Last==2?Tetris.TSpin(State.Board,p,State.Test):0;
        var placement=Tetris.Placed(State.Board,kind,p);
        int n=placement.Item2;
        State.Board=placement.Item1;
        history.Add(start.Copy());
        State.Pieces++;State.Stats.Kinds[kind]++;State.Stats.Operations+=State.Keys;
        var info=Tetris.Clearance(spin,n);
        int level=State.Level;
        int points=info.Points*level;
        int sent=info.Sent;
        bool back=false;
        if(n>0)
        {
            State.Streak++;
            if(n==4||spin!=0){State.Chain++;back=State.Chain>=2;}
            else State.Chain=0;
        }
        else State.Streak=0;
        if(back){points=points*3/2;sent++;}
        int combo=State.Streak-1;
        int comboPoints=combo>=1?50*combo*level:0;
        if(combo>=0)sent+=new[]{0,1,1,2,2,3,3,4,4,4,5}[Math.Min(combo,10)];
        bool perfect=n>0&&State.Board.All(row=>row==0);
        int perfectPoints=perfect?(n==4&&back?3200:new[]{800,1200,1800,2000}[n-1])*level:0;
        if(perfect){sent+=10;State.Stats.Perfect++;}
        int gained=points+comboPoints+perfectPoints;
        State.Score+=gained;State.Lines+=n;State.Stats.Sent+=sent;
        State.Stats.Combo=Math.Max(State.Stats.Combo,combo);
        State.Stats.Chain=Math.Max(State.Stats.Chain,State.Chain);
        Console.WriteLine($"lock {State.Pieces} {Tetris.Kinds[kind]} {Tetris.States[p.State]} {p.X} {p.Y} keys {State.Keys} {(shortest==null?"-":shortest.Count.ToString())} drop {State.Drop} lines {n} sent {sent} +{gained} total {State.Score}");
        if(shortest!=null&&State.Keys>shortest.Count)
        {
            State.Stats.Faults++;
            Console.WriteLine("finesse "+(shortest.Count==0?"none":Tetris.OperationText(shortest)));
        }
        if(info.Name>=0)
        {
            State.Stats.Clears[info.Name]++;
            var line=new StringBuilder($"clear {Tetris.ClearNames[info.Name]} {points}");
            if(back)line.Append(" b2b");
            if(combo>=1)line.Append($" combo {combo} {comboPoints}");
            if(perfect)line.Append($" perfect {perfectPoints}");
            Console.WriteLine(line.ToString());
        }
        int nextLevel=State.InitialLevel+State.Lines/10;
        if(nextLevel>level){State.Level=nextLevel;Console.WriteLine($"level {State.Level}");}
        if(oldCells.All(cell=>cell.Y>=21))GameOver("lock out");
        int cancelled=Math.Min(sent,State.Pending.Sum());
        int remaining=cancelled;
        while(remaining>0)
        {
            int used=Math.Min(remaining,State.Pending[0]);
            remaining-=used;State.Pending[0]-=used;
            if(State.Pending[0]==0)State.Pending.RemoveAt(0);
        }
        if(cancelled>0){State.Stats.Cancelled+=cancelled;Console.WriteLine($"cancel {cancelled} pending {State.Pending.Sum()}");}
        if(n==0)
        {
            int risen=0;
            while(State.Pending.Count>0&&risen<8)
            {
                int count=Math.Min(State.Pending[0],8-risen);
                State.Random=Tetris.SeedStep(State.Random);
                int hole=(int)(State.Random%10)+1;
                InsertGarbage(count,hole);
                State.Stats.Received+=count;
                risen+=count;State.Pending[0]-=count;
                if(State.Pending[0]==0)State.Pending.RemoveAt(0);
                Console.WriteLine($"rise {count} hole {hole} pending {State.Pending.Sum()}");
            }
        }
        State.UsedHold=false;
        SpawnPiece(TakeNext());
        start=State.Copy();
    }
    private List<Candidate> Candidates(int kind,Position start,List<int> prefix)
    {
        var result=new List<Candidate>();
        var seen=new HashSet<string>();
        foreach(var turns in new[]{Array.Empty<int>(),new[]{6},new[]{6,6},new[]{7}})
        {
            var p=start;
            bool valid=true;
            foreach(int turn in turns)
            {
                var next=Tetris.Move(State.Board,kind,p,turn);
                if(!next.HasValue){valid=false;break;}
                p=next.Value.Position;
            }
            if(!valid)continue;
            void Add(Position q,List<int> shifts)
            {
                var landed=Tetris.Landing(State.Board,kind,q);
                var occupied=Tetris.Cells(kind,landed).Select(cell=>(cell.Y-1)*10+cell.X-1).OrderBy(x=>x).ToArray();
                string id=string.Join(",",occupied);
                if(!seen.Add(id))return;
                var placed=Tetris.Placed(State.Board,kind,landed);
                int value=Tetris.Evaluate(placed.Item1,placed.Item2).Value;
                var ops=prefix.Concat(turns).Concat(shifts).Append(8).ToList();
                result.Add(new Candidate(kind,value,ops,id));
            }
            Add(p,new List<int>());
            foreach(int direction in new[]{0,1})
            {
                var q=p;
                var shifts=new List<int>();
                while(true)
                {
                    var next=Tetris.Move(State.Board,kind,q,direction);
                    if(!next.HasValue)break;
                    q=next.Value.Position;
                    shifts.Add(direction);
                    Add(q,shifts);
                }
            }
        }
        return result;
    }
    private List<Candidate> Ranked()
    {
        var all=Candidates(State.Kind,State.Position,new List<int>());
        int held=State.Hold??State.Queue[0];
        if(!State.UsedHold&&Tetris.Fits(State.Board,held,Tetris.Spawn(held)))all.AddRange(Candidates(held,Tetris.Spawn(held),new List<int>{10}));
        for(int i=0;i<all.Count;i++)all[i]=all[i] with {Order=i};
        return all.OrderByDescending(c=>c.Value).ThenBy(c=>c.Order).ToList();
    }
    private void Spins()
    {
        if(State.Kind!=2){Console.WriteLine("spins 0");return;}
        var found=new Dictionary<Position,int>();
        foreach(var route in Tetris.Routes(State.Board,2,State.Position).Item1)
        {
            foreach(int turn in new[]{6,7})
            {
                var next=Tetris.Move(State.Board,2,route.Position,turn);
                if(!next.HasValue||Tetris.Move(State.Board,2,next.Value.Position,4).HasValue)continue;
                int spin=Tetris.TSpin(State.Board,next.Value.Position,next.Value.Test);
                if(spin>0)
                {
                    found.TryGetValue(next.Value.Position,out int previous);
                    found[next.Value.Position]=Math.Max(previous,spin);
                }
            }
        }
        var rows=found.Select(item=>new SpinCandidate(item.Key,item.Value))
            .OrderBy(item=>item.Position.Y).ThenBy(item=>item.Position.X).ThenBy(item=>item.Position.State).ToList();
        foreach(var item in rows)
        {
            int lines=Tetris.Placed(State.Board,2,item.Position).Item2;
            int kind=Tetris.Clearance(item.Spin,lines).Name;
            Console.WriteLine($"spin {Tetris.States[item.Position.State]} {item.Position.X} {item.Position.Y} {Tetris.ClearNames[kind]}");
        }
        Console.WriteLine($"spins {rows.Count}");
    }
    public void Summary()
    {
        var s=State;var a=State.Stats;var c=a.Clears;
        string Ratio(int x,int y){int q=y==0?0:100*x/y;return $"{q/100}.{q%100:D2}";}
        Console.WriteLine($"summary game {number} score {s.Score} level {s.Level} lines {s.Lines} pieces {s.Pieces}");
        Console.WriteLine($"clears single {c[0]} double {c[1]} triple {c[2]} tetris {c[3]} perfect {a.Perfect}");
        Console.WriteLine($"tspins mini {c[4]} mini_single {c[5]} mini_double {c[6]} zero {c[7]} single {c[8]} double {c[9]} triple {c[10]}");
        Console.WriteLine("pieces "+string.Join(" ",Enumerable.Range(0,7).Select(i=>$"{Tetris.Kinds[i]} {a.Kinds[i]}")));
        Console.WriteLine($"best combo {a.Combo} chain {a.Chain} holds {a.Holds} drops {a.Drops} faults {a.Faults}");
        Console.WriteLine($"garbage sent {a.Sent} cancelled {a.Cancelled} received {a.Received}");
        Console.WriteLine($"rates app {Ratio(a.Sent,s.Pieces)} apl {Ratio(a.Sent,s.Lines)} kpp {Ratio(a.Operations,s.Pieces)}");
    }
    public void Command(string name,string[] args)
    {
        switch(name)
        {
            case "PRINT":
            {
                var current=State.Ended?new HashSet<Cell>():Tetris.Cells(State.Kind,State.Position).ToHashSet();
                var ghost=State.Ended?new HashSet<Cell>():Tetris.Cells(State.Kind,Tetris.Landing(State.Board,State.Kind,State.Position)).ToHashSet();
                for(int row=22;row>=1;row--)
                {
                    var text=new StringBuilder($"{row,2} ");
                    for(int col=1;col<=10;col++)
                    {
                        char character=(State.Board[row-1]&(1<<(col-1)))!=0?'#':current.Contains(new Cell(col,row))?'@':ghost.Contains(new Cell(col,row))?'+':'.';
                        text.Append(character);
                    }
                    Console.WriteLine(text.ToString());
                }
                break;
            }
            case "NEXT":Console.WriteLine($"hold {(State.Hold.HasValue?Tetris.Kinds[State.Hold.Value]:'-')} next {new string(State.Queue.Take(5).Select(i=>Tetris.Kinds[i]).ToArray())}");break;
            case "PREVIEW":
            {
                int count=int.Parse(args[0]);var queue=new List<int>(State.Queue);long random=State.Random;
                while(queue.Count<count){var result=Tetris.Bag(random);random=result.Item1;queue.AddRange(result.Item2);}
                Console.WriteLine("preview "+new string(queue.Take(count).Select(i=>Tetris.Kinds[i]).ToArray()));break;
            }
            case "STATUS":
            {
                Console.WriteLine($"score {State.Score} level {State.Level} lines {State.Lines} pieces {State.Pieces}");
                string piece=State.Ended?"-":$"{Tetris.Kinds[State.Kind]} {Tetris.States[State.Position.State]} {State.Position.X} {State.Position.Y}";
                Console.WriteLine($"piece {piece} streak {State.Streak} chain {State.Chain} pending {State.Pending.Sum()}");break;
            }
            case "ANALYZE":
            {
                var metrics=Tetris.Evaluate(State.Board,0);
                Console.WriteLine("heights "+string.Join(" ",metrics.Heights));
                Console.WriteLine($"holes {metrics.Holes} bumpiness {metrics.Bumpiness} value {metrics.Value}");break;
            }
            case "ROW":
            {
                int row=int.Parse(args[0]);string pattern=args[1];
                if(Tetris.Cells(State.Kind,State.Position).Any(c=>c.Y==row&&pattern[c.X-1]=='#')){Console.WriteLine("ERROR overlap");break;}
                int mask=0;for(int i=0;i<10;i++)if(pattern[i]=='#')mask|=1<<i;
                State.Board[row-1]=mask;
                Console.WriteLine("OK");break;
            }
            case "GARBAGE":
            {
                int count=int.Parse(args[0]),hole=int.Parse(args[1]);InsertGarbage(count,hole);
                for(int j=0;j<=count;j++)
                {
                    var next=State.Position with {Y=State.Position.Y+j};
                    if(Tetris.Fits(State.Board,State.Kind,next)){State.Position=next;Console.WriteLine("OK");return;}
                }
                GameOver("top out");break;
            }
            case "ATTACK":State.Pending.Add(int.Parse(args[0]));Console.WriteLine($"pending {State.Pending.Sum()}");break;
            case "TICK":for(int i=0;i<int.Parse(args[0]);i++)Tick();break;
            case "UNDO":
                if(history.Count==0){Console.WriteLine("ERROR nothing to undo");break;}
                State=history[^1].Copy();history.RemoveAt(history.Count-1);start=State.Copy();
                Console.WriteLine($"undo {State.Pieces} {Tetris.Kinds[State.Kind]}");break;
            case "SAVE":
                saves[args[0]]=new SavedGame{State=State.Copy(),History=history.Select(s=>s.Copy()).ToList(),Start=start.Copy()};
                Console.WriteLine("OK");break;
            case "LOAD":
                if(!saves.TryGetValue(args[0],out var saved)){Console.WriteLine("ERROR unknown save");break;}
                State=saved.State.Copy();history=saved.History.Select(s=>s.Copy()).ToList();start=saved.Start.Copy();
                Console.WriteLine($"load {State.Pieces} {Tetris.Kinds[State.Kind]}");break;
            case "SPINS":Spins();break;
            case "HINT":
            {
                var list=Ranked().Take(int.Parse(args[0])).ToList();
                for(int i=0;i<list.Count;i++)Console.WriteLine($"hint {i+1} {Tetris.Kinds[list[i].Kind]} {Tetris.OperationText(list[i].Operations)} value {list[i].Value}");
                break;
            }
            case "AUTO":
                for(int i=0;i<int.Parse(args[0]);i++)
                {
                    var first=Ranked()[0];
                    Console.WriteLine($"auto {Tetris.Kinds[first.Kind]} {Tetris.OperationText(first.Operations)}");
                    foreach(int op in first.Operations)Operation(op);
                }
                break;
        }
    }
}
