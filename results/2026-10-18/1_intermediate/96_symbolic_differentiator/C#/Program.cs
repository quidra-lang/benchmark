using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

readonly struct Rational : IComparable<Rational>, IEquatable<Rational>
{
    public readonly long P, Q;
    public Rational(long p, long q = 1) { if(q==0) throw new InvalidOperationException("division by zero"); if(q<0){p=-p;q=-q;} long a=Math.Abs(p),b=q;while(b!=0){long t=a%b;a=b;b=t;}P=p/a;Q=q/a; }
    public int CompareTo(Rational b) => (P*b.Q).CompareTo(b.P*Q);
    public bool Equals(Rational b) => P==b.P && Q==b.Q;
    public override bool Equals(object? b) => b is Rational r && Equals(r);
    public override int GetHashCode() => HashCode.Combine(P,Q);
    public static Rational operator +(Rational a,Rational b) => new(a.P*b.Q+b.P*a.Q,a.Q*b.Q);
    public static Rational operator *(Rational a,Rational b) => new(a.P*b.P,a.Q*b.Q);
    public static Rational operator -(Rational a) => new(-a.P,a.Q);
    public static bool operator ==(Rational a,Rational b) => a.Equals(b);
    public static bool operator !=(Rational a,Rational b) => !a.Equals(b);
}
enum Kind { Variable, Sum, Product, Power, Function, Number }
sealed record Expr(Kind Kind, Rational Value, string Name, Expr[] Args);
sealed record Syntax(string Op, Expr? Value, Syntax[] Args);
static class Program
{
    static readonly HashSet<string> Functions = new() {"sin","cos","tan","exp","ln","sqrt"};
    static Expr Num(long p,long q=1) => new(Kind.Number,new Rational(p,q),"",[]);
    static Expr Num(Rational q) => new(Kind.Number,q,"",[]);
    static Expr Node(Kind k,Expr[] a,string s="") => new(k,new Rational(0),s,a);
    static readonly Expr Zero=Num(0),One=Num(1),Minus=Num(-1),Half=Num(1,2);
    static int Compare(Expr a,Expr b) {
        if(a.Kind!=b.Kind)return a.Kind.CompareTo(b.Kind);
        if(a.Kind==Kind.Number)return a.Value.CompareTo(b.Value);
        int c=StringComparer.Ordinal.Compare(a.Name,b.Name);if(c!=0)return c;
        for(int i=0;i<Math.Min(a.Args.Length,b.Args.Length);i++){c=Compare(a.Args[i],b.Args[i]);if(c!=0)return c;}
        return a.Args.Length.CompareTo(b.Args.Length);
    }
    static bool Equal(Expr a,Expr b) => Compare(a,b)==0;
    static bool Integer(Expr f) => f.Kind==Kind.Number && f.Value.Q==1;
    static bool Negative(Expr f) => f.Kind==Kind.Power && f.Args[1].Kind==Kind.Number && f.Args[1].Value.P<0;
    static Expr Base(Expr f) => f.Kind==Kind.Power?f.Args[0]:f;
    static Expr Exponent(Expr f) => f.Kind==Kind.Power?f.Args[1]:One;
    static (Rational,Expr[]) Coefficient(Expr f) {
        if(f.Kind==Kind.Number)return (f.Value,[]);
        if(f.Kind==Kind.Product)return f.Args[0].Kind==Kind.Number?(f.Args[0].Value,f.Args[1..]):(new Rational(1),f.Args);
        return (new Rational(1),[f]);
    }
    static Expr Product(Rational c,Expr[] a) {
        if(a.Length==0)return Num(c);if(c!=new Rational(1))a=[Num(c),..a];return a.Length==1?a[0]:Node(Kind.Product,a);
    }
    static int ExponentCompare(Expr a,Expr b) {
        if(a.Kind==Kind.Number && b.Kind!=Kind.Number)return -1;
        if(a.Kind!=Kind.Number && b.Kind==Kind.Number)return 1;return Compare(a,b);
    }
    static int TermCompare(Expr a,Expr b) {
        Expr[] x=Coefficient(a).Item2,y=Coefficient(b).Item2;
        List<Expr> bases=[];foreach(Expr f in x.Concat(y)){Expr v=Base(f);if(!bases.Any(t=>Equal(t,v)))bases.Add(v);}bases.Sort(Compare);
        foreach(Expr f in bases){Expr? s=x.FirstOrDefault(t=>Equal(Base(t),f)),t=y.FirstOrDefault(g=>Equal(Base(g),f));int c=ExponentCompare(t==null?Zero:Exponent(t),s==null?Zero:Exponent(s));if(c!=0)return c;}return 0;
    }
    static Expr Add(params Expr[] operands) {
        List<Expr> terms=[];foreach(Expr f in operands){if(f.Kind==Kind.Sum)terms.AddRange(f.Args);else if(f.Kind==Kind.Product && f.Args.Length==2 && f.Args[0].Kind==Kind.Number && f.Args[1].Kind==Kind.Sum)foreach(Expr t in f.Args[1].Args)terms.Add(Mul(f.Args[0],t));else terms.Add(f);}
        List<Expr[]> keys=[];List<Rational> values=[];
        foreach(Expr f in terms){var(c,m)=Coefficient(f);int i=keys.FindIndex(a=>a.Length==m.Length && a.Zip(m).All(p=>Equal(p.First,p.Second)));if(i<0){keys.Add(m);values.Add(c);}else values[i]+=c;}
        List<Expr> built=[];for(int i=0;i<keys.Count;i++)if(values[i].P!=0)built.Add(Product(values[i],keys[i]));built.Sort(TermCompare);return built.Count==0?Zero:built.Count==1?built[0]:Node(Kind.Sum,built.ToArray());
    }
    static Expr Mul(params Expr[] operands) {
        Rational c=new(1);List<Expr>bases=[];List<List<Expr>>groups=[];
        foreach(Expr f in operands.SelectMany(t=>t.Kind==Kind.Product?t.Args:[t])){
            if(f.Kind==Kind.Number)c*=f.Value;else{Expr b=Base(f);int i=bases.FindIndex(t=>Equal(t,b));if(i<0){bases.Add(b);groups.Add([]);i=groups.Count-1;}groups[i].Add(f);}
        }
        if(c.P==0)return Zero;List<Expr>r=[];for(int i=0;i<groups.Count;i++)r.Add(groups[i].Count==1?groups[i][0]:Power(bases[i],Add(groups[i].Select(Exponent).ToArray())));
        bool regroup=r.Any(f=>f.Kind is Kind.Number or Kind.Product);for(int i=0;i<r.Count;i++)for(int j=0;j<i;j++)if(Equal(Base(r[i]),Base(r[j])))regroup=true;
        if(regroup)return Mul([Num(c),..r]);r.Sort((a,b)=>Compare(Base(a),Base(b)));return Product(c,r.ToArray());
    }
    static long? Root(long v,long d) {
        if(v==1)return 1;if(d>20)return null;long r=(long)Math.Round(Math.Pow(v,1.0/d));for(long s=Math.Max(0,r-1);s<=r+1;s++){long a=1;for(int i=0;i<d && a<=v;i++)a*=s;if(a==v)return s;}return null;
    }
    static Expr RationalPower(Rational b,long n) {
        if(n<0){b=new Rational(b.Q,b.P);n=-n;}Rational r=new(1);while(n>0){if(n%2!=0)r*=b;n/=2;if(n>0)b*=b;}return Num(r);
    }
    static Expr Power(Expr b,Expr x) {
        if(Equal(x,Zero))return One;if(Equal(x,One))return b;
        if(b.Kind==Kind.Number){if(Equal(b,One))return One;if(x.Kind!=Kind.Number)return Node(Kind.Power,[b,x]);if(b.Value.P==0){if(x.Value.P>0)return Zero;throw new InvalidOperationException("division by zero");}if(Integer(x))return RationalPower(b.Value,x.Value.P);if(b.Value.P>0){long? s=Root(b.Value.P,x.Value.Q),t=Root(b.Value.Q,x.Value.Q);if(s.HasValue && t.HasValue)return RationalPower(new Rational(s.Value,t.Value),x.Value.P);}}
        else if(Integer(x)){if(b.Kind==Kind.Power)return Power(b.Args[0],Mul(b.Args[1],x));if(b.Kind==Kind.Product)return Mul(b.Args.Select(f=>Power(f,x)).ToArray());}
        return Node(Kind.Power,[b,x]);
    }
    static Expr Fn(string s,Expr a) {
        if(s=="sqrt")return Power(a,Half);if(Equal(a,Zero) && (s is "sin" or "tan"))return Zero;if(Equal(a,Zero) && (s is "cos" or "exp"))return One;if(Equal(a,One) && s=="ln")return Zero;
        if((s is "sin" or "cos" or "tan") && Coefficient(a).Item1.P<0){Expr r=Fn(s,Mul(Minus,a));return s=="cos"?r:Mul(Minus,r);}
        if(a.Kind==Kind.Function && ((s=="exp" && a.Name=="ln")||(s=="ln" && a.Name=="exp")))return a.Args[0];return Node(Kind.Function,[a],s);
    }
    static SortedSet<string> Variables(Expr f) {SortedSet<string>r=new(StringComparer.Ordinal);if(f.Kind==Kind.Variable)r.Add(f.Name);foreach(Expr a in f.Args)r.UnionWith(Variables(a));return r;}
    static Expr Derivative(Expr f,string v) {
        if(f.Kind==Kind.Number)return Zero;if(f.Kind==Kind.Variable)return f.Name==v?One:Zero;
        if(f.Kind==Kind.Sum)return Add(f.Args.Select(t=>Derivative(t,v)).ToArray());
        if(f.Kind==Kind.Product)return Add(f.Args.Select((_,i)=>Mul(f.Args.Select((t,j)=>i==j?Derivative(t,v):t).ToArray())).ToArray());
        if(f.Kind==Kind.Power){Expr b=f.Args[0],x=f.Args[1];if(!Variables(x).Contains(v))return Mul(x,Power(b,Add(x,Minus)),Derivative(b,v));if(!Variables(b).Contains(v))return Mul(f,Fn("ln",b),Derivative(x,v));return Mul(f,Add(Mul(Derivative(x,v),Fn("ln",b)),Mul(x,Derivative(b,v),Power(b,Minus))));}
        Expr a=f.Args[0],h=f.Name switch {"sin"=>Fn("cos",a),"cos"=>Mul(Minus,Fn("sin",a)),"tan"=>Power(Fn("cos",a),Num(-2)),"exp"=>f,_=>Power(a,Minus)};return Mul(h,Derivative(a,v));
    }
    static Expr Rebuild(Expr f,Expr[] a) => f.Kind switch {Kind.Sum=>Add(a),Kind.Product=>Mul(a),Kind.Power=>Power(a[0],a[1]),_=>Fn(f.Name,a[0])};
    static Expr Substitute(Expr f,Dictionary<string,Expr>m) {if(f.Kind==Kind.Variable)return m.GetValueOrDefault(f.Name,f);if(f.Kind==Kind.Number)return f;return Rebuild(f,f.Args.Select(t=>Substitute(t,m)).ToArray());}
    static Expr[] Terms(Expr f) => f.Kind==Kind.Sum?f.Args:[f];
    static Expr Distribute(Expr a,Expr b) => Add(Terms(a).SelectMany(x=>Terms(b).Select(y=>Mul(x,y))).ToArray());
    static Expr Expand(Expr f) {if(f.Kind is Kind.Variable or Kind.Number)return f;Expr[] a=f.Args.Select(Expand).ToArray();if(f.Kind==Kind.Product)return a.Aggregate(Distribute);if(f.Kind==Kind.Power && a[0].Kind==Kind.Sum && Integer(a[1]) && a[1].Value.P>0){Expr r=a[0];for(int i=1;i<a[1].Value.P;i++)r=Distribute(r,a[0]);return r;}return Rebuild(f,a);}
    static double Numeric(Expr f) {
        if(f.Kind==Kind.Number)return (double)f.Value.P/f.Value.Q;
        if(f.Kind==Kind.Sum)return f.Args.Aggregate(0.0,(r,t)=>r+Numeric(t));if(f.Kind==Kind.Product)return f.Args.Aggregate(1.0,(r,t)=>r*Numeric(t));
        if(f.Kind==Kind.Power){double u=Numeric(f.Args[0]),z=Numeric(f.Args[1]);bool integral=f.Args[1].Kind==Kind.Number?Integer(f.Args[1]):z==Math.Truncate(z);if(u<0 && !integral)throw new InvalidOperationException("domain error");return Equal(f.Args[1],Half)?Math.Sqrt(u):Math.Pow(u,z);}
        double a=Numeric(f.Args[0]);if(f.Name=="ln" && a<=0)throw new InvalidOperationException("domain error");return f.Name switch {"sin"=>Math.Sin(a),"cos"=>Math.Cos(a),"tan"=>Math.Tan(a),"exp"=>Math.Exp(a),_=>Math.Log(a)};
    }
    static bool Atomic(Expr f) => f.Kind is Kind.Variable or Kind.Function || (Integer(f) && f.Value.P>=0) || (f.Kind==Kind.Power && Equal(f.Args[1],Half));
    static string Atom(Expr f) => Atomic(f)?Show(f):"("+Show(f)+")";
    static string ShowPower(Expr b,Expr x) => Equal(x,Half)?"sqrt("+Show(b)+")":Atom(b)+"^"+Atom(x);
    static string Factor(Expr f) => f.Kind==Kind.Sum?"("+Show(f)+")":f.Kind==Kind.Power?ShowPower(f.Args[0],f.Args[1]):Show(f);
    static string Quotient(Rational c,Expr[] a) {
        List<string>top=[],bottom=[];if(Math.Abs(c.P)!=1)top.Add(Math.Abs(c.P).ToString());if(c.Q!=1)bottom.Add(c.Q.ToString());foreach(Expr f in a)if(Negative(f)){Expr r=Num(-f.Args[1].Value);bottom.Add(Equal(r,One)?Factor(f.Args[0]):ShowPower(f.Args[0],r));}else top.Add(Factor(f));string s=top.Count==0?"1":string.Join("*",top);if(bottom.Count==1)s+="/"+bottom[0];else if(bottom.Count>1)s+="/("+string.Join("*",bottom)+")";return c.P<0?"-"+s:s;
    }
    static string Show(Expr f) {
        if(f.Kind==Kind.Number)return f.Value.P+(f.Value.Q==1?"":"/"+f.Value.Q);if(f.Kind==Kind.Variable)return f.Name;if(f.Kind==Kind.Function)return f.Name+"("+Show(f.Args[0])+")";if(f.Kind==Kind.Power)return Negative(f)?Quotient(new Rational(1),[f]):ShowPower(f.Args[0],f.Args[1]);if(f.Kind==Kind.Product){var(c,a)=Coefficient(f);return Quotient(c,a);}return f.Args.Select(Show).Aggregate((a,b)=>a+(b.StartsWith('-')?" - "+b[1..]:" + "+b));
    }
    sealed class Parser {
        readonly List<string> tokens=[];readonly Dictionary<string,Expr> names;int position;
        string Peek => position<tokens.Count?tokens[position]:"";
        void Unexpected() => throw new InvalidOperationException(position==tokens.Count?"unexpected end of expression":"unexpected '"+Peek+"'");
        bool Accept(string s){if(Peek!=s)return false;position++;return true;}
        void Expect(string s){if(!Accept(s))Unexpected();}
        public Parser(string text,Dictionary<string,Expr> n) {names=n;foreach(Match m in Regex.Matches(text,@"[0-9]+|[a-z][a-z0-9]*|[A-Z][A-Z0-9]*|[-+*/^()]| +|.")){string t=m.Value;if(t[0]==' ')continue;if(!Regex.IsMatch(t,@"\A[a-zA-Z0-9+*/^()-]+\z"))throw new InvalidOperationException("invalid character '"+t+"'");tokens.Add(t);}}
        Syntax AtomTree(){string t=Peek;if(t=="")Unexpected();if(Accept("(")){Syntax a=Expression();Expect(")");return a;}if(!char.IsAsciiLetterOrDigit(t[0]))Unexpected();position++;if(char.IsAsciiDigit(t[0]))return new("",Num(long.Parse(t)),[]);if(char.IsAsciiLetterUpper(t[0])){if(!names.TryGetValue(t,out Expr? f))throw new InvalidOperationException("undefined name '"+t+"'");return new("",f,[]);}if(!Functions.Contains(t))return new("",Node(Kind.Variable,[],t),[]);Expect("(");Syntax inner=Expression();Expect(")");return new(t,null,[inner]);}
        Syntax Unary(){if(Accept("-"))return new("neg",null,[Unary()]);Syntax a=AtomTree();return Accept("^")?new("^",null,[a,Unary()]):a;}
        Syntax Term(){Syntax a=Unary();while(Peek is "*" or "/"){string op=tokens[position++];a=new(op,null,[a,Unary()]);}return a;}
        Syntax Expression(){Syntax a=Term();while(Peek is "+" or "-"){string op=tokens[position++];a=new(op,null,[a,Term()]);}return a;}
        static Expr Evaluate(Syntax t){if(t.Value!=null)return t.Value;Expr[] a=t.Args.Select(Evaluate).ToArray();return t.Op switch {"+"=>Add(a),"-"=>Add(a[0],Mul(Minus,a[1])),"*"=>Mul(a),"/"=>Mul(a[0],Power(a[1],Minus)),"^"=>Power(a[0],a[1]),"neg"=>Mul(Minus,a[0]),_=>Fn(t.Op,a[0])};}
        public Expr Parse(){Syntax t=Expression();if(position<tokens.Count)Unexpected();return Evaluate(t);}
    }
    static bool Variable(string s) => Regex.IsMatch(s,@"\A[a-z][a-z0-9]*\z") && !Functions.Contains(s);
    static bool RationalLiteral(string s) => Regex.IsMatch(s,@"\A-?[0-9]+(?:/[0-9]+)?\z");
    static Expr Literal(string s){if(!RationalLiteral(s))throw new InvalidOperationException("invalid number '"+s+"'");string[] a=s.Split('/');return Num(long.Parse(a[0]),a.Length==1?1:long.Parse(a[1]));}
    static readonly Dictionary<string,string> Signatures=new(){{"SIMPLIFY","e"},{"EXPAND","e"},{"DIFF","ev"},{"DIFFN","evn"},{"GRAD","e"},{"HESSIAN","e"},{"IMPLICIT","evv"},{"SUBST","eve"},{"EVAL","ea"},{"TANGENT","evc"},{"LIMIT","evc"},{"TAYLOR","evcn"}};
    static string[] Command(string line,Dictionary<string,Expr> names) {
        int p=line.IndexOf(' ');string c=p<0?line:line[..p],arg=p<0?"":line[(p+1)..];
        if(c=="LET"){int i=arg.IndexOf('=');if(i<0)throw new InvalidOperationException("wrong number of arguments");string s=arg[..i].Trim(' ');if(!Regex.IsMatch(s,@"\A[A-Z][A-Z0-9]*\z"))throw new InvalidOperationException("invalid name '"+s+"'");Expr f=new Parser(arg[(i+1)..].Trim(' '),names).Parse();names[s]=f;return [s+" = "+Show(f)];}
        if(!Signatures.TryGetValue(c,out string? sig))throw new InvalidOperationException("unknown command "+c);
        string[] fields=p<0?[]:arg.Split(';').Select(s=>s.Trim(' ')).ToArray();if(c=="EVAL"?fields.Length is not (1 or 2):fields.Length!=sig.Length)throw new InvalidOperationException("wrong number of arguments");
        Expr[] forms=Enumerable.Repeat(Zero,fields.Length).ToArray();int n=0;
        for(int i=0;i<fields.Length;i++){string s=fields[i];switch(sig[i]){case 'e':forms[i]=new Parser(s,names).Parse();break;case 'v':if(!Variable(s))throw new InvalidOperationException("invalid variable '"+s+"'");break;case 'n':if(!Regex.IsMatch(s,@"\A[1-8]\z"))throw new InvalidOperationException("invalid order '"+s+"'");n=int.Parse(s);break;case 'c':forms[i]=Literal(s);break;}}
        Expr f0=forms[0];string v=fields.Length>1?fields[1]:"";List<string>output=[];
        switch(c){
        case "SIMPLIFY":return ["simplified: "+Show(f0)];case "EXPAND":return ["expanded: "+Show(Expand(f0))];case "DIFF":return ["d/d"+v+" = "+Show(Derivative(f0,v))];
        case "DIFFN":for(int k=1;k<=n;k++){f0=Derivative(f0,v);output.Add($"d^{k}/d{v}^{k} = {Show(f0)}");}return output.ToArray();
        case "GRAD":case "HESSIAN":string[] vs=Variables(f0).ToArray();if(vs.Length==0)return ["no variables"];for(int i=0;i<vs.Length;i++){Expr d=Derivative(f0,vs[i]);if(c=="GRAD")output.Add($"d/d{vs[i]} = {Show(d)}");else for(int j=i;j<vs.Length;j++)output.Add($"d2/d{vs[i]}d{vs[j]} = {Show(Derivative(d,vs[j]))}");}return output.ToArray();
        case "IMPLICIT":string w=fields[2];if(v==w)throw new InvalidOperationException("same variable");return [$"d{w}/d{v} = {Show(Mul(Minus,Derivative(f0,v),Power(Derivative(f0,w),Minus)))}"];
        case "SUBST":return ["substituted: "+Show(Substitute(f0,new(){{v,forms[2]}}))];
        case "EVAL":Dictionary<string,Expr>values=new();foreach(string word in v.Split(' ',StringSplitOptions.RemoveEmptyEntries)){int i=word.IndexOf('=');string s=i<0?word:word[..i],t=i<0?"":word[(i+1)..];if(i<0||!Variable(s)||!RationalLiteral(t))throw new InvalidOperationException("invalid assignment '"+word+"'");Expr q=Literal(t);if(values.ContainsKey(s))throw new InvalidOperationException("duplicate variable "+s);values[s]=q;}foreach(string s in Variables(f0))if(!values.ContainsKey(s))throw new InvalidOperationException("no value for "+s);Expr r=Substitute(f0,values);return [r.Kind==Kind.Number?"exact: "+Show(r):"approx: "+Numeric(r).ToString("F6",CultureInfo.InvariantCulture)];
        }
        Expr x=forms[2];Dictionary<string,Expr>point=new(){{v,x}};
        if(c=="TANGENT"){Expr m=Substitute(Derivative(f0,v),point),y=Substitute(f0,point),z=Node(Kind.Variable,[],v);string t="tangent: y = "+Show(Add(Mul(m,z),y,Mul(Num(-x.Value),m)));if(Equal(m,Zero))return [t,"normal: "+v+" = "+Show(x)];Expr k=Power(m,Minus);return [t,"normal: y = "+Show(Add(Mul(Minus,k,z),y,Mul(x,k)))];}
        if(c=="LIMIT"){List<Expr>top=[],bottom=[];foreach(Expr t in f0.Kind==Kind.Product?f0.Args:[f0])if(Negative(t))bottom.Add(Power(t.Args[0],Num(-t.Args[1].Value)));else top.Add(t);Expr g=Mul(top.ToArray()),h=Mul(bottom.ToArray());for(int i=0;i<=5;i++){Expr a=Substitute(g,point),b=Substitute(h,point);if(!Equal(b,Zero))return ["limit: "+Show(Mul(a,Power(b,Minus)))];if(!Equal(a,Zero))return ["limit: unbounded"];if(i<5){g=Derivative(g,v);h=Derivative(h,v);}}return ["limit: unknown"];}
        List<Expr>ds=[f0],ps=[];for(int i=0;i<n;i++)ds.Add(Derivative(ds[^1],v));long fac=1;for(int i=0;i<=n;i++){if(i>0)fac*=i;Expr co=Mul(Substitute(ds[i],point),Num(1,fac));ps.Add(Mul(co,Power(Add(Node(Kind.Variable,[],v),Num(-x.Value)),Num(i))));}return ["taylor: "+Show(Expand(Add(ps.ToArray())))];
    }
    static void Main(){int n=int.Parse(Console.ReadLine()!);Dictionary<string,Expr>names=new();while(n-->0){try{foreach(string s in Command(Console.ReadLine()!,names))Console.WriteLine(s);}catch(InvalidOperationException e){Console.WriteLine("error: "+e.Message);}}}
}
