using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

sealed class SyntaxFault : Exception {}
sealed class BasicFault : Exception
{
    public BasicFault(string message) : base(message) {}
}

sealed record Token(string Kind,string Text,object Value);

sealed class Expr
{
    public string Kind;
    public string Type;
    public object Value;
    public List<Expr> Args;
    public Expr(string kind,string type,object value,List<Expr>? args=null)
    {
        Kind=kind;Type=type;Value=value;Args=args??new();
    }
}

sealed record PrintItem(string Kind,Expr? Expr);
sealed record Clause(int? Line,List<Statement> Body);

sealed class Statement
{
    public string Kind;
    public int Line;
    public Statement? Next;
    public Expr? Expr,Target;
    public List<Expr> Targets=new(),Expressions=new();
    public List<object> Values=new();
    public List<int> Numbers=new();
    public string Name="",Mode="";
    public List<Clause> Clauses=new();
    public List<PrintItem> Items=new();
    public Statement(string kind){Kind=kind;}
}

static class Basic
{
    public static readonly Dictionary<string,string[]> Signatures=new(){
        ["ABS"]=["I"],["SGN"]=["I"],["INT"]=["I"],["SQR"]=["I"],["RND"]=["I"],
        ["LEN"]=["S"],["ASC"]=["S"],["VAL"]=["S"],["CHR$"]=["I"],
        ["STR$"]=["I"],["LEFT$"]=["SI"],["RIGHT$"]=["SI"],
        ["MID$"]=["SI","SII"],["INSTR"]=["SS"]
    };

    public static readonly Dictionary<string,int> Errors=new(){
        ["NEXT WITHOUT FOR"]=1,["RETURN WITHOUT GOSUB"]=3,
        ["OUT OF DATA"]=4,["ILLEGAL FUNCTION CALL"]=5,
        ["OVERFLOW"]=6,["OUT OF MEMORY"]=7,["UNDEFINED LINE NUMBER"]=8,
        ["SUBSCRIPT OUT OF RANGE"]=9,["DUPLICATE DEFINITION"]=10,
        ["DIVISION BY ZERO"]=11,["TYPE MISMATCH"]=13,
        ["STRING TOO LONG"]=15,["RESUME WITHOUT ERROR"]=20,
        ["FOR WITHOUT NEXT"]=26,["WHILE WITHOUT WEND"]=29,
        ["WEND WITHOUT WHILE"]=30,["INPUT PAST END"]=62
    };

    public static readonly string[][] Ops=[
        ["OR"],["AND"],[],["=","<>","<",">","<=",">="],
        ["+","-"],["*","/","MOD"],[],["^"]
    ];

    public static void Syntax()=>throw new SyntaxFault();
    public static void Fault(string reason)=>throw new BasicFault(reason);
    public static bool Variable(string word)=>
        Regex.IsMatch(word,@"\A[A-Z][0-9]?\$?\z");
    public static string NameType(string name)=>name.EndsWith('$')?"S":"I";
    public static string ValueType(object value)=>value is string?"S":"I";

    public static List<Token> Tokenize(string text)
    {
        List<Token>tokens=[];
        for(int p=0;p<text.Length;)
        {
            char ch=text[p];
            if(ch==' '){p++;continue;}
            if(ch=='"')
            {
                int end=text.IndexOf('"',p+1);
                if(end<0)Syntax();
                tokens.Add(new("S",text[p..(end+1)],text[(p+1)..end]));
                p=end+1;
            }
            else if(ch is >= '0' and <= '9')
            {
                int start=p;
                while(p<text.Length&&text[p] is >= '0' and <= '9')p++;
                string word=text[start..p];
                if(!int.TryParse(word,out int value)||value>32767)Syntax();
                tokens.Add(new("I",word,value));
            }
            else if(ch is >= 'A' and <= 'Z')
            {
                if(text.AsSpan(p).StartsWith("REM",StringComparison.Ordinal))
                {
                    tokens.Add(new("W","REM","REM"));break;
                }
                int start=p;
                while(p<text.Length&&
                      (text[p] is >= 'A' and <= 'Z' or >= '0' and <= '9'))p++;
                if(p<text.Length&&text[p]=='$')p++;
                string word=text[start..p];
                tokens.Add(new("W",word,word));
            }
            else
            {
                if(!"+-*/^=<>() ,;:".Contains(ch))Syntax();
                string word=p+1<text.Length?text.Substring(p,2):ch.ToString();
                if(word is not ("<>" or "<=" or ">="))word=ch.ToString();
                tokens.Add(new("P",word,word));p+=word.Length;
            }
        }
        tokens.Add(new("E","",""));
        return tokens;
    }
}

