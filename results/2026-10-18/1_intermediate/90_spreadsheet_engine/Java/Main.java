import java.io.*;
import java.util.*;
import java.util.function.UnaryOperator;
import java.util.regex.*;

public class Main {
    record Expr(char kind, int n, int row, int flags, String text, Expr a, Expr b, List<Expr> args) {}
    static Expr node(char k, int n, String s, Expr a, Expr b, List<Expr> args) { return new Expr(k,n,0,0,s,a,b,args); }
    static Expr leaf(char k, int n, String s) { return node(k,n,s,null,null,List.of()); }
    static Expr num(int n) { return leaf('N',n,""); }
    static Expr text(String s) { return leaf('S',0,s); }
    static Expr error(String s) { return leaf('E',0,s); }
    static Expr ref(int c,int r,int f) { return new Expr('R',c,r,f,"",null,null,List.of()); }
    static final Expr INVALID=leaf('X',0,"");
    static int id(Expr r) { return r.row*26+r.n; }
    static String label(int i) { return ""+(char)('A'+i%26)+(i/26+1); }
    static boolean inside(Expr r) { return r.n>=0&&r.n<26&&r.row>=0&&r.row<99; }
    static Expr range(Expr a,Expr b) {
        int c=a.n,d=b.n,r=a.row,t=b.row,ac=a.flags&1,bc=b.flags&1,ar=a.flags&2,br=b.flags&2;
        if(c>d){int z=c;c=d;d=z;z=ac;ac=bc;bc=z;}if(r>t){int z=r;r=t;t=z;z=ar;ar=br;br=z;}
        return node('G',0,"",ref(c,r,ac|ar),ref(d,t,bc|br),List.of());
    }
    static Expr address(String s) {
        if(!s.matches("[A-Z][1-9][0-9]?"))throw new IllegalArgumentException("bad address");
        return ref(s.charAt(0)-'A',Integer.parseInt(s.substring(1))-1,0);
    }
    static Expr area(String s) { int p=s.indexOf(':');if(p<0){Expr a=address(s);return range(a,a);}Expr a=address(s.substring(0,p)),b=address(s.substring(p+1));return range(a,b); }
    static List<Integer> cells(Expr g) { List<Integer> out=new ArrayList<>();for(int r=g.a.row;r<=g.b.row;r++)for(int c=g.a.n;c<=g.b.n;c++)out.add(r*26+c);return out; }
    static boolean contains(Expr g,Expr r) { return r.n>=g.a.n&&r.n<=g.b.n&&r.row>=g.a.row&&r.row<=g.b.row; }
    static final List<Set<String>> LEVELS=List.of(Set.of("=","<>","<","<=",">",">="),Set.of("&"),Set.of("+","-"),Set.of("*","/"));
    static int precedence(String op) { for(int i=0;i<4;i++)if(LEVELS.get(i).contains(op))return i;return -1; }
    record Token(Expr value,int position) {}
    static class Parser {
        final List<Token> tokens=new ArrayList<>();int at;
        void syntax(int p) { throw new IllegalArgumentException("syntax error at "+p); }
        Parser(String s) {
            for(int i=1;i<s.length();){int p=i+1;char ch=s.charAt(i);if(ch==' '){i++;continue;}Expr x;
                if(ch>='0'&&ch<='9'){int j=i;while(j<s.length()&&Character.isDigit(s.charAt(j)))j++;if(j-i>=10)syntax(p);x=num(Integer.parseInt(s.substring(i,j)));i=j;}
                else if(ch=='"'){int j=s.indexOf('"',i+1);if(j<0)syntax(p);x=text(s.substring(i+1,j));i=j+1;}
                else if(Character.isLetter(ch)||ch=='$'){
                    int j=i;while(j<s.length()&&(Character.isLetterOrDigit(s.charAt(j))||s.charAt(j)=='$'))j++;
                    String w=s.substring(i,j).toUpperCase(Locale.ROOT);i=j;Matcher m=Pattern.compile("(\\$?)([A-Z])(\\$?)([1-9][0-9]?)").matcher(w);
                    if(m.matches())x=ref(m.group(2).charAt(0)-'A',Integer.parseInt(m.group(4))-1,(m.group(1).isEmpty()?0:1)|(m.group(3).isEmpty()?0:2));
                    else if(w.matches("[A-Z][A-Z0-9]*"))x=leaf(s.substring(j).stripLeading().startsWith("(")?'C':'W',0,w);
                    else {syntax(p);return;}
                }else{
                    String op=s.substring(i,Math.min(i+2,s.length()));if(!Set.of("<>","<=",">=").contains(op))op=""+ch;
                    if("+-*/&(),:=<>".indexOf(ch)<0)syntax(p);x=leaf('T',0,op);i+=op.length();
                }tokens.add(new Token(x,p));
            }tokens.add(new Token(leaf('Z',0,""),s.length()+1));
        }
        boolean take(String op){Expr x=tokens.get(at).value;if(x.kind=='T'&&x.text.equals(op)){at++;return true;}return false;}
        void expect(String op){if(!take(op))syntax(tokens.get(at).position);}
        Expr expression(int level){
            if(level==4)return primary();Expr a=expression(level+1);
            while(tokens.get(at).value.kind=='T'&&LEVELS.get(level).contains(tokens.get(at).value.text)){String op=tokens.get(at++).value.text;a=node('B',0,op,a,expression(level+1),List.of());}return a;
        }
        Expr primary(){
            if(take("-"))return node('U',0,"",primary(),null,List.of());Token t=tokens.get(at++);Expr x=t.value;
            if(x.kind=='N'||x.kind=='S'||x.kind=='W')return x;
            if(x.kind=='R'){if(!take(":"))return x;if(tokens.get(at).value.kind!='R')syntax(tokens.get(at).position);return range(x,tokens.get(at++).value);}
            if(x.kind=='C'){expect("(");List<Expr> args=new ArrayList<>();if(!take(")")){args.add(expression(0));while(take(","))args.add(expression(0));expect(")");}return node('F',0,x.text,null,null,List.copyOf(args));}
            if(x.kind=='T'&&x.text.equals("(")){Expr a=expression(0);expect(")");return a;}syntax(t.position);return null;
        }
        Expr parse(){Expr x=expression(0);if(tokens.get(at).value.kind!='Z')syntax(tokens.get(at).position);return x;}
    }
    static String canonical(Expr x){
        switch(x.kind){
        case 'N':return ""+x.n;case 'S':return "\""+x.text+"\"";case 'W':return x.text;case 'X':return "#REF!";
        case 'R':return (x.flags%2!=0?"$":"")+(char)('A'+x.n)+((x.flags&2)!=0?"$":"")+(x.row+1);
        case 'G':return canonical(x.a)+":"+canonical(x.b);
        case 'F':{StringJoiner j=new StringJoiner(",",x.text+"(",")");for(Expr a:x.args)j.add(canonical(a));return j.toString();}
        case 'U':return "-"+(x.a.kind=='B'?"("+canonical(x.a)+")":canonical(x.a));
        case 'B':{String a=canonical(x.a),b=canonical(x.b);if(x.a.kind=='B'&&precedence(x.a.text)<precedence(x.text))a="("+a+")";if(x.b.kind=='B'&&precedence(x.b.text)<=precedence(x.text))b="("+b+")";return a+x.text+b;}
        default:throw new IllegalStateException();
        }
    }
    static String display(Expr x){return x==null?"":x.kind=='N'?""+x.n:x.text;}
    static String notation(Expr x){return x==null?"(empty)":x.kind=='='?"="+canonical(x.a):x.kind=='S'?"\""+x.text+"\"":display(x);}
    static Expr number(Expr x){return x==null?num(0):x.kind=='S'||x.kind=='G'?error("#VALUE!"):x;}
    static Expr string(Expr x){return x==null?text(""):x.kind=='N'?text(""+x.n):x.kind=='G'?error("#VALUE!"):x;}
    static Expr rewrite(Expr x,UnaryOperator<Expr> f){
        if(x==null)return null;if(x.kind=='R'||x.kind=='G')return f.apply(x);
        Expr a=rewrite(x.a,f),b=rewrite(x.b,f);List<Expr> args=new ArrayList<>();boolean changed=a!=x.a||b!=x.b;
        for(Expr old:x.args){Expr v=rewrite(old,f);changed|=v!=old;args.add(v);}return changed?node(x.kind,x.n,x.text,a,b,List.copyOf(args)):x;
    }
    static void dependencies(Expr x,Set<Integer> out){if(x==null)return;if(x.kind=='R')out.add(id(x));else if(x.kind=='G')out.addAll(cells(x));else{dependencies(x.a,out);dependencies(x.b,out);for(Expr a:x.args)dependencies(a,out);}}
    record History(String name,Expr[] contents) {}
    static class Sheet {
        Expr[] contents=new Expr[2574],values=new Expr[2574];List<Set<Integer>> deps=new ArrayList<>();List<History> history=new ArrayList<>();
        Sheet(){for(int i=0;i<2574;i++)deps.add(new TreeSet<>());}
        Expr evaluate(Expr x){
            if(x.kind=='N'||x.kind=='S'||x.kind=='G')return x;if(x.kind=='R')return values[id(x)];if(x.kind=='W')return error("#NAME?");if(x.kind=='X')return error("#REF!");
            if(x.kind=='U'){Expr a=number(evaluate(x.a));return a.kind=='E'?a:num(-a.n);}
            if(x.kind=='B'){
                Expr a=evaluate(x.a),b=evaluate(x.b);if(a!=null&&a.kind=='E')return a;if(b!=null&&b.kind=='E')return b;String op=x.text;
                if(precedence(op)==0){
                    if((a!=null&&a.kind=='G')||(b!=null&&b.kind=='G'))return error("#VALUE!");boolean strings=(a!=null&&a.kind=='S')||(b!=null&&b.kind=='S');if(a==null)a=strings?text(""):num(0);if(b==null)b=strings?text(""):num(0);
                    int c=a.kind!=b.kind?(a.kind=='N'?-1:1):a.kind=='N'?Integer.compare(a.n,b.n):a.text.compareTo(b.text);
                    boolean yes=switch(op){case "="->c==0;case "<>"->c!=0;case "<"->c<0;case "<="->c<=0;case ">"->c>0;default->c>=0;};return num(yes?1:0);
                }
                a=op.equals("&")?string(a):number(a);b=op.equals("&")?string(b):number(b);if(a.kind=='E')return a;if(b.kind=='E')return b;
                return switch(op){case "&"->text(a.text+b.text);case "+"->num(a.n+b.n);case "-"->num(a.n-b.n);case "*"->num(a.n*b.n);default->b.n==0?error("#DIV/0!"):num(a.n/b.n);};
            }
            String name=x.text;List<Expr> args=x.args;
            if(Set.of("SUM","MIN","MAX","COUNT","AVERAGE","AND","OR","CONCAT").contains(name)){
                if(args.isEmpty())return error("#VALUE!");List<Expr> items=new ArrayList<>();List<Integer> ns=new ArrayList<>();for(Expr arg:args){Expr v=evaluate(arg);if(v!=null&&v.kind=='G'){for(int i:cells(v))items.add(values[i]);}else items.add(v);}
                for(Expr v:items)if(v!=null&&v.kind=='N')ns.add(v.n);if(name.equals("COUNT"))return num(ns.size());for(Expr v:items)if(v!=null&&v.kind=='E')return v;
                if(name.equals("CONCAT")){StringBuilder s=new StringBuilder();for(Expr v:items)s.append(string(v).text);return text(s.toString());}int sum=0;for(int n:ns)sum+=n;
                if(name.equals("SUM"))return num(sum);if(name.equals("MIN"))return num(ns.isEmpty()?0:Collections.min(ns));if(name.equals("MAX"))return num(ns.isEmpty()?0:Collections.max(ns));
                if(ns.isEmpty())return error(name.equals("AVERAGE")?"#DIV/0!":"#VALUE!");if(name.equals("AVERAGE"))return num(sum/ns.size());boolean result=name.equals("AND");for(int n:ns)result=name.equals("AND")?result&&n!=0:result||n!=0;return num(result?1:0);
            }
            if(name.equals("IF")){if(args.size()!=2&&args.size()!=3)return error("#VALUE!");Expr c=number(evaluate(args.get(0)));if(c.kind=='E')return c;return c.n!=0?evaluate(args.get(1)):args.size()==3?evaluate(args.get(2)):num(0);}
            if(!Set.of("ABS","NOT","LEN").contains(name))return error("#NAME?");if(args.size()!=1)return error("#VALUE!");Expr v=evaluate(args.get(0));v=name.equals("LEN")?string(v):number(v);return v.kind=='E'?v:num(name.equals("LEN")?v.text.length():name.equals("ABS")?Math.abs(v.n):v.n==0?1:0);
        }
        void recalculate(){
            for(int i=0;i<2574;i++){deps.get(i).clear();if(contents[i]!=null&&contents[i].kind=='='){dependencies(contents[i].a,deps.get(i));values[i]=null;}else values[i]=contents[i];}
            class Graph {
                int serial;int[] index=new int[2574],low=new int[2574];boolean[] on=new boolean[2574],cyclic=new boolean[2574],done=new boolean[2574];Deque<Integer> stack=new ArrayDeque<>();
                Graph(){Arrays.fill(index,-1);}
                void visit(int i){
                    index[i]=low[i]=serial++;stack.push(i);on[i]=true;for(int j:deps.get(i))if(contents[j]!=null&&contents[j].kind=='='){if(index[j]<0){visit(j);low[i]=Math.min(low[i],low[j]);}else if(on[j])low[i]=Math.min(low[i],index[j]);}
                    if(low[i]==index[i]){List<Integer> part=new ArrayList<>();int j;do{j=stack.pop();on[j]=false;part.add(j);}while(j!=i);if(part.size()>1||deps.get(i).contains(i))for(int k:part)cyclic[k]=true;}
                }
                void calculate(int i){if(contents[i]==null||contents[i].kind!='='||done[i])return;done[i]=true;if(cyclic[i]){values[i]=error("#CYCLE!");return;}for(int j:deps.get(i))calculate(j);Expr v=evaluate(contents[i].a);values[i]=v==null?num(0):v.kind=='G'?error("#VALUE!"):v;}
            }
            Graph graph=new Graph();for(int i=0;i<2574;i++)if(contents[i]!=null&&contents[i].kind=='='&&graph.index[i]<0)graph.visit(i);for(int i=0;i<2574;i++)graph.calculate(i);
        }
        int replace(Expr[] next){Expr[] old=values;values=new Expr[2574];contents=next;recalculate();int count=0;for(int i=0;i<2574;i++)if(!notation(old[i]).equals(notation(values[i])))count++;return count;}
        String describe(int i){return label(i)+": "+notation(contents[i])+" -> "+notation(values[i]);}
        String formatted(Collection<Integer> xs){StringJoiner j=new StringJoiner(",");for(int i:xs)j.add(label(i));return xs.isEmpty()?"none":j.toString();}
        List<String> execute(String line){
            int p=line.indexOf(' ');String name=p<0?line:line.substring(0,p),rest=p<0?"":line.substring(p+1);
            if(name.equals("SHOW"))return List.of(describe(id(address(rest))));
            if(name.equals("LIST")){List<String> out=new ArrayList<>();for(int i=0;i<2574;i++)if(contents[i]!=null)out.add(describe(i));return out.isEmpty()?List.of("(no cells)"):out;}
            if(name.equals("DEPS")){int i=id(address(rest));Set<Integer> ds=new TreeSet<>();for(int j=0;j<2574;j++)if(deps.get(j).contains(i))ds.add(j);return List.of(rest+": precedents="+formatted(deps.get(i))+" dependents="+formatted(ds));}
            if(name.equals("PRINT")){
                Expr g=area(rest);int rw=(""+(g.b.row+1)).length();List<Integer> widths=new ArrayList<>();String sep="+"+"-".repeat(rw)+"+",header="|"+" ".repeat(rw)+"|";
                for(int c=g.a.n;c<=g.b.n;c++){int w=1;for(int r=g.a.row;r<=g.b.row;r++)w=Math.max(w,display(values[r*26+c]).length());widths.add(w);sep+="-".repeat(w)+"+";header+=(char)('A'+c)+" ".repeat(w-1)+"|";}
                List<String> out=new ArrayList<>(List.of(sep,header,sep));for(int r=g.a.row;r<=g.b.row;r++){String s=""+(r+1),row="|"+" ".repeat(rw-s.length())+s+"|";for(int j=0;j<widths.size();j++){Expr v=values[r*26+g.a.n+j];s=display(v);String pad=" ".repeat(widths.get(j)-s.length());row+=(v!=null&&v.kind=='N'?pad+s:s+pad)+"|";}out.add(row);}out.add(sep);return out;
            }
            if(name.equals("UNDO")){if(history.isEmpty())throw new IllegalArgumentException("nothing to undo");History e=history.remove(history.size()-1);return List.of("UNDO "+e.name+" changed="+replace(e.contents));}
            Expr[] next=contents.clone();int target=-1;
            if(name.equals("SET")){
                p=rest.indexOf(' ');target=id(address(rest.substring(0,p)));String s=rest.substring(p+1);
                if(s.startsWith("="))next[target]=node('=',0,"",new Parser(s).parse(),null,List.of());else if(s.matches("\"[^\"]*\""))next[target]=text(s.substring(1,s.length()-1));else if(s.matches("0|-?[1-9][0-9]{0,8}"))next[target]=num(Integer.parseInt(s));else throw new IllegalArgumentException("bad value");
            }else if(name.equals("CLEAR")){for(int i:cells(area(rest)))next[i]=null;}
            else if(name.equals("COPY")||name.equals("MOVE")){
                p=rest.indexOf(' ');Expr source=area(rest.substring(0,p)),dest=address(rest.substring(p+1));int dc=dest.n-source.a.n,dr=dest.row-source.a.row;
                class Shift {Expr apply(Expr r,boolean relative){return ref(r.n+(relative&&(r.flags&1)!=0?0:dc),r.row+(relative&&(r.flags&2)!=0?0:dr),r.flags);}}
                Shift shift=new Shift();Expr destination=range(shift.apply(source.a,false),shift.apply(source.b,false));if(!inside(destination.a)||!inside(destination.b))throw new IllegalArgumentException("out of grid");
                UnaryOperator<Expr> transform=x->{if(x.kind=='R'){if(name.equals("COPY")){Expr r=shift.apply(x,true);return inside(r)?r:INVALID;}return contains(source,x)?shift.apply(x,false):contains(destination,x)?INVALID:x;}
                    if(name.equals("MOVE")&&!(contains(source,x.a)&&contains(source,x.b)))return x;Expr a=shift.apply(x.a,name.equals("COPY")),b=shift.apply(x.b,name.equals("COPY"));return inside(a)&&inside(b)?range(a,b):INVALID;};
                if(name.equals("MOVE"))for(int i=0;i<2574;i++)next[i]=rewrite(next[i],transform);List<Integer> ids=cells(source);List<Expr> moving=new ArrayList<>();for(int i:ids)moving.add(name.equals("COPY")?rewrite(contents[i],transform):next[i]);if(name.equals("MOVE"))for(int i:ids)next[i]=null;for(int j=0;j<ids.size();j++)next[ids.get(j)+dr*26+dc]=moving.get(j);
            }else if(Set.of("INSERTROW","DELETEROW","INSERTCOL","DELETECOL").contains(name)){
                boolean row=name.endsWith("ROW"),insert=name.startsWith("INSERT");if(!rest.matches(row?"[1-9][0-9]?":"[A-Z]"))throw new IllegalArgumentException("bad address");int at=row?Integer.parseInt(rest)-1:rest.charAt(0)-'A',limit=row?99:26;
                class Axis {int get(Expr x){return row?x.row:x.n;}Expr set(Expr x,int v){return ref(row?x.n:v,row?v:x.row,x.flags);}}
                Axis axis=new Axis();if(insert)for(int i=0;i<2574;i++)if(contents[i]!=null&&(row?i/26:i%26)==limit-1)throw new IllegalArgumentException("last "+(row?"row":"column")+" not empty");
                UnaryOperator<Expr> transform=x->{if(x.kind=='R'){int v=axis.get(x);if(!insert&&v==at)return INVALID;int n=v+(insert?(v>=at?1:0):(v>at?-1:0));return n>=limit?INVALID:axis.set(x,n);}int a=axis.get(x.a),b=axis.get(x.b);if(!insert&&a==at&&b==at)return INVALID;int u=a+(insert?(a>=at?1:0):(a>at?-1:0)),v=b+(insert?(b>=at?1:0):(b>=at?-1:0));return v>=limit?INVALID:range(axis.set(x.a,u),axis.set(x.b,v));};
                next=new Expr[2574];for(int i=0;i<2574;i++)if(contents[i]!=null){Expr r=ref(i%26,i/26,0);int v=axis.get(r);if(!insert&&v==at)continue;Expr t=axis.set(r,v+(insert?(v>=at?1:0):(v>at?-1:0)));next[id(t)]=rewrite(contents[i],transform);}
            }else throw new IllegalArgumentException("unknown command");
            history.add(new History(name,contents));int changed=replace(next);return List.of(name+(name.equals("SET")?" "+label(target)+"="+notation(values[target]):"")+" changed="+changed);
        }
    }
    public static void main(String[] args)throws IOException {
        BufferedReader in=new BufferedReader(new InputStreamReader(System.in));int n=Integer.parseInt(in.readLine());Sheet sheet=new Sheet();StringBuilder out=new StringBuilder();
        for(int i=0;i<n;i++){String line=in.readLine();try{for(String s:sheet.execute(line))out.append(s).append('\n');}catch(IllegalArgumentException e){out.append("ERROR ").append(e.getMessage()).append('\n');}}
        System.out.print(out);
    }
}
