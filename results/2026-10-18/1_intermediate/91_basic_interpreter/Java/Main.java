import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    record Token(String kind,String text,Object value) {}

    static class SyntaxFault extends RuntimeException {}
    static class BasicFault extends RuntimeException {
        BasicFault(String message){super(message);}
    }

    static void syntax(){throw new SyntaxFault();}
    static void fault(String reason){throw new BasicFault(reason);}

    static final Map<String,List<String>> signatures=Map.ofEntries(
        Map.entry("ABS",List.of("I")),Map.entry("SGN",List.of("I")),
        Map.entry("INT",List.of("I")),Map.entry("SQR",List.of("I")),
        Map.entry("RND",List.of("I")),Map.entry("LEN",List.of("S")),
        Map.entry("ASC",List.of("S")),Map.entry("VAL",List.of("S")),
        Map.entry("CHR$",List.of("I")),Map.entry("STR$",List.of("I")),
        Map.entry("LEFT$",List.of("SI")),Map.entry("RIGHT$",List.of("SI")),
        Map.entry("MID$",List.of("SI","SII")),Map.entry("INSTR",List.of("SS"))
    );

    static final Map<String,Integer> errorCodes=Map.ofEntries(
        Map.entry("NEXT WITHOUT FOR",1),Map.entry("RETURN WITHOUT GOSUB",3),
        Map.entry("OUT OF DATA",4),Map.entry("ILLEGAL FUNCTION CALL",5),
        Map.entry("OVERFLOW",6),Map.entry("OUT OF MEMORY",7),
        Map.entry("UNDEFINED LINE NUMBER",8),Map.entry("SUBSCRIPT OUT OF RANGE",9),
        Map.entry("DUPLICATE DEFINITION",10),Map.entry("DIVISION BY ZERO",11),
        Map.entry("TYPE MISMATCH",13),Map.entry("STRING TOO LONG",15),
        Map.entry("RESUME WITHOUT ERROR",20),Map.entry("FOR WITHOUT NEXT",26),
        Map.entry("WHILE WITHOUT WEND",29),Map.entry("WEND WITHOUT WHILE",30),
        Map.entry("INPUT PAST END",62)
    );

    static final List<List<String>> operators=List.of(
        List.of("OR"),List.of("AND"),List.of(),
        List.of("=","<>","<",">","<=",">="),
        List.of("+","-"),List.of("*","/","MOD"),List.of(),List.of("^")
    );

    static boolean digit(char c){return c>='0'&&c<='9';}
    static boolean upper(char c){return c>='A'&&c<='Z';}
    static boolean variable(String word){
        if(word.isEmpty()||!upper(word.charAt(0)))return false;
        String name=word.endsWith("$")?word.substring(0,word.length()-1):word;
        return name.length()==1||name.length()==2&&digit(name.charAt(1));
    }
    static String nameType(String name){return name.endsWith("$")?"S":"I";}
    static String valueType(Object value){return value instanceof String?"S":"I";}
    static int integer(Object o){return (int)o;}

    static List<Token> tokenize(String text){
        List<Token>tokens=new ArrayList<>();
        for(int p=0;p<text.length();){
            char c=text.charAt(p);
            if(c==' '){p++;continue;}
            if(c=='"'){
                int end=text.indexOf('"',p+1);
                if(end<0)syntax();
                tokens.add(new Token("S",text.substring(p,end+1),text.substring(p+1,end)));
                p=end+1;
            }else if(digit(c)){
                int start=p;
                while(p<text.length()&&digit(text.charAt(p)))p++;
                String word=text.substring(start,p);
                int n;
                try{n=Integer.parseInt(word);}
                catch(NumberFormatException error){syntax();throw error;}
                if(n>32767)syntax();
                tokens.add(new Token("I",word,n));
            }else if(upper(c)){
                if(text.startsWith("REM",p)){
                    tokens.add(new Token("W","REM","REM"));break;
                }
                int start=p;
                while(p<text.length()&&(upper(text.charAt(p))||digit(text.charAt(p))))p++;
                if(p<text.length()&&text.charAt(p)=='$')p++;
                String word=text.substring(start,p);
                tokens.add(new Token("W",word,word));
            }else{
                if("+-*/^=<>() ,;:".indexOf(c)<0)syntax();
                String pair=p+1<text.length()?text.substring(p,p+2):String.valueOf(c);
                String word=List.of("<>","<=",">=").contains(pair)?pair:String.valueOf(c);
                tokens.add(new Token("P",word,word));p+=word.length();
            }
        }
        tokens.add(new Token("E","",""));
        return tokens;
    }

    static class Expr {
        String kind;
        final String type;
        final Object value;
        final List<Expr> args;
        Expr(String kind,String type,Object value){
            this(kind,type,value,new ArrayList<>());
        }
        Expr(String kind,String type,Object value,List<Expr>args){
            this.kind=kind;this.type=type;this.value=value;this.args=args;
        }
    }
    record PrintItem(String kind,Expr expr){}
    record Clause(Integer line,List<Statement>body){}
    static class Statement {
        String kind;
        int line;
        Statement next;
        Expr expr,target;
        List<Expr> targets=new ArrayList<>(),expressions=new ArrayList<>();
        List<Object> values=new ArrayList<>();
        List<Integer> numbers=new ArrayList<>();
        String name="",mode="";
        List<Clause> clauses=new ArrayList<>();
        List<PrintItem> items=new ArrayList<>();
        Statement(String kind){this.kind=kind;}
    }

    static class Parser {
        final List<Token>tokens;
        int pos;
        Parser(List<Token>tokens){this.tokens=tokens;}
        Token current(){return tokens.get(pos);}
        boolean at(String word){
            Token t=current();
            return (t.kind().equals("P")||t.kind().equals("W"))&&t.text().equals(word);
        }
        boolean take(String word){
            if(!at(word))return false;
            pos++;return true;
        }
        void expect(String word){if(!take(word))syntax();}
        int number(){
            if(!current().kind().equals("I"))syntax();
            return (int)tokens.get(pos++).value();
        }
        Expr integer(){return integer(0);}
        Expr integer(int level){
            Expr e=expression(level);
            if(!e.type.equals("I"))syntax();
            return e;
        }
        Expr target(){
            Token token=current();
            if(!token.kind().equals("W")||!variable(token.text()))syntax();
            pos++;
            Expr result=new Expr("variable",nameType(token.text()),token.text());
            if(take("(")){
                result.kind="array";
                result.args.add(integer());
                if(take(","))result.args.add(integer());
                expect(")");
            }
            return result;
        }
        Expr primary(){
            Token token=current();
            if(token.kind().equals("I")||token.kind().equals("S")){
                pos++;return new Expr("constant",token.kind(),token.value());
            }
            if(take("(")){Expr e=expression();expect(")");return e;}
            if(token.kind().equals("W")&&variable(token.text()))return target();
            if(take("ERR"))return new Expr("builtin","I","ERR");
            if(take("ERL"))return new Expr("builtin","I","ERL");
            if(token.kind().equals("W")&&signatures.containsKey(token.text())){
                pos++;expect("(");
                List<Expr>args=new ArrayList<>();
                args.add(expression());
                while(take(","))args.add(expression());
                expect(")");
                StringBuilder types=new StringBuilder();
                for(Expr e:args)types.append(e.type);
                if(!signatures.get(token.text()).contains(types.toString()))syntax();
                return new Expr("call",nameType(token.text()),token.text(),args);
            }
            syntax();return null;
        }
        Expr expression(){return expression(0);}
        Expr expression(int level){
            if(level==2&&take("NOT"))
                return new Expr("unary","I","NOT",List.of(integer(2)));
            if(level==6&&take("-"))
                return new Expr("unary","I","-",List.of(integer(6)));
            if(level==8)return primary();
            Expr left=expression(level+1);
            while(operators.get(level).contains(current().text())){
                String op=current().text();pos++;
                Expr right=expression(level==7?6:level+1);
                if(!left.type.equals(right.type)||
                   left.type.equals("S")&&level!=3&&!op.equals("+"))syntax();
                left=new Expr("binary",level==3?"I":left.type,op,List.of(left,right));
                if(level==7)break;
            }
            return left;
        }
        Clause clause(){
            if(current().kind().equals("I"))return new Clause(number(),List.of());
            return new Clause(null,listing(true));
        }
        List<Statement>listing(){return listing(false);}
        List<Statement>listing(boolean inside){
            List<Statement>body=new ArrayList<>();
            body.add(statement(inside));
            while(take(":"))body.add(statement(inside));
            return body;
        }
        Statement statement(boolean inside){
            String word=current().text();
            if(inside&&List.of("IF","FOR","NEXT","WHILE","WEND","DATA").contains(word))
                syntax();
            Statement s=new Statement(word);
            for(String kind:List.of("REM","RETURN","WEND","END","STOP")){
                if(take(kind))return s;
            }
            if(take("PRINT")){
                boolean lastValue=false;
                while(!current().kind().equals("E")&&!at(":")&&!at("ELSE")){
                    if(take(";")){
                        s.items.add(new PrintItem(";",null));lastValue=false;
                    }else if(take(",")){
                        s.items.add(new PrintItem(",",null));lastValue=false;
                    }else{
                        String kind=at("TAB")?"TAB":at("SPC")?"SPC":"value";
                        if(kind.equals("value")&&lastValue)syntax();
                        Expr e;
                        if(kind.equals("value"))e=expression();
                        else{pos++;expect("(");e=integer();expect(")");}
                        s.items.add(new PrintItem(kind,e));lastValue=kind.equals("value");
                    }
                }
                return s;
            }
            if(take("INPUT")||take("READ")||take("DIM")){
                do{
                    Expr target=target();
                    if(word.equals("DIM")&&!target.kind.equals("array"))syntax();
                    s.targets.add(target);
                }while(take(","));
                return s;
            }
            if(take("DATA")){
                do{
                    boolean negative=take("-");
                    Token t=current();
                    if(!t.kind().equals("I")&&(!t.kind().equals("S")||negative))syntax();
                    pos++;
                    s.values.add(negative?-(int)t.value():t.value());
                }while(take(","));
                return s;
            }
            if(take("IF")){
                s.expr=integer();expect("THEN");
                s.clauses.add(clause());
                if(take("ELSE"))s.clauses.add(clause());
                if(!current().kind().equals("E"))syntax();
                return s;
            }
            if(take("GOTO")||take("GOSUB")){
                s.numbers.add(number());return s;
            }
            if(take("ON")){
                if(take("ERROR")){
                    s.kind="handler";expect("GOTO");s.numbers.add(number());
                }else{
                    s.expr=integer();
                    if(take("GOTO"))s.mode="GOTO";
                    else{expect("GOSUB");s.mode="GOSUB";}
                    s.numbers.add(number());
                    while(take(","))s.numbers.add(number());
                }
                return s;
            }
            if(take("RESUME")){
                if(take("NEXT"))s.mode="NEXT";
                else if(current().kind().equals("I")){
                    s.mode="line";s.numbers.add(number());
                }
                return s;
            }
            if(take("FOR")){
                Token t=current();
                if(!t.kind().equals("W")||!variable(t.text())||!nameType(t.text()).equals("I"))
                    syntax();
                s.name=t.text();pos++;expect("=");
                s.expressions.add(integer());expect("TO");s.expressions.add(integer());
                s.expressions.add(take("STEP")?integer():new Expr("constant","I",1));
                return s;
            }
            if(take("NEXT")){
                Token t=current();
                if(t.kind().equals("W")&&variable(t.text())&&nameType(t.text()).equals("I")){
                    s.name=t.text();pos++;
                }
                return s;
            }
            if(take("WHILE")||take("RANDOMIZE")){s.expr=integer();return s;}
            if(take("RESTORE")){
                if(current().kind().equals("I"))s.numbers.add(number());
                return s;
            }
            take("LET");s.kind="assign";s.target=target();expect("=");s.expr=expression();
            if(!s.expr.type.equals(s.target.type))syntax();
            return s;
        }
        List<Statement>parse(){
            List<Statement>result=listing();
            if(!current().kind().equals("E"))syntax();
            return result;
        }
    }

    record Address(String name,Integer index){}
    record ArrayDef(int[]bounds,Object[]values){}
    record Frame(String kind,Statement position,String name,int limit,int step){
        Frame(String kind,Statement pos){this(kind,pos,"",0,0);}
    }
    record DataValue(int line,Object value){}
    record ProgramLine(int number,List<Statement>body){}

    static class Machine {
        final List<String> inputs;
        final Map<String,Object>variables=new HashMap<>();
        final Map<String,ArrayDef>arrays=new HashMap<>();
        final List<Frame>stack=new ArrayList<>();
        final Map<Integer,Statement>entries=new HashMap<>();
        final List<Statement>sequence=new ArrayList<>();
        final List<DataValue>data=new ArrayList<>();
        final List<String>output=new ArrayList<>();
        int dataPos,inputPos,random=1,handler,err,erl;
        boolean handling;
        Statement remembered;
        StringBuilder buffer=new StringBuilder();

        Machine(List<String>inputs){this.inputs=inputs;}
        void endLine(){
            String s=buffer.toString().replaceFirst(" +$","");
            output.add(s);buffer.setLength(0);
        }
        void message(String s){if(buffer.length()>0)endLine();output.add(s);}
        static int checked(long n){
            if(n< -32768||n>32767)fault("OVERFLOW");
            return (int)n;
        }
        Object valueOf(String name){
            return variables.getOrDefault(name,nameType(name).equals("S")?"":0);
        }
        void declare(String name,int[]bounds){
            int count=1;
            for(int b:bounds)count*=b+1;
            Object[]values=new Object[count];
            Arrays.fill(values,nameType(name).equals("S")?"":0);
            arrays.put(name,new ArrayDef(bounds,values));
        }
        Address address(Expr target){
            String name=(String)target.value;
            if(target.kind.equals("variable"))return new Address(name,null);
            int[]indices=new int[target.args.size()];
            for(int i=0;i<indices.length;i++)indices[i]=(int)evaluate(target.args.get(i));
            if(!arrays.containsKey(name)){
                int[]bounds=new int[indices.length];Arrays.fill(bounds,10);
                declare(name,bounds);
            }
            ArrayDef array=arrays.get(name);
            if(indices.length!=array.bounds().length)fault("SUBSCRIPT OUT OF RANGE");
            int index=0;
            for(int i=0;i<indices.length;i++){
                int value=indices[i];
                if(value<0||value>array.bounds()[i])fault("SUBSCRIPT OUT OF RANGE");
                index=index*(array.bounds()[i]+1)+value;
            }
            return new Address(name,index);
        }
        Object load(Address a){
            if(a.index()==null)return valueOf(a.name());
            return arrays.get(a.name()).values()[a.index()];
        }
        void store(Address a,Object value){
            if(a.index()==null)variables.put(a.name(),value);
            else arrays.get(a.name()).values()[a.index()]=value;
        }
        Object evaluate(Expr e){
            Object op=e.value;
            if(e.kind.equals("constant"))return op;
            if(e.kind.equals("variable")||e.kind.equals("array"))
                return load(address(e));
            if(e.kind.equals("builtin"))return op.equals("ERR")?err:erl;
            if(e.kind.equals("unary")){
                int n=(int)evaluate(e.args.get(0));
                return op.equals("NOT")?~n:checked(-(long)n);
            }
            List<Object>args=new ArrayList<>();
            for(Expr child:e.args)args.add(evaluate(child));
            if(e.kind.equals("call"))return call((String)op,args);
            Object left=args.get(0),right=args.get(1);
            if(operators.get(3).contains(op)){
                int cmp=left instanceof String
                    ?((String)left).compareTo((String)right)
                    :Integer.compare((int)left,(int)right);
                boolean success=switch((String)op){
                    case "="->cmp==0;case "<>"->cmp!=0;case "<"->cmp<0;
                    case ">"->cmp>0;case "<="->cmp<=0;case ">="->cmp>=0;
                    default->false;
                };
                return success?-1:0;
            }
            if(e.type.equals("S")){
                String s=(String)left+(String)right;
                if(s.length()>255)fault("STRING TOO LONG");
                return s;
            }
            int a=(int)left,b=(int)right;
            switch((String)op){
                case "+":return checked((long)a+b);
                case "-":return checked((long)a-b);
                case "*":return checked((long)a*b);
                case "/":
                    if(b==0)fault("DIVISION BY ZERO");
                    return checked(a/b);
                case "MOD":
                    if(b==0)fault("DIVISION BY ZERO");
                    return a-b*(a/b);
                case "^":
                    if(b<0)fault("ILLEGAL FUNCTION CALL");
                    if(Math.abs(a)>1&&b>15)fault("OVERFLOW");
                    long total=1;
                    for(int i=0;i<b;i++)total*=a;
                    return checked(total);
                case "AND":return a&b;
                case "OR":return a|b;
            }
            fault("ILLEGAL FUNCTION CALL");
            return 0;
        }
        Object call(String name,List<Object>args){
            Object a=args.get(0),b=args.size()>1?args.get(1):null,
                   c=args.size()>2?args.get(2):null;
            switch(name){
                case "ABS":return checked(Math.abs((long)(int)a));
                case "SGN":return Integer.compare((int)a,0);
                case "INT":return a;
                case "SQR":
                    if((int)a<0)fault("ILLEGAL FUNCTION CALL");
                    return (int)Math.sqrt((int)a);
                case "RND":
                    int n=(int)a;
                    if(n<1)fault("ILLEGAL FUNCTION CALL");
                    random=(int)(48271L*random%2147483647L);
                    return random%n+1;
                case "LEN":return ((String)a).length();
                case "ASC":
                    if(((String)a).isEmpty())fault("ILLEGAL FUNCTION CALL");
                    return (int)((String)a).charAt(0);
                case "VAL":
                    Matcher m=Pattern.compile("^ *([+-]?[0-9]+)").matcher((String)a);
                    if(!m.find())return 0;
                    long number;
                    try{number=Long.parseLong(m.group(1));}
                    catch(NumberFormatException e){fault("OVERFLOW");return 0;}
                    return checked(number);
                case "CHR$":
                    int code=(int)a;
                    if(code<32||code>126)fault("ILLEGAL FUNCTION CALL");
                    return Character.toString(code);
                case "STR$":return Integer.toString((int)a);
                case "LEFT$":
                    int count=(int)b;
                    if(count<0)fault("ILLEGAL FUNCTION CALL");
                    return ((String)a).substring(0,Math.min(count,((String)a).length()));
                case "RIGHT$":
                    int k=(int)b;
                    if(k<0)fault("ILLEGAL FUNCTION CALL");
                    String word=(String)a;
                    return word.substring(Math.max(0,word.length()-k));
                case "MID$":
                    int start=(int)b;
                    Integer len=c==null?null:(int)c;
                    if(start<1||len!=null&&len<0)fault("ILLEGAL FUNCTION CALL");
                    String text=(String)a;
                    int begin=Math.min(start-1,text.length());
                    int end=len==null?text.length():Math.min(text.length(),begin+len);
                    return text.substring(begin,end);
                case "INSTR":return ((String)a).indexOf((String)b)+1;
            }
            fault("ILLEGAL FUNCTION CALL");return 0;
        }
        Statement line(int number){
            Statement result=entries.get(number);
            if(result==null)fault("UNDEFINED LINE NUMBER");
            return result;
        }
        void push(Frame f){
            if(stack.size()==100)fault("OUT OF MEMORY");
            stack.add(f);
        }
        int search(String kind,String name){
            for(int i=stack.size()-1;i>=0;i--){
                Frame f=stack.get(i);
                if(f.kind().equals("GOSUB"))break;
                if(f.kind().equals(kind)&&(name.isEmpty()||f.name().equals(name)))return i;
            }
            return -1;
        }
        Statement matching(Statement s,String opening,String closing){
            int start=sequence.indexOf(s),depth=0;
            for(int i=start+1;i<sequence.size();i++){
                Statement t=sequence.get(i);
                if(t.kind.equals(opening))depth++;
                else if(t.kind.equals(closing)){
                    if(depth==0)return t.next;
                    depth--;
                }
            }
            fault(opening+" WITHOUT "+closing);
            return null;
        }
        Statement subroutine(int number,Statement after){
            Statement target=line(number);
            push(new Frame("GOSUB",after));
            return target;
        }
        Statement execute(Statement s){
            Statement following=s.next;
            switch(s.kind){
                case "assign":{
                    Address a=address(s.target);
                    store(a,evaluate(s.expr));
                    break;
                }
                case "PRINT":{
                    for(PrintItem item:s.items){
                        if(item.kind().equals(",")){
                            buffer.append(" ".repeat(10-buffer.length()%10));
                        }else if(!item.kind().equals(";")){
                            Object value=evaluate(item.expr());
                            if(item.kind().equals("value"))buffer.append(value);
                            else{
                                int n=(int)value;
                                if(n<0)fault("ILLEGAL FUNCTION CALL");
                                buffer.append(" ".repeat(item.kind().equals("SPC")
                                    ?n:Math.max(0,n-buffer.length())));
                            }
                        }
                    }
                    if(s.items.isEmpty()||!List.of(";",",").contains(s.items.getLast().kind()))
                        endLine();
                    break;
                }
                case "INPUT","READ":{
                    for(Expr target:s.targets){
                        Address a=address(target);
                        Object value;
                        if(s.kind.equals("READ")){
                            if(dataPos>=data.size())fault("OUT OF DATA");
                            value=data.get(dataPos++).value();
                            if(!valueType(value).equals(target.type))fault("TYPE MISMATCH");
                        }else{
                            while(true){
                                if(inputPos>=inputs.size())fault("INPUT PAST END");
                                String text=inputs.get(inputPos++);
                                if(target.type.equals("S")){value=text;break;}
                                Integer n=null;
                                try{n=Integer.parseInt(text);}
                                catch(NumberFormatException ignored){}
                                if(n!=null&&n>=-32768&&n<=32767&&text.matches("-?[0-9]+")){
                                    value=n;break;
                                }
                                message("?REDO FROM START");
                            }
                        }
                        store(a,value);
                    }
                    break;
                }
                case "RESTORE":{
                    if(s.numbers.isEmpty())dataPos=0;
                    else{
                        int number=s.numbers.get(0);line(number);
                        dataPos=data.size();
                        for(int i=0;i<data.size();i++){
                            if(data.get(i).line()>=number){dataPos=i;break;}
                        }
                    }
                    break;
                }
                case "IF":{
                    int index=(int)evaluate(s.expr)==0?1:0;
                    if(index<s.clauses.size()){
                        Clause chosen=s.clauses.get(index);
                        following=chosen.line()==null?chosen.body().get(0):line(chosen.line());
                    }
                    break;
                }
                case "GOTO":following=line(s.numbers.get(0));break;
                case "GOSUB":following=subroutine(s.numbers.get(0),following);break;
                case "ON":{
                    int ix=(int)evaluate(s.expr);
                    if(ix<0)fault("ILLEGAL FUNCTION CALL");
                    if(ix>=1&&ix<=s.numbers.size()){
                        following=s.mode.equals("GOTO")?line(s.numbers.get(ix-1)):
                            subroutine(s.numbers.get(ix-1),following);
                    }
                    break;
                }
                case "RETURN":{
                    int ix=-1;
                    for(int i=stack.size()-1;i>=0;i--){
                        if(stack.get(i).kind().equals("GOSUB")){ix=i;break;}
                    }
                    if(ix<0)fault("RETURN WITHOUT GOSUB");
                    following=stack.get(ix).position();
                    stack.subList(ix,stack.size()).clear();
                    break;
                }
                case "FOR":{
                    int start=(int)evaluate(s.expressions.get(0));
                    int limit=(int)evaluate(s.expressions.get(1));
                    int step=(int)evaluate(s.expressions.get(2));
                    if(step==0)fault("ILLEGAL FUNCTION CALL");
                    int ix=search("FOR",s.name);
                    if(ix>=0)stack.subList(ix,stack.size()).clear();
                    variables.put(s.name,start);
                    if(step>0&&start>limit||step<0&&start<limit)
                        following=matching(s,"FOR","NEXT");
                    else push(new Frame("FOR",following,s.name,limit,step));
                    break;
                }
                case "NEXT":{
                    int ix=search("FOR",s.name);
                    if(ix<0)fault("NEXT WITHOUT FOR");
                    stack.subList(ix+1,stack.size()).clear();
                    Frame f=stack.get(ix);
                    int value=checked((long)(int)valueOf(f.name())+f.step());
                    variables.put(f.name(),value);
                    if(f.step()>0&&value>f.limit()||f.step()<0&&value<f.limit())
                        stack.remove(ix);
                    else following=f.position();
                    break;
                }
                case "WHILE":{
                    if((int)evaluate(s.expr)==0)following=matching(s,"WHILE","WEND");
                    else push(new Frame("WHILE",s));
                    break;
                }
                case "WEND":{
                    int ix=search("WHILE","");
                    if(ix<0)fault("WEND WITHOUT WHILE");
                    following=stack.get(ix).position();
                    stack.subList(ix,stack.size()).clear();
                    break;
                }
                case "DIM":{
                    for(Expr target:s.targets){
                        String name=(String)target.value;
                        int[]bounds=new int[target.args.size()];
                        for(int i=0;i<bounds.length;i++)bounds[i]=(int)evaluate(target.args.get(i));
                        if(arrays.containsKey(name))fault("DUPLICATE DEFINITION");
                        int count=1;
                        for(int bound:bounds){
                            if(bound<0)fault("ILLEGAL FUNCTION CALL");
                            count*=bound+1;
                        }
                        if(count>10000)fault("OUT OF MEMORY");
                        declare(name,bounds);
                    }
                    break;
                }
                case "RANDOMIZE":{
                    int n=(int)evaluate(s.expr);
                    if(n<1)fault("ILLEGAL FUNCTION CALL");
                    random=n;
                    break;
                }
                case "handler":{
                    if(s.numbers.get(0)!=0)line(s.numbers.get(0));
                    handler=s.numbers.get(0);
                    break;
                }
                case "RESUME":{
                    if(!handling)fault("RESUME WITHOUT ERROR");
                    following=s.mode.equals("line")?line(s.numbers.get(0)):
                              s.mode.equals("NEXT")?remembered.next:remembered;
                    handling=false;
                    break;
                }
                case "STOP":message("BREAK IN LINE "+s.line);return null;
                case "END":return null;
            }
            return following;
        }
        void connect(List<Statement>body,Statement after,int number){
            Statement following=after;
            for(int i=body.size()-1;i>=0;i--){
                Statement s=body.get(i);
                s.line=number;s.next=following;
                for(Clause c:s.clauses)connect(c.body(),following,number);
                following=s;
            }
        }
        List<String>finish(){
            if(!buffer.isEmpty())endLine();
            output.add("READY");return output;
        }
        List<String>run(Map<Integer,String>source){
            List<ProgramLine>parsed=new ArrayList<>();
            List<Integer>numbers=new ArrayList<>(source.keySet());
            numbers.sort(Comparator.naturalOrder());
            for(int number:numbers){
                try{
                    parsed.add(new ProgramLine(number,new Parser(tokenize(source.get(number))).parse()));
                }catch(SyntaxFault failure){
                    message("ERROR IN LINE "+number+": SYNTAX ERROR");
                    return finish();
                }
            }
            Statement after=null;
            for(int i=parsed.size()-1;i>=0;i--){
                ProgramLine e=parsed.get(i);
                connect(e.body(),after,e.number());
                entries.put(e.number(),e.body().get(0));
                after=e.body().get(0);
            }
            for(ProgramLine e:parsed){
                for(Statement s:e.body()){
                    sequence.add(s);
                    if(s.kind.equals("DATA")){
                        for(Object value:s.values)data.add(new DataValue(s.line,value));
                    }
                }
            }
            Statement position=after;
            while(position!=null){
                Statement s=position;
                try{position=execute(s);}
                catch(BasicFault failure){
                    if(handler!=0&&!handling){
                        err=errorCodes.getOrDefault(failure.getMessage(),0);
                        erl=s.line;remembered=s;handling=true;
                        try{position=line(handler);}
                        catch(BasicFault secondary){
                            message("ERROR IN LINE "+s.line+": "+secondary.getMessage());
                            position=null;
                        }
                    }else{
                        message("ERROR IN LINE "+s.line+": "+failure.getMessage());
                        position=null;
                    }
                }
            }
            return finish();
        }
    }

    public static void main(String[]args)throws Exception{
        BufferedReader reader=new BufferedReader(new InputStreamReader(System.in));
        int count=Integer.parseInt(reader.readLine());
        StringBuilder output=new StringBuilder();
        for(int n=0;n<count;n++){
            Map<Integer,String>source=new HashMap<>();
            while(true){
                String line=reader.readLine();
                if(line.equals("RUN"))break;
                int at=line.indexOf(' ');
                int number=Integer.parseInt(at<0?line:line.substring(0,at));
                if(at<0)source.remove(number);
                else source.put(number,line.substring(at+1).replaceFirst("^ +",""));
            }
            List<String>inputs=new ArrayList<>();
            while(true){
                String line=reader.readLine();
                if(line.equals("END"))break;
                inputs.add(line);
            }
            for(String line:new Machine(inputs).run(source))
                output.append(line).append('\n');
        }
        System.out.print(output);
    }
}