sealed class Parser
{
    readonly List<Token> tokens;
    int position;
    public Parser(List<Token>tokens){this.tokens=tokens;}
    Token Current=>tokens[position];
    bool At(string word)=>(Current.Kind is "P" or "W")&&Current.Text==word;
    bool Take(string word)
    {
        if(!At(word))return false;
        position++;return true;
    }
    void Expect(string word){if(!Take(word))Basic.Syntax();}
    int Number()
    {
        if(Current.Kind!="I")Basic.Syntax();
        return (int)tokens[position++].Value;
    }
    Expr Integer(int level=0)
    {
        Expr result=Expression(level);
        if(result.Type!="I")Basic.Syntax();
        return result;
    }
    Expr Target()
    {
        Token token=Current;
        if(token.Kind!="W"||!Basic.Variable(token.Text))Basic.Syntax();
        position++;
        Expr result=new("variable",Basic.NameType(token.Text),token.Text);
        if(Take("("))
        {
            result.Kind="array";
            result.Args.Add(Integer());
            if(Take(","))result.Args.Add(Integer());
            Expect(")");
        }
        return result;
    }
    Expr Primary()
    {
        Token token=Current;
        if(token.Kind is "I" or "S")
        {
            position++;return new("constant",token.Kind,token.Value);
        }
        if(Take("("))
        {
            Expr value=Expression();Expect(")");return value;
        }
        if(token.Kind=="W"&&Basic.Variable(token.Text))return Target();
        if(Take("ERR"))return new("builtin","I","ERR");
        if(Take("ERL"))return new("builtin","I","ERL");
        if(token.Kind=="W"&&Basic.Signatures.ContainsKey(token.Text))
        {
            position++;Expect("(");
            List<Expr>args=[Expression()];
            while(Take(","))args.Add(Expression());
            Expect(")");
            if(!Basic.Signatures[token.Text].Contains(string.Concat(args.Select(e=>e.Type))))
                Basic.Syntax();
            return new("call",Basic.NameType(token.Text),token.Text,args);
        }
        Basic.Syntax();throw new InvalidOperationException();
    }
    Expr Expression(int level=0)
    {
        if(level==2&&Take("NOT"))return new("unary","I","NOT",[Integer(2)]);
        if(level==6&&Take("-"))return new("unary","I","-",[Integer(6)]);
        if(level==8)return Primary();
        Expr left=Expression(level+1);
        while(Basic.Ops[level].Contains(Current.Text))
        {
            string op=Current.Text;position++;
            Expr right=Expression(level==7?6:level+1);
            if(left.Type!=right.Type||(left.Type=="S"&&level!=3&&op!="+"))
                Basic.Syntax();
            left=new("binary",level==3?"I":left.Type,op,[left,right]);
            if(level==7)break;
        }
        return left;
    }
    Clause ParseClause()=>Current.Kind=="I"?new(Number(),[]):new(null,Listing(true));
    List<Statement> Listing(bool inside=false)
    {
        List<Statement>body=[ParseStatement(inside)];
        while(Take(":"))body.Add(ParseStatement(inside));
        return body;
    }
    Statement ParseStatement(bool inside)
    {
        string word=Current.Text;
        if(inside&&new[]{"IF","FOR","NEXT","WHILE","WEND","DATA"}.Contains(word))
            Basic.Syntax();
        Statement s=new(word);
        foreach(string kind in new[]{"REM","RETURN","WEND","END","STOP"})
            if(Take(kind))return s;
        if(Take("PRINT"))
        {
            bool lastValue=false;
            while(Current.Kind!="E"&&!At(":")&&!At("ELSE"))
            {
                if(Take(";"))
                {
                    s.Items.Add(new(";",null));lastValue=false;
                }
                else if(Take(","))
                {
                    s.Items.Add(new(",",null));lastValue=false;
                }
                else
                {
                    string kind=At("TAB")?"TAB":At("SPC")?"SPC":"value";
                    if(kind=="value"&&lastValue)Basic.Syntax();
                    Expr expr;
                    if(kind=="value")expr=Expression();
                    else
                    {
                        position++;Expect("(");expr=Integer();Expect(")");
                    }
                    s.Items.Add(new(kind,expr));lastValue=kind=="value";
                }
            }
            return s;
        }
        if(Take("INPUT")||Take("READ")||Take("DIM"))
        {
            do
            {
                Expr target=Target();
                if(word=="DIM"&&target.Kind!="array")Basic.Syntax();
                s.Targets.Add(target);
            }while(Take(","));
            return s;
        }
        if(Take("DATA"))
        {
            do
            {
                bool negative=Take("-");
                Token token=Current;
                if(token.Kind!="I"&&(token.Kind!="S"||negative))Basic.Syntax();
                position++;
                s.Values.Add(negative?-(int)token.Value:token.Value);
            }while(Take(","));
            return s;
        }
        if(Take("IF"))
        {
            s.Expr=Integer();Expect("THEN");
            s.Clauses.Add(ParseClause());
            if(Take("ELSE"))s.Clauses.Add(ParseClause());
            if(Current.Kind!="E")Basic.Syntax();
            return s;
        }
        if(Take("GOTO")||Take("GOSUB"))
        {
            s.Numbers.Add(Number());return s;
        }
        if(Take("ON"))
        {
            if(Take("ERROR"))
            {
                s.Kind="handler";Expect("GOTO");s.Numbers.Add(Number());
            }
            else
            {
                s.Expr=Integer();
                if(Take("GOTO"))s.Mode="GOTO";
                else{Expect("GOSUB");s.Mode="GOSUB";}
                s.Numbers.Add(Number());
                while(Take(","))s.Numbers.Add(Number());
            }
            return s;
        }
        if(Take("RESUME"))
        {
            if(Take("NEXT"))s.Mode="NEXT";
            else if(Current.Kind=="I"){s.Mode="line";s.Numbers.Add(Number());}
            return s;
        }
        if(Take("FOR"))
        {
            Token token=Current;
            if(token.Kind!="W"||!Basic.Variable(token.Text)||
               Basic.NameType(token.Text)!="I")Basic.Syntax();
            s.Name=token.Text;position++;Expect("=");
            s.Expressions.Add(Integer());Expect("TO");s.Expressions.Add(Integer());
            s.Expressions.Add(Take("STEP")?Integer():new Expr("constant","I",1));
            return s;
        }
        if(Take("NEXT"))
        {
            Token token=Current;
            if(token.Kind=="W"&&Basic.Variable(token.Text)&&
               Basic.NameType(token.Text)=="I")
            {
                s.Name=token.Text;position++;
            }
            return s;
        }
        if(Take("WHILE")||Take("RANDOMIZE")){s.Expr=Integer();return s;}
        if(Take("RESTORE"))
        {
            if(Current.Kind=="I")s.Numbers.Add(Number());
            return s;
        }
        Take("LET");s.Kind="assign";s.Target=Target();Expect("=");
        s.Expr=Expression();
        if(s.Expr.Type!=s.Target.Type)Basic.Syntax();
        return s;
    }
    public List<Statement> Parse()
    {
        List<Statement> result=Listing();
        if(Current.Kind!="E")Basic.Syntax();
        return result;
    }
}

