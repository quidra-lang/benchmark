import java.io.*;
import java.util.*;
import java.util.function.Supplier;

public class Main {
    static class SqlError extends RuntimeException {SqlError(String s){super(s);}}
    static SqlError error(String s){return new SqlError(s);}
    static final Set<String> RESERVED=Set.of("SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT".split(" "));
    static final Set<String> AGGREGATES=Set.of("COUNT","SUM","MIN","MAX","AVG"),COMPARISONS=Set.of("=","<>","!=","<","<=",">",">=");
    record Token(String kind,String text,Object value){}
    static List<Token> tokenize(String s){
        List<Token>a=new ArrayList<>();int i=0;while(i<s.length()){
            char c=s.charAt(i);int start=i;if(c==' '||c=='\n'){i++;continue;}if(s.startsWith("--",i)){int end=s.indexOf('\n',i);i=end<0?s.length():end;continue;}
            if(c=='\''){i=s.indexOf('\'',i+1)+1;a.add(new Token("string",s.substring(start,i),s.substring(start+1,i-1)));}
            else if(c>='0'&&c<='9'){while(i<s.length()&&s.charAt(i)>='0'&&s.charAt(i)<='9')i++;String t=s.substring(start,i);a.add(new Token("integer",t,Long.parseLong(t)));}
            else if(Character.isLetter(c)||c=='_'){while(i<s.length()&&(Character.isLetterOrDigit(s.charAt(i))||s.charAt(i)=='_'))i++;String t=s.substring(start,i),up=t.toUpperCase(Locale.ROOT);a.add(new Token(RESERVED.contains(up)?"keyword":"name",t,RESERVED.contains(up)?up:t));}
            else{String t=s.substring(i,Math.min(i+2,s.length()));if(!Set.of("<>","!=","<=",">=","||").contains(t))t=String.valueOf(c);if(t.length()==1&&"(),.;*/%+-=<>".indexOf(c)<0)throw error("unexpected character '"+c+"'");a.add(new Token("symbol",t,t));i+=t.length();}
        }return a;
    }
    static class Expr {
        String kind,op,table=null,column="",text="";List<Expr>args;Object value;int index=-1;boolean distinct,negated;
        Expr(String kind,String op,List<Expr>args,Object value){this.kind=kind;this.op=op;this.args=args;this.value=value;}
    }
    static Expr node(String kind){return node(kind,"",new ArrayList<>(),null);}
    static Expr node(String kind,String op,List<Expr>args){return node(kind,op,args,null);}
    static Expr node(String kind,String op,List<Expr>args,Object value){return new Expr(kind,op,new ArrayList<>(args),value);}
    record Column(String name,String type,int primary,boolean notNull){}
    record TableRef(String name,String alias){}
    record Item(Expr expr,String alias,String heading){}
    record Order(Expr expr,boolean descending,Long ordinal,String alias){}
    record Join(TableRef table,boolean left,Expr condition){}
    static class Query {
        boolean distinct,star;List<Item>items=new ArrayList<>();TableRef source;List<Join>joins=new ArrayList<>();Expr where,having;List<Expr>group=null;List<Order>order=new ArrayList<>();Long limit;long offset;
    }
    static class Command {
        String kind="",name="";List<Column>columns;List<String>names;List<List<Expr>>tuples;List<Map.Entry<String,Expr>>assignments;Expr where;Query query;
    }
    static class Parser {
        final List<Token>tokens;int position;Parser(List<Token>tokens){this.tokens=tokens;}
        Token peek(){return tokens.get(position);}Token take(){return tokens.get(position++);}
        boolean at(String w){Token t=peek();return (t.kind.equals("keyword")||t.kind.equals("symbol"))&&t.value.equals(w);}
        boolean accept(String w){if(!at(w))return false;position++;return true;}
        SqlError syntax(){return error("syntax error at '"+peek().text+"'");}
        void expect(String w){if(!accept(w))throw syntax();}
        String name(){if(!peek().kind.equals("name"))throw syntax();return (String)take().value;}
        long integer(){if(!peek().kind.equals("integer"))throw syntax();return (Long)take().value;}
        <T> List<T> comma(Supplier<T>read){List<T>a=new ArrayList<>();a.add(read.get());while(accept(","))a.add(read.get());return a;}
        <T> List<T> parens(Supplier<T>read){expect("(");List<T>a=comma(read);expect(")");return a;}
        String alias(){if(accept("AS"))return name();return peek().kind.equals("name")?name():null;}
        TableRef table(){String n=name(),a=alias();return new TableRef(n,a==null?n:a);}
        Expr reference(){String name=name();Expr e=node("ref");if(accept(".")){e.table=name;e.column=name();e.text=name+"."+e.column;}else e.column=e.text=name;return e;}
        Expr expr(){return expr(0);}
        Expr expr(int level){
            if(level==2&&accept("NOT"))return node("unary","NOT",List.of(expr(2)));if(level==6&&accept("-"))return node("unary","-",List.of(expr(6)));if(level==7)return primary();Expr left=expr(level+1);
            if(level==3){if(peek().kind.equals("symbol")&&COMPARISONS.contains(peek().value)){String op=(String)take().value;return node("binary",op,List.of(left,expr(4)));}if(accept("IS")){boolean neg=accept("NOT");expect("NULL");Expr e=node("isnull","",List.of(left));e.negated=neg;return e;}boolean neg=accept("NOT");Expr e=null;
                if(accept("IN")){List<Expr>a=new ArrayList<>();a.add(left);a.addAll(parens(this::expr));e=node("in","",a);}else if(accept("BETWEEN")){Expr low=expr(4);expect("AND");e=node("between","",List.of(left,low,expr(4)));}else if(accept("LIKE"))e=node("like","",List.of(left,expr(4)));else if(neg)throw syntax();if(e!=null){e.negated=neg;return e;}return left;}
            List<List<String>>ops=List.of(List.of("OR"),List.of("AND"),List.of(),List.of(),List.of("+","-","||"),List.of("*","/","%"),List.of());while(ops.get(level).stream().anyMatch(this::at)){String op=(String)take().value;left=node("binary",op,List.of(left,expr(level+1)));}return left;
        }
        Expr primary(){Token t=peek();if(t.kind.equals("integer")||t.kind.equals("string")){take();return node("literal","",List.of(),t.value);}if(accept("NULL"))return node("literal");if(t.kind.equals("name"))return reference();if(t.kind.equals("keyword")&&AGGREGATES.contains(t.value)){String n=(String)take().value;expect("(");Expr e=node("aggregate",n,List.of());if(!(n.equals("COUNT")&&accept("*"))){e.distinct=accept("DISTINCT");e.args.add(expr());}expect(")");return e;}if(accept("(")){Expr e=expr();expect(")");return node("group","",List.of(e));}throw syntax();}
        Expr clause(String w){return accept(w)?expr():null;}
        Item item(){int start=position;Expr e=expr();int stop=position;String alias=alias(),heading=alias;if(heading==null){if(e.kind.equals("ref"))heading=e.column;else{StringBuilder s=new StringBuilder();for(int i=start;i<stop;i++){if(i>start&&!tokens.get(i).kind.equals("symbol")&&!tokens.get(i-1).kind.equals("symbol"))s.append(' ');s.append(tokens.get(i).text);}heading=s.toString();}}return new Item(e,alias,heading);}
        Order orderItem(){int start=position;Expr e=expr();boolean single=position==start+1;Token t=tokens.get(start);boolean desc=accept("DESC");if(!desc)accept("ASC");return new Order(e,desc,single&&t.kind.equals("integer")?(Long)t.value:null,single&&t.kind.equals("name")?(String)t.value:null);}
        Query query(){Query q=new Query();q.distinct=accept("DISTINCT");q.star=accept("*");if(!q.star)q.items=comma(this::item);expect("FROM");q.source=table();while(at("JOIN")||at("INNER")||at("LEFT")){boolean left=accept("LEFT");if(left)accept("OUTER");else accept("INNER");expect("JOIN");TableRef t=table();expect("ON");q.joins.add(new Join(t,left,expr()));}q.where=clause("WHERE");if(accept("GROUP")){expect("BY");q.group=comma(this::reference);}q.having=clause("HAVING");if(accept("ORDER")){expect("BY");q.order=comma(this::orderItem);}if(accept("LIMIT")){q.limit=integer();if(accept("OFFSET"))q.offset=integer();}return q;}
        Column column(){String n=name();if(!at("INT")&&!at("TEXT"))throw syntax();String type=(String)take().value;int pk=0;boolean nn=false;while(true){if(accept("PRIMARY")){expect("KEY");pk++;nn=true;}else if(accept("NOT")){expect("NULL");nn=true;}else break;}return new Column(n,type,pk,nn);}
        Command statement(){Command c=new Command();if(accept("CREATE")){c.kind="create";expect("TABLE");c.name=name();c.columns=parens(this::column);}else if(accept("DROP")){c.kind="drop";expect("TABLE");c.name=name();}else if(accept("INSERT")){c.kind="insert";expect("INTO");c.name=name();if(at("("))c.names=parens(this::name);expect("VALUES");c.tuples=comma(()->parens(this::expr));}else if(accept("UPDATE")){c.kind="update";c.name=name();expect("SET");c.assignments=comma(()->{String n=name();expect("=");return Map.entry(n,expr());});c.where=clause("WHERE");}else if(accept("DELETE")){c.kind="delete";expect("FROM");c.name=name();c.where=clause("WHERE");}else if(accept("SELECT")){c.kind="select";c.query=query();}else if(accept("EXIT"))c.kind="exit";expect(";");return c;}
    }
    static class Table {
        final String name;final List<Column>columns;final int key;List<List<Object>>rows=new ArrayList<>();Table(String n,List<Column>c,int key){name=n;columns=c;this.key=key;}
        int column(String n){for(int i=0;i<columns.size();i++)if(columns.get(i).name.equals(n))return i;return -1;}
    }
    record Entry(String name,Table table,int offset){}
    static class Scope {
        final List<Entry>entries=new ArrayList<>();int width;
        void add(String n,Table t){if(entries.stream().anyMatch(e->e.name.equals(n)))throw error("duplicate table name "+n);entries.add(new Entry(n,t,width));width+=t.columns.size();}
        String resolve(Expr ref){List<Map.Entry<Integer,String>>found=new ArrayList<>();boolean seen=false;for(Entry e:entries)if(ref.table==null||e.name.equals(ref.table)){seen=true;int i=e.table.column(ref.column);if(i>=0)found.add(Map.entry(e.offset+i,e.table.columns.get(i).type));}if(ref.table!=null&&!seen)throw error("unknown table "+ref.table);if(found.isEmpty())throw error("unknown column "+ref.text);if(found.size()>1)throw error("ambiguous column "+ref.column);ref.index=found.get(0).getKey();return found.get(0).getValue();}
    }
    static boolean compatible(String a,String b){return a.equals(b)||a.equals("NULL")||b.equals("NULL");}
    static void require(String a,String b,String op){if(!compatible(a,b))throw error("type mismatch for "+op);}
    static String check(Expr e,Scope s){return check(e,s,false,null,false);}
    static String check(Expr e,Scope s,boolean allow,List<Integer>grouped,boolean inside){
        if(e.kind.equals("literal"))return e.value==null?"NULL":e.value instanceof Long?"INT":"TEXT";if(e.kind.equals("ref")){String type=s.resolve(e);if(grouped!=null&&!inside&&!grouped.contains(e.index))throw error("column "+e.text+" is not grouped");return type;}
        if(e.kind.equals("aggregate")){if(!allow||inside)throw error("misuse of aggregate "+e.op);if(e.args.isEmpty())return "INT";String type=check(e.args.get(0),s,allow,grouped,true);if(e.op.equals("SUM")||e.op.equals("AVG"))require(type,"INT",e.op);return e.op.equals("MIN")||e.op.equals("MAX")?type:"INT";}
        List<String>types=new ArrayList<>();for(Expr a:e.args)types.add(check(a,s,allow,grouped,inside));if(e.kind.equals("group"))return types.get(0);if(e.kind.equals("isnull"))return "INT";if(e.kind.equals("binary")&&COMPARISONS.contains(e.op)){require(types.get(0),types.get(1),e.op);return "INT";}if(e.kind.equals("in")||e.kind.equals("between")){for(String t:types.subList(1,types.size()))require(t,types.get(0),e.kind.equals("in")?"IN":"BETWEEN");return "INT";}String op=e.kind.equals("like")?"LIKE":e.op,type=op.equals("LIKE")||op.equals("||")?"TEXT":"INT";for(String t:types)require(t,type,op);return op.equals("||")?"TEXT":"INT";
    }
    static void condition(Expr e,Scope s,String name){condition(e,s,name,false,null);}
    static void condition(Expr e,Scope s,String name,boolean allow,List<Integer>grouped){if(e!=null)require(check(e,s,allow,grouped,false),"INT",name);}
    static boolean hasAggregate(Expr e){return e.kind.equals("aggregate")||e.args.stream().anyMatch(Main::hasAggregate);}
    static boolean truth(Object v){return v!=null&&(Long)v!=0;}
    static Object inverse(Object v){return v==null?null:((Long)v==0?1L:0L);}
    static int compare(Object a,Object b){if(Objects.equals(a,b))return 0;if(a==null)return -1;if(b==null)return 1;return a instanceof Long?Long.compare((Long)a,(Long)b):((String)a).compareTo((String)b);}
    static Object operate(String op,Object a,Object b){
        if(op.equals("AND")){if(Objects.equals(a,0L)||Objects.equals(b,0L))return 0L;return a==null||b==null?null:1L;}if(op.equals("OR")){if(truth(a)||truth(b))return 1L;return a==null||b==null?null:0L;}if(a==null||b==null)return null;if(COMPARISONS.contains(op)){int c=compare(a,b);return (switch(op){case "="->c==0;case "<>","!="->c!=0;case "<"->c<0;case "<="->c<=0;case ">"->c>0;default->c>=0;})?1L:0L;}if(op.equals("||"))return (String)a+(String)b;long x=(Long)a,y=(Long)b;return switch(op){case "+"->x+y;case "-"->x-y;case "*"->x*y;case "/"->y==0?null:x/y;case "%"->y==0?null:x%y;default->throw new IllegalStateException();};
    }
    static boolean like(String text,String pattern){boolean[]dp=new boolean[text.length()+1];dp[0]=true;for(char c:pattern.toCharArray()){if(c=='%'){for(int i=1;i<=text.length();i++)dp[i]=dp[i]||dp[i-1];}else{for(int i=text.length();i>0;i--)dp[i]=dp[i-1]&&(c=='_'||c==text.charAt(i-1));dp[0]=false;}}return dp[text.length()];}
    static Object evaluate(Expr e,List<Object>row){return evaluate(e,row,null);}
    static Object evaluate(Expr e,List<Object>row,List<List<Object>>group){
        if(e.kind.equals("literal"))return e.value;if(e.kind.equals("ref"))return row.get(e.index);if(e.kind.equals("aggregate")){if(e.args.isEmpty())return (long)group.size();List<Object>values=new ArrayList<>();for(List<Object>r:group){Object v=evaluate(e.args.get(0),r);if(v!=null&&(!e.distinct||!values.contains(v)))values.add(v);}if(e.op.equals("COUNT"))return (long)values.size();if(values.isEmpty())return null;if(e.op.equals("MIN")||e.op.equals("MAX")){Object result=values.get(0);for(Object v:values)if(e.op.equals("MIN")?compare(v,result)<0:compare(v,result)>0)result=v;return result;}long sum=0;for(Object v:values)sum+=(Long)v;return e.op.equals("AVG")?sum/values.size():sum;}
        List<Object>a=new ArrayList<>();for(Expr arg:e.args)a.add(evaluate(arg,row,group));if(e.kind.equals("group"))return a.get(0);if(e.kind.equals("unary"))return e.op.equals("NOT")?inverse(a.get(0)):a.get(0)==null?null:-(Long)a.get(0);if(e.kind.equals("binary"))return operate(e.op,a.get(0),a.get(1));if(e.kind.equals("isnull"))return (a.get(0)==null)!=e.negated?1L:0L;Object result=null;
        if(e.kind.equals("in")){if(a.get(0)!=null)result=a.subList(1,a.size()).contains(a.get(0))?1L:a.subList(1,a.size()).contains(null)?null:0L;}
        else if(e.kind.equals("between"))result=operate("AND",operate(">=",a.get(0),a.get(1)),operate("<=",a.get(0),a.get(2)));else if(a.get(0)!=null&&a.get(1)!=null)result=like((String)a.get(0),(String)a.get(1))?1L:0L;return e.negated?inverse(result):result;
    }
    static boolean satisfies(Expr e,List<Object>row,List<List<Object>>group){return e==null||truth(evaluate(e,row,group));}
    static String count(int n){return n+(n==1?" row":" rows");}
    static String written(Object v){return v==null?"NULL":v.toString();}
    static void printTable(List<Item>items,List<String>types,List<List<Object>>rows){
        List<List<String>>cells=new ArrayList<>();int[]width=new int[items.size()];for(int i=0;i<items.size();i++)width[i]=items.get(i).heading.length();for(List<Object>r:rows){List<String>a=new ArrayList<>();for(int i=0;i<r.size();i++){a.add(written(r.get(i)));width[i]=Math.max(width[i],a.get(i).length());}cells.add(a);}StringBuilder sep=new StringBuilder("+");for(int w:width)sep.append("-".repeat(w+2)).append('+');System.out.println(sep);List<String>headings=items.stream().map(Item::heading).toList();System.out.println(formatRow(headings,width,types,true));System.out.println(sep);for(List<String>r:cells)System.out.println(formatRow(r,width,types,false));System.out.println(sep);System.out.println("("+count(rows.size())+")");
    }
    static String formatRow(List<String>row,int[]width,List<String>types,boolean header){StringBuilder s=new StringBuilder("|");for(int i=0;i<row.size();i++){String v=row.get(i),pad=" ".repeat(width[i]-v.length());s.append(' ').append(!header&&types.get(i).equals("INT")?pad+v:v+pad).append(" |");}return s.toString();}
    static class Database {
        final Map<String,Table>tables=new HashMap<>();
        Table table(String n){Table t=tables.get(n);if(t==null)throw error("unknown table "+n);return t;}
        List<Integer>targets(Table t,List<String>names){List<Integer>a=new ArrayList<>();for(String n:names){int i=t.column(n);if(i<0)throw error("unknown column "+n);if(a.contains(i))throw error("duplicate column "+n);a.add(i);}return a;}
        void constraints(Table t,List<List<Object>>rows,List<Integer>checked){for(int i:checked){for(int j=0;j<t.columns.size();j++)if(t.columns.get(j).notNull&&rows.get(i).get(j)==null)throw error("NULL value in column "+t.columns.get(j).name);if(t.key>=0)for(int j=0;j<rows.size();j++)if(i!=j&&Objects.equals(rows.get(i).get(t.key),rows.get(j).get(t.key)))throw error("duplicate primary key "+written(rows.get(i).get(t.key)));}}
        void execute(Command c){
            if(c.kind.equals("select")){select(c.query);return;}
            if(c.kind.equals("create")){if(tables.containsKey(c.name))throw error("table "+c.name+" already exists");Set<String>seen=new HashSet<>();int primary=0,key=-1;for(int i=0;i<c.columns.size();i++){Column column=c.columns.get(i);if(!seen.add(column.name))throw error("duplicate column "+column.name);primary+=column.primary;if(primary>=2)throw error("multiple primary keys");if(column.primary>0)key=i;}tables.put(c.name,new Table(c.name,c.columns,key));System.out.println("Table "+c.name+" created.");return;}
            Table t=table(c.name);if(c.kind.equals("drop")){tables.remove(c.name);System.out.println("Table "+c.name+" dropped.");return;}List<List<Object>>rows=new ArrayList<>();List<Integer>checked=new ArrayList<>();int count=0;
            if(c.kind.equals("insert")){
                List<Integer>target;if(c.names!=null)target=targets(t,c.names);else{target=new ArrayList<>();for(int i=0;i<t.columns.size();i++)target.add(i);}Scope empty=new Scope();for(List<Expr>tuple:c.tuples){if(tuple.size()!=target.size())throw error("expected "+target.size()+" values, got "+tuple.size());for(int i=0;i<tuple.size();i++){Column column=t.columns.get(target.get(i));require(check(tuple.get(i),empty),column.type,"column "+column.name);}}
                rows.addAll(t.rows);for(List<Expr>tuple:c.tuples){List<Object>row=new ArrayList<>(Collections.nCopies(t.columns.size(),null));for(int i=0;i<tuple.size();i++)row.set(target.get(i),evaluate(tuple.get(i),List.of()));checked.add(rows.size());rows.add(row);}constraints(t,rows,checked);count=c.tuples.size();
            }else if(c.kind.equals("update")){
                List<Integer>target=targets(t,c.assignments.stream().map(Map.Entry::getKey).toList());Scope scope=new Scope();scope.add(t.name,t);for(int i=0;i<c.assignments.size();i++){Column column=t.columns.get(target.get(i));require(check(c.assignments.get(i).getValue(),scope),column.type,"column "+column.name);}condition(c.where,scope,"WHERE");for(int i=0;i<t.rows.size();i++){List<Object>row=t.rows.get(i),next=row;if(satisfies(c.where,row,null)){next=new ArrayList<>(row);for(int j=0;j<c.assignments.size();j++)next.set(target.get(j),evaluate(c.assignments.get(j).getValue(),row));checked.add(i);count++;}rows.add(next);}constraints(t,rows,checked);
            }else{Scope scope=new Scope();scope.add(t.name,t);condition(c.where,scope,"WHERE");for(List<Object>row:t.rows)if(satisfies(c.where,row,null))count++;else rows.add(row);}
            t.rows=rows;System.out.println(count(count)+(c.kind.equals("insert")?" inserted.":c.kind.equals("update")?" updated.":" deleted."));
        }
        void select(Query q){
            Scope scope=new Scope();scope.add(q.source.alias,table(q.source.name));for(Join j:q.joins){scope.add(j.table.alias,table(j.table.name));condition(j.condition,scope,"ON");}condition(q.where,scope,"WHERE");List<Integer>grouping=new ArrayList<>();if(q.group!=null)for(Expr e:q.group){scope.resolve(e);grouping.add(e.index);}
            if(q.star)for(Entry part:scope.entries)for(Column c:part.table.columns){Expr e=node("ref");e.table=part.name;e.column=e.text=c.name;q.items.add(new Item(e,null,c.name));}boolean aggregate=q.group!=null||q.having!=null;for(Item i:q.items)aggregate=aggregate||hasAggregate(i.expr);for(Order o:q.order)aggregate=aggregate||hasAggregate(o.expr);List<Integer>grouped=aggregate?grouping:null;List<String>types=new ArrayList<>();for(Item i:q.items)types.add(check(i.expr,scope,true,grouped,false));condition(q.having,scope,"HAVING",true,grouped);
            List<Expr>keys=new ArrayList<>();for(Order o:q.order){Expr key=null;if(o.ordinal!=null){long k=o.ordinal;if(k<1||k>q.items.size())throw error("ORDER BY position "+k+" is out of range");key=q.items.get((int)k-1).expr;}else if(o.alias!=null)for(Item i:q.items)if(o.alias.equals(i.alias)){key=i.expr;break;}if(key==null){check(o.expr,scope,true,grouped,false);key=o.expr;}keys.add(key);}
            List<List<Object>>rows=scope.entries.get(0).table.rows;for(int ji=0;ji<q.joins.size();ji++){Join j=q.joins.get(ji);Table t=scope.entries.get(ji+1).table;List<List<Object>>next=new ArrayList<>();for(List<Object>left:rows){boolean found=false;for(List<Object>right:t.rows){List<Object>combined=new ArrayList<>(left);combined.addAll(right);if(satisfies(j.condition,combined,null)){next.add(combined);found=true;}}if(j.left&&!found){List<Object>combined=new ArrayList<>(left);combined.addAll(Collections.nCopies(t.columns.size(),null));next.add(combined);}}rows=next;}List<List<Object>>filtered=new ArrayList<>();for(List<Object>r:rows)if(satisfies(q.where,r,null))filtered.add(r);rows=filtered;
            List<List<List<Object>>>groups=new ArrayList<>();if(!aggregate){for(List<Object>r:rows)groups.add(Collections.singletonList(r));}else if(q.group==null)groups.add(rows);else{Map<List<Object>,List<List<Object>>>byKey=new LinkedHashMap<>();for(List<Object>r:rows){List<Object>key=new ArrayList<>();for(int i:grouping)key.add(r.get(i));byKey.computeIfAbsent(key,k->new ArrayList<>()).add(r);}groups.addAll(byKey.values());}
            record Result(List<Object>values,List<Object>keys){}List<Result>results=new ArrayList<>();for(List<List<Object>>g:groups){List<Object>row=g.isEmpty()?List.of():g.get(0);List<List<Object>>context=aggregate?g:null;if(!satisfies(q.having,row,context))continue;List<Object>values=new ArrayList<>(),sort=new ArrayList<>();for(Item i:q.items)values.add(evaluate(i.expr,row,context));for(Expr key:keys)sort.add(evaluate(key,row,context));results.add(new Result(values,sort));}
            results.sort((a,b)->{for(int i=0;i<keys.size();i++){int c=compare(a.keys.get(i),b.keys.get(i));if(c!=0)return q.order.get(i).descending?-c:c;}return 0;});List<List<Object>>unique=new ArrayList<>();Set<List<Object>>seen=new HashSet<>();for(Result r:results)if(!q.distinct||seen.add(r.values))unique.add(r.values);int first=(int)Math.min(q.offset,unique.size()),last=q.limit==null?unique.size():(int)Math.min(unique.size(),first+q.limit);printTable(q.items,types,new ArrayList<>(unique.subList(first,last)));
        }
    }
    public static void main(String[]args)throws IOException{String source=new String(System.in.readAllBytes(),java.nio.charset.StandardCharsets.US_ASCII);List<String>statements=new ArrayList<>();int start=0;for(int i=0;i<source.length();i++){if(source.charAt(i)=='\'')i=source.indexOf('\'',i+1);else if(source.startsWith("--",i)){int end=source.indexOf('\n',i);if(end<0)break;i=end;}else if(source.charAt(i)==';'){statements.add(source.substring(start,i+1));start=i+1;}}Database db=new Database();for(String s:statements){try{Command c=new Parser(tokenize(s)).statement();if(c.kind.equals("exit"))break;if(!c.kind.isEmpty())db.execute(c);}catch(SqlError err){System.out.println("ERROR: "+err.getMessage());}}}
}
