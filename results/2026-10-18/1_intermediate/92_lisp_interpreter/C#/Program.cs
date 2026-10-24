using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

class Program
{
    static readonly object Nil=new(), Void=new(), Uninitialized=new();
    sealed record Symbol(string Name);
    sealed record Pair(object Car,object Cdr);
    sealed class Environment
    {
        public readonly Dictionary<string,object> Frame=new();
        public readonly Environment? Parent;
        public Environment(Environment? parent=null)=>Parent=parent;
        public Environment Find(string name){for(Environment? e=this;e!=null;e=e.Parent)if(e.Frame.ContainsKey(name))return e;throw new Exception("unbound variable: "+name);}
        public object Get(string name){object v=Find(name).Frame[name];if(ReferenceEquals(v,Uninitialized))throw new Exception("uninitialized variable: "+name);return v;}
    }
    sealed class Procedure
    {
        public string? Name,Rest;
        public int Minimum;
        public bool Variadic;
        public List<string> Parameters=new();
        public List<object> Body=new();
        public Environment? Scope;
        public Func<List<object>,object>? Builtin;
        public object Call(List<object> args)
        {
            if(args.Count<Minimum||(!Variadic&&args.Count!=Minimum))throw new Exception($"{Name??"lambda"}: wrong number of arguments (expected {(Variadic?"at least ":"")}{Minimum}, got {args.Count})");
            if(Builtin!=null)return Builtin(args);
            Environment e=new(Scope);for(int i=0;i<Parameters.Count;i++)e.Frame[Parameters[i]]=args[i];if(Rest!=null)e.Frame[Rest]=List(args.Skip(Minimum));return EvalBody(Body,e);
        }
    }
    static object List(IEnumerable<object> values,object? tail=null){object v=tail??Nil;foreach(object x in values.Reverse())v=new Pair(x,v);return v;}
    static List<object>? Items(object v){List<object>a=new();while(v is Pair p){a.Add(p.Car);v=p.Cdr;}return ReferenceEquals(v,Nil)?a:null;}
    static bool Truth(object v)=>v is not false;
    static string Repr(object v,bool quoted=true)
    {
        if(ReferenceEquals(v,Nil))return "()";if(ReferenceEquals(v,Void))return "#<void>";
        if(v is bool b)return b?"#t":"#f";if(v is long n)return n.ToString();if(v is string s)return quoted?'"'+s.Replace("\\","\\\\").Replace("\"","\\\"").Replace("\n","\\n")+'"':s;
        if(v is Symbol symbol)return symbol.Name;if(v is Procedure f)return f.Name==null?"#<procedure>":$"#<procedure {f.Name}>";
        List<string>a=new();while(v is Pair p){a.Add(Repr(p.Car,quoted));v=p.Cdr;}if(!ReferenceEquals(v,Nil)){a.Add(".");a.Add(Repr(v,quoted));}return "("+string.Join(" ",a)+")";
    }
    static bool Same(object a,object b,bool deep=false){if(a is Pair p&&b is Pair q)return deep?Same(p.Car,q.Car,true)&&Same(p.Cdr,q.Cdr,true):ReferenceEquals(a,b);if(a is Procedure||b is Procedure)return ReferenceEquals(a,b);return Equals(a,b);}
    sealed record Formals(List<string> Names,string? Rest);
    static Formals? Parameters(object v){List<string>names=new();while(v is Pair p){if(p.Car is not Symbol s)return null;names.Add(s.Name);v=p.Cdr;}string? r=(v as Symbol)?.Name;if(!ReferenceEquals(v,Nil)&&r==null)return null;List<string>all=new(names);if(r!=null)all.Add(r);return all.Distinct().Count()==all.Count?new(names,r):null;}
    static Procedure Closure(Formals p,List<object>b,Environment e,string? name=null)=>new(){Name=name,Minimum=p.Names.Count,Variadic=p.Rest!=null,Rest=p.Rest,Parameters=p.Names,Body=b,Scope=e};
    sealed record Binding(string Name,object Expression);
    static List<Binding>? Bindings(object v,bool unique){List<object>? a=Items(v);if(a==null)return null;List<Binding>bs=new();HashSet<string>seen=new();foreach(object x in a){List<object>? b=Items(x);if(b==null||b.Count!=2||b[0] is not Symbol s)return null;if(unique&&!seen.Add(s.Name))return null;bs.Add(new(s.Name,b[1]));}return bs;}
    static void Shape(bool valid,object x){if(!valid)throw new Exception("bad syntax: "+Repr(x));}
    static object EvalBody(IEnumerable<object>a,Environment e){object v=Void;foreach(object x in a)v=Evaluate(x,e);return v;}
    static object Evaluate(object x,Environment e)
    {
        if(x is Symbol symbol)return e.Get(symbol.Name);if(x is not Pair){Shape(!ReferenceEquals(x,Nil),x);return x;}
        List<object>? parsed=Items(x);Shape(parsed!=null,x);List<object>a=parsed!;int n=a.Count;string h=(a[0] as Symbol)?.Name??"";
        switch(h)
        {
            case "quote":Shape(n==2,x);return a[1];
            case "if":Shape(n==3||n==4,x);return Truth(Evaluate(a[1],e))?Evaluate(a[2],e):n==4?Evaluate(a[3],e):Void;
            case "begin":return EvalBody(a.Skip(1),e);
            case "lambda":{Formals? p=n>=3?Parameters(a[1]):null;Shape(p!=null,x);return Closure(p!,a.Skip(2).ToList(),e);}
            case "define":
                if(n>1&&a[1] is Symbol s){Shape(n==3,x);object v=Evaluate(a[2],e);if(v is Procedure f&&f.Builtin==null&&f.Name==null)f.Name=s.Name;e.Frame[s.Name]=v;}
                else{object target=n>1?a[1]:Nil;Formals? p=n>=3&&target is Pair q&&q.Car is Symbol?Parameters(q.Cdr):null;Shape(p!=null,x);string name=((Symbol)((Pair)target).Car).Name;e.Frame[name]=Closure(p!,a.Skip(2).ToList(),e,name);}return Void;
            case "set!":Shape(n==3&&a[1] is Symbol,x);{string name=((Symbol)a[1]).Name;object v=Evaluate(a[2],e);e.Find(name).Frame[name]=v;}return Void;
            case "let":case "let*":case "letrec":
            {
                bool named=h=="let"&&n>1&&a[1] is Symbol;int at=named?2:1;List<Binding>? bs=n>=at+2?Bindings(a[at],h!="let*"):null;Shape(bs!=null,x);Environment scope=new(e);
                if(h=="let*"){if(bs!.Count>0)scope=e;foreach(Binding b in bs){object v=Evaluate(b.Expression,scope);scope=new(scope);scope.Frame[b.Name]=v;}}
                else if(h=="letrec"){foreach(Binding b in bs!)scope.Frame[b.Name]=Uninitialized;foreach(Binding b in bs)scope.Frame[b.Name]=Evaluate(b.Expression,scope);}
                else{List<object>values=bs!.Select(b=>Evaluate(b.Expression,e)).ToList();if(named){string name=((Symbol)a[1]).Name;Procedure f=Closure(new(bs.Select(b=>b.Name).ToList(),null),a.Skip(3).ToList(),scope,name);scope.Frame[name]=f;return f.Call(values);}for(int i=0;i<bs.Count;i++)scope.Frame[bs[i].Name]=values[i];}return EvalBody(a.Skip(at+1),scope);
            }
            case "cond":
            {
                List<List<object>?>cs=a.Skip(1).Select(Items).ToList();for(int i=0;i<cs.Count;i++){List<object>? c=cs[i];Shape(c!=null&&c.Count>0,x);if(c![0] is Symbol s&&s.Name=="else")Shape(c.Count>=2&&i==cs.Count-1,x);}
                foreach(List<object>? c in cs){if(c![0] is Symbol s&&s.Name=="else")return EvalBody(c.Skip(1),e);object v=Evaluate(c[0],e);if(Truth(v))return c.Count==1?v:EvalBody(c.Skip(1),e);}return Void;
            }
            case "and":{object v=true;foreach(object z in a.Skip(1)){v=Evaluate(z,e);if(!Truth(v))break;}return v;}
            case "or":foreach(object z in a.Skip(1)){object v=Evaluate(z,e);if(Truth(v))return v;}return false;
            case "when":case "unless":Shape(n>=3,x);return Truth(Evaluate(a[1],e))==(h=="when")?EvalBody(a.Skip(2),e):Void;
        }
        object fn=Evaluate(a[0],e);List<object>args=a.Skip(1).Select(z=>Evaluate(z,e)).ToList();if(fn is not Procedure proc)throw new Exception("not a procedure: "+Repr(fn));return proc.Call(args);
    }
    static bool mid;
    static void Write(string s){Console.Write(s);if(s.Length>0)mid=!s.EndsWith('\n');}static void Line(string s){if(mid)Write("\n");Write(s+"\n");}
    static object Expect(string name,object v,string kind){bool ok=kind switch{"integer"=>v is long,"string"=>v is string,"pair"=>v is Pair,"procedure"=>v is Procedure,_=>Items(v)!=null};if(!ok)throw new Exception($"{name}: expected {kind}, got {Repr(v)}");return v;}
    static List<object> AsList(string n,object v){Expect(n,v,"list");return Items(v)!;}
    static void Add(Environment e,string n,int minimum,bool rest,Func<List<object>,object>fn)=>e.Frame[n]=new Procedure{Name=n,Minimum=minimum,Variadic=rest,Builtin=fn};
    static Environment Global()
    {
        Environment e=new();
        foreach(string name in new[]{"+","*","-","quotient","remainder","modulo","abs","min","max","gcd","=","<",">","<=",">="})
        {
            int fixedCount=new[]{"quotient","remainder","modulo"}.Contains(name)?2:name=="abs"?1:-1;
            Add(e,name,fixedCount>=0?fixedCount:new[]{"+","*","gcd"}.Contains(name)?0:1,fixedCount<0,a=>{
                foreach(object x in a)Expect(name,x,"integer");long v=a.Count>0?(long)a[0]:0;
                switch(name){case "+":case "*":v=name=="+"?0:1;foreach(object x in a)v=name=="+"?v+(long)x:v*(long)x;return v;case "-":if(a.Count==1)return -v;foreach(object x in a.Skip(1))v-=(long)x;return v;case "abs":return Math.Abs(v);case "min":case "max":foreach(object x in a)v=name=="min"?Math.Min(v,(long)x):Math.Max(v,(long)x);return v;case "gcd":v=0;foreach(object x in a){long b=Math.Abs((long)x);while(b!=0){long r=v%b;v=b;b=r;}}return v;case "quotient":case "remainder":case "modulo":long divisor=(long)a[1];if(divisor==0)throw new Exception(name+": division by zero");long rem=v%divisor;return name=="quotient"?v/divisor:name=="modulo"&&rem!=0&&((rem<0)!=(divisor<0))?rem+divisor:rem;}
                for(int i=1;i<a.Count;i++){long l=(long)a[i-1],r=(long)a[i];bool ok=name switch{"="=>l==r,"<"=>l<r,">"=>l>r,"<="=>l<=r,_=>l>=r};if(!ok)return false;}return true;
            });
        }
        Add(e,"not",1,false,a=>!Truth(a[0]));foreach(string n in new[]{"eq?","equal?"})Add(e,n,2,false,a=>Same(a[0],a[1],n=="equal?"));
        foreach(string n in new[]{"null?","pair?","list?","number?","symbol?","procedure?"})Add(e,n,1,false,a=>n switch{"null?"=>ReferenceEquals(a[0],Nil),"pair?"=>a[0] is Pair,"list?"=>Items(a[0])!=null,"number?"=>a[0] is long,"symbol?"=>a[0] is Symbol,_=>a[0] is Procedure});
        Add(e,"cons",2,false,a=>new Pair(a[0],a[1]));Add(e,"list",0,true,a=>List(a));
        foreach(string n in new[]{"car","cdr","cadr"})Add(e,n,1,false,a=>{Pair p=(Pair)Expect(n,a[0],"pair");return n=="car"?p.Car:n=="cdr"?p.Cdr:((Pair)Expect(n,p.Cdr,"pair")).Car;});
        foreach(string n in new[]{"length","reverse","list-ref"})Add(e,n,n=="list-ref"?2:1,false,a=>{List<object>z=AsList(n,a[0]);if(n=="length")return (long)z.Count;if(n=="reverse")return List(z.AsEnumerable().Reverse());long k=(long)Expect(n,a[1],"integer");if(k<0||k>=z.Count)throw new Exception("list-ref: index out of range: "+k);return z[(int)k];});
        Add(e,"append",0,true,a=>{if(a.Count==0)return Nil;List<object>z=new();foreach(object v in a.Take(a.Count-1))z.AddRange(AsList("append",v));return List(z,a[^1]);});
        foreach(string n in new[]{"map","filter","fold-left","apply"})Add(e,n,n=="fold-left"?3:2,n!="filter",a=>{
            Procedure f=(Procedure)Expect(n,a[0],"procedure");if(n=="apply")return f.Call(a.Skip(1).Take(a.Count-2).Concat(AsList(n,a[^1])).ToList());List<List<object>>ls=a.Skip(n=="fold-left"?2:1).Select(v=>AsList(n,v)).ToList();int count=ls.Min(z=>z.Count);List<object>result=new();object acc=a[1];for(int i=0;i<count;i++){if(n=="filter"){if(Truth(f.Call(new(){ls[0][i]})))result.Add(ls[0][i]);}else{List<object>args=new();if(n=="fold-left")args.Add(acc);args.AddRange(ls.Select(z=>z[i]));object v=f.Call(args);if(n=="map")result.Add(v);else acc=v;}}return n=="fold-left"?acc:List(result);
        });
        Add(e,"string-append",0,true,a=>string.Concat(a.Select(v=>(string)Expect("string-append",v,"string"))));Add(e,"number->string",1,false,a=>Expect("number->string",a[0],"integer").ToString()!);
        Add(e,"display",1,false,a=>{Write(Repr(a[0],false));return Void;});Add(e,"newline",0,false,a=>{Write("\n");return Void;});Add(e,"error",1,true,a=>throw new Exception((string)Expect("error",a[0],"string")+string.Concat(a.Skip(1).Select(v=>" "+Repr(v)))));return e;
    }
    readonly record struct Token(char Kind,object? Value);
    sealed class Reader
    {
        readonly List<string> lines;int row,col;
        public Reader(List<string> lines)=>this.lines=lines;
        public void Skip(){row++;col=0;}
        public bool End(){while(row<lines.Count){string s=lines[row];while(col<s.Length&&s[col]==' ')col++;if(col<s.Length&&s[col]!=';')return false;Skip();}return true;}
        Token Next(){if(End())throw new Exception("unexpected end of input");string s=lines[row];char c=s[col++];if("()'".Contains(c))return new(c,null);if(c=='"'){StringBuilder v=new();while(col<s.Length){c=s[col++];if(c=='"')return new('v',v.ToString());if(c=='\\'){if(col==s.Length)break;c=s[col++];if(c!='"'&&c!='\\'&&c!='n')throw new Exception("bad escape");if(c=='n')c='\n';}v.Append(c);}throw new Exception("unterminated string");}int start=col-1;while(col<s.Length&&!" ()'\";".Contains(s[col]))col++;string atom=s[start..col];if(atom==".")return new('.',null);if(System.Text.RegularExpressions.Regex.IsMatch(atom,"^[+-]?[0-9]+$"))return new('v',long.Parse(atom));if(atom=="#t"||atom=="#f")return new('v',atom=="#t");if(atom[0]=='#')throw new Exception("bad token: "+atom);return new('v',new Symbol(atom));}
        public object Datum()=>From(Next());
        object From(Token t){if(t.Kind=='v')return t.Value!;if(t.Kind=='\'')return List(new object[]{new Symbol("quote"),Datum()});if(t.Kind!='(')throw new Exception("unexpected "+t.Kind);List<object>a=new();while(true){t=Next();if(t.Kind==')')return List(a);if(t.Kind=='.'&&a.Count>0){object tail=Datum();if(Next().Kind!=')')throw new Exception("expected )");return List(a,tail);}a.Add(From(t));}}
    }
    static void Main(){List<string>lines=new();string? s;while((s=Console.ReadLine())!=null&&s!="(exit)")lines.Add(s);Reader r=new(lines);Environment e=Global();while(!r.End()){object x;try{x=r.Datum();}catch(Exception err){Line("Error: read: "+err.Message);if(err.Message=="unexpected end of input")break;r.Skip();continue;}try{object v=Evaluate(x,e);if(!ReferenceEquals(v,Void))Line(Repr(v));}catch(Exception err){Line("Error: "+err.Message);}}if(mid)Write("\n");}
}
