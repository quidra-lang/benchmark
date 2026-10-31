using System;
using System.Collections.Generic;
using System.Linq;
using Comp = System.Collections.Generic.Dictionary<string, long>;
class Program
{
    static readonly string[] Symbols="H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe".Split(' ');
    static readonly long[] Weights={
        1008,4003,6941,9012,10811,12011,14007,15999,18998,20180,22990,24305,26982,28086,30974,32065,35453,39948,39098,40078,44956,47867,50942,51996,54938,55845,58933,58693,63546,65380,69723,72630,74922,78971,79904,83798,85468,87620,88906,91224,92906,95950,98000,101070,102906,106420,107868,112414,114818,118710,121760,127600,126904,131293
    };
    static readonly Comp W=Symbols.Select((s,i)=>(s,i)).ToDictionary(x=>x.s,x=>Weights[x.i]);
    static readonly Comp Valence=new(){
        {
            "H",1
        },{
            "F",1
        },{
            "Cl",1
        },{
            "Br",1
        },{
            "I",1
        },{
            "O",2
        },{
            "S",2
        },{
            "Se",2
        },{
            "B",3
        },{
            "N",3
        },{
            "P",3
        },{
            "As",3
        },{
            "C",4
        },{
            "Si",4
        },{
            "Ge",4
        }
    };
    static readonly Comp Metals=new(){
        {
            "Li",1
        },{
            "Na",1
        },{
            "K",1
        },{
            "Rb",1
        },{
            "Be",2
        },{
            "Mg",2
        },{
            "Ca",2
        },{
            "Sr",2
        },{
            "Al",3
        }
    };
    static readonly Dictionary<string,int> Counts=new(){
        {
            "ELEMENT",1
        },{
            "PARSE",1
        },{
            "MASS",1
        },{
            "PERCENT",1
        },{
            "EMPIRICAL",1
        },{
            "DBE",1
        },{
            "OXSTATE",1
        },{
            "MOLES",2
        },{
            "GRAMS",2
        },{
            "MOLECULAR",2
        },{
            "SALT",2
        },{
            "HEAT",2
        },{
            "COMBUST",3
        },{
            "HEATS",0
        },{
            "DERIVE",-2
        },{
            "BALANCE",-1
        },{
            "MATRIX",-1
        },{
            "CHECK",-1
        },{
            "DELTAH",-1
        },{
            "REDOX",-3
        },{
            "HALF",-3
        },{
            "STOICH",-4
        },{
            "LIMITING",-4
        },{
            "YIELD",-4
        }
    };
    static void Fail(string s)=>throw new ArgumentException("error: "+s);
    static long Gcd(long a,long b){
        a=Math.Abs(a);
        b=Math.Abs(b);
        while(b!=0)(a,b)=(b,a%b);
        return a;
    }
    static string Dec(long n,int d){
        long p=1;
        for(int i=0;i<d;i++)p*=10;
        return n/p+"."+(n%p).ToString().PadLeft(d,'0');
    }
    static string Ent(long n)=>(n<0?"-":"")+Dec(Math.Abs(n),2);
    static string Signed(long n)=>(n>0?"+":"")+n;
    readonly struct Fraction
    {
        public readonly long N,D;
        public Fraction(long n,long d=1){
            long g=Gcd(n,d);
            N=n/g*(d<0?-1:1);
            D=Math.Abs(d)/g;
        }
        public static Fraction operator -(Fraction a,Fraction b)=>new(a.N*b.D-b.N*a.D,a.D*b.D);
        public static Fraction operator *(Fraction a,Fraction b)=>new(a.N*b.N,a.D*b.D);
        public static Fraction operator /(Fraction a,Fraction b)=>new(a.N*b.D,a.D*b.N);
        public override string ToString()=>Signed(N)+(D==1?"":"/"+D);
    }
    record Formula(Comp C,long Q){
        public long Mass=>Program.Mass(C);
    }
    record Species(string F,string State,long Coefficient,Formula Formula){
        public string Name=>F+State;
        public long Mass=>Formula.Mass;
    }
    record Equation(List<Species> List,int R){
        public long[] Signs=>Enumerable.Range(0,List.Count).Select(i=>i<R?1L:-1L).ToArray();
    }
    static string[] Order(Comp c){
        string[] es=c.Keys.OrderBy(e=>e,StringComparer.Ordinal).ToArray();
        return c.ContainsKey("C")?new[]{
            "C"
        }.Concat(c.ContainsKey("H")?new[]{
            "H"
        }:Array.Empty<string>()).Concat(es.Where(e=>e!="C"&&e!="H")).ToArray():es;
    }
    static Comp Add(Comp a,Comp b,long k=1){
        foreach(var (e,n) in b)a[e]=a.GetValueOrDefault(e)+n*k;
        return a;
    }
    static Comp Scale(Comp c,long k)=>c.ToDictionary(x=>x.Key,x=>x.Value*k);
    static long Mass(Comp c)=>c.Sum(x=>x.Value*W[x.Key]);
    static string Hill(Comp c,long q=0)=>string.Concat(Order(c).Select(e=>e+(c[e]==1?"":c[e].ToString())))+(q==0?"":"^"+(Math.Abs(q)==1?"":Math.Abs(q).ToString())+(q>0?"+":"-"));
    class Parser
    {
        readonly string text;
        int p;
        public readonly List<string> Seen=new();
        public Parser(string s){
            text=s;
        }
        char Peek()=>p<text.Length?text[p]:'\0';
        long Number(){
            int start=p;
            while(Peek()>='0'&&Peek()<='9')p++;
            if(start==p)return 1;
            if(text[start]=='0')throw new FormatException();
            return long.Parse(text[start..p]);
        }
        Comp Sequence(){
            Comp c=new();
            int items=0;
            while(true){
                char ch=Peek();
                Comp item;
                if(ch>='A'&&ch<='Z'){
                    string e=text[p++].ToString();
                    if(Peek()>='a'&&Peek()<='z')e+=text[p++];
                    Seen.Add(e);
                    item=new(){
                        {
                            e,1
                        }
                    };
                }else if(ch=='('||ch=='['){
                    p++;
                    item=Sequence();
                    if(Peek()!=(ch=='('?')':']'))throw new FormatException();
                    p++;
                }else break;
                Add(c,item,Number());
                items++;
            }
            if(items==0)throw new FormatException();
            return c;
        }
        public Formula Parse(){
            Comp c=Sequence();
            while(Peek()=='.'){
                p++;
                long k=Number();
                Add(c,Sequence(),k);
            }
            long q=0;
            if(Peek()=='^'){
                p++;
                long k=Number();
                char ch=Peek();
                if(ch!='+'&&ch!='-')throw new FormatException();
                p++;
                q=ch=='+'?k:-k;
            }
            if(p!=text.Length)throw new FormatException();
            return new(c,q);
        }
    }
    static Formula ReadFormula(string text,string? word=null){
        Parser p=new(text);
        Formula f;
        try{
            f=p.Parse();
        }catch(FormatException){
            Fail("invalid formula "+(word??text));
            throw;
        }
        foreach(string e in p.Seen)if(!W.ContainsKey(e))Fail("unknown element "+e);
        return f;
    }
    static Species ReadSpecies(string word,bool check=false){
        string state="",f=word;
        long k=1;
        foreach(string s in new[]{
            "(s)","(l)","(g)","(aq)"
        })if(word.EndsWith(s,StringComparison.Ordinal)){
            state=s;
            f=word[..^s.Length];
            break;
        }
        if(check&&f.Length>0&&char.IsAsciiDigit(f[0])){
            int i=0;
            while(i<f.Length&&char.IsAsciiDigit(f[i]))i++;
            if(f[0]=='0')Fail("invalid formula "+word);
            k=long.Parse(f[..i]);
            f=f[i..];
        }
        return new(f,state,k,ReadFormula(f,word));
    }
    static Equation ReadEquation(string[] a,bool check=false){
        bool valid=a.Length%2==1;
        int arrow=-1;
        for(int i=0;i<a.Length;i++){
            bool op=a[i]=="+"||a[i]=="->";
            if(i%2==1){
                if(!op)valid=false;
                if(a[i]=="->"){
                    if(arrow>=0)valid=false;
                    arrow=i;
                }
            }else if(op)valid=false;
        }
        if(!valid||arrow<0)Fail("malformed equation");
        return new(a.Where((_,i)=>i%2==0).Select(s=>ReadSpecies(s,check)).ToList(),(arrow+1)/2);
    }
    static long Quantity(string s){
        if(!System.Text.RegularExpressions.Regex.IsMatch(s,@"\A(0|[1-9][0-9]{0,3})(\.[0-9]{1,3})?\z"))Fail("invalid quantity "+s);
        string[] p=s.Split('.');
        long q=long.Parse(p[0])*1000+(p.Length==1?0:long.Parse(p[1].PadRight(3,'0')));
        if(q==0)Fail("invalid quantity "+s);
        return q;
    }
    static long Enthalpy(string s){
        if(!System.Text.RegularExpressions.Regex.IsMatch(s,@"\A-?(0|[1-9][0-9]{0,4})(\.[0-9]{1,2})?\z"))Fail("invalid enthalpy "+s);
        string[] p=s.TrimStart('-').Split('.');
        return (s[0]=='-'?-1:1)*(long.Parse(p[0])*100+(p.Length==1?0:long.Parse(p[1].PadRight(2,'0'))));
    }
    static (string[] Labels,long[][] Rows) Matrix(List<Species> list,long[] signs){
        Comp all=new();
        foreach(Species s in list)Add(all,s.Formula.C);
        string[] labels=Order(all).Append("charge").ToArray();
        return(labels,labels.Select(e=>list.Select((s,i)=>signs[i]*(e=="charge"?s.Formula.Q:s.Formula.C.GetValueOrDefault(e))).ToArray()).ToArray());
    }
    static (int Rank,List<long[]> Basis) Nullspace(long[][] rows,int n){
        Fraction[][] a=rows.Select(r=>r.Select(x=>new Fraction(x)).ToArray()).ToArray();
        List<int> piv=new(),free=new();
        for(int j=0;j<n;j++){
            int r=piv.Count,i=r;
            while(i<a.Length&&a[i][j].N==0)i++;
            if(i==a.Length){
                free.Add(j);
                continue;
            }
            (a[r],a[i])=(a[i],a[r]);
            Fraction t=a[r][j];
            a[r]=a[r].Select(x=>x/t).ToArray();
            for(int k=0;k<a.Length;k++)if(k!=r&&a[k][j].N!=0){
                Fraction f=a[k][j];
                for(int z=0;z<n;z++)a[k][z]=a[k][z]-f*a[r][z];
            }
            piv.Add(j);
        }
        List<long[]> basis=new();
        foreach(int f in free){
            Fraction[] v=Enumerable.Range(0,n).Select(_=>new Fraction(0)).ToArray();
            v[f]=new(1);
            for(int i=0;i<piv.Count;i++)v[piv[i]]=new(-a[i][f].N,a[i][f].D);
            long l=1;
            foreach(Fraction x in v)l=l/Gcd(l,x.D)*x.D;
            long[] b=v.Select(x=>x.N*(l/x.D)).ToArray();
            long g=b.Aggregate(0L,Gcd);
            basis.Add(b.Select(x=>x/g).ToArray());
        }
        return(piv.Count,basis);
    }
    static long[] Coefficients(List<Species> list,long[] signs,int? required=null){
        var ns=Nullspace(Matrix(list,signs).Rows,list.Count);
        int d=ns.Basis.Count;
        if(d>=2)throw new InvalidOperationException($"AMBIGUOUS (nullity {d})");
        if(d==0)throw new InvalidOperationException("IMPOSSIBLE");
        long[] v=ns.Basis[0];
        if(v[0]<0)v=v.Select(x=>-x).ToArray();
        if(v.Take(required??list.Count).Any(x=>x<=0))throw new InvalidOperationException("IMPOSSIBLE");
        return v;
    }
    static string Term(string s,long k)=>(k==1?"":k.ToString())+s;
    static string Notation(Equation eq,long[] v){
        string[] t=eq.List.Select((s,i)=>Term(s.Name,v[i])).ToArray();
        return string.Join(" + ",t.Take(eq.R))+" -> "+string.Join(" + ",t.Skip(eq.R));
    }
    static string Gas(Species s,long n,long d)=>s.State=="(g)"?" "+Dec(n*22414/d,3)+" L":"";
    static List<string> Ratios(Comp a){
        string[] es=Order(a);
        string f=es[0];
        foreach(string e in es)if(a[e]*W[f]<a[f]*W[e])f=e;
        List<string> output=es.Select(e=>e+" "+Dec(1000*a[e]*W[f]/(W[e]*a[f]),3)).ToList();
        for(long k=1;k<=12;k++){
            Comp c=new();
            bool ok=true;
            foreach(string e in es){
                long n=k*a[e]*W[f],d=W[e]*a[f],i=(2*n+d)/(2*d);
                c[e]=i;
                if(20*Math.Abs(n-i*d)>d)ok=false;
            }
            if(ok){
                output.Add(Hill(c)+$" (k = {k})");
                return output;
            }
        }
        output.Add("no simple ratio");
        return output;
    }
    static string Group(string f,long k){
        string c=f.Split('^')[0];
        if(k==1)return c;
        int depth=0,last=-1;
        if(c[0]=='[')for(int i=0;i<c.Length;i++){
            if(c[i]=='[')depth++;
            if(c[i]==']'&&--depth==0){
                last=i;
                break;
            }
        }
        return (System.Text.RegularExpressions.Regex.IsMatch(c,@"\A[A-Z][a-z]?\z")||last==c.Length-1?c:"("+c+")")+k;
    }
    class Chemistry
    {
        readonly Comp heats=new();
        public List<string> Execute(string line){
            string[] all=line.Split(' ');
            string cmd=all[0];
            string[] a=all.Skip(1).ToArray();
            int n=a.Length;
            if(!Counts.TryGetValue(cmd,out int e))Fail("unknown command "+cmd);
            if((e>=0&&n!=e)||(e==-1&&n<1)||(e==-2&&(n<2||n%2!=0))||(e==-3&&n<2))Fail("wrong argument count for "+cmd);
            if(cmd=="ELEMENT"){
                if(!W.ContainsKey(a[0]))Fail("unknown element "+a[0]);
                return new(){
                    $"{a[0]} (Z = {Array.IndexOf(Symbols,a[0])+1}) {Dec(W[a[0]],3)} u"
                };
            }
            if(cmd=="HEATS")return heats.Count==0?new(){
                "no enthalpies"
            }:heats.Keys.OrderBy(s=>s,StringComparer.Ordinal).Select(s=>$"{s} {Ent(heats[s])} kJ/mol").ToList();
            if(cmd=="HEAT"){
                ReadSpecies(a[0]);
                long h=Enthalpy(a[1]);
                string text=$"dHf({a[0]}) = {Ent(h)} kJ/mol"+(heats.ContainsKey(a[0])?$" (was {Ent(heats[a[0]])})":"");
                heats[a[0]]=h;
                return new(){
                    text
                };
            }
            if(cmd=="DERIVE"){
                Comp b=new();
                for(int i=0;i<n;i+=2){
                    string s=a[i];
                    if(!W.ContainsKey(s))Fail("unknown element "+s);
                    if(b.ContainsKey(s))Fail("duplicate element "+s);
                    long q=Quantity(a[i+1]);
                    if(q>100000)Fail("invalid percentage "+a[i+1]);
                    b[s]=q;
                }
                long t=b.Values.Sum();
                if(Math.Abs(t-100000)>1000)Fail("percentages sum to "+Dec(t,3));
                return Ratios(b);
            }
            if(cmd=="COMBUST"){
                long sample=Quantity(a[0]),p=Quantity(a[1]),r=Quantity(a[2]),c=p*12011/44009,h=r*2016/18015,o=sample-c-h;
                if(c==0||h==0||100*o < -sample)Fail("inconsistent masses");
                Comp b=new(){
                    {
                        "C",c
                    },{
                        "H",h
                    }
                };
                if(100*o>sample)b["O"]=o;
                return Order(b).Select(s=>$"mass {s} {Dec(b[s],3)} g").Concat(Ratios(b)).ToList();
            }
            if(new[]{
                "PARSE","MASS","PERCENT","EMPIRICAL","DBE","OXSTATE","MOLES","GRAMS","MOLECULAR","SALT"
            }.Contains(cmd)){
                Formula f=ReadFormula(a[0]);
                Comp c=f.C;
                long q=f.Q,m=f.Mass;
                string[] es=Order(c);
                if(cmd=="PARSE")return new(){
                    $"{Hill(c,q)} ({string.Join(", ",es.Select(s=>$"{s} {c[s]}"))}; charge {Signed(q)})"
                };
                if(cmd=="MASS")return new(){
                    $"M({a[0]}) = {Dec(m,3)} g/mol"
                };
                if(cmd=="PERCENT")return es.Select(s=>$"{s} {Dec(10000*c[s]*W[s]/m,2)}%").ToList();
                if(cmd=="EMPIRICAL"){
                    long g=c.Values.Aggregate(0L,Gcd);
                    return new(){
                        $"{Hill(c.ToDictionary(x=>x.Key,x=>x.Value/g))} (n = {g})"
                    };
                }
                if(cmd=="DBE"){
                    if(q!=0)Fail("charged formula "+a[0]);
                    long t=2;
                    foreach(string s in es){
                        if(!Valence.ContainsKey(s))Fail("no valence for "+s);
                        t+=c[s]*(Valence[s]-2);
                    }
                    return new(){
                        "DBE = "+(t<0?"-":"")+Math.Abs(t)/2+"."+(t%2!=0?5:0)
                    };
                }
                if(cmd=="OXSTATE"){
                    Dictionary<string,Fraction> st=new();
                    string last="";
                    void Assign(string s,long x){
                        st[s]=new(x);
                        last=s;
                    }
                    if(es.Length==1)st[es[0]]=new(q,c[es[0]]);
                    else{
                        if(c.ContainsKey("F"))Assign("F",-1);
                        foreach(string s in es)if(Metals.ContainsKey(s))Assign(s,Metals[s]);
                        if(c.ContainsKey("H"))Assign("H",es.All(s=>s=="H"||Metals.ContainsKey(s))?-1:1);
                        if(c.ContainsKey("O"))Assign("O",-2);
                        else if(!c.ContainsKey("F"))foreach(string s in new[]{
                            "Cl","Br","I"
                        })if(c.ContainsKey(s)){
                            Assign(s,-1);
                            break;
                        }
                        string[] u=es.Where(s=>!st.ContainsKey(s)).ToArray();
                        if(u.Length>1)return new(){
                            "indeterminate: "+string.Join(" ",u)
                        };
                        long sum=st.Sum(x=>c[x.Key]*x.Value.N);
                        if(u.Length==1)st[u[0]]=new(q-sum,c[u[0]]);
                        else if(sum!=q)st[last]=new(q-sum+c[last]*st[last].N,c[last]);
                    }
                    return new(){
                        string.Join(", ",es.Select(s=>s+" "+st[s]))
                    };
                }
                if(cmd=="SALT"){
                    Formula b=ReadFormula(a[1]);
                    if(q<=0)Fail("not a cation "+a[0]);
                    if(b.Q>=0)Fail("not an anion "+a[1]);
                    foreach(string s in a)if(s.Contains('.'))Fail("hydrate ion "+s);
                    long g=Gcd(q,b.Q),x=-b.Q/g,y=q/g;
                    Comp z=Add(Scale(c,x),b.C,y);
                    return new(){
                        $"{Group(a[0],x)}{Group(a[1],y)} ({Hill(z)}, {Dec(Mass(z),3)} g/mol)"
                    };
                }
                if(cmd=="MOLECULAR"&&q!=0)Fail("charged formula "+a[0]);
                long value=Quantity(a[1]);
                if(cmd=="MOLES")return new(){
                    $"{Dec(value,3)} g {a[0]} = {Dec(value*1000000/m,6)} mol"
                };
                if(cmd=="GRAMS")return new(){
                    $"{Dec(value,3)} mol {a[0]} = {Dec(value*m/1000,3)} g"
                };
                long k=(2*value+m)/(2*m);
                return k==0||10*Math.Abs(value-k*m)>m?new(){
                    $"no integer multiple (ratio {Dec(1000*value/m,3)})"
                }:new(){
                    $"{Hill(Scale(c,k))} (n = {k}, {Dec(k*m,3)} g/mol)"
                };
            }
            if(cmd=="REDOX"||cmd=="HALF"){
                if(a[0]!="acidic"&&a[0]!="basic")Fail("invalid medium "+a[0]);
                Equation eq0=ReadEquation(a.Skip(1).ToArray());
                foreach(Species s in eq0.List)if(new[]{
                    "H^+","OH^-","H2O"
                }.Contains(s.F))Fail("reserved species "+s.Name);
                List<Species> aux=new(){
                    ReadSpecies(a[0]=="acidic"?"H^+":"OH^-"),ReadSpecies("H2O")
                };
                if(cmd=="HALF")aux.Add(new("e^-","",1,new(new(),-1)));
                List<Species> species=eq0.List.Concat(aux).ToList();
                long[] vals=Coefficients(species,eq0.Signs.Concat(Enumerable.Repeat(1L,aux.Count)).ToArray(),eq0.List.Count);
                List<string> left=new(),right=new();
                for(int i=0;i<eq0.List.Count;i++)(i<eq0.R?left:right).Add(Term(species[i].Name,vals[i]));
                for(int i=eq0.List.Count;i<species.Count;i++)if(vals[i]!=0)(vals[i]>0?left:right).Add(Term(species[i].Name,Math.Abs(vals[i])));
                List<string> result=new(){
                    string.Join(" + ",left)+" -> "+string.Join(" + ",right)
                };
                if(cmd=="HALF")result.Add(vals[^1]>0?"reduction":vals[^1]<0?"oxidation":"no electron transfer");
                return result;
            }
            string[] words=a,rest=Array.Empty<string>();
            if(new[]{
                "STOICH","LIMITING","YIELD"
            }.Contains(cmd)){
                if(a.Count(s=>s==":")!=1)Fail("invalid separator");
                int i=Array.IndexOf(a,":");
                words=a.Take(i).ToArray();
                rest=a.Skip(i+1).ToArray();
                if((cmd=="STOICH"&&rest.Length!=2)||(cmd=="YIELD"&&rest.Length!=4))Fail("wrong argument count for "+cmd);
            }
            Equation eq=ReadEquation(words,cmd=="CHECK");
            List<Species> list=eq.List;
            int split=eq.R;
            long[] signs=eq.Signs;
            if(cmd=="MATRIX"){
                var matrix=Matrix(list,signs);
                var ns=Nullspace(matrix.Rows,list.Count);
                List<string> result=new(){
                    "columns: "+string.Join(" ",list.Select(s=>s.Name))
                };
                result.AddRange(matrix.Rows.Select((row,i)=>matrix.Labels[i]+": "+string.Join(" ",row)));
                result.Add($"rank {ns.Rank}, nullity {ns.Basis.Count}");
                result.AddRange(ns.Basis.Select(row=>"null: "+string.Join(" ",row)));
                return result;
            }
            if(cmd=="CHECK"){
                var matrix=Matrix(list,signs);
                List<string> diff=new();
                for(int i=0;i<matrix.Rows.Length;i++){
                    long l=0,r=0;
                    for(int j=0;j<list.Count;j++){
                        long x=matrix.Rows[i][j]*list[j].Coefficient;
                        if(j<split)l+=x;
                        else r-=x;
                    }
                    if(l!=r)diff.Add(matrix.Labels[i]+": "+(matrix.Labels[i]=="charge"?Signed(l):l.ToString())+" != "+(matrix.Labels[i]=="charge"?Signed(r):r.ToString()));
                }
                if(diff.Count>0){
                    diff.Insert(0,"not balanced");
                    return diff;
                }
                long g=list.Select(s=>s.Coefficient).Aggregate(0L,Gcd);
                return new(){
                    g==1?"balanced":$"balanced, not in lowest terms (gcd {g})"
                };
            }
            int target=-1,product=-1;
            long[] qs=Array.Empty<long>();
            if(cmd=="DELTAH")foreach(Species s in list)if(!heats.ContainsKey(s.Name))Fail("no enthalpy for "+s.Name);
            if(cmd=="STOICH"){
                target=list.FindIndex(s=>s.Name==rest[0]);
                if(target<0)Fail("species "+rest[0]+" not in equation");
                qs=new[]{
                    Quantity(rest[1])
                };
            }
            if(cmd=="LIMITING"){
                if(rest.Length!=split)Fail($"expected {split} masses, got {rest.Length}");
                qs=rest.Select(Quantity).ToArray();
            }
            if(cmd=="YIELD"){
                target=list.FindIndex(0,split,s=>s.Name==rest[0]);
                if(target<0)Fail(rest[0]+" is not a reactant");
                product=list.FindIndex(split,list.Count-split,s=>s.Name==rest[2]);
                if(product<0)Fail(rest[2]+" is not a product");
                qs=new[]{
                    Quantity(rest[1]),Quantity(rest[3])
                };
            }
            long[] v=Coefficients(list,signs);
            List<string> output=new(){
                Notation(eq,v)
            };
            if(cmd=="BALANCE")return output;
            if(cmd=="DELTAH"){
                long h=list.Select((s,i)=>-signs[i]*v[i]*heats[s.Name]).Sum();
                output.Add($"dH = {Ent(h)} kJ ({(h<0?"exothermic":h>0?"endothermic":"thermoneutral")})");
                return output;
            }
            if(cmd=="STOICH"){
                long d=v[target]*list[target].Mass;
                output.AddRange(list.Select((s,i)=>$"{s.Name} {Dec(qs[0]*v[i]*1000000/d,6)} mol {Dec(qs[0]*v[i]*s.Mass/d,3)} g"+Gas(s,qs[0]*v[i],d)));
                return output;
            }
            if(cmd=="YIELD"){
                long t=qs[0]*v[product]*list[product].Mass/(v[target]*list[target].Mass);
                output.AddRange(new[]{
                    $"theoretical {Dec(t,3)} g",$"actual {Dec(qs[1],3)} g",t==0?"yield undefined":$"yield {Dec(qs[1]*10000/t,2)}%"
                });
                return output;
            }
            int limiting=0;
            for(int i=1;i<split;i++)if(qs[i]*v[limiting]*list[limiting].Mass<qs[limiting]*v[i]*list[i].Mass)limiting=i;
            long divisor=v[limiting]*list[limiting].Mass;
            output.Add("limiting "+list[limiting].Name);
            output.Add("extent "+Dec(qs[limiting]*1000000/divisor,6)+" mol");
            for(int i=split;i<list.Count;i++)output.Add($"product {list[i].Name} {Dec(qs[limiting]*v[i]*list[i].Mass/divisor,3)} g"+Gas(list[i],qs[limiting]*v[i],divisor));
            for(int i=0;i<split;i++)if(i!=limiting)output.Add($"remaining {list[i].Name} {Dec((qs[i]*divisor-qs[limiting]*v[i]*list[i].Mass)/divisor,3)} g");
            return output;
        }
    }
    static void Main(){
        int n=int.Parse(Console.ReadLine()!);
        Chemistry engine=new();
        for(int i=0;i<n;i++){
            string line=Console.ReadLine()!;
            try{
                foreach(string s in engine.Execute(line))Console.WriteLine(s);
            }catch(ArgumentException e){
                Console.WriteLine(e.Message);
            }catch(InvalidOperationException e){
                Console.WriteLine(e.Message);
            }
        }
    }
}
