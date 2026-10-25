import java.io.*;
import java.util.*;
import java.util.regex.*;
public class Main {
    static final String COLUMNS="ABCDEFGHJKLMNOPQRST";
    static final Map<Integer,List<String>>HANDICAP=Map.of(9,List.of("C3","G7","C7","G3","C5","G5","E3","E7","E5"),13,List.of("D4","K10","D10","K4","D7","K7","G4","G10","G7"),19,List.of("D4","Q16","D16","Q4","D10","Q10","K4","K16","K10"));
    static final Map<String,Integer>ARITY=Map.ofEntries(Map.entry("BOARD",2),Map.entry("KOMI",1),Map.entry("SUPERKO",1),Map.entry("HANDICAP",1),Map.entry("PLAY",2),Map.entry("PASS",1),Map.entry("REPLAY",1),Map.entry("UNDO",0),Map.entry("SHOW",0),Map.entry("MAP",0),Map.entry("STATUS",0),Map.entry("CAPTURES",0),Map.entry("HISTORY",0),Map.entry("MOVES",0),Map.entry("GROUP",1),Map.entry("GROUPS",0),Map.entry("ATARI",0),Map.entry("LEGAL",1),Map.entry("EYES",1),Map.entry("SAFE",1),Map.entry("LADDER",1),Map.entry("DEAD",1),Map.entry("REGIONS",0),Map.entry("SCORE",1));
    static char other(char c){
        return c=='B'?'W':'B';
    }
    static int index(char c){
        return c=='B'?0:1;
    }
    static String half(int x){
        return(x<0?"-":"")+Integer.toString(Math.abs(x)/2)+(Math.abs(x)%2==0?".0":".5");
    }
    static void emit(Object...values){
        StringJoiner s=new StringJoiner(" ");
        for(Object v:values)s.add(v.toString());
        System.out.println(s);
    }
    static Integer komi(String s){
        if(!s.matches("-?(0|[1-9][0-9]*)(?:\\.[05])?"))return null;
        boolean negative=s.startsWith("-");
        String[]a=(negative?s.substring(1):s).split("\\.");
        if(a[0].length()>3)return null;
        int whole=Integer.parseInt(a[0]);
        if(whole>100)return null;
        int x=2*whole+(a.length==2&&a[1].equals("5")?1:0);
        return negative&&x==0?null:negative?-x:x;
    }
    static List<Integer>adjacent(int p,int n){
        return adjacent(p,n,false);
    }
    static List<Integer>adjacent(int p,int n,boolean diagonal){
        int r=p/n,c=p%n;
        int[][]steps=diagonal?new int[][]{
            {
                -1,-1
            },{
                -1,1
            },{
                1,-1
            },{
                1,1
            }
        }:new int[][]{
            {
                -1,0
            },{
                1,0
            },{
                0,-1
            },{
                0,1
            }
        };
        List<Integer>a=new ArrayList<>();
        for(int[]d:steps)if(r+d[0]>=0&&r+d[0]<n&&c+d[1]>=0&&c+d[1]<n)a.add((r+d[0])*n+c+d[1]);
        return a;
    }
    static SortedSet<Integer>flood(String b,int n,int p,String allowed){
        SortedSet<Integer>seen=new TreeSet<>(Set.of(p));
        Deque<Integer>todo=new ArrayDeque<>();
        todo.push(p);
        while(!todo.isEmpty())for(int q:adjacent(todo.pop(),n))if(!seen.contains(q)&&allowed.indexOf(b.charAt(q))>=0){
            seen.add(q);
            todo.push(q);
        }
        return seen;
    }
    record Group(char color,int first,SortedSet<Integer>stones,SortedSet<Integer>liberties){
    }
    static Group group(String b,int n,int p){
        SortedSet<Integer>s=flood(b,n,p,""+b.charAt(p)),l=new TreeSet<>();
        for(int q:s)for(int t:adjacent(q,n))if(b.charAt(t)=='.')l.add(t);
        return new Group(b.charAt(p),s.first(),s,l);
    }
    static List<Group>groups(String b,int n){
        return groups(b,n,'\0');
    }
    static List<Group>groups(String b,int n,char color){
        List<Group>out=new ArrayList<>();
        Set<Integer>seen=new HashSet<>();
        for(int p=0;p<b.length();p++)if(b.charAt(p)!='.'&&!seen.contains(p)&&(color=='\0'||b.charAt(p)==color)){
            Group g=group(b,n,p);
            seen.addAll(g.stones);
            out.add(g);
        }
        return out;
    }
    record Placement(String board,int captured,String reason){
    }
    static Placement placement(String b,int n,char c,int p){
        if(b.charAt(p)!='.')return new Placement(b,0,"occupied");
        char[]next=b.toCharArray();
        next[p]=c;
        int captured=0;
        Set<Integer>seen=new HashSet<>();
        for(int q:adjacent(p,n))if(next[q]==other(c)&&!seen.contains(q)){
            Group g=group(new String(next),n,q);
            seen.addAll(g.stones);
            if(g.liberties.isEmpty()){
                for(int t:g.stones)next[t]='.';
                captured+=g.stones.size();
            }
        }
        String value=new String(next);
        return new Placement(value,captured,group(value,n,p).liberties.isEmpty()?"suicide":"");
    }
    record Region(int first,SortedSet<Integer>points,String owner){
    }
    static List<Region>regions(String b,int n){
        Set<Integer>seen=new HashSet<>();
        List<Region>out=new ArrayList<>();
        for(int p=0;p<b.length();p++)if(b.charAt(p)=='.'&&!seen.contains(p)){
            SortedSet<Integer>points=flood(b,n,p,".");
            seen.addAll(points);
            Set<Character>border=new HashSet<>();
            for(int q:points)for(int t:adjacent(q,n))if(b.charAt(t)!='.')border.add(b.charAt(t));
            out.add(new Region(p,points,border.size()==1?""+border.iterator().next():"neutral"));
        }
        return out;
    }
    static List<Group>safeGroups(String b,int n,char c){
        List<Group>own=groups(b,n,c);
        List<Set<Integer>>touch=new ArrayList<>(),vital=new ArrayList<>();
        Set<Integer>seen=new HashSet<>();
        for(int p=0;p<b.length();p++)if(b.charAt(p)!=c&&!seen.contains(p)){
            SortedSet<Integer>area=flood(b,n,p,"."+other(c));
            seen.addAll(area);
            List<Integer>empty=area.stream().filter(q->b.charAt(q)=='.').toList();
            Set<Integer>t=new HashSet<>(),v=new HashSet<>();
            for(int i=0;i<own.size();i++){
                Group g=own.get(i);
                boolean touches=false;
                for(int q:area)for(int a:adjacent(q,n))if(g.stones.contains(a))touches=true;
                if(touches)t.add(i);
                if(g.liberties.containsAll(empty))v.add(i);
            }
            touch.add(t);
            vital.add(v);
        }
        Set<Integer>s=new TreeSet<>(),t=new HashSet<>();
        for(int i=0;i<own.size();i++)s.add(i);
        for(int j=0;j<touch.size();j++)t.add(j);
        while(true){
            int before=s.size()+t.size();
            s.removeIf(i->t.stream().filter(j->vital.get(j).contains(i)).count()<2);
            t.removeIf(j->!s.containsAll(touch.get(j)));
            if(before==s.size()+t.size())break;
        }
        return s.stream().map(own::get).toList();
    }
    record Reading(boolean success,int move){
    }
    record ReadKey(String board,int depth,boolean defending){
    }
    record LadderResult(String status,int move){
    }
    static final class Ladder {
        final int n,p;
        final char defender,attacker;
        final Map<ReadKey,Reading>memo=new HashMap<>();
        Ladder(String b,int n,int p){
            this.n=n;
            this.p=p;
            defender=b.charAt(p);
            attacker=other(defender);
        }
        Reading read(String b,int depth,boolean defending){
            if(depth>=40)return new Reading(defending,-1);
            ReadKey key=new ReadKey(b,depth,defending);
            if(memo.containsKey(key))return memo.get(key);
            Group g=group(b,n,p);
            SortedSet<Integer>candidates=new TreeSet<>(g.liberties);
            Set<Integer>seen=new HashSet<>();
            if(defending)for(int q:g.stones)for(int t:adjacent(q,n))if(b.charAt(t)==attacker&&!seen.contains(t)){
                Group e=group(b,n,t);
                seen.addAll(e.stones);
                if(e.liberties.size()==1)candidates.addAll(e.liberties);
            }
            for(int q:candidates){
                Placement next=placement(b,n,defending?defender:attacker,q);
                if(!next.reason.isEmpty())continue;
                boolean success;
                if(defending){
                    int count=group(next.board,n,p).liberties.size();
                    success=count>=3||(count==2&&!read(next.board,depth+1,false).success);
                }else success=!read(next.board,depth+1,true).success;
                if(success){
                    Reading r=new Reading(true,q);
                    memo.put(key,r);
                    return r;
                }
            }
            Reading r=new Reading(false,-1);
            memo.put(key,r);
            return r;
        }
        LadderResult result(String b){
            int count=group(b,n,p).liberties.size();
            if(count>=3)return new LadderResult("safe",-1);
            Reading r=read(b,0,count==1);
            return new LadderResult((count==1?r.success:!r.success)?"escapes":"captured",r.move);
        }
    }
    record Snapshot(String board,char turn,int black,int white,int passes,boolean over){
    }
    record Move(char color,int point,int captured,Snapshot before){
    }
    static final class Game {
        int n=19,komi2=13,passes;
        String board=".".repeat(361);
        char turn='B';
        int[]captures={
            0,0
        };
        boolean over,superko;
        List<Integer>handicap=new ArrayList<>();
        List<Move>history=new ArrayList<>();
        List<String>positions=new ArrayList<>(List.of(board));
        Set<Integer>dead=new HashSet<>();
        void reset(int size,int k){
            n=size;
            komi2=k;
            board=".".repeat(n*n);
            turn='B';
            captures=new int[2];
            passes=0;
            over=false;
            handicap.clear();
            history.clear();
            positions=new ArrayList<>(List.of(board));
            dead.clear();
        }
        int point(String s){
            if(!s.matches("[A-HJ-T](?:[1-9]|1[0-9])"))return -1;
            int c=COLUMNS.indexOf(s.charAt(0)),r=Integer.parseInt(s.substring(1));
            return c<n&&r<=n?(r-1)*n+c:-1;
        }
        String name(int p){
            return ""+COLUMNS.charAt(p%n)+(p/n+1);
        }
        String sgf(int p){
            return ""+(char)(97+p%n)+(char)(97+n-1-p/n);
        }
        Placement check(char c,int p){
            Placement r=placement(board,n,c,p);
            String reason=r.reason;
            if(reason.isEmpty()&&positions.size()>=2&&r.board.equals(positions.get(positions.size()-2)))reason="ko";
            if(reason.isEmpty()&&superko&&positions.contains(r.board))reason="superko";
            return new Placement(r.board,r.captured,reason);
        }
        int move(char c,int p,Placement checked){
            Snapshot before=new Snapshot(board,turn,captures[0],captures[1],passes,over);
            int captured=0;
            if(p<0){
                passes++;
                if(passes==2)over=true;
            }else{
                Placement r=checked==null?check(c,p):checked;
                board=r.board;
                captured=r.captured;
                captures[index(c)]+=captured;
                passes=0;
            }
            turn=other(c);
            history.add(new Move(c,p,captured,before));
            positions.add(board);
            dead.clear();
            return captured;
        }
        String clean(){
            char[]b=board.toCharArray();
            for(int p:dead)b[p]='.';
            return new String(b);
        }
        void show(boolean map){
            String b=map?clean():board;
            char[]chars=b.toCharArray();
            Set<Integer>stars=new HashSet<>();
            for(int i=0;i<9;i++)if(n==19||i<4||i==8)stars.add(point(HANDICAP.get(n).get(i)));
            if(map)for(Region r:regions(b,n))for(int p:r.points)chars[p]=r.owner.equals("B")?'x':r.owner.equals("W")?'o':'.';
            for(int p=0;p<b.length();p++)if(b.charAt(p)!='.'){
                char c=b.charAt(p)=='B'?'X':'O';
                chars[p]=!map&&dead.contains(p)?Character.toLowerCase(c):c;
            }else if(!map)chars[p]=stars.contains(p)?'+':'.';
            StringJoiner h=new StringJoiner(" ","   ","");
            for(int c=0;c<n;c++)h.add(""+COLUMNS.charAt(c));
            emit(h);
            for(int r=n;r>=1;r--){
                StringJoiner row=new StringJoiner(" ");
                for(int c=0;c<n;c++)row.add(""+chars[(r-1)*n+c]);
                emit(String.format(Locale.ROOT,"%2d",r),row,r);
            }
            emit(h);
        }
        void score(String method){
            String b=clean();
            int[]territory=new int[2],total=new int[2];
            for(Region r:regions(b,n))if(!r.owner.equals("neutral"))territory[index(r.owner.charAt(0))]+=r.points.size();
            for(char c:new char[]{
                'B','W'
            }){
                int i=index(c);
                List<Object>fields=new ArrayList<>(List.of(c));
                if(method.equals("AREA")){
                    int stones=(int)b.chars().filter(s->s==c).count();
                    total[i]=2*(stones+territory[i])+(c=='W'?komi2:0);
                    fields.addAll(List.of("stones",stones,"territory",territory[i]));
                }else{
                    int prisoners=captures[i];
                    for(int p:dead)if(board.charAt(p)==other(c))prisoners++;
                    total[i]=2*(territory[i]+prisoners)+(c=='W'?komi2:0);
                    fields.addAll(List.of("territory",territory[i],"prisoners",prisoners));
                }
                if(c=='W')fields.addAll(List.of("komi",half(komi2)));
                fields.addAll(List.of("total",half(total[i])));
                emit(fields.toArray());
            }
            int d=total[0]-total[1];
            emit("result",d>0?"B+"+half(d):d<0?"W+"+half(-d):"Draw");
        }
        void execute(String line){
            String[]words=line.split(" ");
            String c=words[0];
            String[]a=Arrays.copyOfRange(words,1,words.length);
            if(!ARITY.containsKey(c)){
                emit("ERROR unknown command");
                return;
            }
            if(a.length!=ARITY.get(c)){
                emit("ERROR bad arguments");
                return;
            }
            boolean valid=switch(c){
                case "BOARD"->Set.of("9","13","19").contains(a[0])&&komi(a[1])!=null;
                case "KOMI"->komi(a[0])!=null;
                case "SUPERKO"->Set.of("ON","OFF").contains(a[0]);
                case "HANDICAP"->a[0].matches("[2-9]");
                case "PLAY","PASS","LEGAL","EYES","SAFE"->Set.of("B","W").contains(a[0]);
                case "SCORE"->Set.of("AREA","TERRITORY").contains(a[0]);
                default->true;
            };
            if(!valid){
                emit("ERROR bad arguments");
                return;
            }
            int p=-1;
            if(Set.of("PLAY","GROUP","LADDER","DEAD").contains(c)){
                p=point(a[c.equals("PLAY")?1:0]);
                if(p<0){
                    emit("ERROR bad point");
                    return;
                }
            }
            List<Map.Entry<Character,Integer>>records=new ArrayList<>();
            if(c.equals("REPLAY")){
                if(!a[0].matches("(?:;[BW]\\[[a-z]{0,2}\\])+")){
                    emit("ERROR bad sequence");
                    return;
                }
                Matcher m=Pattern.compile(";([BW])\\[([a-z]*)\\]").matcher(a[0]);
                while(m.find()){
                    String text=m.group(2);
                    if(!text.isEmpty()&&(text.length()!=2||text.chars().anyMatch(ch->ch-'a'>=n))){
                        emit("ERROR bad sequence");
                        return;
                    }
                    records.add(Map.entry(m.group(1).charAt(0),text.isEmpty()?-1:(n-1-(text.charAt(1)-'a'))*n+text.charAt(0)-'a'));
                }
            }
            if(Set.of("PLAY","PASS","REPLAY").contains(c)&&over){
                emit("ERROR game over");
                return;
            }
            switch(c){
                case "BOARD"->{
                    reset(Integer.parseInt(a[0]),komi(a[1]));
                    emit("board",n,"komi",half(komi2));
                }
                case "KOMI"->{
                    komi2=komi(a[0]);
                    emit("komi",half(komi2));
                }
                case "SUPERKO"->{
                    superko=a[0].equals("ON");
                    emit("superko",superko?"on":"off");
                }
                case "HANDICAP"->{
                    if(!history.isEmpty()||board.chars().anyMatch(t->t!='.')){
                        emit("ERROR handicap not allowed");
                        return;
                    }
                    int k=Integer.parseInt(a[0]);
                    List<Integer>ix=k==5?List.of(0,1,2,3,8):k==7?List.of(0,1,2,3,4,5,8):java.util.stream.IntStream.range(0,k).boxed().toList();
                    handicap=new ArrayList<>();
                    char[]b=board.toCharArray();
                    List<Object>fields=new ArrayList<>(List.of("handicap",k));
                    for(int i:ix){
                        int q=point(HANDICAP.get(n).get(i));
                        handicap.add(q);
                        b[q]='B';
                        fields.add(name(q));
                    }
                    board=new String(b);
                    turn='W';
                    positions=new ArrayList<>(List.of(board));
                    dead.clear();
                    emit(fields.toArray());
                }
                case "PLAY"->{
                    char color=a[0].charAt(0);
                    Placement r=check(color,p);
                    String reason=color!=turn?"turn":r.reason;
                    if(!reason.isEmpty())emit("ILLEGAL",color,a[1],reason);
                    else{
                        int count=move(color,p,r);
                        if(count==0)emit(color,a[1]);
                        else emit(color,a[1],"captures",count);
                    }
                }
                case "PASS"->{
                    char color=a[0].charAt(0);
                    if(color!=turn)emit("ILLEGAL",color,"pass turn");
                    else{
                        move(color,-1,null);
                        emit(color,"pass");
                        if(over)emit("game over");
                    }
                }
                case "REPLAY"->{
                    int played=0;
                    List<Object>stop=new ArrayList<>();
                    for(var record:records){
                        char color=record.getKey();
                        int q=record.getValue();
                        Placement next=q<0?null:check(color,q);
                        String reason=over?"game over":color!=turn?"turn":next==null?"":next.reason;
                        if(!reason.isEmpty()){
                            stop=List.of("stopped",color,q<0?"pass":name(q),reason);
                            break;
                        }
                        move(color,q,next);
                        played++;
                    }
                    List<Object>fields=new ArrayList<>(List.of("replay",played,"moves"));
                    fields.addAll(stop);
                    emit(fields.toArray());
                    if(over)emit("game over");
                }
                case "UNDO"->{
                    if(history.isEmpty()){
                        emit("ERROR nothing to undo");
                        return;
                    }
                    Move m=history.removeLast();
                    Snapshot s=m.before;
                    board=s.board;
                    turn=s.turn;
                    captures=new int[]{
                        s.black,s.white
                    };
                    passes=s.passes;
                    over=s.over;
                    positions.removeLast();
                    dead.clear();
                    emit("undo",m.color,m.point<0?"pass":name(m.point));
                }
                case "SHOW"->show(false);
                case "MAP"->show(true);
                case "STATUS"->{
                    emit("size",n,"komi",half(komi2),"handicap",handicap.size(),"superko",superko?"on":"off");
                    if(over)emit("moves",history.size(),"game over");
                    else emit("moves",history.size(),"next",turn,"passes",passes);
                }
                case "CAPTURES"->emit("captures B",captures[0],"W",captures[1]);
                case "HISTORY"->{
                    emit("history",history.size());
                    for(int i=0;i<history.size();i++){
                        Move m=history.get(i);
                        List<Object>fields=new ArrayList<>(List.of(i+1,m.color,m.point<0?"pass":name(m.point)));
                        if(m.captured>0)fields.addAll(List.of("captures",m.captured));
                        emit(fields.toArray());
                    }
                }
                case "MOVES"->{
                    StringBuilder s=new StringBuilder("(;GM[1]FF[4]SZ["+n+"]KM["+half(komi2)+"]");
                    if(!handicap.isEmpty()){
                        s.append("HA[").append(handicap.size()).append("]AB");
                        for(int q:handicap)s.append('[').append(sgf(q)).append(']');
                    }
                    for(Move m:history)s.append(';').append(m.color).append('[').append(m.point<0?"":sgf(m.point)).append(']');
                    emit(s.append(')'));
                }
                case "GROUP","DEAD","LADDER"->{
                    if(board.charAt(p)=='.'){
                        emit("ERROR no stone");
                        return;
                    }
                    Group g=group(board,n,p);
                    if(c.equals("GROUP")){
                        emit("group",g.color,name(g.first),"size",g.stones.size(),"liberties",g.liberties.size());
                        List<Object>stones=new ArrayList<>(List.of("stones")),liberties=new ArrayList<>(List.of("liberties"));
                        for(int q:g.stones)stones.add(name(q));
                        for(int q:g.liberties)liberties.add(name(q));
                        emit(stones.toArray());
                        emit(liberties.toArray());
                    }else if(c.equals("DEAD")){
                        boolean alive=dead.contains(p);
                        if(alive)dead.removeAll(g.stones);
                        else dead.addAll(g.stones);
                        emit(alive?"alive":"dead",g.color,name(g.first),"size",g.stones.size());
                    }else{
                        LadderResult r=new Ladder(board,n,p).result(board);
                        if(r.move<0)emit("ladder",a[0],r.status);
                        else emit("ladder",a[0],r.status,name(r.move));
                    }
                }
                case "GROUPS"->{
                    List<Group>gs=groups(board,n);
                    emit("groups",gs.size());
                    for(Group g:gs){
                        List<Object>row=new ArrayList<>(List.of(g.color,name(g.first),"size",g.stones.size(),"liberties",g.liberties.size()));
                        if(dead.contains(g.first))row.add("dead");
                        emit(row.toArray());
                    }
                }
                case "ATARI"->{
                    List<Group>gs=groups(board,n).stream().filter(g->g.liberties.size()==1).toList();
                    if(gs.isEmpty())emit("atari none");
                    for(Group g:gs)emit("atari",g.color,name(g.first),"size",g.stones.size(),"at",name(g.liberties.first()));
                }
                case "LEGAL"->{
                    List<List<Object>>rejected=new ArrayList<>();
                    int count=0;
                    for(int q=0;q<board.length();q++)if(board.charAt(q)=='.'){
                        String reason=check(a[0].charAt(0),q).reason;
                        if(reason.isEmpty())count++;
                        else rejected.add(List.of(name(q),reason));
                    }
                    emit("legal",a[0],count);
                    for(List<Object>row:rejected)emit(row.toArray());
                }
                case "EYES"->{
                    List<List<Object>>found=new ArrayList<>();
                    for(int q=0;q<board.length();q++)if(board.charAt(q)=='.'){
                        List<Integer>ns=adjacent(q,n);
                        if(ns.stream().allMatch(t->board.charAt(t)==a[0].charAt(0))){
                            long enemies=adjacent(q,n,true).stream().filter(t->board.charAt(t)==other(a[0].charAt(0))).count();
                            found.add(List.of(name(q),enemies<=(ns.size()==4?1:0)?"real":"false"));
                        }
                    }
                    emit("eyes",a[0],found.size());
                    for(List<Object>row:found)emit(row.toArray());
                }
                case "SAFE"->{
                    List<Group>gs=safeGroups(board,n,a[0].charAt(0));
                    emit("safe",a[0],gs.size());
                    for(Group g:gs)emit(name(g.first),"size",g.stones.size());
                }
                case "REGIONS"->{
                    List<Region>rs=regions(clean(),n);
                    emit("regions",rs.size());
                    for(Region r:rs)emit(name(r.first),"size",r.points.size(),r.owner);
                }
                case "SCORE"->score(a[0]);
            }
        }
    }
    public static void main(String[]args)throws IOException{
        BufferedReader in=new BufferedReader(new InputStreamReader(System.in));
        int count=Integer.parseInt(in.readLine());
        Game game=new Game();
        while(count-->0)game.execute(in.readLine());
    }
}
