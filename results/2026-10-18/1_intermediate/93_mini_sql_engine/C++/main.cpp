#include <iostream>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <memory>
#include <functional>
#include <algorithm>
#include <cctype>
#include <stdexcept>
#include <sstream>
using namespace std;
[[noreturn]] void fail(const string&s){throw runtime_error(s);}
struct Cell {
    enum Kind {Null,Int,Text} kind=Null;long long number=0;string text;
    Cell()=default;Cell(long long n):kind(Int),number(n){}Cell(string s):kind(Text),text(move(s)){}
    bool operator==(const Cell&b)const{return kind==b.kind&&(kind==Null||(kind==Int?number==b.number:text==b.text));}
    string written()const{return kind==Null?"NULL":kind==Int?to_string(number):text;}
};
int compare(const Cell&a,const Cell&b){if(a==b)return 0;if(a.kind==Cell::Null)return -1;if(b.kind==Cell::Null)return 1;return a.kind==Cell::Int?(a.number<b.number?-1:1):(a.text<b.text?-1:1);}
using Row=vector<Cell>;using Rows=vector<Row>;
bool truth(const Cell&v){return v.kind!=Cell::Null&&v.number!=0;}
Cell inverse(const Cell&v){return v.kind==Cell::Null?Cell():Cell(v.number==0?1LL:0LL);}
const unordered_set<string> aggregates={"COUNT","SUM","MIN","MAX","AVG"},comparisons={"=","<>","!=","<","<=",">",">="};
struct Token{string kind,text;Cell value;};
vector<Token>tokenize(const string&s){
    static const unordered_set<string>reserved={"SELECT","DISTINCT","FROM","AS","JOIN","INNER","LEFT","OUTER","ON","WHERE","GROUP","BY","HAVING","ORDER","ASC","DESC","LIMIT","OFFSET","INSERT","INTO","VALUES","UPDATE","SET","DELETE","CREATE","TABLE","DROP","PRIMARY","KEY","NOT","NULL","INT","TEXT","AND","OR","IS","IN","BETWEEN","LIKE","COUNT","SUM","MIN","MAX","AVG","EXIT"};
    vector<Token>a;size_t i=0;while(i<s.size()){char c=s[i];size_t start=i;if(c==' '||c=='\n'){i++;continue;}if(s.compare(i,2,"--")==0){i=s.find('\n',i);if(i==string::npos)break;continue;}
        if(c=='\''){i=s.find('\'',i+1)+1;a.push_back({"string",s.substr(start,i-start),Cell(s.substr(start+1,i-start-2))});}
        else if(isdigit(static_cast<unsigned char>(c))){while(i<s.size()&&isdigit(static_cast<unsigned char>(s[i])))i++;string t=s.substr(start,i-start);a.push_back({"integer",t,Cell(stoll(t))});}
        else if(isalpha(static_cast<unsigned char>(c))||c=='_'){while(i<s.size()&&(isalnum(static_cast<unsigned char>(s[i]))||s[i]=='_'))i++;string t=s.substr(start,i-start),up=t;for(char&ch:up)ch=static_cast<char>(toupper(static_cast<unsigned char>(ch)));bool keyword=reserved.count(up);a.push_back({keyword?"keyword":"name",t,Cell(keyword?up:t)});}
        else{string t=s.substr(i,2);if(t!="<>"&&t!="!="&&t!="<="&&t!=">="&&t!="||")t=string(1,c);if(t.size()==1&&string("(),.;*/%+-=<>").find(c)==string::npos)fail(string("unexpected character '")+c+"'");a.push_back({"symbol",t,Cell(t)});i+=t.size();}}
    return a;
}
struct Expr;using E=shared_ptr<Expr>;
struct Expr {string kind,op;vector<E>args;Cell value;string table,column,text;int index=-1;bool distinct=false,negated=false;};
E node(string kind,string op="",vector<E>args={},Cell value=Cell()){E e=make_shared<Expr>();e->kind=move(kind);e->op=move(op);e->args=move(args);e->value=move(value);return e;}
struct Column {string name,type;bool not_null=false;int primary=0;};
struct Ref{string name,alias;};
struct Item{E expr;string alias,heading;};
struct Order{E expr;bool descending=false;long long ordinal=-1;string alias;};
struct Join{Ref table;bool left=false;E condition;};
struct Query{bool distinct=false,star=false,grouped=false;vector<Item>items;Ref source;vector<Join>joins;E where,having;vector<E>group;vector<Order>order;long long limit=-1,offset=0;};
struct Command{string kind,name;vector<Column>columns;bool named_targets=false;vector<string>names;vector<vector<E>>tuples;vector<pair<string,E>>assignments;E where;Query query;};
struct Parser{
    vector<Token>ts;size_t pos=0;explicit Parser(vector<Token>a):ts(move(a)){}
    const Token&peek()const{return ts[pos];}Token take(){return ts[pos++];}
    bool at(const string&w)const{return (peek().kind=="symbol"||peek().kind=="keyword")&&peek().value.text==w;}
    bool accept(const string&w){if(!at(w))return false;pos++;return true;}
    [[noreturn]]void syntax()const{fail("syntax error at '"+peek().text+"'");}
    void expect(const string&w){if(!accept(w))syntax();}
    string name(){if(peek().kind!="name")syntax();return take().value.text;}
    long long integer(){if(peek().kind!="integer")syntax();return take().value.number;}
    template<class F>auto comma(F read){using T=decltype(read());vector<T>a{read()};while(accept(","))a.push_back(read());return a;}
    template<class F>auto parens(F read){expect("(");auto a=comma(read);expect(")");return a;}
    string alias(){if(accept("AS"))return name();return peek().kind=="name"?name():"";}
    Ref table(){string n=name(),a=alias();return {n,a.empty()?n:a};}
    E reference(){string n=name();E e=node("ref");if(accept(".")){e->table=n;e->column=name();e->text=n+"."+e->column;}else e->column=e->text=n;return e;}
    E expr(int level=0){
        if(level==2&&accept("NOT"))return node("unary","NOT",{expr(2)});if(level==6&&accept("-"))return node("unary","-",{expr(6)});if(level==7)return primary();E left=expr(level+1);
        if(level==3){if(peek().kind=="symbol"&&comparisons.count(peek().value.text)){string op=take().value.text;return node("binary",op,{left,expr(4)});}if(accept("IS")){bool neg=accept("NOT");expect("NULL");E e=node("isnull","",{left});e->negated=neg;return e;}bool neg=accept("NOT");E e;
            if(accept("IN")){vector<E>a{left},b=parens([&]{return expr();});a.insert(a.end(),b.begin(),b.end());e=node("in","",a);}else if(accept("BETWEEN")){E low=expr(4);expect("AND");e=node("between","",{left,low,expr(4)});}else if(accept("LIKE"))e=node("like","",{left,expr(4)});else if(neg)syntax();if(e){e->negated=neg;return e;}return left;}
        static const vector<vector<string>>ops={{"OR"},{"AND"},{},{},{"+","-","||"},{"*","/","%"},{}};while(any_of(ops[level].begin(),ops[level].end(),[&](const string&s){return at(s);})){string op=take().value.text;left=node("binary",op,{left,expr(level+1)});}return left;
    }
    E primary(){Token t=peek();if(t.kind=="integer"||t.kind=="string"){take();return node("literal","",{},t.value);}if(accept("NULL"))return node("literal");if(t.kind=="name")return reference();if(t.kind=="keyword"&&aggregates.count(t.value.text)){string n=take().value.text;expect("(");E e=node("aggregate",n);if(!(n=="COUNT"&&accept("*"))){e->distinct=accept("DISTINCT");e->args.push_back(expr());}expect(")");return e;}if(accept("(")){E e=expr();expect(")");return node("group","",{e});}syntax();}
    E clause(const string&w){return accept(w)?expr():nullptr;}
    Item item(){size_t start=pos;E e=expr();size_t stop=pos;string a=alias(),h=a;if(h.empty()){if(e->kind=="ref")h=e->column;else for(size_t i=start;i<stop;i++){if(i>start&&ts[i-1].kind!="symbol"&&ts[i].kind!="symbol")h+=' ';h+=ts[i].text;}}return {e,a,h};}
    Order order_item(){size_t start=pos;E e=expr();bool single=pos==start+1,desc=accept("DESC");if(!desc)accept("ASC");Order o;o.expr=e;o.descending=desc;if(single&&ts[start].kind=="integer")o.ordinal=ts[start].value.number;if(single&&ts[start].kind=="name")o.alias=ts[start].value.text;return o;}
    Query query(){Query q;q.distinct=accept("DISTINCT");q.star=accept("*");if(!q.star)q.items=comma([&]{return item();});expect("FROM");q.source=table();while(at("JOIN")||at("INNER")||at("LEFT")){bool left=accept("LEFT");if(left)accept("OUTER");else accept("INNER");expect("JOIN");Ref t=table();expect("ON");q.joins.push_back({t,left,expr()});}q.where=clause("WHERE");if(accept("GROUP")){q.grouped=true;expect("BY");q.group=comma([&]{return reference();});}q.having=clause("HAVING");if(accept("ORDER")){expect("BY");q.order=comma([&]{return order_item();});}if(accept("LIMIT")){q.limit=integer();if(accept("OFFSET"))q.offset=integer();}return q;}
    Column column(){Column c;c.name=name();if(!at("INT")&&!at("TEXT"))syntax();c.type=take().value.text;while(true){if(accept("PRIMARY")){expect("KEY");c.primary++;c.not_null=true;}else if(accept("NOT")){expect("NULL");c.not_null=true;}else break;}return c;}
    Command statement(){Command c;if(accept("CREATE")){c.kind="create";expect("TABLE");c.name=name();c.columns=parens([&]{return column();});}else if(accept("DROP")){c.kind="drop";expect("TABLE");c.name=name();}else if(accept("INSERT")){c.kind="insert";expect("INTO");c.name=name();if(at("(")){c.named_targets=true;c.names=parens([&]{return name();});}expect("VALUES");c.tuples=comma([&]{return parens([&]{return expr();});});}else if(accept("UPDATE")){c.kind="update";c.name=name();expect("SET");c.assignments=comma([&]{string n=name();expect("=");E e=expr();return make_pair(n,e);});c.where=clause("WHERE");}else if(accept("DELETE")){c.kind="delete";expect("FROM");c.name=name();c.where=clause("WHERE");}else if(accept("SELECT")){c.kind="select";c.query=query();}else if(accept("EXIT"))c.kind="exit";expect(";");return c;}
};
struct Table{string name;vector<Column>columns;int key=-1;Rows rows;int column(const string&n)const{for(size_t i=0;i<columns.size();i++)if(columns[i].name==n)return static_cast<int>(i);return -1;}};
struct Entry{string name;Table*table;int offset;};
struct Scope{vector<Entry>entries;int width=0;void add(string name,Table&t){for(const Entry&e:entries)if(e.name==name)fail("duplicate table name "+name);entries.push_back({name,&t,width});width+=static_cast<int>(t.columns.size());}string resolve(E e){vector<pair<int,string>>found;bool seen=false;for(const Entry&part:entries)if(e->table.empty()||e->table==part.name){seen=true;int i=part.table->column(e->column);if(i>=0)found.emplace_back(part.offset+i,part.table->columns[i].type);}if(!e->table.empty()&&!seen)fail("unknown table "+e->table);if(found.empty())fail("unknown column "+e->text);if(found.size()>1)fail("ambiguous column "+e->column);e->index=found[0].first;return found[0].second;}};
bool compatible(const string&a,const string&b){return a==b||a=="NULL"||b=="NULL";}
void require_type(const string&a,const string&b,const string&op){if(!compatible(a,b))fail("type mismatch for "+op);}
string check(E e,Scope&s,bool allow=false,const vector<int>*grouped=nullptr,bool inside=false){
    if(e->kind=="literal")return e->value.kind==Cell::Null?"NULL":e->value.kind==Cell::Int?"INT":"TEXT";if(e->kind=="ref"){string t=s.resolve(e);if(grouped&&!inside&&find(grouped->begin(),grouped->end(),e->index)==grouped->end())fail("column "+e->text+" is not grouped");return t;}
    if(e->kind=="aggregate"){if(!allow||inside)fail("misuse of aggregate "+e->op);if(e->args.empty())return "INT";string t=check(e->args[0],s,allow,grouped,true);if(e->op=="SUM"||e->op=="AVG")require_type(t,"INT",e->op);return e->op=="MIN"||e->op=="MAX"?t:"INT";}
    vector<string>types;for(E a:e->args)types.push_back(check(a,s,allow,grouped,inside));if(e->kind=="group")return types[0];if(e->kind=="isnull")return "INT";if(e->kind=="binary"&&comparisons.count(e->op)){require_type(types[0],types[1],e->op);return "INT";}if(e->kind=="in"||e->kind=="between"){for(size_t i=1;i<types.size();i++)require_type(types[i],types[0],e->kind=="in"?"IN":"BETWEEN");return "INT";}string op=e->kind=="like"?"LIKE":e->op,t=op=="LIKE"||op=="||"?"TEXT":"INT";for(const string&a:types)require_type(a,t,op);return op=="||"?"TEXT":"INT";
}
void condition(E e,Scope&s,const string&name,bool allow=false,const vector<int>*grouped=nullptr){if(e)require_type(check(e,s,allow,grouped),"INT",name);}
bool has_aggregate(E e){if(e->kind=="aggregate")return true;for(E a:e->args)if(has_aggregate(a))return true;return false;}
Cell operate(const string&op,const Cell&a,const Cell&b){
    if(op=="AND"){if((a.kind==Cell::Int&&a.number==0)||(b.kind==Cell::Int&&b.number==0))return Cell(0LL);return a.kind==Cell::Null||b.kind==Cell::Null?Cell():Cell(1LL);}if(op=="OR"){if(truth(a)||truth(b))return Cell(1LL);return a.kind==Cell::Null||b.kind==Cell::Null?Cell():Cell(0LL);}if(a.kind==Cell::Null||b.kind==Cell::Null)return Cell();long long x=a.number,y=b.number;
    if(op=="+")return Cell(x+y);if(op=="-")return Cell(x-y);if(op=="*")return Cell(x*y);if(op=="/")return y==0?Cell():Cell(x/y);if(op=="%")return y==0?Cell():Cell(x%y);if(op=="||")return Cell(a.text+b.text);int c=compare(a,b);return Cell((op=="="?c==0:op=="<>"||op=="!="?c!=0:op=="<"?c<0:op=="<="?c<=0:op==">"?c>0:c>=0)?1LL:0LL);
}
bool like(const string&text,const string&pattern){vector<bool>dp(text.size()+1);dp[0]=true;for(char c:pattern){if(c=='%'){for(size_t i=1;i<=text.size();i++)dp[i]=dp[i]||dp[i-1];}else{for(size_t i=text.size();i>0;i--)dp[i]=dp[i-1]&&(c=='_'||c==text[i-1]);dp[0]=false;}}return dp.back();}
Cell evaluate(E e,const Row&row,const Rows*group=nullptr){
    if(e->kind=="literal")return e->value;if(e->kind=="ref")return row[e->index];if(e->kind=="aggregate"){if(e->args.empty())return Cell(static_cast<long long>(group->size()));vector<Cell>vs;for(const Row&r:*group){Cell v=evaluate(e->args[0],r);if(v.kind!=Cell::Null&&(!e->distinct||find(vs.begin(),vs.end(),v)==vs.end()))vs.push_back(v);}if(e->op=="COUNT")return Cell(static_cast<long long>(vs.size()));if(vs.empty())return Cell();if(e->op=="MIN"||e->op=="MAX"){Cell v=vs[0];for(const Cell&x:vs)if(e->op=="MIN"?compare(x,v)<0:compare(x,v)>0)v=x;return v;}long long sum=0;for(const Cell&v:vs)sum+=v.number;return Cell(e->op=="AVG"?sum/static_cast<long long>(vs.size()):sum);}
    vector<Cell>a;for(E arg:e->args)a.push_back(evaluate(arg,row,group));if(e->kind=="group")return a[0];if(e->kind=="unary")return e->op=="NOT"?inverse(a[0]):a[0].kind==Cell::Null?Cell():Cell(-a[0].number);if(e->kind=="binary")return operate(e->op,a[0],a[1]);if(e->kind=="isnull")return Cell((a[0].kind==Cell::Null)!=e->negated?1LL:0LL);Cell result;
    if(e->kind=="in"){if(a[0].kind!=Cell::Null){bool found=false,unknown=false;for(size_t i=1;i<a.size();i++){if(a[i].kind==Cell::Null)unknown=true;else if(a[i]==a[0])found=true;}result=found?Cell(1LL):unknown?Cell():Cell(0LL);}}
    else if(e->kind=="between")result=operate("AND",operate(">=",a[0],a[1]),operate("<=",a[0],a[2]));else if(a[0].kind!=Cell::Null&&a[1].kind!=Cell::Null)result=Cell(like(a[0].text,a[1].text)?1LL:0LL);return e->negated?inverse(result):result;
}
bool satisfies(E e,const Row&r,const Rows*g=nullptr){return !e||truth(evaluate(e,r,g));}
string count_rows(size_t n){return to_string(n)+(n==1?" row":" rows");}
void print_table(const vector<Item>&items,const vector<string>&types,const Rows&rows){vector<size_t>width;for(const Item&i:items)width.push_back(i.heading.size());vector<vector<string>>cells;for(const Row&r:rows){vector<string>a;for(size_t i=0;i<r.size();i++){a.push_back(r[i].written());width[i]=max(width[i],a.back().size());}cells.push_back(a);}string sep="+";for(size_t w:width)sep+=string(w+2,'-')+"+";auto render=[&](const vector<string>&a,bool header){string s="|";for(size_t i=0;i<a.size();i++){string pad(width[i]-a[i].size(),' ');s+=" "+(!header&&types[i]=="INT"?pad+a[i]:a[i]+pad)+" |";}cout<<s<<'\n';};vector<string>heads;for(const Item&i:items)heads.push_back(i.heading);cout<<sep<<'\n';render(heads,true);cout<<sep<<'\n';for(const auto&r:cells)render(r,false);cout<<sep<<"\n("<<count_rows(rows.size())<<")\n";}
struct Database{
    unordered_map<string,Table>tables;
    Table&table(const string&n){auto it=tables.find(n);if(it==tables.end())fail("unknown table "+n);return it->second;}
    vector<int>targets(const Table&t,const vector<string>&names){vector<int>a;for(const string&n:names){int i=t.column(n);if(i<0)fail("unknown column "+n);if(find(a.begin(),a.end(),i)!=a.end())fail("duplicate column "+n);a.push_back(i);}return a;}
    void constraints(const Table&t,const Rows&rows,const vector<size_t>&checked){for(size_t i:checked){for(size_t j=0;j<t.columns.size();j++)if(t.columns[j].not_null&&rows[i][j].kind==Cell::Null)fail("NULL value in column "+t.columns[j].name);if(t.key>=0)for(size_t j=0;j<rows.size();j++)if(i!=j&&rows[i][t.key]==rows[j][t.key])fail("duplicate primary key "+rows[i][t.key].written());}}
    void select(Query q){
        Scope scope;scope.add(q.source.alias,table(q.source.name));for(const Join&j:q.joins){scope.add(j.table.alias,table(j.table.name));condition(j.condition,scope,"ON");}condition(q.where,scope,"WHERE");vector<int>grouping;for(E ref:q.group){scope.resolve(ref);grouping.push_back(ref->index);}
        if(q.star)for(const Entry&part:scope.entries)for(const Column&c:part.table->columns){E e=node("ref");e->table=part.name;e->column=e->text=c.name;q.items.push_back({e,"",c.name});}
        bool aggregate=q.grouped||bool(q.having);for(const Item&i:q.items)aggregate=aggregate||has_aggregate(i.expr);for(const Order&o:q.order)aggregate=aggregate||has_aggregate(o.expr);const vector<int>*grouped=aggregate?&grouping:nullptr;vector<string>types;for(const Item&i:q.items)types.push_back(check(i.expr,scope,true,grouped));condition(q.having,scope,"HAVING",true,grouped);
        vector<E>keys;for(const Order&o:q.order){E key;if(o.ordinal>=0){if(o.ordinal<1||o.ordinal>static_cast<long long>(q.items.size()))fail("ORDER BY position "+to_string(o.ordinal)+" is out of range");key=q.items[o.ordinal-1].expr;}else if(!o.alias.empty()){for(const Item&i:q.items)if(i.alias==o.alias){key=i.expr;break;}}if(!key){check(o.expr,scope,true,grouped);key=o.expr;}keys.push_back(key);}
        Rows rows=scope.entries[0].table->rows;for(size_t ji=0;ji<q.joins.size();ji++){const Join&j=q.joins[ji];const Table&t=*scope.entries[ji+1].table;Rows next;for(const Row&left:rows){bool found=false;for(const Row&right:t.rows){Row combined=left;combined.insert(combined.end(),right.begin(),right.end());if(satisfies(j.condition,combined)){next.push_back(combined);found=true;}}if(j.left&&!found){Row combined=left;combined.resize(left.size()+t.columns.size());next.push_back(combined);}}rows=move(next);}rows.erase(remove_if(rows.begin(),rows.end(),[&](const Row&r){return !satisfies(q.where,r);}),rows.end());
        vector<Rows>groups;if(!aggregate){for(const Row&r:rows)groups.push_back({r});}else if(!q.grouped)groups.push_back(rows);else{vector<Row>groupkeys;for(const Row&r:rows){Row key;for(int i:grouping)key.push_back(r[i]);auto it=find(groupkeys.begin(),groupkeys.end(),key);size_t at=it-groupkeys.begin();if(it==groupkeys.end()){groupkeys.push_back(key);groups.push_back({});}groups[at].push_back(r);}}
        struct Result{Row values,keys;};vector<Result>results;for(const Rows&g:groups){Row empty;const Row&r=g.empty()?empty:g[0];const Rows*context=aggregate?&g:nullptr;if(!satisfies(q.having,r,context))continue;Result result;for(const Item&i:q.items)result.values.push_back(evaluate(i.expr,r,context));for(E key:keys)result.keys.push_back(evaluate(key,r,context));results.push_back(move(result));}
        stable_sort(results.begin(),results.end(),[&](const Result&a,const Result&b){for(size_t i=0;i<keys.size();i++){int c=compare(a.keys[i],b.keys[i]);if(c)return q.order[i].descending?c>0:c<0;}return false;});Rows unique;for(const Result&r:results)if(!q.distinct||find(unique.begin(),unique.end(),r.values)==unique.end())unique.push_back(r.values);size_t first=min(static_cast<size_t>(q.offset),unique.size()),last=q.limit<0?unique.size():min(unique.size(),first+static_cast<size_t>(q.limit));Rows output(unique.begin()+first,unique.begin()+last);print_table(q.items,types,output);
    }
    void execute(const Command&c){
        if(c.kind=="select"){select(c.query);return;}if(c.kind=="create"){if(tables.count(c.name))fail("table "+c.name+" already exists");unordered_set<string>seen;int primary=0,key=-1;for(size_t i=0;i<c.columns.size();i++){const Column&column=c.columns[i];if(!seen.insert(column.name).second)fail("duplicate column "+column.name);primary+=column.primary;if(primary>=2)fail("multiple primary keys");if(column.primary)key=static_cast<int>(i);}tables[c.name]=Table{c.name,c.columns,key,{}};cout<<"Table "<<c.name<<" created.\n";return;}
        Table&t=table(c.name);if(c.kind=="drop"){tables.erase(c.name);cout<<"Table "<<c.name<<" dropped.\n";return;}Rows rows;vector<size_t>checked;size_t count=0;
        if(c.kind=="insert"){vector<int>target;if(c.named_targets)target=targets(t,c.names);else for(size_t i=0;i<t.columns.size();i++)target.push_back(static_cast<int>(i));Scope empty;for(const auto&tuple:c.tuples){if(tuple.size()!=target.size())fail("expected "+to_string(target.size())+" values, got "+to_string(tuple.size()));for(size_t i=0;i<tuple.size();i++){const Column&column=t.columns[target[i]];require_type(check(tuple[i],empty),column.type,"column "+column.name);}}
            rows=t.rows;for(const auto&tuple:c.tuples){Row row(t.columns.size());for(size_t i=0;i<tuple.size();i++)row[target[i]]=evaluate(tuple[i],{});checked.push_back(rows.size());rows.push_back(row);}constraints(t,rows,checked);count=c.tuples.size();
        }else if(c.kind=="update"){vector<string>names;for(const auto&a:c.assignments)names.push_back(a.first);vector<int>target=targets(t,names);Scope scope;scope.add(t.name,t);for(size_t i=0;i<c.assignments.size();i++){const Column&column=t.columns[target[i]];require_type(check(c.assignments[i].second,scope),column.type,"column "+column.name);}condition(c.where,scope,"WHERE");rows=t.rows;for(size_t i=0;i<t.rows.size();i++)if(satisfies(c.where,t.rows[i])){Row row=t.rows[i];for(size_t j=0;j<c.assignments.size();j++)row[target[j]]=evaluate(c.assignments[j].second,t.rows[i]);rows[i]=row;checked.push_back(i);count++;}constraints(t,rows,checked);
        }else{Scope scope;scope.add(t.name,t);condition(c.where,scope,"WHERE");for(const Row&r:t.rows)if(satisfies(c.where,r))count++;else rows.push_back(r);}
        t.rows=move(rows);cout<<count_rows(count)<<(c.kind=="insert"?" inserted.\n":c.kind=="update"?" updated.\n":" deleted.\n");
    }
};
int main(){string source((istreambuf_iterator<char>(cin)),istreambuf_iterator<char>());vector<string>statements;size_t start=0;for(size_t i=0;i<source.size();i++){if(source[i]=='\'')i=source.find('\'',i+1);else if(source.compare(i,2,"--")==0){size_t end=source.find('\n',i);if(end==string::npos)break;i=end;}else if(source[i]==';'){statements.push_back(source.substr(start,i-start+1));start=i+1;}}Database db;for(const string&s:statements){try{Command c=Parser(tokenize(s)).statement();if(c.kind=="exit")break;if(!c.kind.empty())db.execute(c);}catch(const runtime_error&error){cout<<"ERROR: "<<error.what()<<'\n';}}}
