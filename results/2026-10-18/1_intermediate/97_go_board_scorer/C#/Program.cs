using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

sealed record Group(char Color,int First,SortedSet<int> Stones,SortedSet<int> Liberties);
sealed record Region(int First,SortedSet<int> Points,string Owner);
sealed record Placement(string Board,int Captured,string Reason);
sealed record Snapshot(string Board,char Turn,int Black,int White,int Passes,bool Over);
sealed record Move(char Color,int Point,int Captured,Snapshot Before);
sealed class Game
{
    const string Columns="ABCDEFGHJKLMNOPQRST";
    static readonly Dictionary<int,string[]> HandicapPoints=new(){{9,"C3 G7 C7 G3 C5 G5 E3 E7 E5".Split(' ')},{13,"D4 K10 D10 K4 D7 K7 G4 G10 G7".Split(' ')},{19,"D4 Q16 D16 Q4 D10 Q10 K4 K16 K10".Split(' ')}};
    static readonly Dictionary<string,int> Arity=new(){{"BOARD",2},{"KOMI",1},{"SUPERKO",1},{"HANDICAP",1},{"PLAY",2},{"PASS",1},{"REPLAY",1},{"UNDO",0},{"SHOW",0},{"MAP",0},{"STATUS",0},{"CAPTURES",0},{"HISTORY",0},{"MOVES",0},{"GROUP",1},{"GROUPS",0},{"ATARI",0},{"LEGAL",1},{"EYES",1},{"SAFE",1},{"LADDER",1},{"DEAD",1},{"REGIONS",0},{"SCORE",1}};
    int size=19,komi=13,passes;string board=new('.',361);char turn='B';int[] captures=[0,0];bool over,superko;
    List<int> handicap=[];List<Move> history=[];List<string> positions=[new('.',361)];HashSet<int> dead=[];
    static char Other(char c)=>c=='B'?'W':'B';
    static int Index(char c)=>c=='B'?0:1;
    static string Half(int x)=>(x<0?"-":"")+(Math.Abs(x)/2)+(Math.Abs(x)%2==0?".0":".5");
    static void Emit(params object[] values)=>Console.WriteLine(string.Join(" ",values));
    static int? ParseKomi(string s){if(!Regex.IsMatch(s,@"\A-?(0|[1-9][0-9]*)(?:\.[05])?\z"))return null;bool neg=s[0]=='-';string[] parts=(neg?s[1..]:s).Split('.');if(!int.TryParse(parts[0],out int whole)||whole>100)return null;int value=whole*2+(parts.Length==2&&parts[1]=="5"?1:0);return neg&&value==0?null:neg?-value:value;}
    static int[] Adjacent(int p,int n,bool diagonal=false){int r=p/n,c=p%n;List<int>points=[];(int,int)[] steps=diagonal?[(-1,-1),(-1,1),(1,-1),(1,1)]:[(-1,0),(1,0),(0,-1),(0,1)];foreach(var(dr,dc) in steps)if(r+dr>=0&&r+dr<n&&c+dc>=0&&c+dc<n)points.Add((r+dr)*n+c+dc);return points.ToArray();}
    static SortedSet<int> Flood(string b,int n,int p,string allowed){SortedSet<int>seen=[p];Stack<int>todo=new();todo.Push(p);while(todo.Count>0)foreach(int q in Adjacent(todo.Pop(),n))if(!seen.Contains(q)&&allowed.Contains(b[q])){seen.Add(q);todo.Push(q);}return seen;}
    static Group GetGroup(string b,int n,int p){SortedSet<int>s=Flood(b,n,p,b[p].ToString()),l=[];foreach(int q in s)foreach(int t in Adjacent(q,n))if(b[t]=='.')l.Add(t);return new(b[p],s.Min,s,l);}
    static List<Group> Groups(string b,int n,char color='\0'){List<Group>result=[];HashSet<int>seen=[];for(int p=0;p<b.Length;p++)if(b[p]!='.'&&!seen.Contains(p)&&(color=='\0'||color==b[p])){Group g=GetGroup(b,n,p);seen.UnionWith(g.Stones);result.Add(g);}return result;}
    static Placement Place(string b,int n,char c,int p){if(b[p]!='.')return new(b,0,"occupied");char[] next=b.ToCharArray();next[p]=c;int captured=0;HashSet<int>seen=[];foreach(int q in Adjacent(p,n))if(next[q]==Other(c)&&!seen.Contains(q)){Group g=GetGroup(new string(next),n,q);seen.UnionWith(g.Stones);if(g.Liberties.Count==0){foreach(int t in g.Stones)next[t]='.';captured+=g.Stones.Count;}}string value=new(next);return new(value,captured,GetGroup(value,n,p).Liberties.Count==0?"suicide":"");}
    static List<Region> Regions(string b,int n){List<Region>result=[];HashSet<int>seen=[];for(int p=0;p<b.Length;p++)if(b[p]=='.'&&!seen.Contains(p)){SortedSet<int>points=Flood(b,n,p,".");seen.UnionWith(points);HashSet<char>border=[];foreach(int q in points)foreach(int t in Adjacent(q,n))if(b[t]!='.')border.Add(b[t]);result.Add(new(p,points,border.Count==1?border.First().ToString():"neutral"));}return result;}
    static List<Group> SafeGroups(string b,int n,char c){
        List<Group>own=Groups(b,n,c);List<HashSet<int>>touch=[],vital=[];HashSet<int>seen=[];
        for(int p=0;p<b.Length;p++)if(b[p]!=c&&!seen.Contains(p)){SortedSet<int>area=Flood(b,n,p,"."+Other(c));seen.UnionWith(area);int[] empty=area.Where(q=>b[q]=='.').ToArray();HashSet<int>t=[],v=[];for(int i=0;i<own.Count;i++){if(area.Any(q=>Adjacent(q,n).Any(a=>own[i].Stones.Contains(a))))t.Add(i);if(empty.All(q=>own[i].Liberties.Contains(q)))v.Add(i);}touch.Add(t);vital.Add(v);}
        HashSet<int>s=Enumerable.Range(0,own.Count).ToHashSet(),a=Enumerable.Range(0,touch.Count).ToHashSet();while(true){int count=s.Count+a.Count;s.RemoveWhere(i=>a.Count(j=>vital[j].Contains(i))<2);a.RemoveWhere(j=>!touch[j].IsSubsetOf(s));if(count==s.Count+a.Count)break;}return s.Order().Select(i=>own[i]).ToList();
    }
    static (string,int) Ladder(string b,int n,int p){
        char defender=b[p],attacker=Other(defender);Dictionary<(string,int,bool),(bool,int)>memo=new();
        (bool,int) Read(string current,int depth,bool defending){if(depth>=40)return (defending,-1);var key=(current,depth,defending);if(memo.TryGetValue(key,out var known))return known;Group g=GetGroup(current,n,p);SortedSet<int>candidates=new(g.Liberties);HashSet<int>seen=[];if(defending)foreach(int q in g.Stones)foreach(int t in Adjacent(q,n))if(current[t]==attacker&&!seen.Contains(t)){Group e=GetGroup(current,n,t);seen.UnionWith(e.Stones);if(e.Liberties.Count==1)candidates.UnionWith(e.Liberties);}foreach(int q in candidates){Placement next=Place(current,n,defending?defender:attacker,q);if(next.Reason!="")continue;bool success;if(defending){int count=GetGroup(next.Board,n,p).Liberties.Count;success=count>=3||(count==2&&!Read(next.Board,depth+1,false).Item1);}else success=!Read(next.Board,depth+1,true).Item1;if(success)return memo[key]=(true,q);}return memo[key]=(false,-1);}
        int liberties=GetGroup(b,n,p).Liberties.Count;if(liberties>=3)return ("safe",-1);var(success,move)=Read(b,0,liberties==1);return ((liberties==1?success:!success)?"escapes":"captured",move);
    }
    void Reset(int n,int k){size=n;komi=k;board=new('.',n*n);turn='B';captures=[0,0];passes=0;over=false;handicap.Clear();history.Clear();positions=[board];dead.Clear();}
    int Point(string s){if(!Regex.IsMatch(s,@"\A[A-HJ-T](?:[1-9]|1[0-9])\z"))return -1;int c=Columns.IndexOf(s[0]),r=int.Parse(s[1..]);return c<size&&r<=size?(r-1)*size+c:-1;}
    string Name(int p)=>Columns[p%size]+(p/size+1).ToString();
    string Sgf(int p)=>new([(char)(97+p%size),(char)(97+size-1-p/size)]);
    Placement Check(char c,int p){Placement r=Place(board,size,c,p);if(r.Reason==""&&positions.Count>=2&&r.Board==positions[^2])r=r with {Reason="ko"};if(r.Reason==""&&superko&&positions.Contains(r.Board))r=r with {Reason="superko"};return r;}
    int Play(char c,int p,Placement? checkedMove=null){Snapshot before=new(board,turn,captures[0],captures[1],passes,over);int captured=0;if(p<0){passes++;if(passes==2)over=true;}else{Placement r=checkedMove??Check(c,p);board=r.Board;captured=r.Captured;captures[Index(c)]+=captured;passes=0;}turn=Other(c);history.Add(new(c,p,captured,before));positions.Add(board);dead.Clear();return captured;}
    string Clean()=>new(board.Select((c,p)=>dead.Contains(p)?'.':c).ToArray());
    void Show(bool map=false){string b=map?Clean():board;char[] chars=b.ToCharArray();HashSet<int>stars=HandicapPoints[size].Where((_,i)=>size==19||i<4||i==8).Select(Point).ToHashSet();if(map)foreach(Region r in Regions(b,size))foreach(int p in r.Points)chars[p]=r.Owner=="B"?'x':r.Owner=="W"?'o':'.';for(int p=0;p<b.Length;p++)if(b[p]!='.'){char c=b[p]=='B'?'X':'O';chars[p]=dead.Contains(p)&&!map?char.ToLowerInvariant(c):c;}else if(!map)chars[p]=stars.Contains(p)?'+':'.';string header="   "+string.Join(" ",Columns[..size].ToCharArray());Emit(header);for(int r=size;r>=1;r--)Emit(r.ToString().PadLeft(2),string.Join(" ",chars[((r-1)*size)..(r*size)]),r);Emit(header);}
    void Score(string method){string b=Clean();int[] territory=[0,0],total=[0,0];foreach(Region r in Regions(b,size))if(r.Owner!="neutral")territory[Index(r.Owner[0])]+=r.Points.Count;foreach(char c in "BW"){int i=Index(c);List<object>fields=[c];if(method=="AREA"){int stones=b.Count(t=>t==c);total[i]=2*(stones+territory[i])+(c=='W'?komi:0);fields.AddRange(["stones",stones,"territory",territory[i]]);}else{int prisoners=captures[i]+dead.Count(p=>board[p]==Other(c));total[i]=2*(territory[i]+prisoners)+(c=='W'?komi:0);fields.AddRange(["territory",territory[i],"prisoners",prisoners]);}if(c=='W')fields.AddRange(["komi",Half(komi)]);fields.AddRange(["total",Half(total[i])]);Emit(fields.ToArray());}int d=total[0]-total[1];Emit("result",d>0?"B+"+Half(d):d<0?"W+"+Half(-d):"Draw");}
    public void Execute(string line){
        string[] words=line.Split(' ');string c=words[0];string[] a=words[1..];if(!Arity.TryGetValue(c,out int count)){Emit("ERROR unknown command");return;}if(a.Length!=count){Emit("ERROR bad arguments");return;}
        bool valid=c switch {"BOARD"=>(a[0] is "9" or "13" or "19") && ParseKomi(a[1])!=null,"KOMI"=>ParseKomi(a[0])!=null,"SUPERKO"=>a[0] is "ON" or "OFF","HANDICAP"=>Regex.IsMatch(a[0],@"\A[2-9]\z"),"PLAY" or "PASS" or "LEGAL" or "EYES" or "SAFE"=>a[0] is "B" or "W","SCORE"=>a[0] is "AREA" or "TERRITORY",_=>true};if(!valid){Emit("ERROR bad arguments");return;}
        int p=-1;if(c is "PLAY" or "GROUP" or "LADDER" or "DEAD"){p=Point(a[c=="PLAY"?1:0]);if(p<0){Emit("ERROR bad point");return;}}
        List<(char,int)>records=[];if(c=="REPLAY"){if(!Regex.IsMatch(a[0],@"\A(?:;[BW]\[[a-z]{0,2}\])+\z")){Emit("ERROR bad sequence");return;}foreach(Match m in Regex.Matches(a[0],@";([BW])\[([a-z]*)\]")){string text=m.Groups[2].Value;if(text!=""&&(text.Length!=2||text.Any(ch=>ch-'a'>=size))){Emit("ERROR bad sequence");return;}records.Add((m.Groups[1].Value[0],text==""?-1:(size-1-(text[1]-'a'))*size+text[0]-'a'));}}
        if((c is "PLAY" or "PASS" or "REPLAY") && over){Emit("ERROR game over");return;}
        switch(c){
        case "BOARD":Reset(int.Parse(a[0]),ParseKomi(a[1])!.Value);Emit("board",size,"komi",Half(komi));break;
        case "KOMI":komi=ParseKomi(a[0])!.Value;Emit("komi",Half(komi));break;
        case "SUPERKO":superko=a[0]=="ON";Emit("superko",superko?"on":"off");break;
        case "HANDICAP":if(history.Count>0||board.Any(t=>t is 'B' or 'W')){Emit("ERROR handicap not allowed");break;}int k=int.Parse(a[0]);int[] indices=k==5?[0,1,2,3,8]:k==7?[0,1,2,3,4,5,8]:Enumerable.Range(0,k).ToArray();handicap=indices.Select(i=>Point(HandicapPoints[size][i])).ToList();char[] b=board.ToCharArray();foreach(int q in handicap)b[q]='B';board=new(b);turn='W';positions=[board];dead.Clear();Emit(new object[]{"handicap",k}.Concat(handicap.Select(q=>(object)Name(q))).ToArray());break;
        case "PLAY":char color=a[0][0];Placement next=Check(color,p);string reason=color!=turn?"turn":next.Reason;if(reason!="")Emit("ILLEGAL",color,a[1],reason);else{int captured=Play(color,p,next);if(captured==0)Emit(color,a[1]);else Emit(color,a[1],"captures",captured);}break;
        case "PASS":if(a[0][0]!=turn)Emit("ILLEGAL",a[0],"pass","turn");else{Play(a[0][0],-1);Emit(a[0],"pass");if(over)Emit("game over");}break;
        case "REPLAY":int played=0;List<object>stop=[];foreach(var(col,q) in records){Placement? r=q<0?null:Check(col,q);string why=over?"game over":col!=turn?"turn":r?.Reason??"";if(why!=""){stop=["stopped",col,q<0?"pass":Name(q),why];break;}Play(col,q,r);played++;}Emit(new object[]{"replay",played,"moves"}.Concat(stop).ToArray());if(over)Emit("game over");break;
        case "UNDO":if(history.Count==0){Emit("ERROR nothing to undo");break;}Move move=history[^1];history.RemoveAt(history.Count-1);Snapshot state=move.Before;board=state.Board;turn=state.Turn;captures=[state.Black,state.White];passes=state.Passes;over=state.Over;positions.RemoveAt(positions.Count-1);dead.Clear();Emit("undo",move.Color,move.Point<0?"pass":Name(move.Point));break;
        case "SHOW":Show();break;case "MAP":Show(true);break;
        case "STATUS":Emit("size",size,"komi",Half(komi),"handicap",handicap.Count,"superko",superko?"on":"off");if(over)Emit("moves",history.Count,"game over");else Emit("moves",history.Count,"next",turn,"passes",passes);break;
        case "CAPTURES":Emit("captures B",captures[0],"W",captures[1]);break;
        case "HISTORY":Emit("history",history.Count);for(int i=0;i<history.Count;i++){Move m=history[i];List<object>row=[i+1,m.Color,m.Point<0?"pass":Name(m.Point)];if(m.Captured>0)row.AddRange(["captures",m.Captured]);Emit(row.ToArray());}break;
        case "MOVES":StringBuilder record=new($"(;GM[1]FF[4]SZ[{size}]KM[{Half(komi)}]");if(handicap.Count>0){record.Append($"HA[{handicap.Count}]AB");foreach(int q in handicap)record.Append('[').Append(Sgf(q)).Append(']');}foreach(Move m in history)record.Append(';').Append(m.Color).Append('[').Append(m.Point<0?"":Sgf(m.Point)).Append(']');Emit(record.Append(')').ToString());break;
        case "GROUP":case "DEAD":case "LADDER":if(board[p]=='.'){Emit("ERROR no stone");break;}Group g=GetGroup(board,size,p);if(c=="GROUP"){Emit("group",g.Color,Name(g.First),"size",g.Stones.Count,"liberties",g.Liberties.Count);Emit(new object[]{"stones"}.Concat(g.Stones.Select(q=>(object)Name(q))).ToArray());Emit(new object[]{"liberties"}.Concat(g.Liberties.Select(q=>(object)Name(q))).ToArray());}else if(c=="DEAD"){bool alive=dead.Contains(p);if(alive)dead.ExceptWith(g.Stones);else dead.UnionWith(g.Stones);Emit(alive?"alive":"dead",g.Color,Name(g.First),"size",g.Stones.Count);}else{var(status,q)=Ladder(board,size,p);if(q<0)Emit("ladder",a[0],status);else Emit("ladder",a[0],status,Name(q));}break;
        case "GROUPS":List<Group>gs=Groups(board,size);Emit("groups",gs.Count);foreach(Group gr in gs){List<object>row=[gr.Color,Name(gr.First),"size",gr.Stones.Count,"liberties",gr.Liberties.Count];if(dead.Contains(gr.First))row.Add("dead");Emit(row.ToArray());}break;
        case "ATARI":List<Group>atari=Groups(board,size).Where(gr=>gr.Liberties.Count==1).ToList();if(atari.Count==0)Emit("atari none");foreach(Group gr in atari)Emit("atari",gr.Color,Name(gr.First),"size",gr.Stones.Count,"at",Name(gr.Liberties.Min));break;
        case "LEGAL":List<(string,string)>rejected=[];int legal=0;for(int q=0;q<board.Length;q++)if(board[q]=='.'){string why=Check(a[0][0],q).Reason;if(why=="")legal++;else rejected.Add((Name(q),why));}Emit("legal",a[0],legal);foreach(var(q,why) in rejected)Emit(q,why);break;
        case "EYES":List<(string,string)>eyes=[];for(int q=0;q<board.Length;q++)if(board[q]=='.'){int[] ns=Adjacent(q,size);if(ns.All(t=>board[t]==a[0][0])){int enemies=Adjacent(q,size,true).Count(t=>board[t]==Other(a[0][0]));eyes.Add((Name(q),enemies<=(ns.Length==4?1:0)?"real":"false"));}}Emit("eyes",a[0],eyes.Count);foreach(var(q,kind) in eyes)Emit(q,kind);break;
        case "SAFE":List<Group>safe=SafeGroups(board,size,a[0][0]);Emit("safe",a[0],safe.Count);foreach(Group gr in safe)Emit(Name(gr.First),"size",gr.Stones.Count);break;
        case "REGIONS":List<Region>regions=Regions(Clean(),size);Emit("regions",regions.Count);foreach(Region r in regions)Emit(Name(r.First),"size",r.Points.Count,r.Owner);break;
        case "SCORE":Score(a[0]);break;
        }
    }
}
static class Program
{
    static void Main(){Game game=new();int count=int.Parse(Console.ReadLine()!);while(count-->0)game.Execute(Console.ReadLine()!);}
}