sealed record ArrayDef(int[] Bounds,object[] Values);
sealed record Address(string Name,int? Index);
sealed record Frame(string Kind,Statement? Position,string Name="",int Limit=0,int Step=0);
sealed record DataValue(int Line,object Value);
sealed record ProgramLine(int Number,List<Statement> Body);

sealed class Machine
{
    readonly List<string> inputs;
    readonly Dictionary<string,object> variables=new();
    readonly Dictionary<string,ArrayDef> arrays=new();
    readonly List<Frame> stack=new();
    readonly Dictionary<int,Statement> entries=new();
    readonly List<Statement> sequence=new();
    readonly List<DataValue> data=new();
    readonly List<string> output=new();
    int dataPosition,inputPosition,random=1,handler,err,erl;
    bool handling;
    Statement? remembered;
    string buffer="";

    public Machine(List<string>inputs){this.inputs=inputs;}
    void EndLine(){output.Add(buffer.TrimEnd(' '));buffer="";}
    void Message(string line)
    {
        if(buffer.Length>0)EndLine();
        output.Add(line);
    }
    static int Checked(long value)
    {
        if(value is < -32768 or > 32767)Basic.Fault("OVERFLOW");
        return (int)value;
    }
    object ValueOf(string name)=>variables.TryGetValue(name,out object? value)?
         value:Basic.NameType(name)=="S"?"":0;
    void Declare(string name,int[]bounds)
    {
        int count=1;
        foreach(int b in bounds)count*=b+1;
        object initial=Basic.NameType(name)=="S"?"":0;
        arrays[name]=new(bounds,Enumerable.Repeat(initial,count).ToArray());
    }
    Address GetAddress(Expr target)
    {
        string name=(string)target.Value;
        if(target.Kind=="variable")return new(name,null);
        int[]indices=target.Args.Select(e=>(int)Evaluate(e)).ToArray();
        if(!arrays.ContainsKey(name))Declare(name,Enumerable.Repeat(10,indices.Length).ToArray());
        ArrayDef array=arrays[name];
        if(indices.Length!=array.Bounds.Length)Basic.Fault("SUBSCRIPT OUT OF RANGE");
        int index=0;
        for(int i=0;i<indices.Length;i++)
        {
            int value=indices[i];
            if(value<0||value>array.Bounds[i])Basic.Fault("SUBSCRIPT OUT OF RANGE");
            index=index*(array.Bounds[i]+1)+value;
        }
        return new(name,index);
    }
    object Load(Address addr)=>addr.Index==null?ValueOf(addr.Name):
        arrays[addr.Name].Values[addr.Index.Value];
    void Store(Address addr,object value)
    {
        if(addr.Index==null)variables[addr.Name]=value;
        else arrays[addr.Name].Values[addr.Index.Value]=value;
    }
    object Evaluate(Expr e)
    {
        object op=e.Value;
        if(e.Kind=="constant")return op;
        if(e.Kind is "variable" or "array")return Load(GetAddress(e));
        if(e.Kind=="builtin")return (string)op=="ERR"?err:erl;
        if(e.Kind=="unary")
        {
            int a=(int)Evaluate(e.Args[0]);
            return (string)op=="NOT"?~a:Checked(-(long)a);
        }
        object[]values=e.Args.Select(Evaluate).ToArray();
        if(e.Kind=="call")return Call((string)op,values);
        object a0=values[0],b0=values[1];
        if(Basic.Ops[3].Contains((string)op))
        {
            int cmp=a0 is string x?string.CompareOrdinal(x,(string)b0):
                 ((int)a0).CompareTo((int)b0);
            bool success=(string)op switch{
                "="=>cmp==0,"<>"=>cmp!=0,"<"=>cmp<0,">"=>cmp>0,
                "<="=>cmp<=0,">="=>cmp>=0,_=>false
            };
            return success?-1:0;
        }
        if(e.Type=="S")
        {
            string value=(string)a0+(string)b0;
            if(value.Length>255)Basic.Fault("STRING TOO LONG");
            return value;
        }
        int a=(int)a0,b=(int)b0;
        switch((string)op)
        {
            case "+":return Checked((long)a+b);
            case "-":return Checked((long)a-b);
            case "*":return Checked((long)a*b);
            case "/":
                if(b==0)Basic.Fault("DIVISION BY ZERO");
                return Checked(a/b);
            case "MOD":
                if(b==0)Basic.Fault("DIVISION BY ZERO");
                return a-b*(a/b);
            case "^":
                if(b<0)Basic.Fault("ILLEGAL FUNCTION CALL");
                if(Math.Abs(a)>1&&b>15)Basic.Fault("OVERFLOW");
                long result=1;
                for(int i=0;i<b;i++)result*=a;
                return Checked(result);
            case "AND":return a&b;
            case "OR":return a|b;
        }
        Basic.Fault("ILLEGAL FUNCTION CALL");
        return 0;
    }
    object Call(string name,object[]args)
    {
        object first=args[0];
        object? second=args.Length>1?args[1]:null;
        object? third=args.Length>2?args[2]:null;
        switch(name)
        {
            case "ABS":return Checked(Math.Abs((long)(int)first));
            case "SGN":return Math.Sign((int)first);
            case "INT":return first;
            case "SQR":
                if((int)first<0)Basic.Fault("ILLEGAL FUNCTION CALL");
                return (int)Math.Sqrt((int)first);
            case "RND":
                int n=(int)first;
                if(n<1)Basic.Fault("ILLEGAL FUNCTION CALL");
                random=(int)(48271L*random%2147483647);
                return random%n+1;
            case "LEN":return ((string)first).Length;
            case "ASC":
                string source=(string)first;
                if(source.Length==0)Basic.Fault("ILLEGAL FUNCTION CALL");
                return (int)source[0];
            case "VAL":
                Match match=Regex.Match((string)first,@"\A *([+-]?[0-9]+)");
                if(!match.Success)return 0;
                if(!long.TryParse(match.Groups[1].Value,out long number))Basic.Fault("OVERFLOW");
                return Checked(number);
            case "CHR$":
                int code=(int)first;
                if(code<32||code>126)Basic.Fault("ILLEGAL FUNCTION CALL");
                return ((char)code).ToString();
            case "STR$":return ((int)first).ToString();
            case "LEFT$":
                int count=(int)second!;
                if(count<0)Basic.Fault("ILLEGAL FUNCTION CALL");
                return ((string)first)[..Math.Min(count,((string)first).Length)];
            case "RIGHT$":
                int k=(int)second!;
                if(k<0)Basic.Fault("ILLEGAL FUNCTION CALL");
                string text=(string)first;
                return text[Math.Max(0,text.Length-k)..];
            case "MID$":
                int start=(int)second!;
                int? length=third==null?null:(int)third;
                if(start<1||(length!=null&&length<0))Basic.Fault("ILLEGAL FUNCTION CALL");
                string word=(string)first;
                int begin=Math.Min(start-1,word.Length);
                return word.Substring(begin,length==null?word.Length-begin:
                    Math.Min(length.Value,word.Length-begin));
            case "INSTR":return ((string)first).IndexOf((string)second!,StringComparison.Ordinal)+1;
        }
        Basic.Fault("ILLEGAL FUNCTION CALL");
        return 0;
    }
    Statement Line(int number)
    {
        if(!entries.TryGetValue(number,out Statement? s))Basic.Fault("UNDEFINED LINE NUMBER");
        return s!;
    }
    void Push(Frame f)
    {
        if(stack.Count==100)Basic.Fault("OUT OF MEMORY");
        stack.Add(f);
    }
    int Search(string kind,string name="")
    {
        for(int i=stack.Count-1;i>=0;i--)
        {
            Frame f=stack[i];
            if(f.Kind=="GOSUB")break;
            if(f.Kind==kind&&(name==""||f.Name==name))return i;
        }
        return -1;
    }
    Statement? Matching(Statement s,string opening,string closing)
    {
        int start=sequence.IndexOf(s),depth=0;
        for(int i=start+1;i<sequence.Count;i++)
        {
            Statement t=sequence[i];
            if(t.Kind==opening)depth++;
            else if(t.Kind==closing)
            {
                if(depth==0)return t.Next;
                depth--;
            }
        }
        Basic.Fault(opening+" WITHOUT "+closing);
        return null;
    }
    Statement Subroutine(int number,Statement? after)
    {
        Statement target=Line(number);
        Push(new("GOSUB",after));
        return target;
    }
    Statement? Execute(Statement s)
    {
        Statement? following=s.Next;
        switch(s.Kind)
        {
            case "assign":
                Address addr=GetAddress(s.Target!);
                Store(addr,Evaluate(s.Expr!));
                break;
            case "PRINT":
                foreach(PrintItem item in s.Items)
                {
                    if(item.Kind==",")
                    {
                        buffer+=new string(' ',10-buffer.Length%10);
                    }
                    else if(item.Kind!=";")
                    {
                        object value=Evaluate(item.Expr!);
                        if(item.Kind=="value")buffer+=value.ToString();
                        else
                        {
                            int space=(int)value;
                            if(space<0)Basic.Fault("ILLEGAL FUNCTION CALL");
                            buffer+=new string(' ',item.Kind=="SPC"?space:
                                Math.Max(0,space-buffer.Length));
                        }
                    }
                }
                if(s.Items.Count==0||s.Items[^1].Kind is not (";" or ","))EndLine();
                break;
            case "INPUT":
            case "READ":
                foreach(Expr target in s.Targets)
                {
                    Address place=GetAddress(target);
                    object value;
                    if(s.Kind=="READ")
                    {
                        if(dataPosition==data.Count)Basic.Fault("OUT OF DATA");
                        value=data[dataPosition++].Value;
                        if(Basic.ValueType(value)!=target.Type)Basic.Fault("TYPE MISMATCH");
                    }
                    else
                    {
                        while(true)
                        {
                            if(inputPosition==inputs.Count)Basic.Fault("INPUT PAST END");
                            string word=inputs[inputPosition++];
                            if(target.Type=="S"){value=word;break;}
                            if(Regex.IsMatch(word,@"\A-?[0-9]+\z")&&
                               int.TryParse(word,out int v)&&v is >= -32768 and <= 32767)
                            {
                                value=v;break;
                            }
                            Message("?REDO FROM START");
                        }
                    }
                    Store(place,value);
                }
                break;
            case "RESTORE":
                if(s.Numbers.Count==0)dataPosition=0;
                else
                {
                    int number=s.Numbers[0];Line(number);
                    dataPosition=data.FindIndex(d=>d.Line>=number);
                    if(dataPosition<0)dataPosition=data.Count;
                }
                break;
            case "IF":
                int ci=(int)Evaluate(s.Expr!)==0?1:0;
                if(ci<s.Clauses.Count)
                {
                    Clause chosen=s.Clauses[ci];
                    following=chosen.Line==null?chosen.Body[0]:Line(chosen.Line.Value);
                }
                break;
            case "GOTO":following=Line(s.Numbers[0]);break;
            case "GOSUB":following=Subroutine(s.Numbers[0],following);break;
            case "ON":
                int index=(int)Evaluate(s.Expr!);
                if(index<0)Basic.Fault("ILLEGAL FUNCTION CALL");
                if(index>=1&&index<=s.Numbers.Count)
                {
                    following=s.Mode=="GOTO"?Line(s.Numbers[index-1]):
                        Subroutine(s.Numbers[index-1],following);
                }
                break;
            case "RETURN":
                int frame=stack.FindLastIndex(f=>f.Kind=="GOSUB");
                if(frame<0)Basic.Fault("RETURN WITHOUT GOSUB");
                following=stack[frame].Position;
                stack.RemoveRange(frame,stack.Count-frame);
                break;
            case "FOR":
                int[]numbers=s.Expressions.Select(e=>(int)Evaluate(e)).ToArray();
                int from=numbers[0],end=numbers[1],step=numbers[2];
                if(step==0)Basic.Fault("ILLEGAL FUNCTION CALL");
                int ix=Search("FOR",s.Name);
                if(ix>=0)stack.RemoveRange(ix,stack.Count-ix);
                variables[s.Name]=from;
                if((step>0&&from>end)||(step<0&&from<end))
                    following=Matching(s,"FOR","NEXT");
                else Push(new("FOR",following,s.Name,end,step));
                break;
            case "NEXT":
                int fidx=Search("FOR",s.Name);
                if(fidx<0)Basic.Fault("NEXT WITHOUT FOR");
                stack.RemoveRange(fidx+1,stack.Count-fidx-1);
                Frame current=stack[fidx];
                int count=Checked((long)(int)ValueOf(current.Name)+current.Step);
                variables[current.Name]=count;
                if((current.Step>0&&count>current.Limit)||
                   (current.Step<0&&count<current.Limit))
                    stack.RemoveAt(fidx);
                else following=current.Position;
                break;
            case "WHILE":
                if((int)Evaluate(s.Expr!)==0)following=Matching(s,"WHILE","WEND");
                else Push(new("WHILE",s));
                break;
            case "WEND":
                int widx=Search("WHILE");
                if(widx<0)Basic.Fault("WEND WITHOUT WHILE");
                following=stack[widx].Position;
                stack.RemoveRange(widx,stack.Count-widx);
                break;
            case "DIM":
                foreach(Expr target in s.Targets)
                {
                    string name=(string)target.Value;
                    int[]bounds=target.Args.Select(e=>(int)Evaluate(e)).ToArray();
                    if(arrays.ContainsKey(name))Basic.Fault("DUPLICATE DEFINITION");
                    if(bounds.Any(v=>v<0))Basic.Fault("ILLEGAL FUNCTION CALL");
                    long size=1;
                    foreach(int b in bounds)size*=b+1;
                    if(size>10000)Basic.Fault("OUT OF MEMORY");
                    Declare(name,bounds);
                }
                break;
            case "RANDOMIZE":
                int seed=(int)Evaluate(s.Expr!);
                if(seed<1)Basic.Fault("ILLEGAL FUNCTION CALL");
                random=seed;
                break;
            case "handler":
                if(s.Numbers[0]!=0)Line(s.Numbers[0]);
                handler=s.Numbers[0];
                break;
            case "RESUME":
                if(!handling)Basic.Fault("RESUME WITHOUT ERROR");
                following=s.Mode=="line"?Line(s.Numbers[0]):
                    s.Mode=="NEXT"?remembered!.Next:remembered;
                handling=false;
                break;
            case "STOP":Message("BREAK IN LINE "+s.Line);return null;
            case "END":return null;
        }
        return following;
    }
    void Connect(List<Statement> body,Statement? after,int number)
    {
        Statement? following=after;
        for(int i=body.Count-1;i>=0;i--)
        {
            Statement s=body[i];
            s.Line=number;s.Next=following;
            foreach(Clause c in s.Clauses)Connect(c.Body,following,number);
            following=s;
        }
    }
    List<string> Finish()
    {
        if(buffer.Length>0)EndLine();
        output.Add("READY");
        return output;
    }
    public List<string> Run(Dictionary<int,string> source)
    {
        List<ProgramLine>parsed=[];
        foreach(int number in source.Keys.Order())
        {
            try{parsed.Add(new(number,new Parser(Basic.Tokenize(source[number])).Parse()));}
            catch(SyntaxFault)
            {
                Message("ERROR IN LINE "+number+": SYNTAX ERROR");
                return Finish();
            }
        }
        Statement? after=null;
        for(int i=parsed.Count-1;i>=0;i--)
        {
            ProgramLine e=parsed[i];
            Connect(e.Body,after,e.Number);
            entries[e.Number]=e.Body[0];after=e.Body[0];
        }
        foreach(ProgramLine e in parsed)
            foreach(Statement s in e.Body)
            {
                sequence.Add(s);
                if(s.Kind=="DATA")foreach(object value in s.Values)data.Add(new(s.Line,value));
            }
        Statement? position=after;
        while(position!=null)
        {
            Statement current=position;
            try{position=Execute(current);}
            catch(BasicFault error)
            {
                if(handler!=0&&!handling)
                {
                    err=Basic.Errors.GetValueOrDefault(error.Message,0);
                    erl=current.Line;remembered=current;handling=true;
                    try{position=Line(handler);}
                    catch(BasicFault secondary)
                    {
                        Message("ERROR IN LINE "+current.Line+": "+secondary.Message);
                        position=null;
                    }
                }
                else
                {
                    Message("ERROR IN LINE "+current.Line+": "+error.Message);
                    position=null;
                }
            }
        }
        return Finish();
    }
}

static class Program
{
    public static void Main()
    {
        int count=int.Parse(Console.ReadLine()!);
        for(int k=0;k<count;k++)
        {
            Dictionary<int,string>source=new();
            while(true)
            {
                string line=Console.ReadLine()!;
                if(line=="RUN")break;
                Match match=Regex.Match(line,@"\A([0-9]+)(?: +(.*))?\z");
                int number=int.Parse(match.Groups[1].Value);
                if(match.Groups[2].Success)source[number]=match.Groups[2].Value;
                else source.Remove(number);
            }
            List<string>inputs=[];
            while(true)
            {
                string word=Console.ReadLine()!;
                if(word=="END")break;
                inputs.Add(word);
            }
            foreach(string line in new Machine(inputs).Run(source))Console.WriteLine(line);
        }
    }
}
