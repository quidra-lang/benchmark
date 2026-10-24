using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

class Program
{
    sealed class SqlError:Exception{public SqlError(string s):base(s){}}
    static Exception Error(string s)=>new SqlError(s);
    static readonly HashSet<string> Reserved=new("SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT".Split(' '));
    static readonly HashSet<string> Aggregates=new(){"COUNT","SUM","MIN","MAX","AVG"},Comparisons=new(){"=","<>","!=","<","<=",">",">="};
    sealed record Token(string Kind,string Text,object? Value);
    static List<Token> Tokenize(string s)
    {
        List<Token>a=new();int i=0;while(i<s.Length){char c=s[i];int start=i;if(c==' '||c=='\n'){i++;continue;}if(s.AsSpan(i).StartsWith("--")){int end=s.IndexOf('\n',i);i=end<0?s.Length:end;continue;}
            if(c=='\''){i=s.IndexOf('\'',i+1)+1;a.Add(new("string",s[start..i],s[(start+1)..(i-1)]));}
            else if(char.IsAsciiDigit(c)){while(i<s.Length&&char.IsAsciiDigit(s[i]))i++;string t=s[start..i];a.Add(new("integer",t,long.Parse(t)));}
            else if(char.IsAsciiLetter(c)||c=='_'){while(i<s.Length&&(char.IsAsciiLetterOrDigit(s[i])||s[i]=='_'))i++;string t=s[start..i],up=t.ToUpperInvariant();a.Add(new(Reserved.Contains(up)?"keyword":"name",t,Reserved.Contains(up)?up:t));}
            else{string t=s.Substring(i,Math.Min(2,s.Length-i));if(!new[]{"<>","!=","<=",">=","||"}.Contains(t))t=c.ToString();if(t.Length==1&&!"(),.;*/%+-=<>".Contains(c))throw Error($"unexpected character '{c}'");a.Add(new("symbol",t,t));i+=t.Length;}
        }return a;
    }
    sealed class Expr
    {
        public string Kind,Op,Column="",Text="";public string? Table;public List<Expr> Args;public object? Value;public int Index=-1;public bool Distinct,Negated;
        public Expr(string kind,string op="",IEnumerable<Expr>? args=null,object? value=null){Kind=kind;Op=op;Args=args?.ToList()??new();Value=value;}
    }
    sealed record Column(string Name,string Type,int Primary,bool NotNull);
    sealed record TableRef(string Name,string Alias);
    sealed record Item(Expr Expression,string? Alias,string Heading);
    sealed record Order(Expr Expression,bool Descending,long? Ordinal,string? Alias);
    sealed record Join(TableRef Table,bool Left,Expr Condition);
    sealed class Query
    {
        public bool Distinct,Star;public List<Item>Items=new();public TableRef Source=null!;public List<Join>Joins=new();public Expr? Where,Having;public List<Expr>? Group;public List<Order>Order=new();public long? Limit;public long Offset;
    }
    sealed class Command
    {
        public string Kind="",Name="";public List<Column>Columns=new();public List<string>? Names;public List<List<Expr>>Tuples=new();public List<(string Name,Expr Expression)>Assignments=new();public Expr? Where;public Query? Query;
    }
    sealed class Parser
    {
        readonly List<Token>tokens;int position;public Parser(List<Token>tokens)=>this.tokens=tokens;
        Token Peek()=>tokens[position];Token Take()=>tokens[position++];
        bool At(string word){Token t=Peek();return (t.Kind=="keyword"||t.Kind=="symbol")&&Equals(t.Value,word);}
        bool Accept(string word){if(!At(word))return false;position++;return true;}
        Exception Syntax()=>Error($"syntax error at '{Peek().Text}'");
        void Expect(string word){if(!Accept(word))throw Syntax();}
        string Name(){if(Peek().Kind!="name")throw Syntax();return (string)Take().Value!;}
        long Integer(){if(Peek().Kind!="integer")throw Syntax();return (long)Take().Value!;}
        List<T> Comma<T>(Func<T>read){List<T>a=new(){read()};while(Accept(","))a.Add(read());return a;}
        List<T> Parens<T>(Func<T>read){Expect("(");List<T>a=Comma(read);Expect(")");return a;}
        string? Alias(){if(Accept("AS"))return Name();return Peek().Kind=="name"?Name():null;}
        TableRef Table(){string n=Name();return new(n,Alias()??n);}
        Expr Reference(){string n=Name();Expr e=new("ref");if(Accept(".")){e.Table=n;e.Column=Name();e.Text=n+"."+e.Column;}else e.Column=e.Text=n;return e;}
        Expr Expression(int level=0)
        {
            if(level==2&&Accept("NOT"))return new("unary","NOT",new[]{Expression(2)});if(level==6&&Accept("-"))return new("unary","-",new[]{Expression(6)});if(level==7)return Primary();Expr left=Expression(level+1);
            if(level==3){if(Peek().Kind=="symbol"&&Comparisons.Contains((string)Peek().Value!)){string op=(string)Take().Value!;return new("binary",op,new[]{left,Expression(4)});}if(Accept("IS")){bool neg=Accept("NOT");Expect("NULL");return new("isnull","",new[]{left}){Negated=neg};}bool not=Accept("NOT");Expr? result=null;
                if(Accept("IN"))result=new("in","",new[]{left}.Concat(Parens(()=>Expression())));else if(Accept("BETWEEN")){Expr low=Expression(4);Expect("AND");result=new("between","",new[]{left,low,Expression(4)});}else if(Accept("LIKE"))result=new("like","",new[]{left,Expression(4)});else if(not)throw Syntax();if(result!=null){result.Negated=not;return result;}return left;}
            string[][]ops={new[]{"OR"},new[]{"AND"},Array.Empty<string>(),Array.Empty<string>(),new[]{"+","-","||"},new[]{"*","/","%"},Array.Empty<string>()};while(ops[level].Any(At)){string op=(string)Take().Value!;left=new("binary",op,new[]{left,Expression(level+1)});}return left;
        }
        Expr Primary(){Token t=Peek();if(t.Kind=="integer"||t.Kind=="string"){Take();return new("literal",value:t.Value);}if(Accept("NULL"))return new("literal");if(t.Kind=="name")return Reference();if(t.Kind=="keyword"&&Aggregates.Contains((string)t.Value!)){string n=(string)Take().Value!;Expect("(");Expr e=new("aggregate",n);if(!(n=="COUNT"&&Accept("*"))){e.Distinct=Accept("DISTINCT");e.Args.Add(Expression());}Expect(")");return e;}if(Accept("(")){Expr e=Expression();Expect(")");return new("group","",new[]{e});}throw Syntax();}
        Expr? Clause(string word)=>Accept(word)?Expression():null;
        Item SelectItem(){int start=position;Expr e=Expression();int stop=position;string? alias=Alias();string heading=alias??"";if(alias==null){if(e.Kind=="ref")heading=e.Column;else{StringBuilder s=new();for(int i=start;i<stop;i++){if(i>start&&tokens[i].Kind!="symbol"&&tokens[i-1].Kind!="symbol")s.Append(' ');s.Append(tokens[i].Text);}heading=s.ToString();}}return new(e,alias,heading);}
        Order OrderItem(){int start=position;Expr e=Expression();bool single=position==start+1;Token t=tokens[start];bool desc=Accept("DESC");if(!desc)Accept("ASC");return new(e,desc,single&&t.Kind=="integer"?(long)t.Value!:null,single&&t.Kind=="name"?(string)t.Value!:null);}
        Query Select(){Query q=new(){Distinct=Accept("DISTINCT"),Star=Accept("*")};if(!q.Star)q.Items=Comma(SelectItem);Expect("FROM");q.Source=Table();while(At("JOIN")||At("INNER")||At("LEFT")){bool left=Accept("LEFT");if(left)Accept("OUTER");else Accept("INNER");Expect("JOIN");TableRef t=Table();Expect("ON");q.Joins.Add(new(t,left,Expression()));}q.Where=Clause("WHERE");if(Accept("GROUP")){Expect("BY");q.Group=Comma(Reference);}q.Having=Clause("HAVING");if(Accept("ORDER")){Expect("BY");q.Order=Comma(OrderItem);}if(Accept("LIMIT")){q.Limit=Integer();if(Accept("OFFSET"))q.Offset=Integer();}return q;}
        Column ColumnDefinition(){string n=Name();if(!At("INT")&&!At("TEXT"))throw Syntax();string t=(string)Take().Value!;int pk=0;bool nn=false;while(true){if(Accept("PRIMARY")){Expect("KEY");pk++;nn=true;}else if(Accept("NOT")){Expect("NULL");nn=true;}else break;}return new(n,t,pk,nn);}
        public Command Statement(){Command c=new();if(Accept("CREATE")){c.Kind="create";Expect("TABLE");c.Name=Name();c.Columns=Parens(ColumnDefinition);}else if(Accept("DROP")){c.Kind="drop";Expect("TABLE");c.Name=Name();}else if(Accept("INSERT")){c.Kind="insert";Expect("INTO");c.Name=Name();if(At("("))c.Names=Parens(Name);Expect("VALUES");c.Tuples=Comma(()=>Parens(()=>Expression()));}else if(Accept("UPDATE")){c.Kind="update";c.Name=Name();Expect("SET");c.Assignments=Comma(()=>{string n=Name();Expect("=");return(n,Expression());});c.Where=Clause("WHERE");}else if(Accept("DELETE")){c.Kind="delete";Expect("FROM");c.Name=Name();c.Where=Clause("WHERE");}else if(Accept("SELECT")){c.Kind="select";c.Query=Select();}else if(Accept("EXIT"))c.Kind="exit";Expect(";");return c;}
    }
    sealed class Table
    {
        public readonly string Name;public readonly List<Column>Columns;public readonly int Key;public List<List<object?>>Rows=new();public Table(string name,List<Column>columns,int key){Name=name;Columns=columns;Key=key;}
        public int Column(string name)=>Columns.FindIndex(c=>c.Name==name);
    }
    sealed record Entry(string Name,Table Table,int Offset);
    sealed class Scope
    {
        public readonly List<Entry>Entries=new();int width;
        public void Add(string n,Table t){if(Entries.Any(e=>e.Name==n))throw Error("duplicate table name "+n);Entries.Add(new(n,t,width));width+=t.Columns.Count;}
        public string Resolve(Expr e){List<(int Index,string Type)>found=new();bool seen=false;foreach(Entry p in Entries)if(e.Table==null||e.Table==p.Name){seen=true;int i=p.Table.Column(e.Column);if(i>=0)found.Add((p.Offset+i,p.Table.Columns[i].Type));}if(e.Table!=null&&!seen)throw Error("unknown table "+e.Table);if(found.Count==0)throw Error("unknown column "+e.Text);if(found.Count>1)throw Error("ambiguous column "+e.Column);e.Index=found[0].Index;return found[0].Type;}
    }
    static bool Compatible(string a,string b)=>a==b||a=="NULL"||b=="NULL";
    static void Require(string a,string b,string op){if(!Compatible(a,b))throw Error("type mismatch for "+op);}
    static string Check(Expr e,Scope s,bool allow=false,List<int>? grouped=null,bool inside=false)
    {
        if(e.Kind=="literal")return e.Value==null?"NULL":e.Value is long?"INT":"TEXT";if(e.Kind=="ref"){string type=s.Resolve(e);if(grouped!=null&&!inside&&!grouped.Contains(e.Index))throw Error("column "+e.Text+" is not grouped");return type;}
        if(e.Kind=="aggregate"){if(!allow||inside)throw Error("misuse of aggregate "+e.Op);if(e.Args.Count==0)return "INT";string type=Check(e.Args[0],s,allow,grouped,true);if(e.Op=="SUM"||e.Op=="AVG")Require(type,"INT",e.Op);return e.Op=="MIN"||e.Op=="MAX"?type:"INT";}
        List<string>types=e.Args.Select(a=>Check(a,s,allow,grouped,inside)).ToList();if(e.Kind=="group")return types[0];if(e.Kind=="isnull")return "INT";if(e.Kind=="binary"&&Comparisons.Contains(e.Op)){Require(types[0],types[1],e.Op);return "INT";}if(e.Kind=="in"||e.Kind=="between"){foreach(string t in types.Skip(1))Require(t,types[0],e.Kind=="in"?"IN":"BETWEEN");return "INT";}string op=e.Kind=="like"?"LIKE":e.Op,typeRequired=op=="LIKE"||op=="||"?"TEXT":"INT";foreach(string t in types)Require(t,typeRequired,op);return op=="||"?"TEXT":"INT";
    }
    static void Condition(Expr? e,Scope s,string name,bool allow=false,List<int>? grouped=null){if(e!=null)Require(Check(e,s,allow,grouped),"INT",name);}
    static bool HasAggregate(Expr e)=>e.Kind=="aggregate"||e.Args.Any(HasAggregate);
    static bool Truth(object? v)=>v!=null&&(long)v!=0;
    static object? Inverse(object? v)=>v==null?null:(long)v==0?1L:0L;
    static int Compare(object? a,object? b){if(Equals(a,b))return 0;if(a==null)return -1;if(b==null)return 1;return a is long x?x.CompareTo((long)b):string.CompareOrdinal((string)a,(string)b);}
    static object? Operate(string op,object? a,object? b)
    {
        if(op=="AND"){if(Equals(a,0L)||Equals(b,0L))return 0L;return a==null||b==null?null:1L;}if(op=="OR"){if(Truth(a)||Truth(b))return 1L;return a==null||b==null?null:0L;}if(a==null||b==null)return null;if(Comparisons.Contains(op)){int c=Compare(a,b);bool ok=op switch{"="=>c==0,"<>" or "!="=>c!=0,"<"=>c<0,"<="=>c<=0,">"=>c>0,_=>c>=0};return ok?1L:0L;}if(op=="||")return (string)a+(string)b;long x=(long)a,y=(long)b;return op switch{"+"=>x+y,"-"=>x-y,"*"=>x*y,"/"=>y==0?null:x/y,"%"=>y==0?null:x%y,_=>throw new InvalidOperationException()};
    }
    static bool Like(string text,string pattern){bool[]dp=new bool[text.Length+1];dp[0]=true;foreach(char c in pattern){if(c=='%'){for(int i=1;i<=text.Length;i++)dp[i]|=dp[i-1];}else{for(int i=text.Length;i>0;i--)dp[i]=dp[i-1]&&(c=='_'||c==text[i-1]);dp[0]=false;}}return dp[text.Length];}
    static object? Evaluate(Expr e,List<object?>row,List<List<object?>>? group=null)
    {
        if(e.Kind=="literal")return e.Value;if(e.Kind=="ref")return row[e.Index];if(e.Kind=="aggregate"){if(e.Args.Count==0)return (long)group!.Count;List<object?>values=new();foreach(List<object?>r in group!){object? v=Evaluate(e.Args[0],r);if(v!=null&&(!e.Distinct||!values.Contains(v)))values.Add(v);}if(e.Op=="COUNT")return (long)values.Count;if(values.Count==0)return null;if(e.Op=="MIN"||e.Op=="MAX"){object? result=values[0];foreach(object? v in values)if(e.Op=="MIN"?Compare(v,result)<0:Compare(v,result)>0)result=v;return result;}long sum=values.Sum(v=>(long)v!);return e.Op=="AVG"?sum/values.Count:sum;}
        List<object?>a=e.Args.Select(arg=>Evaluate(arg,row,group)).ToList();if(e.Kind=="group")return a[0];if(e.Kind=="unary")return e.Op=="NOT"?Inverse(a[0]):a[0]==null?null:-(long)a[0]!;if(e.Kind=="binary")return Operate(e.Op,a[0],a[1]);if(e.Kind=="isnull")return (a[0]==null)!=e.Negated?1L:0L;object? resultValue=null;
        if(e.Kind=="in"){if(a[0]!=null)resultValue=a.Skip(1).Contains(a[0])?1L:a.Skip(1).Contains(null)?null:0L;}else if(e.Kind=="between")resultValue=Operate("AND",Operate(">=",a[0],a[1]),Operate("<=",a[0],a[2]));else if(a[0]!=null&&a[1]!=null)resultValue=Like((string)a[0]!, (string)a[1]!)?1L:0L;return e.Negated?Inverse(resultValue):resultValue;
    }
    static bool Satisfies(Expr? e,List<object?>row,List<List<object?>>? group=null)=>e==null||Truth(Evaluate(e,row,group));
    static string CountRows(int n)=>n+(n==1?" row":" rows");
    static string Written(object? v)=>v?.ToString()??"NULL";
    static void PrintTable(List<Item>items,List<string>types,List<List<object?>>rows)
    {
        int[]width=items.Select(i=>i.Heading.Length).ToArray();List<List<string>>cells=rows.Select(r=>r.Select(Written).ToList()).ToList();foreach(List<string>r in cells)for(int i=0;i<r.Count;i++)width[i]=Math.Max(width[i],r[i].Length);string sep="+"+string.Concat(width.Select(w=>new string('-',w+2)+"+"));
        string Format(List<string>r,bool header)=>"|"+string.Concat(r.Select((v,i)=>" "+(!header&&types[i]=="INT"?v.PadLeft(width[i]):v.PadRight(width[i]))+" |"));Console.WriteLine(sep);Console.WriteLine(Format(items.Select(i=>i.Heading).ToList(),true));Console.WriteLine(sep);foreach(List<string>r in cells)Console.WriteLine(Format(r,false));Console.WriteLine(sep);Console.WriteLine("("+CountRows(rows.Count)+")");
    }
    sealed class Database
    {
        readonly Dictionary<string,Table>tables=new();
        Table GetTable(string n){if(!tables.TryGetValue(n,out Table? t))throw Error("unknown table "+n);return t;}
        List<int>Targets(Table t,List<string>names){List<int>a=new();foreach(string n in names){int i=t.Column(n);if(i<0)throw Error("unknown column "+n);if(a.Contains(i))throw Error("duplicate column "+n);a.Add(i);}return a;}
        void Constraints(Table t,List<List<object?>>rows,List<int>checkedRows){foreach(int i in checkedRows){for(int j=0;j<t.Columns.Count;j++)if(t.Columns[j].NotNull&&rows[i][j]==null)throw Error("NULL value in column "+t.Columns[j].Name);if(t.Key>=0)for(int j=0;j<rows.Count;j++)if(i!=j&&Equals(rows[i][t.Key],rows[j][t.Key]))throw Error("duplicate primary key "+Written(rows[i][t.Key]));}}
        public void Execute(Command c)
        {
            if(c.Kind=="select"){Select(c.Query!);return;}if(c.Kind=="create"){if(tables.ContainsKey(c.Name))throw Error("table "+c.Name+" already exists");HashSet<string>seen=new();int primary=0,key=-1;for(int i=0;i<c.Columns.Count;i++){Column column=c.Columns[i];if(!seen.Add(column.Name))throw Error("duplicate column "+column.Name);primary+=column.Primary;if(primary>=2)throw Error("multiple primary keys");if(column.Primary>0)key=i;}tables[c.Name]=new(c.Name,c.Columns,key);Console.WriteLine("Table "+c.Name+" created.");return;}
            Table t=GetTable(c.Name);if(c.Kind=="drop"){tables.Remove(c.Name);Console.WriteLine("Table "+c.Name+" dropped.");return;}List<List<object?>>rows=new();List<int>checkedRows=new();int count=0;
            if(c.Kind=="insert"){
                List<int>target=c.Names==null?Enumerable.Range(0,t.Columns.Count).ToList():Targets(t,c.Names);Scope empty=new();foreach(List<Expr>tuple in c.Tuples){if(tuple.Count!=target.Count)throw Error($"expected {target.Count} values, got {tuple.Count}");for(int i=0;i<tuple.Count;i++){Column column=t.Columns[target[i]];Require(Check(tuple[i],empty),column.Type,"column "+column.Name);}}
                rows.AddRange(t.Rows);foreach(List<Expr>tuple in c.Tuples){List<object?>row=Enumerable.Repeat<object?>(null,t.Columns.Count).ToList();for(int i=0;i<tuple.Count;i++)row[target[i]]=Evaluate(tuple[i],new());checkedRows.Add(rows.Count);rows.Add(row);}Constraints(t,rows,checkedRows);count=c.Tuples.Count;
            }else if(c.Kind=="update"){
                List<int>target=Targets(t,c.Assignments.Select(a=>a.Name).ToList());Scope scope=new();scope.Add(t.Name,t);for(int i=0;i<c.Assignments.Count;i++){Column column=t.Columns[target[i]];Require(Check(c.Assignments[i].Expression,scope),column.Type,"column "+column.Name);}Condition(c.Where,scope,"WHERE");for(int i=0;i<t.Rows.Count;i++){List<object?>row=t.Rows[i],next=row;if(Satisfies(c.Where,row)){next=new(row);for(int j=0;j<c.Assignments.Count;j++)next[target[j]]=Evaluate(c.Assignments[j].Expression,row);checkedRows.Add(i);count++;}rows.Add(next);}Constraints(t,rows,checkedRows);
            }else{Scope scope=new();scope.Add(t.Name,t);Condition(c.Where,scope,"WHERE");foreach(List<object?>row in t.Rows)if(Satisfies(c.Where,row))count++;else rows.Add(row);}
            t.Rows=rows;Console.WriteLine(CountRows(count)+(c.Kind=="insert"?" inserted.":c.Kind=="update"?" updated.":" deleted."));
        }
        sealed record Result(List<object?>Values,List<object?>Keys,int Position);
        void Select(Query q)
        {
            Scope scope=new();scope.Add(q.Source.Alias,GetTable(q.Source.Name));foreach(Join j in q.Joins){scope.Add(j.Table.Alias,GetTable(j.Table.Name));Condition(j.Condition,scope,"ON");}Condition(q.Where,scope,"WHERE");List<int>grouping=new();if(q.Group!=null)foreach(Expr e in q.Group){scope.Resolve(e);grouping.Add(e.Index);}
            if(q.Star)foreach(Entry p in scope.Entries)foreach(Column c in p.Table.Columns){Expr e=new("ref"){Table=p.Name,Column=c.Name,Text=c.Name};q.Items.Add(new(e,null,c.Name));}bool aggregate=q.Group!=null||q.Having!=null||q.Items.Any(i=>HasAggregate(i.Expression))||q.Order.Any(o=>HasAggregate(o.Expression));List<int>? grouped=aggregate?grouping:null;List<string>types=q.Items.Select(i=>Check(i.Expression,scope,true,grouped)).ToList();Condition(q.Having,scope,"HAVING",true,grouped);
            List<Expr>keys=new();foreach(Order o in q.Order){Expr? key=null;if(o.Ordinal!=null){long k=o.Ordinal.Value;if(k<1||k>q.Items.Count)throw Error("ORDER BY position "+k+" is out of range");key=q.Items[(int)k-1].Expression;}else if(o.Alias!=null)key=q.Items.FirstOrDefault(i=>i.Alias==o.Alias)?.Expression;if(key==null){Check(o.Expression,scope,true,grouped);key=o.Expression;}keys.Add(key);}
            List<List<object?>>rows=scope.Entries[0].Table.Rows;for(int ji=0;ji<q.Joins.Count;ji++){Join j=q.Joins[ji];Table t=scope.Entries[ji+1].Table;List<List<object?>>next=new();foreach(List<object?>left in rows){bool found=false;foreach(List<object?>right in t.Rows){List<object?>combined=left.Concat(right).ToList();if(Satisfies(j.Condition,combined)){next.Add(combined);found=true;}}if(j.Left&&!found)next.Add(left.Concat(Enumerable.Repeat<object?>(null,t.Columns.Count)).ToList());}rows=next;}rows=rows.Where(r=>Satisfies(q.Where,r)).ToList();
            List<List<List<object?>>>groups=new();if(!aggregate){foreach(List<object?>r in rows)groups.Add(new(){r});}else if(q.Group==null)groups.Add(rows);else{List<List<object?>>groupKeys=new();foreach(List<object?>r in rows){List<object?>key=grouping.Select(i=>r[i]).ToList();int at=groupKeys.FindIndex(k=>k.SequenceEqual(key));if(at<0){at=groups.Count;groups.Add(new());groupKeys.Add(key);}groups[at].Add(r);}}
            List<Result>results=new();foreach(List<List<object?>>g in groups){List<object?>row=g.Count==0?new():g[0];List<List<object?>>? context=aggregate?g:null;if(!Satisfies(q.Having,row,context))continue;List<object?>values=q.Items.Select(i=>Evaluate(i.Expression,row,context)).ToList(),sort=keys.Select(key=>Evaluate(key,row,context)).ToList();results.Add(new(values,sort,results.Count));}
            results.Sort((a,b)=>{for(int i=0;i<keys.Count;i++){int c=Compare(a.Keys[i],b.Keys[i]);if(c!=0)return q.Order[i].Descending?-c:c;}return a.Position.CompareTo(b.Position);});List<List<object?>>unique=new();foreach(Result r in results)if(!q.Distinct||!unique.Any(row=>row.SequenceEqual(r.Values)))unique.Add(r.Values);int first=(int)Math.Min(q.Offset,unique.Count),last=q.Limit==null?unique.Count:(int)Math.Min(unique.Count,first+q.Limit.Value);PrintTable(q.Items,types,unique.GetRange(first,last-first));
        }
    }
    static void Main()
    {
        string source=Console.In.ReadToEnd();List<string>statements=new();int start=0;for(int i=0;i<source.Length;i++){if(source[i]=='\'')i=source.IndexOf('\'',i+1);else if(source.AsSpan(i).StartsWith("--")){int end=source.IndexOf('\n',i);if(end<0)break;i=end;}else if(source[i]==';'){statements.Add(source[start..(i+1)]);start=i+1;}}Database db=new();foreach(string s in statements){try{Command c=new Parser(Tokenize(s)).Statement();if(c.Kind=="exit")break;if(c.Kind.Length>0)db.Execute(c);}catch(SqlError err){Console.WriteLine("ERROR: "+err.Message);}}
    }
}
