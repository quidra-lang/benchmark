import java.io.*;
import java.util.*;
import java.util.function.Function;

public class Main {
    static final Object NIL=new Object(), VOID=new Object(), UNINIT=new Object();
    record Symbol(String name) {}
    record Pair(Object car,Object cdr) {}
    static class Env {
        final Map<String,Object> frame=new HashMap<>(); final Env parent;
        Env(Env parent){this.parent=parent;}
        Env find(String n){for(Env e=this;e!=null;e=e.parent)if(e.frame.containsKey(n))return e;throw error("unbound variable: "+n);}
        Object get(String n){Object v=find(n).frame.get(n);if(v==UNINIT)throw error("uninitialized variable: "+n);return v;}
    }
    static class Procedure {
        String name,rest;int minimum;boolean variadic;List<String> params;List<Object> body;Env env;Function<List<Object>,Object> builtin;
        Object call(List<Object>a){
            if(a.size()<minimum||(!variadic&&a.size()!=minimum))throw error((name==null?"lambda":name)+": wrong number of arguments (expected "+(variadic?"at least ":"")+minimum+", got "+a.size()+")");
            if(builtin!=null)return builtin.apply(a);Env e=new Env(env);for(int i=0;i<params.size();i++)e.frame.put(params.get(i),a.get(i));if(rest!=null)e.frame.put(rest,list(a.subList(minimum,a.size()),NIL));return body(body,e);
        }
    }
    static RuntimeException error(String s){return new RuntimeException(s);}
    static Object list(List<Object>a,Object tail){for(int i=a.size()-1;i>=0;i--)tail=new Pair(a.get(i),tail);return tail;}
    static List<Object> items(Object v){List<Object>a=new ArrayList<>();while(v instanceof Pair p){a.add(p.car);v=p.cdr;}return v==NIL?a:null;}
    static boolean truth(Object v){return !Boolean.FALSE.equals(v);}
    static String repr(Object v,boolean quoted){
        if(v==NIL)return "()";if(v==VOID)return "#<void>";if(v instanceof Boolean b)return b?"#t":"#f";if(v instanceof Long)return v.toString();if(v instanceof String s)return quoted?'"'+s.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n")+'"':s;
        if(v instanceof Symbol s)return s.name;if(v instanceof Procedure p)return p.name==null?"#<procedure>":"#<procedure "+p.name+">";
        List<String>a=new ArrayList<>();while(v instanceof Pair p){a.add(repr(p.car,quoted));v=p.cdr;}if(v!=NIL){a.add(".");a.add(repr(v,quoted));}return "("+String.join(" ",a)+")";
    }
    static boolean same(Object a,Object b,boolean deep){if(a instanceof Pair p&&b instanceof Pair q)return deep?same(p.car,q.car,true)&&same(p.cdr,q.cdr,true):a==b;if(a instanceof Procedure||b instanceof Procedure)return a==b;return Objects.equals(a,b);}
    record Parameters(List<String> names,String rest) {}
    static Parameters parameters(Object v){List<String>p=new ArrayList<>();while(v instanceof Pair x){if(!(x.car instanceof Symbol s))return null;p.add(s.name);v=x.cdr;}String r=v instanceof Symbol s?s.name:null;if(v!=NIL&&r==null)return null;List<String>all=new ArrayList<>(p);if(r!=null)all.add(r);return new HashSet<>(all).size()==all.size()?new Parameters(p,r):null;}
    static Procedure closure(Parameters p,List<Object>b,Env e,String name){Procedure f=new Procedure();f.name=name;f.params=p.names;f.minimum=p.names.size();f.rest=p.rest;f.variadic=p.rest!=null;f.body=b;f.env=e;return f;}
    record Binding(String name,Object expr) {}
    static List<Binding> bindings(Object v,boolean unique){List<Object>a=items(v);if(a==null)return null;List<Binding>bs=new ArrayList<>();Set<String>seen=new HashSet<>();for(Object x:a){List<Object>b=items(x);if(b==null||b.size()!=2||!(b.get(0) instanceof Symbol s))return null;if(unique&&!seen.add(s.name))return null;bs.add(new Binding(s.name,b.get(1)));}return bs;}
    static void shape(boolean b,Object x){if(!b)throw error("bad syntax: "+repr(x,true));}
    static Object body(List<Object>a,Env e){Object v=VOID;for(Object x:a)v=evaluate(x,e);return v;}
    static Object evaluate(Object x,Env e){
        if(x instanceof Symbol s)return e.get(s.name);if(!(x instanceof Pair)){shape(x!=NIL,x);return x;}List<Object>a=items(x);shape(a!=null,x);int n=a.size();String h=a.get(0) instanceof Symbol s?s.name:"";
        switch(h){
            case "quote":shape(n==2,x);return a.get(1);
            case "if":shape(n==3||n==4,x);return truth(evaluate(a.get(1),e))?evaluate(a.get(2),e):n==4?evaluate(a.get(3),e):VOID;
            case "begin":return body(a.subList(1,n),e);
            case "lambda":{Parameters p=n>=3?parameters(a.get(1)):null;shape(p!=null,x);return closure(p,a.subList(2,n),e,null);}
            case "define":{
                if(n>1&&a.get(1) instanceof Symbol s){shape(n==3,x);Object v=evaluate(a.get(2),e);if(v instanceof Procedure f&&f.builtin==null&&f.name==null)f.name=s.name;e.frame.put(s.name,v);}
                else{Object t=n>1?a.get(1):NIL;Parameters p=n>=3&&t instanceof Pair q&&q.car instanceof Symbol?parameters(q.cdr):null;shape(p!=null,x);Pair q=(Pair)t;String name=((Symbol)q.car).name;e.frame.put(name,closure(p,a.subList(2,n),e,name));}return VOID;
            }
            case "set!":shape(n==3&&a.get(1) instanceof Symbol,x);{String name=((Symbol)a.get(1)).name;Object v=evaluate(a.get(2),e);e.find(name).frame.put(name,v);}return VOID;
            case "let":case "let*":case "letrec":{
                boolean named=h.equals("let")&&n>1&&a.get(1) instanceof Symbol;int at=named?2:1;List<Binding>bs=n>=at+2?bindings(a.get(at),!h.equals("let*")):null;shape(bs!=null,x);Env scope=new Env(e);
                if(h.equals("let*")){if(!bs.isEmpty())scope=e;for(Binding b:bs){Object v=evaluate(b.expr,scope);scope=new Env(scope);scope.frame.put(b.name,v);}}
                else if(h.equals("letrec")){for(Binding b:bs)scope.frame.put(b.name,UNINIT);for(Binding b:bs)scope.frame.put(b.name,evaluate(b.expr,scope));}
                else{List<Object>vs=new ArrayList<>();List<String>names=new ArrayList<>();for(Binding b:bs){vs.add(evaluate(b.expr,e));names.add(b.name);}if(named){String name=((Symbol)a.get(1)).name;Procedure f=closure(new Parameters(names,null),a.subList(3,n),scope,name);scope.frame.put(name,f);return f.call(vs);}for(int i=0;i<bs.size();i++)scope.frame.put(bs.get(i).name,vs.get(i));}return body(a.subList(at+1,n),scope);
            }
            case "cond":{
                List<List<Object>>cs=new ArrayList<>();for(int i=1;i<n;i++){List<Object>c=items(a.get(i));shape(c!=null&&!c.isEmpty(),x);if(c.get(0).equals(new Symbol("else")))shape(c.size()>=2&&i==n-1,x);cs.add(c);}for(List<Object>c:cs){if(c.get(0).equals(new Symbol("else")))return body(c.subList(1,c.size()),e);Object v=evaluate(c.get(0),e);if(truth(v))return c.size()==1?v:body(c.subList(1,c.size()),e);}return VOID;
            }
            case "and":{Object v=true;for(int i=1;i<n;i++){v=evaluate(a.get(i),e);if(!truth(v))break;}return v;}
            case "or":for(int i=1;i<n;i++){Object v=evaluate(a.get(i),e);if(truth(v))return v;}return false;
            case "when":case "unless":shape(n>=3,x);return truth(evaluate(a.get(1),e))==h.equals("when")?body(a.subList(2,n),e):VOID;
        }
        Object f=evaluate(a.get(0),e);List<Object>args=new ArrayList<>();for(int i=1;i<n;i++)args.add(evaluate(a.get(i),e));if(!(f instanceof Procedure p))throw error("not a procedure: "+repr(f,true));return p.call(args);
    }
    static boolean mid=false;
    static void write(String s){System.out.print(s);if(!s.isEmpty())mid=!s.endsWith("\n");}static void line(String s){if(mid)write("\n");write(s+"\n");}
    static Object expect(String n,Object v,String k){boolean ok=switch(k){case "integer"->v instanceof Long;case "string"->v instanceof String;case "pair"->v instanceof Pair;case "procedure"->v instanceof Procedure;default->items(v)!=null;};if(!ok)throw error(n+": expected "+k+", got "+repr(v,true));return v;}
    static List<Object> asList(String n,Object v){expect(n,v,"list");return items(v);}
    static void add(Env e,String n,int m,boolean r,Function<List<Object>,Object>fn){Procedure p=new Procedure();p.name=n;p.minimum=m;p.variadic=r;p.builtin=fn;e.frame.put(n,p);}
    static Env global(){Env e=new Env(null);
        for(String name:List.of("+","*","-","quotient","remainder","modulo","abs","min","max","gcd","=","<",">","<=",">=")){int fixed=List.of("quotient","remainder","modulo").contains(name)?2:name.equals("abs")?1:-1;add(e,name,fixed>=0?fixed:List.of("+","*","gcd").contains(name)?0:1,fixed<0,a->{
            for(Object v:a)expect(name,v,"integer");long v=a.isEmpty()?0:(Long)a.get(0);
            switch(name){case "+":case "*":v=name.equals("+")?0:1;for(Object x:a)v=name.equals("+")?v+(Long)x:v*(Long)x;return v;case "-":if(a.size()==1)return -v;for(int i=1;i<a.size();i++)v-=(Long)a.get(i);return v;case "abs":return Math.abs(v);case "min":case "max":for(Object x:a)v=name.equals("min")?Math.min(v,(Long)x):Math.max(v,(Long)x);return v;case "gcd":v=0;for(Object x:a){long b=Math.abs((Long)x);while(b!=0){long r=v%b;v=b;b=r;}}return v;case "quotient":case "remainder":case "modulo":long b=(Long)a.get(1);if(b==0)throw error(name+": division by zero");long r=v%b;return name.equals("quotient")?v/b:name.equals("modulo")&&r!=0&&((r<0)!=(b<0))?r+b:r;}
            for(int i=1;i<a.size();i++){long l=(Long)a.get(i-1),r=(Long)a.get(i);boolean ok=switch(name){case "="->l==r;case "<"->l<r;case ">"->l>r;case "<="->l<=r;default->l>=r;};if(!ok)return false;}return true;
        });}
        add(e,"not",1,false,a->!truth(a.get(0)));for(String n:List.of("eq?","equal?"))add(e,n,2,false,a->same(a.get(0),a.get(1),n.equals("equal?")));
        for(String n:List.of("null?","pair?","list?","number?","symbol?","procedure?"))add(e,n,1,false,a->switch(n){case "null?"->a.get(0)==NIL;case "pair?"->a.get(0) instanceof Pair;case "list?"->items(a.get(0))!=null;case "number?"->a.get(0) instanceof Long;case "symbol?"->a.get(0) instanceof Symbol;default->a.get(0) instanceof Procedure;});
        add(e,"cons",2,false,a->new Pair(a.get(0),a.get(1)));add(e,"list",0,true,a->list(a,NIL));
        for(String n:List.of("car","cdr","cadr"))add(e,n,1,false,a->{Pair p=(Pair)expect(n,a.get(0),"pair");return n.equals("car")?p.car:n.equals("cdr")?p.cdr:((Pair)expect(n,p.cdr,"pair")).car;});
        for(String n:List.of("length","reverse","list-ref"))add(e,n,n.equals("list-ref")?2:1,false,a->{List<Object>z=asList(n,a.get(0));if(n.equals("length"))return (long)z.size();if(n.equals("reverse")){Collections.reverse(z);return list(z,NIL);}long k=(Long)expect(n,a.get(1),"integer");if(k<0||k>=z.size())throw error("list-ref: index out of range: "+k);return z.get((int)k);});
        add(e,"append",0,true,a->{if(a.isEmpty())return NIL;List<Object>z=new ArrayList<>();for(int i=0;i+1<a.size();i++)z.addAll(asList("append",a.get(i)));return list(z,a.getLast());});
        for(String n:List.of("map","filter","fold-left","apply"))add(e,n,n.equals("fold-left")?3:2,!n.equals("filter"),a->{Procedure f=(Procedure)expect(n,a.get(0),"procedure");if(n.equals("apply")){List<Object>z=new ArrayList<>(a.subList(1,a.size()-1));z.addAll(asList(n,a.getLast()));return f.call(z);}List<List<Object>>ls=new ArrayList<>();int count=Integer.MAX_VALUE;for(int i=n.equals("fold-left")?2:1;i<a.size();i++){List<Object>z=asList(n,a.get(i));ls.add(z);count=Math.min(count,z.size());}List<Object>out=new ArrayList<>();Object acc=a.get(1);for(int i=0;i<count;i++){if(n.equals("filter")){if(truth(f.call(List.of(ls.get(0).get(i)))))out.add(ls.get(0).get(i));}else{List<Object>z=new ArrayList<>();if(n.equals("fold-left"))z.add(acc);for(List<Object>l:ls)z.add(l.get(i));Object v=f.call(z);if(n.equals("map"))out.add(v);else acc=v;}}return n.equals("fold-left")?acc:list(out,NIL);});
        add(e,"string-append",0,true,a->{StringBuilder s=new StringBuilder();for(Object v:a)s.append((String)expect("string-append",v,"string"));return s.toString();});add(e,"number->string",1,false,a->expect("number->string",a.get(0),"integer").toString());
        add(e,"display",1,false,a->{write(repr(a.get(0),false));return VOID;});add(e,"newline",0,false,a->{write("\n");return VOID;});add(e,"error",1,true,a->{String s=(String)expect("error",a.get(0),"string");for(int i=1;i<a.size();i++)s+=" "+repr(a.get(i),true);throw error(s);});return e;
    }
    record Token(char kind,Object value) {}
    static class Reader {
        List<String>lines;int row=0,col=0;Reader(List<String>lines){this.lines=lines;}void skip(){row++;col=0;}
        boolean end(){while(row<lines.size()){String s=lines.get(row);while(col<s.length()&&s.charAt(col)==' ')col++;if(col<s.length()&&s.charAt(col)!=';')return false;skip();}return true;}
        Token token(){if(end())throw error("unexpected end of input");String s=lines.get(row);char c=s.charAt(col++);if("()'".indexOf(c)>=0)return new Token(c,null);if(c=='"'){StringBuilder v=new StringBuilder();while(col<s.length()){c=s.charAt(col++);if(c=='"')return new Token('v',v.toString());if(c=='\\'){if(col==s.length())break;c=s.charAt(col++);if(c!='"'&&c!='\\'&&c!='n')throw error("bad escape");if(c=='n')c='\n';}v.append(c);}throw error("unterminated string");}int start=col-1;while(col<s.length()&&" ()'\";".indexOf(s.charAt(col))<0)col++;String a=s.substring(start,col);if(a.equals("."))return new Token('.',null);if(a.matches("[+-]?[0-9]+"))return new Token('v',Long.parseLong(a));if(a.equals("#t")||a.equals("#f"))return new Token('v',a.equals("#t"));if(a.startsWith("#"))throw error("bad token: "+a);return new Token('v',new Symbol(a));}
        Object datum(){return from(token());}Object from(Token t){if(t.kind=='v')return t.value;if(t.kind=='\'')return list(List.of(new Symbol("quote"),datum()),NIL);if(t.kind!='(')throw error("unexpected "+t.kind);List<Object>a=new ArrayList<>();while(true){t=token();if(t.kind==')')return list(a,NIL);if(t.kind=='.'&&!a.isEmpty()){Object tail=datum();if(token().kind!=')')throw error("expected )");return list(a,tail);}a.add(from(t));}}
    }
    public static void main(String[]args)throws IOException {BufferedReader in=new BufferedReader(new InputStreamReader(System.in));List<String>lines=new ArrayList<>();String s;while((s=in.readLine())!=null&&!s.equals("(exit)"))lines.add(s);Reader r=new Reader(lines);Env e=global();while(!r.end()){Object x;try{x=r.datum();}catch(RuntimeException err){line("Error: read: "+err.getMessage());if(err.getMessage().equals("unexpected end of input"))break;r.skip();continue;}try{Object v=evaluate(x,e);if(v!=VOID)line(repr(v,true));}catch(RuntimeException err){line("Error: "+err.getMessage());}}if(mid)write("\n");}
}
