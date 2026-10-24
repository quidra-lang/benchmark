import java.io.*;
import java.util.*;
import java.util.regex.*;

public class Main {
    static final String FILES="abcdefgh",RANKS="12345678",INITIAL="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
    static final int[][] ROOK={{0,1},{0,-1},{-1,0},{1,0}},BISHOP={{1,1},{-1,1},{1,-1},{-1,-1}},KING={{0,1},{0,-1},{-1,0},{1,0},{1,1},{-1,1},{1,-1},{-1,-1}},KNIGHT={{1,2},{2,1},{2,-1},{1,-2},{-1,-2},{-2,-1},{-2,1},{-1,2}};
    record Rule(int king,int rook,int target,int rookTarget,int[] path) {}
    record Move(int source,int target,char promotion) {}
    record Record(String san,String uci,char captured) {}
    static final Map<Character,Rule> RULES=Map.of('K',new Rule(4,7,6,5,new int[]{5,6}),'Q',new Rule(4,0,2,3,new int[]{1,2,3}),'k',new Rule(60,63,62,61,new int[]{61,62}),'q',new Rule(60,56,58,59,new int[]{57,58,59}));
    static final PrintWriter out=new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
    static void emit(String s){out.println(s);}
    static void fail(String s){throw new IllegalArgumentException(s);}
    static char color(char p){return Character.isUpperCase(p)?'w':'b';}
    static char opposite(char c){return c=='w'?'b':'w';}
    static char colored(char p,char c){return c=='w'?p:Character.toLowerCase(p);}
    static int step(char c){return c=='w'?8:-8;}
    static int square(String s){return s.matches("[a-h][1-8]")?s.charAt(0)-'a'+8*(s.charAt(1)-'1'):-1;}
    static String name(int s){return ""+FILES.charAt(s%8)+RANKS.charAt(s/8);}
    static int number(String s,int lo,int hi){if(!s.matches("0|[1-9][0-9]{0,8}"))return -1;int n=Integer.parseInt(s);return n>=lo&&n<=hi?n:-1;}
    static int shift(int s,int dx,int dy){int x=s%8+dx,y=s/8+dy;return x>=0&&x<8&&y>=0&&y<8?8*y+x:-1;}
    static List<Integer> targets(char[]b,int s){
        char p=b[s],k=Character.toUpperCase(p);List<Integer>a=new ArrayList<>();
        if(k=='P'||k=='N'||k=='K'){
            int[][]dirs=k=='P'?new int[][]{{-1,color(p)=='w'?1:-1},{1,color(p)=='w'?1:-1}}:k=='N'?KNIGHT:KING;
            for(int[]d:dirs){int t=shift(s,d[0],d[1]);if(t>=0)a.add(t);}return a;
        }
        int[][]dirs=k=='Q'?KING:k=='R'?ROOK:BISHOP;
        for(int[]d:dirs)for(int t=shift(s,d[0],d[1]);t>=0;t=shift(t,d[0],d[1])){a.add(t);if(b[t]!='.')break;}
        return a;
    }
    static List<Integer> attackers(char[]b,int t,char c){List<Integer>a=new ArrayList<>();for(int s=0;s<64;s++)if(b[s]!='.'&&color(b[s])==c&&targets(b,s).contains(t))a.add(s);return a;}
    static class Position {
        final char[]board;final char side;final String rights;final int ep,half,full;List<Move>cached;
        Position(char[]b,char side,String rights,int ep,int half,int full){this.board=b;this.side=side;this.rights=rights;this.ep=ep;this.half=half;this.full=full;}
        int king(char c){for(int s=0;s<64;s++)if(board[s]==colored('K',c))return s;throw new IllegalStateException();}
        boolean check(char c){return !attackers(board,king(c),opposite(c)).isEmpty();}
        boolean check(){return check(side);}
        boolean castle(Move m){return Character.toUpperCase(board[m.source])=='K'&&Math.abs(m.target-m.source)==2;}
        boolean enpassant(Move m){return Character.toUpperCase(board[m.source])=='P'&&m.source%8!=m.target%8&&board[m.target]=='.';}
        boolean capture(Move m){return board[m.target]!='.'||enpassant(m);}
        char captured(Move m){return board[m.target]!='.'?Character.toLowerCase(board[m.target]):enpassant(m)?'p':'-';}
        Position play(Move m){
            char[]b=board.clone();char piece=b[m.source],kind=Character.toUpperCase(piece);
            if(enpassant(m))b[m.target-step(side)]='.';
            if(castle(m)){Rule r=RULES.get(colored(m.target>m.source?'K':'Q',side));b[r.rookTarget]=b[r.rook];b[r.rook]='.';}
            b[m.target]=m.promotion!=0?colored(m.promotion,side):piece;b[m.source]='.';StringBuilder rights=new StringBuilder();
            for(char r:this.rights.toCharArray())if((kind!='K'||color(r)!=side)&&RULES.get(r).rook!=m.source&&RULES.get(r).rook!=m.target)rights.append(r);
            return new Position(b,opposite(side),rights.toString(),kind=='P'&&Math.abs(m.target-m.source)==16?(m.source+m.target)/2:-1,kind=='P'||capture(m)?0:half+1,full+(side=='b'?1:0));
        }
        List<Move> pseudo(){
            List<Move>result=new ArrayList<>();
            for(int s=0;s<64;s++){
                char p=board[s];if(p=='.'||color(p)!=side)continue;boolean pawn=Character.toUpperCase(p)=='P';List<Integer>a=new ArrayList<>();
                if(pawn){int d=step(side);if(board[s+d]=='.'){a.add(s+d);if(s/8==(side=='w'?1:6)&&board[s+2*d]=='.')a.add(s+2*d);}for(int t:targets(board,s))if((board[t]!='.'&&color(board[t])!=side)||t==ep)a.add(t);}
                else for(int t:targets(board,s))if(board[t]=='.'||color(board[t])!=side)a.add(t);
                for(int t:a)if(pawn&&t/8==(side=='w'?7:0)){for(char promotion:"QRBN".toCharArray())result.add(new Move(s,t,promotion));}else result.add(new Move(s,t,(char)0));
            }return result;
        }
        Move castlingMove(boolean kingside){Rule r=RULES.get(colored(kingside?'K':'Q',side));return new Move(r.king,r.target,(char)0);}
        String castlingProblem(boolean kingside){
            char right=colored(kingside?'K':'Q',side);Rule r=RULES.get(right);
            if(rights.indexOf(right)<0)return "no castling right";
            for(int s:r.path)if(board[s]!='.')return "path blocked";
            if(check())return "in check";
            if(!attackers(board,r.rookTarget,opposite(side)).isEmpty())return "through check";
            if(play(castlingMove(kingside)).check(side))return "into check";
            return "";
        }
        List<Move> legal(){if(cached!=null)return cached;List<Move>a=new ArrayList<>();for(Move m:pseudo())if(!play(m).check(side))a.add(m);for(boolean k:new boolean[]{true,false})if(castlingProblem(k).isEmpty())a.add(castlingMove(k));return cached=a;}
        String mark(Move m){Position q=play(m);return q.check()?(q.legal().isEmpty()?"#":"+"):"";}
        String disambiguation(Move m){
            boolean any=false,file=true,rank=true;
            for(Move x:legal())if(!castle(x)&&x.target==m.target&&x.source!=m.source&&board[x.source]==board[m.source]){any=true;file&=x.source%8!=m.source%8;rank&=x.source/8!=m.source/8;}
            return !any?"":file?""+FILES.charAt(m.source%8):rank?""+RANKS.charAt(m.source/8):name(m.source);
        }
        String san(Move m){
            char kind=Character.toUpperCase(board[m.source]);String text;
            if(castle(m))text=m.target>m.source?"O-O":"O-O-O";
            else if(kind=='P')text=(capture(m)?FILES.charAt(m.source%8)+"x":"")+name(m.target)+(m.promotion!=0?"="+m.promotion:"");
            else text=kind+disambiguation(m)+(capture(m)?"x":"")+name(m.target);
            return text+mark(m);
        }
        String key(){int target=-1;if(ep>=0)for(Move m:legal())if(enpassant(m)){target=ep;break;}return new String(board)+" "+side+" "+rights+" "+target;}
        String state(){return check()?(legal().isEmpty()?"checkmate":"check"):(legal().isEmpty()?"stalemate":"normal");}
        boolean insufficient(){List<Integer>a=new ArrayList<>();for(int s=0;s<64;s++)if(board[s]!='.'&&Character.toUpperCase(board[s])!='K'){if("PRQ".indexOf(Character.toUpperCase(board[s]))>=0)return false;a.add(s);}if(a.size()<=1)return true;int shade=(a.get(0)%8+a.get(0)/8)%2;for(int s:a)if(Character.toUpperCase(board[s])!='B'||(s%8+s/8)%2!=shade)return false;return true;}
        List<int[]> pins(){
            List<int[]>a=new ArrayList<>();int k=king(side);
            for(int[]d:KING){int first=-1;for(int t=shift(k,d[0],d[1]);t>=0;t=shift(t,d[0],d[1])){char p=board[t];if(p=='.')continue;if(first<0){if(color(p)!=side)break;first=t;}else{if(color(p)!=side&&(Character.toUpperCase(p)=='Q'||Character.toUpperCase(p)==(d[0]==0||d[1]==0?'R':'B')))a.add(new int[]{first,t});break;}}}
            a.sort(Comparator.comparingInt(x->x[0]));return a;
        }
        String fen(){
            List<String>rows=new ArrayList<>();for(int r=7;r>=0;r--){StringBuilder row=new StringBuilder();int empty=0;for(int f=0;f<8;f++){char p=board[8*r+f];if(p=='.')empty++;else{if(empty>0)row.append(empty);empty=0;row.append(p);}}if(empty>0)row.append(empty);rows.add(row.toString());}
            return String.join("/",rows)+" "+side+" "+(rights.isEmpty()?"-":rights)+" "+(ep<0?"-":name(ep))+" "+half+" "+full;
        }
    }
    static Position parseFen(String[]a){
        if(a.length!=6)fail("fields");String[]ranks=a[0].split("/",-1);if(ranks.length!=8)fail("placement");char[]b=new char[64];Arrays.fill(b,'.');
        for(int i=0;i<8;i++){int f=0;boolean digit=false;for(char c:ranks[i].toCharArray())if(c>='1'&&c<='8'){if(digit)fail("placement");f+=c-'0';digit=true;}else{if("KQRBNPkqrbnp".indexOf(c)<0||f>=8)fail("placement");b[(7-i)*8+f++]=c;digit=false;}if(f!=8)fail("placement");}
        int white=0,black=0;for(char c:b){if(c=='K')white++;if(c=='k')black++;}if(white!=1||black!=1)fail("kings");
        for(int i=0;i<8;i++)if(Character.toUpperCase(b[i])=='P'||Character.toUpperCase(b[56+i])=='P')fail("pawns");
        if(!a[1].equals("w")&&!a[1].equals("b"))fail("side");char side=a[1].charAt(0);
        if(!a[2].equals("-")&&(a[2].isEmpty()||!a[2].matches("K?Q?k?q?")))fail("castling");String rights=a[2].equals("-")?"":a[2];
        for(char r:rights.toCharArray()){Rule rule=RULES.get(r);if(b[rule.king]!=colored('K',color(r))||b[rule.rook]!=colored('R',color(r)))fail("castling");}
        int ep=-1;if(!a[3].equals("-")){ep=square(a[3]);int d=step(side);if(ep<0||ep/8!=(side=='w'?5:2)||b[ep]!='.'||b[ep+d]!='.'||b[ep-d]!=colored('P',opposite(side)))fail("en passant");}
        int half=number(a[4],0,999),full=number(a[5],1,999);if(half<0||full<0||(ep>=0&&half!=0))fail("clocks");Position p=new Position(b,side,rights,ep,half,full);if(p.check(opposite(side)))fail("check");return p;
    }
    static Move readSan(Position pos,String text){
        String mark=text.endsWith("+")||text.endsWith("#")?text.substring(text.length()-1):"",body=mark.isEmpty()?text:text.substring(0,text.length()-1);
        boolean castling=body.equals("O-O")||body.equals("O-O-O"),capture=false;char promotion=0,kind='P';String file="",rank="";int target=-1;
        if(!castling){
            if(body.length()>=2&&body.charAt(body.length()-2)=='='){promotion=body.charAt(body.length()-1);if("QRBN".indexOf(promotion)<0)fail("syntax");body=body.substring(0,body.length()-2);}
            if(body.length()<2)fail("syntax");target=square(body.substring(body.length()-2));if(target<0)fail("syntax");body=body.substring(0,body.length()-2);capture=body.endsWith("x");if(capture)body=body.substring(0,body.length()-1);
            if(!body.isEmpty()&&"KQRBN".indexOf(body.charAt(0))>=0){kind=body.charAt(0);Matcher h=Pattern.compile("([a-h]?)([1-8]?)").matcher(body.substring(1));if(promotion!=0||!h.matches())fail("syntax");file=h.group(1);rank=h.group(2);}
            else{if(!body.matches(capture?"[a-h]":""))fail("syntax");file=body;}
        }
        List<Move>legal=pos.legal();if(legal.isEmpty())fail("game over");Move move;
        if(castling){boolean k=body.equals("O-O");String problem=pos.castlingProblem(k);if(!problem.isEmpty())fail(problem);move=pos.castlingMove(k);}
        else{
            List<Move>candidates=new ArrayList<>();for(Move m:legal)if(matches(pos,m,kind,target,file,rank,capture))candidates.add(m);
            if(candidates.isEmpty()){for(Move m:pos.pseudo())if(matches(pos,m,kind,target,file,rank,capture))fail("leaves king in check");fail("no such move");}
            move=candidates.get(0);for(Move m:candidates)if(m.source!=move.source)fail("ambiguous");
            if(pos.capture(move)!=capture)fail("capture mark");if(move.promotion!=0&&promotion==0)fail("missing promotion");if(promotion!=0&&move.promotion==0)fail("invalid promotion");if(kind!='P'&&!(file+rank).equals(pos.disambiguation(move)))fail("disambiguation");move=new Move(move.source,move.target,promotion);
        }
        if(!pos.mark(move).equals(mark))fail("check mark");return move;
    }
    static boolean matches(Position p,Move m,char kind,int target,String file,String rank,boolean capture){return Character.toUpperCase(p.board[m.source])==kind&&m.target==target&&!p.castle(m)&&(file.isEmpty()||FILES.charAt(m.source%8)==file.charAt(0))&&(rank.isEmpty()||RANKS.charAt(m.source/8)==rank.charAt(0))&&(kind!='P'||(m.source%8!=m.target%8)==capture);}
    static Move readUci(Position p,String text){
        if(!text.matches("[a-h][1-8][a-h][1-8][qrbn]?"))fail("syntax");int s=square(text.substring(0,2)),t=square(text.substring(2,4));char promotion=text.length()==5?Character.toUpperCase(text.charAt(4)):0;List<Move>legal=p.legal();
        if(legal.isEmpty())fail("game over");if(p.board[s]=='.'||color(p.board[s])!=p.side)fail("no piece");for(Move m:legal)if(m.source==s&&m.target==t){if(m.promotion!=0&&promotion==0)fail("missing promotion");if(promotion!=0&&m.promotion==0)fail("invalid promotion");return new Move(s,t,promotion);}
        for(Move m:p.pseudo())if(m.source==s&&m.target==t)fail("leaves king in check");fail("no such move");return null;
    }
    static long perft(Position p,int d,long[]stats){
        if(d==0)return 1;long total=0;for(Move m:p.legal()){Position q=p.play(m);total+=perft(q,d-1,stats);if(d==1&&stats!=null){stats[0]++;if(p.capture(m))stats[1]++;if(p.enpassant(m))stats[2]++;if(p.castle(m))stats[3]++;if(m.promotion!=0)stats[4]++;if(q.check()){stats[5]++;if(q.legal().isEmpty())stats[6]++;}}}return total;
    }
    static class Game {
        final List<Position>positions=new ArrayList<>();final List<Record>records=new ArrayList<>();final boolean loaded;
        Game(){this(parseFen(INITIAL.split(" ")),false);}
        Game(Position start,boolean loaded){positions.add(start);this.loaded=loaded;}
        Position current(){return positions.get(positions.size()-1);}
        void play(Move m){Position p=current();records.add(new Record(p.san(m),name(m.source)+name(m.target)+(m.promotion!=0?""+Character.toLowerCase(m.promotion):""),p.captured(m)));positions.add(p.play(m));}
        int repetition(){String key=current().key();int n=0;for(Position p:positions)if(p.key().equals(key))n++;return n;}
        List<String>draws(){List<String>a=new ArrayList<>();if(current().half>=100)a.add("fifty");if(repetition()>=3)a.add("threefold");if(current().insufficient())a.add("insufficient");return a;}
        String result(){String s=current().state();if(s.equals("checkmate"))return current().side=='b'?"1-0":"0-1";return s.equals("stalemate")||!draws().isEmpty()?"1/2-1/2":"*";}
    }
    static Game game=new Game();
    static void execute(String line){
        String[]w=line.split(" "),a=Arrays.copyOfRange(w,1,w.length);String cmd=w[0];
        if(!Set.of("NEW","LOAD","FEN","BOARD","MOVE","UCI","LEGAL","STATUS","UNDO","PERFT","DIVIDE","ATTACKS","PINS","HISTORY","PGN").contains(cmd)){emit("ERROR unknown command");return;}
        boolean bad=Set.of("NEW","FEN","BOARD","STATUS","PINS","HISTORY","PGN").contains(cmd)&&a.length!=0;
        if(cmd.equals("MOVE")||cmd.equals("UCI"))bad=a.length==0;if(cmd.equals("LEGAL"))bad=a.length>1||(a.length==1&&square(a[0])<0);if(cmd.equals("ATTACKS"))bad=a.length!=1||(a.length==1&&square(a[0])<0);int n=-1;if(Set.of("UNDO","PERFT","DIVIDE").contains(cmd)){n=a.length==1?number(a[0],1,cmd.equals("UNDO")?9999:3):-1;bad=n<0;}if(bad){emit("ERROR bad arguments");return;}
        Position p=game.current();
        switch(cmd){
        case "NEW" -> {game=new Game();emit("OK");}
        case "LOAD" -> {try{Position q=parseFen(a);game=new Game(q,true);emit("OK");}catch(IllegalArgumentException e){emit("ERROR bad fen ("+e.getMessage()+")");}}
        case "FEN" -> emit(p.fen());
        case "BOARD" -> {for(int r=7;r>=0;r--){StringBuilder row=new StringBuilder(""+(r+1));for(int f=0;f<8;f++)row.append(' ').append(p.board[r*8+f]);emit(row.toString());}emit("  a b c d e f g h");}
        case "MOVE","UCI" -> {List<String>played=new ArrayList<>();String failure="";for(int i=0;i<a.length;i++){try{Move m=cmd.equals("MOVE")?readSan(game.current(),a[i]):readUci(game.current(),a[i]);game.play(m);played.add(game.records.get(game.records.size()-1).san);}catch(IllegalArgumentException e){failure="ILLEGAL move "+(i+1)+": "+a[i]+" ("+e.getMessage()+")";break;}}if(cmd.equals("UCI")&&!played.isEmpty())emit("san "+String.join(" ",played));if(!failure.isEmpty())emit(failure);else if(cmd.equals("MOVE"))emit("OK");}
        case "LEGAL" -> {List<String>list=new ArrayList<>();for(Move m:p.legal())if(a.length==0||m.source==square(a[0]))list.add(p.san(m));Collections.sort(list);emit("legal "+list.size()+(list.isEmpty()?"":" "+String.join(" ",list)));}
        case "STATUS" -> {List<String>marks=game.draws();emit("status "+(p.side=='w'?"white":"black")+" "+p.state()+" rep "+game.repetition()+(marks.isEmpty()?"":" "+String.join(" ",marks)));}
        case "UNDO" -> {if(n>game.records.size())emit("ERROR cannot undo");else{game.records.subList(game.records.size()-n,game.records.size()).clear();game.positions.subList(game.positions.size()-n,game.positions.size()).clear();emit("OK");}}
        case "PERFT" -> {long[]stats=new long[7];perft(p,n,stats);StringBuilder row=new StringBuilder("perft "+n);String[]fields={"nodes","captures","ep","castles","promotions","checks","mates"};for(int i=0;i<7;i++)row.append(' ').append(fields[i]).append(' ').append(stats[i]);emit(row.toString());}
        case "DIVIDE" -> {TreeMap<String,Long>rows=new TreeMap<>();long total=0;for(Move m:p.legal()){long v=perft(p.play(m),n-1,null);rows.put(p.san(m),v);total+=v;}for(Map.Entry<String,Long>r:rows.entrySet())emit(r.getKey()+" "+r.getValue());emit("total "+total);}
        case "ATTACKS" -> {StringBuilder row=new StringBuilder("attacks "+a[0]);for(char c:new char[]{'w','b'}){List<Integer>found=attackers(p.board,square(a[0]),c);row.append(' ').append(c=='w'?"white":"black").append(' ').append(found.size());for(int s:found)row.append(' ').append(name(s));}emit(row.toString());}
        case "PINS" -> {List<int[]>pins=p.pins();StringBuilder row=new StringBuilder("pins "+pins.size());for(int[]pair:pins)row.append(' ').append(name(pair[0])).append('-').append(name(pair[1]));emit(row.toString());}
        case "HISTORY" -> {emit("history "+game.records.size());for(int i=0;i<game.records.size();i++){Record r=game.records.get(i);emit((i+1)+" "+r.uci+" "+r.san+" "+r.captured);}}
        case "PGN" -> {String result=game.result();emit("[Result \""+result+"\"]");if(game.loaded){emit("[SetUp \"1\"]");emit("[FEN \""+game.positions.get(0).fen()+"\"]");}List<String>text=new ArrayList<>();for(int i=0;i<game.records.size();i++){Position q=game.positions.get(i);if(q.side=='w')text.add(q.full+".");else if(i==0)text.add(q.full+"...");text.add(game.records.get(i).san);}text.add(result);emit(String.join(" ",text));}
        }
    }
    public static void main(String[]args)throws IOException{BufferedReader in=new BufferedReader(new InputStreamReader(System.in));int n=Integer.parseInt(in.readLine());for(int i=0;i<n;i++)execute(in.readLine());out.flush();}
}
