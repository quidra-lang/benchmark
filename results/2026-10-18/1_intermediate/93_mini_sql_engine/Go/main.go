package main

import (
 "fmt"
 "io"
 "os"
 "sort"
 "strconv"
 "strings"
)

type sqlError string
func fail(s string){panic(sqlError(s))}
func wordSet(s string)map[string]bool{m:=map[string]bool{};for _,w:=range strings.Fields(s){m[w]=true};return m}
var reserved=wordSet("SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT")
var aggregates=wordSet("COUNT SUM MIN MAX AVG")
var comparisons=wordSet("= <> != < <= > >=")
type token struct{kind,text string;value any}
func digit(c byte)bool{return c>='0'&&c<='9'}
func letter(c byte)bool{return c>='a'&&c<='z'||c>='A'&&c<='Z'||c=='_'}
func tokenize(s string)[]token{
 a:=[]token{};for i:=0;i<len(s);{c:=s[i];start:=i;if c==' '||c=='\n'{i++;continue};if strings.HasPrefix(s[i:],"--"){end:=strings.IndexByte(s[i:],'\n');if end<0{break};i+=end;continue}
  if c=='\''{i+=1+strings.IndexByte(s[i+1:],'\'')+1;a=append(a,token{"string",s[start:i],s[start+1:i-1]})
  }else if digit(c){for i<len(s)&&digit(s[i]){i++};n,_:=strconv.ParseInt(s[start:i],10,64);a=append(a,token{"integer",s[start:i],n})
  }else if letter(c){for i<len(s)&&(letter(s[i])||digit(s[i])){i++};text:=s[start:i];up:=strings.ToUpper(text);kind:="name";value:=text;if reserved[up]{kind="keyword";value=up};a=append(a,token{kind,text,value})
  }else{t:=s[i:i+1];if i+1<len(s){two:=s[i:i+2];if two=="<>"||two=="!="||two=="<="||two==">="||two=="||"{t=two}};if len(t)==1&&!strings.ContainsRune("(),.;*/%+-=<>",rune(c)){fail("unexpected character '"+string(c)+"'")};a=append(a,token{"symbol",t,t});i+=len(t)}
 };return a
}
type expr struct{kind,op,table,column,text string;args []*expr;value any;index int;distinct,negated bool}
func node(k,op string,a ...*expr)*expr{return &expr{kind:k,op:op,args:a,index:-1}}
type column struct{name,kind string;primary int;notNull bool}
type tableRef struct{name,alias string}
type item struct{expr *expr;alias,heading string}
type orderItem struct{expr *expr;descending bool;ordinal *int64;alias string}
type join struct{table tableRef;left bool;condition *expr}
type query struct{distinct,star bool;items []item;source tableRef;joins []join;where,having *expr;group []*expr;order []orderItem;limit *int64;offset int64}
type assignment struct{name string;expr *expr}
type command struct{kind,name string;columns []column;names []string;tuples [][]*expr;assignments []assignment;where *expr;query *query}
type parser struct{tokens []token;position int}
func(p *parser)peek()token{return p.tokens[p.position]}
func(p *parser)take()token{t:=p.peek();p.position++;return t}
func(p *parser)at(w string)bool{t:=p.peek();return (t.kind=="symbol"||t.kind=="keyword")&&t.value==w}
func(p *parser)accept(w string)bool{if !p.at(w){return false};p.position++;return true}
func(p *parser)syntax(){fail("syntax error at '"+p.peek().text+"'")}
func(p *parser)expect(w string){if !p.accept(w){p.syntax()}}
func(p *parser)name()string{if p.peek().kind!="name"{p.syntax()};return p.take().value.(string)}
func(p *parser)integer()int64{if p.peek().kind!="integer"{p.syntax()};return p.take().value.(int64)}
func(p *parser)names()[]string{a:=[]string{p.name()};for p.accept(","){a=append(a,p.name())};return a}
func(p *parser)exprs()[]*expr{a:=[]*expr{p.expression(0)};for p.accept(","){a=append(a,p.expression(0))};return a}
func(p *parser)tuple()[]*expr{p.expect("(");a:=p.exprs();p.expect(")");return a}
func(p *parser)alias()string{if p.accept("AS"){return p.name()};if p.peek().kind=="name"{return p.name()};return ""}
func(p *parser)table()tableRef{n:=p.name();a:=p.alias();if a==""{a=n};return tableRef{n,a}}
func(p *parser)reference()*expr{n:=p.name();e:=node("ref","");if p.accept("."){e.table=n;e.column=p.name();e.text=n+"."+e.column}else{e.column=n;e.text=n};return e}
func(p *parser)expression(level int)*expr{
 if level==2&&p.accept("NOT"){return node("unary","NOT",p.expression(2))};if level==6&&p.accept("-"){return node("unary","-",p.expression(6))};if level==7{return p.primary()};left:=p.expression(level+1)
 if level==3{t:=p.peek();if t.kind=="symbol"&&comparisons[t.value.(string)]{op:=p.take().value.(string);return node("binary",op,left,p.expression(4))};if p.accept("IS"){neg:=p.accept("NOT");p.expect("NULL");e:=node("isnull","",left);e.negated=neg;return e};neg:=p.accept("NOT");var e *expr
  if p.accept("IN"){p.expect("(");a:=append([]*expr{left},p.exprs()...);p.expect(")");e=node("in","",a...)}else if p.accept("BETWEEN"){low:=p.expression(4);p.expect("AND");e=node("between","",left,low,p.expression(4))}else if p.accept("LIKE"){e=node("like","",left,p.expression(4))}else if neg{p.syntax()};if e!=nil{e.negated=neg;return e};return left
 }
 ops:=[][]string{{"OR"},{"AND"},{},{},{"+","-","||"},{"*","/","%"},{}}
 for{found:=false;for _,op:=range ops[level]{if p.at(op){found=true;break}};if !found{break};op:=p.take().value.(string);left=node("binary",op,left,p.expression(level+1))};return left
}
func(p *parser)primary()*expr{t:=p.peek();if t.kind=="integer"||t.kind=="string"{p.take();e:=node("literal","");e.value=t.value;return e};if p.accept("NULL"){return node("literal","")};if t.kind=="name"{return p.reference()};if t.kind=="keyword"&&aggregates[t.value.(string)]{n:=p.take().value.(string);p.expect("(");e:=node("aggregate",n);if !(n=="COUNT"&&p.accept("*")){e.distinct=p.accept("DISTINCT");e.args=[]*expr{p.expression(0)}};p.expect(")");return e};if p.accept("("){e:=p.expression(0);p.expect(")");return node("group","",e)};p.syntax();return nil}
func(p *parser)clause(w string)*expr{if p.accept(w){return p.expression(0)};return nil}
func(p *parser)selectItem()item{start:=p.position;e:=p.expression(0);stop:=p.position;a:=p.alias();h:=a;if h==""{if e.kind=="ref"{h=e.column}else{for i:=start;i<stop;i++{if i>start&&p.tokens[i].kind!="symbol"&&p.tokens[i-1].kind!="symbol"{h+=" "};h+=p.tokens[i].text}}};return item{e,a,h}}
func(p *parser)orderItem()orderItem{start:=p.position;e:=p.expression(0);single:=p.position==start+1;t:=p.tokens[start];desc:=p.accept("DESC");if !desc{p.accept("ASC")};o:=orderItem{expr:e,descending:desc};if single&&t.kind=="integer"{n:=t.value.(int64);o.ordinal=&n};if single&&t.kind=="name"{o.alias=t.value.(string)};return o}
func(p *parser)query()*query{q:=&query{distinct:p.accept("DISTINCT"),star:p.accept("*")};if !q.star{q.items=append(q.items,p.selectItem());for p.accept(","){q.items=append(q.items,p.selectItem())}};p.expect("FROM");q.source=p.table();for p.at("JOIN")||p.at("INNER")||p.at("LEFT"){left:=p.accept("LEFT");if left{p.accept("OUTER")}else{p.accept("INNER")};p.expect("JOIN");t:=p.table();p.expect("ON");q.joins=append(q.joins,join{t,left,p.expression(0)})};q.where=p.clause("WHERE");if p.accept("GROUP"){p.expect("BY");q.group=[]*expr{p.reference()};for p.accept(","){q.group=append(q.group,p.reference())}};q.having=p.clause("HAVING");if p.accept("ORDER"){p.expect("BY");q.order=append(q.order,p.orderItem());for p.accept(","){q.order=append(q.order,p.orderItem())}};if p.accept("LIMIT"){n:=p.integer();q.limit=&n;if p.accept("OFFSET"){q.offset=p.integer()}};return q}
func(p *parser)column()column{n:=p.name();if !p.at("INT")&&!p.at("TEXT"){p.syntax()};c:=column{name:n,kind:p.take().value.(string)};for{if p.accept("PRIMARY"){p.expect("KEY");c.primary++;c.notNull=true}else if p.accept("NOT"){p.expect("NULL");c.notNull=true}else{break}};return c}
func(p *parser)statement()command{c:=command{};if p.accept("CREATE"){c.kind="create";p.expect("TABLE");c.name=p.name();p.expect("(");c.columns=append(c.columns,p.column());for p.accept(","){c.columns=append(c.columns,p.column())};p.expect(")")}else if p.accept("DROP"){c.kind="drop";p.expect("TABLE");c.name=p.name()}else if p.accept("INSERT"){c.kind="insert";p.expect("INTO");c.name=p.name();if p.accept("("){c.names=p.names();p.expect(")")};p.expect("VALUES");c.tuples=append(c.tuples,p.tuple());for p.accept(","){c.tuples=append(c.tuples,p.tuple())}}else if p.accept("UPDATE"){c.kind="update";c.name=p.name();p.expect("SET");for{n:=p.name();p.expect("=");c.assignments=append(c.assignments,assignment{n,p.expression(0)});if !p.accept(","){break}};c.where=p.clause("WHERE")}else if p.accept("DELETE"){c.kind="delete";p.expect("FROM");c.name=p.name();c.where=p.clause("WHERE")}else if p.accept("SELECT"){c.kind="select";c.query=p.query()}else if p.accept("EXIT"){c.kind="exit"};p.expect(";");return c}
type row []any
type table struct{name string;columns []column;key int;rows []row}
func(t *table)column(n string)int{for i,c:=range t.columns{if c.name==n{return i}};return -1}
type entry struct{name string;table *table;offset int}
type scope struct{entries []entry;width int}
func(s *scope)add(n string,t *table){for _,e:=range s.entries{if e.name==n{fail("duplicate table name "+n)}};s.entries=append(s.entries,entry{n,t,s.width});s.width+=len(t.columns)}
func(s *scope)resolve(e *expr)string{found:=-1;kind:="";seen:=false;for _,p:=range s.entries{if e.table==""||e.table==p.name{seen=true;i:=p.table.column(e.column);if i>=0{if found>=0{fail("ambiguous column "+e.column)};found=p.offset+i;kind=p.table.columns[i].kind}}};if e.table!=""&&!seen{fail("unknown table "+e.table)};if found<0{fail("unknown column "+e.text)};e.index=found;return kind}
func compatible(a,b string)bool{return a==b||a=="NULL"||b=="NULL"}
func require(a,b,op string){if !compatible(a,b){fail("type mismatch for "+op)}}
func check(e *expr,s *scope,allow bool,grouped []int,inside bool)string{
 if e.kind=="literal"{if e.value==nil{return "NULL"};if _,ok:=e.value.(int64);ok{return "INT"};return "TEXT"};if e.kind=="ref"{t:=s.resolve(e);if grouped!=nil&&!inside{ok:=false;for _,i:=range grouped{if i==e.index{ok=true}};if !ok{fail("column "+e.text+" is not grouped")}};return t}
 if e.kind=="aggregate"{if !allow||inside{fail("misuse of aggregate "+e.op)};if len(e.args)==0{return "INT"};t:=check(e.args[0],s,allow,grouped,true);if e.op=="SUM"||e.op=="AVG"{require(t,"INT",e.op)};if e.op=="MIN"||e.op=="MAX"{return t};return "INT"}
 types:=[]string{};for _,a:=range e.args{types=append(types,check(a,s,allow,grouped,inside))};if e.kind=="group"{return types[0]};if e.kind=="isnull"{return "INT"};if e.kind=="binary"&&comparisons[e.op]{require(types[0],types[1],e.op);return "INT"};if e.kind=="in"||e.kind=="between"{op:="IN";if e.kind=="between"{op="BETWEEN"};for _,t:=range types[1:]{require(t,types[0],op)};return "INT"};op:=e.op;if e.kind=="like"{op="LIKE"};kind:="INT";if op=="LIKE"||op=="||"{kind="TEXT"};for _,t:=range types{require(t,kind,op)};if op=="||"{return "TEXT"};return "INT"
}
func condition(e *expr,s *scope,name string,allow bool,grouped []int){if e!=nil{require(check(e,s,allow,grouped,false),"INT",name)}}
func hasAggregate(e *expr)bool{if e.kind=="aggregate"{return true};for _,a:=range e.args{if hasAggregate(a){return true}};return false}
func truth(v any)bool{return v!=nil&&v.(int64)!=0}
func boolean(b bool)int64{if b{return 1};return 0}
func inverse(v any)any{if v==nil{return nil};return boolean(v.(int64)==0)}
func compare(a,b any)int{if a==b{return 0};if a==nil{return -1};if b==nil{return 1};if x,ok:=a.(int64);ok{if x<b.(int64){return -1};return 1};return strings.Compare(a.(string),b.(string))}
func operate(op string,a,b any)any{
 if op=="AND"{if a==int64(0)||b==int64(0){return int64(0)};if a==nil||b==nil{return nil};return int64(1)};if op=="OR"{if truth(a)||truth(b){return int64(1)};if a==nil||b==nil{return nil};return int64(0)};if a==nil||b==nil{return nil};if comparisons[op]{c:=compare(a,b);switch op{case "=":return boolean(c==0);case "<>","!=":return boolean(c!=0);case "<":return boolean(c<0);case "<=":return boolean(c<=0);case ">":return boolean(c>0);default:return boolean(c>=0)}};if op=="||"{return a.(string)+b.(string)};x,y:=a.(int64),b.(int64);switch op{case "+":return x+y;case "-":return x-y;case "*":return x*y;case "/":if y==0{return nil};return x/y;case "%":if y==0{return nil};return x%y};panic("invalid operator")
}
func like(text,pattern string)bool{dp:=make([]bool,len(text)+1);dp[0]=true;for _,c:=range pattern{if c=='%'{for i:=1;i<=len(text);i++{dp[i]=dp[i]||dp[i-1]}}else{for i:=len(text);i>0;i--{dp[i]=dp[i-1]&&(c=='_'||byte(c)==text[i-1])};dp[0]=false}};return dp[len(text)]}
func evaluate(e *expr,r row,group []row)any{
 if e.kind=="literal"{return e.value};if e.kind=="ref"{return r[e.index]};if e.kind=="aggregate"{if len(e.args)==0{return int64(len(group))};values:=[]any{};seen:=map[any]bool{};for _,row:=range group{v:=evaluate(e.args[0],row,nil);if v!=nil&&(!e.distinct||!seen[v]){values=append(values,v);seen[v]=true}};if e.op=="COUNT"{return int64(len(values))};if len(values)==0{return nil};if e.op=="MIN"||e.op=="MAX"{result:=values[0];for _,v:=range values{if e.op=="MIN"&&compare(v,result)<0||e.op=="MAX"&&compare(v,result)>0{result=v}};return result};var sum int64;for _,v:=range values{sum+=v.(int64)};if e.op=="AVG"{return sum/int64(len(values))};return sum}
 a:=[]any{};for _,arg:=range e.args{a=append(a,evaluate(arg,r,group))};if e.kind=="group"{return a[0]};if e.kind=="unary"{if e.op=="NOT"{return inverse(a[0])};if a[0]==nil{return nil};return -a[0].(int64)};if e.kind=="binary"{return operate(e.op,a[0],a[1])};if e.kind=="isnull"{return boolean((a[0]==nil)!=e.negated)};var result any
 if e.kind=="in"{if a[0]!=nil{found,unknown:=false,false;for _,v:=range a[1:]{if v==nil{unknown=true}else if v==a[0]{found=true}};if found{result=int64(1)}else if !unknown{result=int64(0)}}}else if e.kind=="between"{result=operate("AND",operate(">=",a[0],a[1]),operate("<=",a[0],a[2]))}else if a[0]!=nil&&a[1]!=nil{result=boolean(like(a[0].(string),a[1].(string)))};if e.negated{return inverse(result)};return result
}
func satisfies(e *expr,r row,g []row)bool{return e==nil||truth(evaluate(e,r,g))}
func countRows(n int)string{if n==1{return "1 row"};return fmt.Sprintf("%d rows",n)}
func written(v any)string{if v==nil{return "NULL"};return fmt.Sprint(v)}
func rowKey(r row)string{var s strings.Builder;for _,v:=range r{if v==nil{s.WriteString("N;")}else if n,ok:=v.(int64);ok{s.WriteString("I"+strconv.FormatInt(n,10)+";")}else{t:=v.(string);s.WriteString("T"+strconv.Itoa(len(t))+":"+t)}};return s.String()}
func printTable(items []item,types []string,rows []row){width:=make([]int,len(items));headings:=[]string{};for i,it:=range items{width[i]=len(it.heading);headings=append(headings,it.heading)};cells:=[][]string{};for _,r:=range rows{a:=[]string{};for i,v:=range r{a=append(a,written(v));if len(a[i])>width[i]{width[i]=len(a[i])}};cells=append(cells,a)};sep:="+";for _,w:=range width{sep+=strings.Repeat("-",w+2)+"+"};render:=func(a []string,header bool)string{s:="|";for i,v:=range a{pad:=strings.Repeat(" ",width[i]-len(v));if !header&&types[i]=="INT"{s+=" "+pad+v+" |"}else{s+=" "+v+pad+" |"}};return s};fmt.Println(sep);fmt.Println(render(headings,true));fmt.Println(sep);for _,r:=range cells{fmt.Println(render(r,false))};fmt.Println(sep);fmt.Println("("+countRows(len(rows))+")")}
type database struct{tables map[string]*table}
func(db *database)table(n string)*table{t,ok:=db.tables[n];if !ok{fail("unknown table "+n)};return t}
func targets(t *table,names []string)[]int{a:=[]int{};seen:=map[int]bool{};for _,n:=range names{i:=t.column(n);if i<0{fail("unknown column "+n)};if seen[i]{fail("duplicate column "+n)};seen[i]=true;a=append(a,i)};return a}
func constraints(t *table,rows []row,checked []int){for _,i:=range checked{for j,c:=range t.columns{if c.notNull&&rows[i][j]==nil{fail("NULL value in column "+c.name)}};if t.key>=0{for j,r:=range rows{if i!=j&&rows[i][t.key]==r[t.key]{fail("duplicate primary key "+written(r[t.key]))}}}}}
func(db *database)execute(c command){
 if c.kind=="select"{db.selectRows(c.query);return};if c.kind=="create"{if _,ok:=db.tables[c.name];ok{fail("table "+c.name+" already exists")};seen:=map[string]bool{};primary,key:=0,-1;for i,col:=range c.columns{if seen[col.name]{fail("duplicate column "+col.name)};seen[col.name]=true;primary+=col.primary;if primary>=2{fail("multiple primary keys")};if col.primary>0{key=i}};db.tables[c.name]=&table{name:c.name,columns:c.columns,key:key};fmt.Println("Table "+c.name+" created.");return};t:=db.table(c.name);if c.kind=="drop"{delete(db.tables,c.name);fmt.Println("Table "+c.name+" dropped.");return};rows:=[]row{};checked:=[]int{};count:=0
 if c.kind=="insert"{target:=[]int{};if c.names!=nil{target=targets(t,c.names)}else{for i:=range t.columns{target=append(target,i)}};empty:=&scope{};for _,tuple:=range c.tuples{if len(tuple)!=len(target){fail(fmt.Sprintf("expected %d values, got %d",len(target),len(tuple)))};for i,e:=range tuple{col:=t.columns[target[i]];require(check(e,empty,false,nil,false),col.kind,"column "+col.name)}};rows=append(rows,t.rows...);for _,tuple:=range c.tuples{r:=make(row,len(t.columns));for i,e:=range tuple{r[target[i]]=evaluate(e,nil,nil)};checked=append(checked,len(rows));rows=append(rows,r)};constraints(t,rows,checked);count=len(c.tuples)
 }else if c.kind=="update"{names:=[]string{};for _,a:=range c.assignments{names=append(names,a.name)};target:=targets(t,names);s:=&scope{};s.add(t.name,t);for i,a:=range c.assignments{col:=t.columns[target[i]];require(check(a.expr,s,false,nil,false),col.kind,"column "+col.name)};condition(c.where,s,"WHERE",false,nil);for i,r:=range t.rows{next:=r;if satisfies(c.where,r,nil){next=append(row{},r...);for j,a:=range c.assignments{next[target[j]]=evaluate(a.expr,r,nil)};checked=append(checked,i);count++};rows=append(rows,next)};constraints(t,rows,checked)
 }else{s:=&scope{};s.add(t.name,t);condition(c.where,s,"WHERE",false,nil);for _,r:=range t.rows{if satisfies(c.where,r,nil){count++}else{rows=append(rows,r)}}};t.rows=rows;verb:=" deleted.";if c.kind=="insert"{verb=" inserted."}else if c.kind=="update"{verb=" updated."};fmt.Println(countRows(count)+verb)
}
func(db *database)selectRows(q *query){
 s:=&scope{};s.add(q.source.alias,db.table(q.source.name));for _,j:=range q.joins{s.add(j.table.alias,db.table(j.table.name));condition(j.condition,s,"ON",false,nil)};condition(q.where,s,"WHERE",false,nil);grouping:=[]int{};for _,ref:=range q.group{s.resolve(ref);grouping=append(grouping,ref.index)}
 if q.star{for _,part:=range s.entries{for _,c:=range part.table.columns{e:=node("ref","");e.table=part.name;e.column=c.name;e.text=c.name;q.items=append(q.items,item{expr:e,heading:c.name})}}};aggregate:=q.group!=nil||q.having!=nil;for _,i:=range q.items{aggregate=aggregate||hasAggregate(i.expr)};for _,o:=range q.order{aggregate=aggregate||hasAggregate(o.expr)};var grouped []int;if aggregate{grouped=grouping};types:=[]string{};for _,i:=range q.items{types=append(types,check(i.expr,s,true,grouped,false))};condition(q.having,s,"HAVING",true,grouped)
 keys:=[]*expr{};for _,o:=range q.order{var key *expr;if o.ordinal!=nil{k:=*o.ordinal;if k<1||k>int64(len(q.items)){fail(fmt.Sprintf("ORDER BY position %d is out of range",k))};key=q.items[k-1].expr}else if o.alias!=""{for _,i:=range q.items{if i.alias==o.alias{key=i.expr;break}}};if key==nil{check(o.expr,s,true,grouped,false);key=o.expr};keys=append(keys,key)}
 rows:=s.entries[0].table.rows;for ji,j:=range q.joins{t:=s.entries[ji+1].table;next:=[]row{};for _,left:=range rows{found:=false;for _,right:=range t.rows{combined:=append(append(row{},left...),right...);if satisfies(j.condition,combined,nil){next=append(next,combined);found=true}};if j.left&&!found{combined:=append(append(row{},left...),make(row,len(t.columns))...);next=append(next,combined)}};rows=next};filtered:=[]row{};for _,r:=range rows{if satisfies(q.where,r,nil){filtered=append(filtered,r)}};rows=filtered
 groups:=[][]row{};if !aggregate{for _,r:=range rows{groups=append(groups,[]row{r})}}else if q.group==nil{groups=append(groups,rows)}else{at:=map[string]int{};for _,r:=range rows{k:=row{};for _,i:=range grouping{k=append(k,r[i])};key:=rowKey(k);index,ok:=at[key];if !ok{index=len(groups);at[key]=index;groups=append(groups,[]row{})};groups[index]=append(groups[index],r)}}
 type result struct{values,keys row};results:=[]result{};for _,g:=range groups{var r row;if len(g)>0{r=g[0]};var context []row;if aggregate{context=g};if !satisfies(q.having,r,context){continue};values,sortkeys:=row{},row{};for _,i:=range q.items{values=append(values,evaluate(i.expr,r,context))};for _,key:=range keys{sortkeys=append(sortkeys,evaluate(key,r,context))};results=append(results,result{values,sortkeys})}
 sort.SliceStable(results,func(i,j int)bool{a,b:=results[i],results[j];for k,o:=range q.order{c:=compare(a.keys[k],b.keys[k]);if c!=0{if o.descending{return c>0};return c<0}};return false});unique:=[]row{};seen:=map[string]bool{};for _,r:=range results{k:=rowKey(r.values);if !q.distinct||!seen[k]{unique=append(unique,r.values);seen[k]=true}};first:=q.offset;if first>int64(len(unique)){first=int64(len(unique))};last:=int64(len(unique));if q.limit!=nil&&first+*q.limit<last{last=first+*q.limit};printTable(q.items,types,unique[first:last])
}
func process(db *database,text string)(exit bool){defer func(){if p:=recover();p!=nil{if e,ok:=p.(sqlError);ok{fmt.Println("ERROR: "+string(e))}else{panic(p)}}}();p:=parser{tokens:tokenize(text)};c:=p.statement();if c.kind=="exit"{return true};if c.kind!=""{db.execute(c)};return false}
func main(){bytes,_:=io.ReadAll(os.Stdin);source:=string(bytes);segments:=[]string{};start:=0;for i:=0;i<len(source);i++{if source[i]=='\''{i+=1+strings.IndexByte(source[i+1:],'\'')}else if strings.HasPrefix(source[i:],"--"){end:=strings.IndexByte(source[i:],'\n');if end<0{break};i+=end}else if source[i]==';'{segments=append(segments,source[start:i+1]);start=i+1}};db:=&database{tables:map[string]*table{}};for _,s:=range segments{if process(db,s){break}}}
