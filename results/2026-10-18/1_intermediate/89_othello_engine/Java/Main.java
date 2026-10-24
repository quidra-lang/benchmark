import java.io.*;
import java.util.*;
import java.util.stream.*;

public class Main {
    static final int[] WEIGHTS={100,-20,10,5,5,10,-20,100,-20,-50,-2,-2,-2,-2,-50,-20,10,-2,-1,-1,-1,-1,-2,10,5,-2,-1,-1,-1,-1,-2,5,5,-2,-1,-1,-1,-1,-2,5,10,-2,-1,-1,-1,-1,-2,10,-20,-50,-2,-2,-2,-2,-50,-20,100,-20,10,5,5,10,-20,100};
    static final Set<String> TRANSFORMS=Set.of("rot90 rot180 rot270 mirror flip diag anti".split(" "));
    static final Set<String> ZERO=Set.of("NEW DUMP SHOW SCORE LEGAL HISTORY SHEET STATS EVAL STABLE SOLVE".split(" "));
    static final Set<String> NUMERIC=Set.of("UNDO REDO HINT PV AI ANALYZE RANDOM PERFT DIVIDE".split(" "));
    static final Set<String> ACTIVE=Set.of("FLIPS MOVE PLAY HINT PV AI SOLVE AUTOPLAY RANDOM MC DIVIDE".split(" "));
    static final Set<String> EXTRA=Set.of("LOAD TRANSFORM AUTOPLAY MC FLIPS MOVE PLAY RECORD".split(" "));
    static char other(char s){return s=='B'?'W':'B';}
    static String name(int p){return ""+(char)('a'+p%8)+(p/8+1);}
    static int square(String s){return (s.charAt(1)-'1')*8+s.charAt(0)-'a';}
    static boolean inside(int r,int c){return r>=0&&r<8&&c>=0&&c<8;}
    static String initial(){char[] b=new char[64];Arrays.fill(b,'.');b[27]=b[36]='W';b[28]=b[35]='B';return new String(b);}
    static List<Integer> flips(String b,char s,int p){List<Integer> out=new ArrayList<>();if(b.charAt(p)!='.')return out;int row=p/8,col=p%8;for(int dr=-1;dr<=1;dr++)for(int dc=-1;dc<=1;dc++){if(dr==0&&dc==0)continue;int r=row+dr,c=col+dc;List<Integer> line=new ArrayList<>();while(inside(r,c)&&b.charAt(8*r+c)==other(s)){line.add(8*r+c);r+=dr;c+=dc;}if(!line.isEmpty()&&inside(r,c)&&b.charAt(8*r+c)==s)out.addAll(line);}Collections.sort(out);return out;}
    static List<Integer> legal(String b,char s){List<Integer> out=new ArrayList<>();for(int p=0;p<64;p++)if(b.charAt(p)=='.'&&!flips(b,s,p).isEmpty())out.add(p);return out;}
    static String place(String b,char s,int p){char[] a=b.toCharArray();for(int q:flips(b,s,p))a[q]=s;a[p]=s;return new String(a);}
    static int count(String b,char s){return (int)b.chars().filter(c->c==s).count();}
    static boolean terminal(String b){return legal(b,'B').isEmpty()&&legal(b,'W').isEmpty();}
    static String gameOver(String b){int x=count(b,'B'),y=count(b,'W');return "game over B "+x+" W "+y+" "+(x>y?"winner B":x<y?"winner W":"draw");}
    static int[] evaluate(String b,char s){int w=0;for(int i=0;i<64;i++)w+=b.charAt(i)==s?WEIGHTS[i]:b.charAt(i)==other(s)?-WEIGHTS[i]:0;int own=legal(b,s).size(),enemy=legal(b,other(s)).size();return new int[]{w+10*(own-enemy),w,own,enemy};}
    record Key(String board,char side,int depth){}
    static final Map<Key,Integer> SEARCH_CACHE=new HashMap<>(),PERFT_CACHE=new HashMap<>();
    static int search(String b,char s,int d){Key key=new Key(b,s,d);Integer found=SEARCH_CACHE.get(key);if(found!=null)return found;List<Integer> moves=legal(b,s);char o=other(s);int v;if(moves.isEmpty()&&legal(b,o).isEmpty())v=(d<0?1:1000)*(count(b,s)-count(b,o));else if(d==0)v=evaluate(b,s)[0];else if(moves.isEmpty())v=-search(b,o,d<0?-1:d-1);else{v=-1000000;for(int p:moves)v=Math.max(v,-search(place(b,s,p),o,d<0?-1:d-1));}if(SEARCH_CACHE.size()>300000)SEARCH_CACHE.clear();SEARCH_CACHE.put(key,v);return v;}
    record Ranking(int value,int square){}
    static List<Ranking> ranked(String b,char s,int d){List<Ranking> rows=new ArrayList<>();for(int p:legal(b,s))rows.add(new Ranking(-search(place(b,s,p),other(s),d<0?-1:d-1),p));rows.sort(Comparator.comparingInt(Ranking::value).reversed().thenComparingInt(Ranking::square));return rows;}
    record Variation(List<String> steps,String board){}
    static Variation variation(String b,char s,int d){List<String> steps=new ArrayList<>();while(d!=0&&!terminal(b)){List<Ranking> rows=ranked(b,s,d);if(rows.isEmpty())steps.add("pass");else{int p=rows.getFirst().square;steps.add(name(p));b=place(b,s,p);}s=other(s);if(d>0)d--;}return new Variation(steps,b);}
    static int perft(String b,char s,int d){if(d==0)return 1;Key key=new Key(b,s,d);Integer found=PERFT_CACHE.get(key);if(found!=null)return found;List<Integer> moves=legal(b,s);char o=other(s);int n=0;if(moves.isEmpty())n=legal(b,o).isEmpty()?1:perft(b,o,d-1);else for(int p:moves)n+=perft(place(b,s,p),o,d-1);if(PERFT_CACHE.size()>200000)PERFT_CACHE.clear();PERFT_CACHE.put(key,n);return n;}
    static int[] stable(String b){boolean[] stable=new boolean[64];int[][] axes={{0,1},{1,0},{1,1},{1,-1}};while(true){List<Integer> found=new ArrayList<>();for(int p=0;p<64;p++){if(b.charAt(p)=='.'||stable[p])continue;boolean ok=true;for(int[] axis:axes){int dr=axis[0],dc=axis[1];boolean full=true,anchor=false;for(int sign:new int[]{-1,1}){int r=p/8+dr*sign,c=p%8+dc*sign;if(!inside(r,c)||(stable[8*r+c]&&b.charAt(8*r+c)==b.charAt(p)))anchor=true;while(inside(r,c)){if(b.charAt(8*r+c)=='.')full=false;r+=dr*sign;c+=dc*sign;}}if(!full&&!anchor){ok=false;break;}}if(ok)found.add(p);}if(found.isEmpty())break;for(int p:found)stable[p]=true;}int black=0,white=0;for(int p=0;p<64;p++)if(stable[p]){if(b.charAt(p)=='B')black++;else white++;}return new int[]{black,white};}
    static int transform(int p,String op){int r=p/8,c=p%8;return switch(op){case "rot90"->8*c+7-r;case "rot180"->63-p;case "rot270"->8*(7-c)+r;case "mirror"->8*r+7-c;case "flip"->8*(7-r)+c;case "diag"->8*c+r;default->8*(7-c)+7-r;};}
    static String transformBoard(String b,String op){char[] a=new char[64];for(int p=0;p<64;p++)a[transform(p,op)]=b.charAt(p);return new String(a);}
    static class Minstd{long value;Minstd(long seed){value=seed;}long draw(){value=value*48271%2147483647;return value;}}
    static String randomGame(String b,char s,Minstd rng){while(true){List<Integer> moves=legal(b,s);if(!moves.isEmpty())b=place(b,s,moves.get((int)(rng.draw()%moves.size())));else if(legal(b,other(s)).isEmpty())return b;s=other(s);}}
    static String average(int f,int n){int v=100*f/n;return v/100+"."+(v%100<10?"0":"")+v%100;}
    record Position(String board,char side,boolean over){}
    record Move(char side,int square,int count,boolean passed,Position before,Position after){}
    static void emit(Object... xs){System.out.println(Arrays.stream(xs).map(Object::toString).collect(Collectors.joining(" ")));}
    static class Othello {
        String board=initial();char side='B';boolean over;List<Move> history=new ArrayList<>(),redo=new ArrayList<>();
        void reset(){board=initial();side='B';over=false;history.clear();redo.clear();}
        Position snapshot(){return new Position(board,side,over);}
        void restore(Position p){board=p.board;side=p.side;over=p.over;}
        String status(){return over?gameOver(board):side+" to move";}
        boolean adjust(boolean quiet){if(!legal(board,side).isEmpty())return false;if(!legal(board,other(side)).isEmpty()){if(!quiet)emit(side,"passes");side=other(side);return true;}over=true;if(!quiet)emit(gameOver(board));return false;}
        boolean move(int p,boolean quiet,Integer value){Position before=snapshot();char s=side;int k=flips(board,s,p).size();board=place(board,s,p);if(!quiet){if(value==null)emit(s,name(p),"flips",k);else emit(s,name(p),"flips",k,"value",value);}side=other(s);boolean passed=adjust(quiet);history.add(new Move(s,p,k,passed,before,snapshot()));redo.clear();return passed;}
        boolean move(int p){return move(p,false,null);}
        String reason(int p){return over?"game over":board.charAt(p)!='.'?"occupied":flips(board,side,p).isEmpty()?"no flips":"";}
        void record(String text){Othello e=new Othello();List<Integer> ps=new ArrayList<>();int passes=0;for(int i=0;i<text.length();i+=2){int p=square(text.substring(i,i+2));String why=e.reason(p);if(!why.isEmpty()){emit("ILLEGAL move",i/2+1,name(p),why);return;}ps.add(p);if(e.move(p,true,null))passes++;}restore(e.snapshot());history=e.history;redo.clear();String op=switch(name(ps.getFirst())){case "e6"->"diag";case "d3"->"anti";case "c4"->"rot180";default->"";};StringBuilder normal=new StringBuilder();for(int p:ps)normal.append(name(op.isEmpty()?p:transform(p,op)));emit("record",ps.size(),"moves",passes,"passes");emit("normal",normal);emit(status());}
        void sheet(){String b=history.isEmpty()?board:history.getFirst().before.board;String[] fields=new String[64];for(int i=0;i<64;i++)fields[i]=""+b.charAt(i);for(int i=0;i<history.size();i++)fields[history.get(i).square]=Integer.toString(i+1);emit("   a  b  c  d  e  f  g  h");for(int r=0;r<8;r++){StringBuilder line=new StringBuilder(Integer.toString(r+1));for(int c=0;c<8;c++){String x=fields[8*r+c];line.append(" ".repeat(3-x.length())).append(x);}emit(line);}}
        void stats(){int total=history.stream().mapToInt(Move::count).sum();if(history.isEmpty())emit("moves 0");else emit("moves",history.size(),"flips",total,"avg",average(total,history.size()),"passes",history.stream().filter(Move::passed).count());for(char s:new char[]{'B','W'}){List<Move> rows=history.stream().filter(r->r.side==s).toList();if(rows.isEmpty()){emit(s,"moves 0");continue;}int sum=rows.stream().mapToInt(Move::count).sum(),max=rows.stream().mapToInt(Move::count).max().orElseThrow();int square=rows.stream().filter(r->r.count==max).findFirst().orElseThrow().square;long corners=rows.stream().filter(r->r.square==0||r.square==7||r.square==56||r.square==63).count();emit(s,"moves",rows.size(),"flips",sum,"avg",average(sum,rows.size()),"max",max,name(square),"corners",corners);}}
        void autoPlay(int black,int white,long seed){Minstd rng=new Minstd(seed);StringBuilder text=new StringBuilder();int n=0,passes=0;while(!over){List<Integer> moves=legal(board,side);int p=seed!=0?moves.get((int)(rng.draw()%moves.size())):ranked(board,side,side=='B'?black:white).getFirst().square;text.append(name(p));n++;if(move(p,true,null))passes++;}emit(seed!=0?"random":"autoplay",n,"moves",passes,"passes");emit("moves",text);emit(gameOver(board));}
        void monteCarlo(int k,long seed){Minstd rng=new Minstd(seed);int best=-1,bp=-1;for(int p:legal(board,side)){int w=0,d=0,l=0;String start=place(board,side,p);for(int i=0;i<k;i++){String b=randomGame(start,other(side),rng);int diff=count(b,side)-count(b,other(side));if(diff>0)w++;else if(diff<0)l++;else d++;}emit(name(p),w,d,l);if(2*w+d>best){best=2*w+d;bp=p;}}emit("best",name(bp),best);}
        void execute(String text){List<String> words=new ArrayList<>(List.of(text.split(" ")));String cmd=words.removeFirst();List<String> a=words;String error="";
            if(!ZERO.contains(cmd)&&!NUMERIC.contains(cmd)&&!EXTRA.contains(cmd))error="unknown command";
            else if(cmd.equals("LOAD")){if(a.size()!=2||!a.get(0).matches("[.BW]{64}")||!List.of("B","W").contains(a.get(1)))error="bad board";}
            else if(List.of("MOVE","FLIPS").contains(cmd)){if(a.size()!=1)error="bad arguments";else if(!a.get(0).matches("[a-h][1-8]"))error="bad square";}
            else if(List.of("PLAY","RECORD").contains(cmd)){if(a.size()!=1)error="bad arguments";else if(a.get(0).length()>120||!a.get(0).matches("([a-h][1-8])+"))error="bad record";}
            else if(ZERO.contains(cmd)){if(!a.isEmpty())error="bad arguments";}
            else if(cmd.equals("TRANSFORM")){if(a.size()!=1||!TRANSFORMS.contains(a.get(0)))error="bad arguments";}
            else{int expected=List.of("AUTOPLAY","MC").contains(cmd)?2:1;boolean valid=a.size()==expected&&a.stream().allMatch(s->s.matches("[0-9]+"));if(valid){long n=Long.parseLong(a.get(0));valid=switch(cmd){case "AUTOPLAY"->n>=1&&n<=4&&Long.parseLong(a.get(1))>=1&&Long.parseLong(a.get(1))<=4;case "HINT","PV","AI","ANALYZE"->n>=1&&n<=4;case "PERFT","DIVIDE"->n>=1&&n<=8;case "MC"->n>=1&&n<=100&&Long.parseLong(a.get(1))>=1&&Long.parseLong(a.get(1))<=2147483646;case "RANDOM"->n>=1&&n<=2147483646;default->n>=1;};}if(!valid)error="bad arguments";}
            if(!error.isEmpty()){emit("ERROR",error);return;}if(over&&ACTIVE.contains(cmd)){emit("ERROR game over");return;}int n=!a.isEmpty()&&a.get(0).matches("[0-9]+")?Integer.parseInt(a.get(0)):0;
            switch(cmd){
                case "NEW"->{reset();emit("OK");}
                case "LOAD"->{board=a.get(0);side=a.get(1).charAt(0);over=false;history.clear();redo.clear();emit("OK");adjust(false);}
                case "DUMP"->emit("board",board,side);
                case "SHOW"->{emit("  a b c d e f g h");Set<Integer> moves=new HashSet<>(over?List.of():legal(board,side));for(int r=0;r<8;r++){StringBuilder line=new StringBuilder(Integer.toString(r+1));for(int c=0;c<8;c++)line.append(' ').append(moves.contains(8*r+c)?'*':board.charAt(8*r+c));emit(line);}emit(status());}
                case "SCORE"->emit("score B",count(board,'B'),"W",count(board,'W'),"empty",count(board,'.'));
                case "LEGAL"->{List<Integer> moves=over?List.of():legal(board,side);StringBuilder line=new StringBuilder("legal "+moves.size());for(int p:moves)line.append(' ').append(name(p));emit(line);}
                case "MOVE","FLIPS"->{int p=square(a.get(0));String why=reason(p);if(!why.isEmpty())emit("ILLEGAL",why);else if(cmd.equals("MOVE"))move(p);else{List<Integer> f=flips(board,side,p);StringBuilder line=new StringBuilder("flips "+a.get(0)+" "+f.size());for(int q:f)line.append(' ').append(name(q));emit(line);}}
                case "PLAY"->{for(int i=0;i<a.get(0).length();i+=2){int p=square(a.get(0).substring(i,i+2));String why=reason(p);if(!why.isEmpty()){emit("ILLEGAL move",i/2+1,name(p),why);break;}move(p);}}
                case "RECORD"->record(a.get(0));
                case "UNDO"->{if(n>history.size())emit("ERROR cannot undo");else{int start=history.size()-n;List<Move> removed=new ArrayList<>(history.subList(start,history.size()));restore(removed.getFirst().before);history.subList(start,history.size()).clear();redo.addAll(0,removed);emit(status());}}
                case "REDO"->{if(n>redo.size())emit("ERROR cannot redo");else{List<Move> added=new ArrayList<>(redo.subList(0,n));redo.subList(0,n).clear();history.addAll(added);restore(added.getLast().after);emit(status());}}
                case "HISTORY"->{emit("history",history.size());for(int i=0;i<history.size();i++){Move r=history.get(i);emit((i+1)+" "+r.side+" "+name(r.square)+" "+r.count+(r.passed?" pass":""));}}
                case "SHEET"->sheet();case "STATS"->stats();
                case "TRANSFORM"->{String op=a.get(0);board=transformBoard(board,op);history=history.stream().map(r->transformed(r,op)).collect(Collectors.toCollection(ArrayList::new));redo=redo.stream().map(r->transformed(r,op)).collect(Collectors.toCollection(ArrayList::new));emit("OK");}
                case "EVAL"->{int[] e=evaluate(board,side);emit("eval",e[0],"weights",e[1],"mobility",e[2],e[3]);}
                case "STABLE"->{int[] e=stable(board);emit("stable B",e[0],"W",e[1]);}
                case "HINT"->{for(Ranking row:ranked(board,side,n))emit(name(row.square),row.value);}
                case "PV"->{Variation pv=variation(board,side,n);emit("pv "+search(board,side,n)+(pv.steps.isEmpty()?"":" "+String.join(" ",pv.steps)));}
                case "AI"->{Ranking row=ranked(board,side,n).getFirst();move(row.square,false,row.value);}
                case "ANALYZE"->{Map<Character,Integer> loss=new HashMap<>(Map.of('B',0,'W',0));for(int i=0;i<history.size();i++){Move r=history.get(i);List<Ranking> rows=ranked(r.before.board,r.side,n);Ranking best=rows.getFirst();int v=rows.stream().filter(x->x.square==r.square).findFirst().orElseThrow().value;loss.merge(r.side,best.value-v,Integer::sum);emit(i+1,r.side,name(r.square),v,"best",name(best.square),best.value);}emit("loss B",loss.get('B'),"W",loss.get('W'));}
                case "SOLVE"->{if(count(board,'.')>=9)emit("ERROR too many empties");else{for(Ranking row:ranked(board,side,-1))emit(name(row.square),row.value);Variation pv=variation(board,side,-1);emit("line "+String.join(" ",pv.steps));emit("final B",count(pv.board,'B'),"W",count(pv.board,'W'));}}
                case "AUTOPLAY"->autoPlay(n,Integer.parseInt(a.get(1)),0);case "RANDOM"->autoPlay(0,0,n);case "MC"->monteCarlo(n,Long.parseLong(a.get(1)));
                case "PERFT"->emit("perft",n,perft(board,side,n));
                case "DIVIDE"->{int total=0;for(int p:legal(board,side)){int v=perft(place(board,side,p),other(side),n-1);emit(name(p),v);total+=v;}emit("total",total);}
            }
        }
        Move transformed(Move r,String op){Position before=new Position(transformBoard(r.before.board,op),r.before.side,r.before.over),after=new Position(transformBoard(r.after.board,op),r.after.side,r.after.over);return new Move(r.side,transform(r.square,op),r.count,r.passed,before,after);}
    }
    public static void main(String[] args)throws IOException{BufferedReader in=new BufferedReader(new InputStreamReader(System.in));int n=Integer.parseInt(in.readLine());Othello e=new Othello();for(int i=0;i<n;i++)e.execute(in.readLine());}
}
