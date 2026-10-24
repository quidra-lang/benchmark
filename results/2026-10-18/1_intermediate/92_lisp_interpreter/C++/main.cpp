#include <iostream>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <memory>
#include <functional>
#include <stdexcept>
#include <algorithm>
#include <numeric>
using namespace std;
struct Value; struct Environment;
using V=shared_ptr<Value>; using E=shared_ptr<Environment>;
struct Value {
    enum Kind { Integer, Boolean, String, Symbol, Nil, Pair, Procedure, Void, Uninitialized } kind;
    long long number=0; string text; V car,cdr; vector<string> params; string rest;
    vector<V> body; E env; int minimum=0; bool variadic=false; function<V(const vector<V>&)> builtin;
    explicit Value(Kind k):kind(k){}
};
V nil=make_shared<Value>(Value::Nil), nothing=make_shared<Value>(Value::Void), uninitialized=make_shared<Value>(Value::Uninitialized);
V num(long long n){V v=make_shared<Value>(Value::Integer);v->number=n;return v;}
V boolean(bool b){V v=make_shared<Value>(Value::Boolean);v->number=b;return v;}
V text(Value::Kind k,const string&s){V v=make_shared<Value>(k);v->text=s;return v;}
V cons(V a,V b){V v=make_shared<Value>(Value::Pair);v->car=a;v->cdr=b;return v;}
V list(const vector<V>&a,V tail=nullptr){if(!tail)tail=nil;for(size_t i=a.size();i-->0;)tail=cons(a[i],tail);return tail;}
bool unpack(V v,vector<V>&a){while(v->kind==Value::Pair){a.push_back(v->car);v=v->cdr;}return v==nil;}
bool truth(V v){return v->kind!=Value::Boolean||v->number;}
string repr(V v,bool quoted=true){
    switch(v->kind){case Value::Integer:return to_string(v->number);case Value::Boolean:return v->number?"#t":"#f";case Value::String:{if(!quoted)return v->text;string s="\"";for(char c:v->text)s+=c=='\n'?"\\n":c=='\\'?"\\\\":c=='\"'?"\\\"":string(1,c);return s+'"';}
    case Value::Symbol:return v->text;case Value::Nil:return "()";case Value::Procedure:return v->text.empty()?"#<procedure>":"#<procedure "+v->text+">";case Value::Pair:{string s="(";bool first=true;while(v->kind==Value::Pair){if(!first)s+=' ';first=false;s+=repr(v->car,quoted);v=v->cdr;}if(v!=nil)s+=" . "+repr(v,quoted);return s+")";}default:return "#<void>";}
}
void fail(const string&s){throw runtime_error(s);}
void shape(bool b,V x){if(!b)fail("bad syntax: "+repr(x));}
bool eq(V a,V b,bool deep=false){if(a->kind!=b->kind)return false;if(a->kind==Value::Pair)return deep?eq(a->car,b->car,true)&&eq(a->cdr,b->cdr,true):a==b;if(a->kind==Value::Procedure)return a==b;if(a->kind==Value::Integer||a->kind==Value::Boolean)return a->number==b->number;if(a->kind==Value::String||a->kind==Value::Symbol)return a->text==b->text;return a==b;}
struct Environment {unordered_map<string,V> frame;E parent;explicit Environment(E p=nullptr):parent(p){} V& locate(const string&s){for(Environment*e=this;e;e=e->parent.get()){auto i=e->frame.find(s);if(i!=e->frame.end())return i->second;}fail("unbound variable: "+s);throw logic_error("unreachable");}V get(const string&s){V v=locate(s);if(v==uninitialized)fail("uninitialized variable: "+s);return v;}};
V evaluate(V,E);V call(V,const vector<V>&);
V body(const vector<V>&a,E e){V v=nothing;for(V x:a)v=evaluate(x,e);return v;}
vector<V> slice(const vector<V>&a,size_t i){return vector<V>(a.begin()+i,a.end());}
bool parameters(V v,vector<string>&p,string&r){unordered_set<string>seen;while(v->kind==Value::Pair){if(v->car->kind!=Value::Symbol||!seen.insert(v->car->text).second)return false;p.push_back(v->car->text);v=v->cdr;}if(v==nil)return true;if(v->kind!=Value::Symbol||!seen.insert(v->text).second)return false;r=v->text;return true;}
V closure(const vector<string>&p,const string&r,const vector<V>&b,E e,const string&name=""){V v=text(Value::Procedure,name);v->params=p;v->rest=r;v->variadic=!r.empty();v->minimum=p.size();v->body=b;v->env=e;return v;}
bool bindings(V v,vector<pair<string,V>>&bs,bool unique){vector<V>a;if(!unpack(v,a))return false;unordered_set<string>seen;for(V x:a){vector<V>b;if(!unpack(x,b)||b.size()!=2||b[0]->kind!=Value::Symbol)return false;string n=b[0]->text;if(unique&&!seen.insert(n).second)return false;bs.emplace_back(n,b[1]);}return true;}
V evaluate(V x,E e){
    if(x->kind==Value::Symbol)return e->get(x->text);if(x->kind!=Value::Pair){shape(x!=nil,x);return x;}vector<V>a;shape(unpack(x,a),x);size_t n=a.size();string h=a[0]->kind==Value::Symbol?a[0]->text:"";
    if(h=="quote"){shape(n==2,x);return a[1];}if(h=="if"){shape(n==3||n==4,x);return truth(evaluate(a[1],e))?evaluate(a[2],e):n==4?evaluate(a[3],e):nothing;}
    if(h=="begin")return body(slice(a,1),e);
    if(h=="lambda"){vector<string>p;string r;shape(n>=3&&parameters(a[1],p,r),x);return closure(p,r,slice(a,2),e);}
    if(h=="define"){
        if(n>1&&a[1]->kind==Value::Symbol){shape(n==3,x);V v=evaluate(a[2],e);if(v->kind==Value::Procedure&&!v->builtin&&v->text.empty())v->text=a[1]->text;e->frame[a[1]->text]=v;}
        else {vector<string>p;string r;shape(n>=3&&a[1]->kind==Value::Pair&&a[1]->car->kind==Value::Symbol&&parameters(a[1]->cdr,p,r),x);e->frame[a[1]->car->text]=closure(p,r,slice(a,2),e,a[1]->car->text);}return nothing;
    }
    if(h=="set!"){shape(n==3&&a[1]->kind==Value::Symbol,x);V v=evaluate(a[2],e);e->locate(a[1]->text)=v;return nothing;}
    if(h=="let"||h=="let*"||h=="letrec"){
        bool named=h=="let"&&n>1&&a[1]->kind==Value::Symbol;size_t at=named?2:1;vector<pair<string,V>>bs;shape(n>=at+2&&bindings(a[at],bs,h!="let*"),x);E scope=make_shared<Environment>(e);
        if(h=="let*"){if(!bs.empty())scope=e;for(const auto&b:bs){V v=evaluate(b.second,scope);scope=make_shared<Environment>(scope);scope->frame[b.first]=v;}}
        else if(h=="letrec"){for(const auto&b:bs)scope->frame[b.first]=uninitialized;for(const auto&b:bs)scope->frame[b.first]=evaluate(b.second,scope);}
        else {vector<V>vs;vector<string>p;for(const auto&b:bs){vs.push_back(evaluate(b.second,e));p.push_back(b.first);}if(named){V f=closure(p,"",slice(a,3),scope,a[1]->text);scope->frame[a[1]->text]=f;return call(f,vs);}for(size_t i=0;i<bs.size();i++)scope->frame[bs[i].first]=vs[i];}return body(slice(a,at+1),scope);
    }
    if(h=="cond"){vector<vector<V>>cs;for(size_t i=1;i<n;i++){vector<V>c;shape(unpack(a[i],c)&&!c.empty(),x);shape(!(c[0]->kind==Value::Symbol&&c[0]->text=="else")||(c.size()>=2&&i+1==n),x);cs.push_back(c);}for(const auto&c:cs){if(c[0]->kind==Value::Symbol&&c[0]->text=="else")return body(slice(c,1),e);V v=evaluate(c[0],e);if(truth(v))return c.size()==1?v:body(slice(c,1),e);}return nothing;}
    if(h=="and"){V v=boolean(true);for(size_t i=1;i<n;i++){v=evaluate(a[i],e);if(!truth(v))break;}return v;}
    if(h=="or"){for(size_t i=1;i<n;i++){V v=evaluate(a[i],e);if(truth(v))return v;}return boolean(false);}
    if(h=="when"||h=="unless"){shape(n>=3,x);return truth(evaluate(a[1],e))==(h=="when")?body(slice(a,2),e):nothing;}
    V f=evaluate(a[0],e);vector<V>args;for(size_t i=1;i<n;i++)args.push_back(evaluate(a[i],e));if(f->kind!=Value::Procedure)fail("not a procedure: "+repr(f));return call(f,args);
}
V call(V f,const vector<V>&a){if(a.size()<size_t(f->minimum)||(!f->variadic&&a.size()!=size_t(f->minimum)))fail((f->text.empty()?"lambda":f->text)+": wrong number of arguments (expected "+(f->variadic?"at least ":"")+to_string(f->minimum)+", got "+to_string(a.size())+")");if(f->builtin)return f->builtin(a);E e=make_shared<Environment>(f->env);for(size_t i=0;i<f->params.size();i++)e->frame[f->params[i]]=a[i];if(f->variadic)e->frame[f->rest]=list(slice(a,f->params.size()));return body(f->body,e);}
bool mid=false;
void write(const string&s){cout<<s;if(!s.empty())mid=s.back()!='\n';}void line(const string&s){if(mid)write("\n");write(s+"\n");}
V expect(const string&n,V v,const string&k){vector<V>a;bool ok=k=="integer"?v->kind==Value::Integer:k=="pair"?v->kind==Value::Pair:k=="string"?v->kind==Value::String:k=="procedure"?v->kind==Value::Procedure:unpack(v,a);if(!ok)fail(n+": expected "+k+", got "+repr(v));return v;}
vector<V> aslist(const string&n,V v){vector<V>a;expect(n,v,"list");unpack(v,a);return a;}
E global(){E e=make_shared<Environment>();auto add=[&](string n,int m,bool r,function<V(const vector<V>&)>fn){V p=text(Value::Procedure,n);p->minimum=m;p->variadic=r;p->builtin=fn;e->frame[n]=p;};
    for(string n:{"+","*","-","quotient","remainder","modulo","abs","min","max","gcd","=","<",">","<=",">="}){int fixed=n=="quotient"||n=="remainder"||n=="modulo"?2:n=="abs"?1:-1;add(n,fixed>=0?fixed:n=="+"||n=="*"||n=="gcd"?0:1,fixed<0,[n](const vector<V>&a){for(V v:a)expect(n,v,"integer");long long v=a.empty()?0:a[0]->number;
      if(n=="+"||n=="*"){v=n=="+"?0:1;for(V x:a)v=n=="+"?v+x->number:v*x->number;return num(v);}if(n=="-"){if(a.size()==1)return num(-v);for(size_t i=1;i<a.size();i++)v-=a[i]->number;return num(v);}if(n=="abs")return num(v<0?-v:v);
      if(n=="min"||n=="max"){for(V x:a)v=n=="min"?min(v,x->number):max(v,x->number);return num(v);}if(n=="gcd"){v=0;for(V x:a)v=gcd(v,x->number);return num(v);}
      if(n=="quotient"||n=="remainder"||n=="modulo"){long long b=a[1]->number;if(!b)fail(n+": division by zero");long long q=v/b,r=v%b;if(n=="quotient")return num(q);if(n=="modulo"&&r&&((r<0)!=(b<0)))r+=b;return num(r);}
      bool ok=true;for(size_t i=1;i<a.size();i++){long long l=a[i-1]->number,r=a[i]->number;ok=ok&&(n=="="?l==r:n=="<"?l<r:n==">"?l>r:n=="<="?l<=r:l>=r);}return boolean(ok);
    });}
    add("not",1,false,[](const vector<V>&a){return boolean(!truth(a[0]));});for(string n:{"eq?","equal?"})add(n,2,false,[n](const vector<V>&a){return boolean(eq(a[0],a[1],n=="equal?"));});
    for(string n:{"null?","pair?","list?","number?","symbol?","procedure?"})add(n,1,false,[n](const vector<V>&a){vector<V>z;V v=a[0];return boolean(n=="null?"?v==nil:n=="pair?"?v->kind==Value::Pair:n=="list?"?unpack(v,z):n=="number?"?v->kind==Value::Integer:n=="symbol?"?v->kind==Value::Symbol:v->kind==Value::Procedure);});
    add("cons",2,false,[](const vector<V>&a){return cons(a[0],a[1]);});add("list",0,true,[](const vector<V>&a){return list(a);});
    for(string n:{"car","cdr","cadr"})add(n,1,false,[n](const vector<V>&a){V p=expect(n,a[0],"pair");return n=="car"?p->car:n=="cdr"?p->cdr:expect(n,p->cdr,"pair")->car;});
    for(string n:{"length","reverse","list-ref"})add(n,n=="list-ref"?2:1,false,[n](const vector<V>&a){vector<V>z=aslist(n,a[0]);if(n=="length")return num(z.size());if(n=="reverse"){reverse(z.begin(),z.end());return list(z);}long long k=expect(n,a[1],"integer")->number;if(k<0||k>=static_cast<long long>(z.size()))fail("list-ref: index out of range: "+to_string(k));return z[k];});
    add("append",0,true,[](const vector<V>&a){if(a.empty())return nil;vector<V>z;for(size_t i=0;i+1<a.size();i++){vector<V>b=aslist("append",a[i]);z.insert(z.end(),b.begin(),b.end());}return list(z,a.back());});
    for(string n:{"map","filter","fold-left","apply"})add(n,n=="fold-left"?3:2,n!="filter",[n](const vector<V>&a){V f=expect(n,a[0],"procedure");if(n=="apply"){vector<V>z(a.begin()+1,a.end()-1),b=aslist(n,a.back());z.insert(z.end(),b.begin(),b.end());return call(f,z);}vector<vector<V>>ls;size_t count=1000000;for(size_t i=n=="fold-left"?2:1;i<a.size();i++){ls.push_back(aslist(n,a[i]));count=min(count,ls.back().size());}vector<V>out;V acc=a[1];for(size_t i=0;i<count;i++){if(n=="filter"){if(truth(call(f,{ls[0][i]})))out.push_back(ls[0][i]);}else {vector<V>z;if(n=="fold-left")z.push_back(acc);for(const auto&b:ls)z.push_back(b[i]);V v=call(f,z);if(n=="map")out.push_back(v);else acc=v;}}return n=="fold-left"?acc:list(out);});
    add("string-append",0,true,[](const vector<V>&a){string s;for(V v:a)s+=expect("string-append",v,"string")->text;return text(Value::String,s);});add("number->string",1,false,[](const vector<V>&a){return text(Value::String,repr(expect("number->string",a[0],"integer")));});
    add("display",1,false,[](const vector<V>&a){write(repr(a[0],false));return nothing;});add("newline",0,false,[](const vector<V>&){write("\n");return nothing;});add("error",1,true,[](const vector<V>&a)->V{string s=expect("error",a[0],"string")->text;for(size_t i=1;i<a.size();i++)s+=" "+repr(a[i]);fail(s);return nothing;});return e;
}
struct Reader {
    vector<string>lines;size_t row=0,col=0;
    void skip(){row++;col=0;}bool end(){while(row<lines.size()){while(col<lines[row].size()&&lines[row][col]==' ')col++;if(col<lines[row].size()&&lines[row][col]!=';')return false;skip();}return true;}
    pair<char,V>token(){if(end())fail("unexpected end of input");string&s=lines[row];char c=s[col++];if(c=='('||c==')'||c=='\'')return {c,nullptr};if(c=='"'){string v;while(col<s.size()){c=s[col++];if(c=='"')return {'v',text(Value::String,v)};if(c=='\\'){if(col==s.size())break;c=s[col++];if(c!='"'&&c!='\\'&&c!='n')fail("bad escape");if(c=='n')c='\n';}v+=c;}fail("unterminated string");}
      size_t start=col-1;while(col<s.size()&&string(" ()'\";").find(s[col])==string::npos)col++;string a=s.substr(start,col-start);if(a==".")return {'.',nullptr};size_t i=(a[0]=='+'||a[0]=='-')?1:0;bool integer=i<a.size();for(;i<a.size();i++)integer=integer&&a[i]>='0'&&a[i]<='9';if(integer)return {'v',num(stoll(a))};if(a=="#t"||a=="#f")return {'v',boolean(a=="#t")};if(a[0]=='#')fail("bad token: "+a);return {'v',text(Value::Symbol,a)};
    }
    V datum(){return from(token());}V from(pair<char,V>t){if(t.first=='v')return t.second;if(t.first=='\'')return list({text(Value::Symbol,"quote"),datum()});if(t.first!='(')fail(string("unexpected ")+t.first);vector<V>a;while(true){t=token();if(t.first==')')return list(a);if(t.first=='.'&&!a.empty()){V tail=datum();if(token().first!=')')fail("expected )");return list(a,tail);}a.push_back(from(t));}}
};
int main(){Reader r;string s;while(getline(cin,s)&&s!="(exit)")r.lines.push_back(s);E e=global();while(!r.end()){V x;try{x=r.datum();}catch(const runtime_error&err){string reason=err.what();line("Error: read: "+reason);if(reason=="unexpected end of input")break;r.skip();continue;}try{V v=evaluate(x,e);if(v!=nothing)line(repr(v));}catch(const runtime_error&err){line(string("Error: ")+err.what());}}if(mid)write("\n");}
