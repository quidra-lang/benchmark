#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>
#include <setjmp.h>
#include <stdint.h>

typedef struct Value Value; typedef struct Env Env;
typedef struct {Value **v;int n,cap;} Vec;
typedef struct Binding {char *name;Value *value;struct Binding *next;} Binding;
struct Env {Binding *frame;Env *parent;};
enum {INTEGER,BOOLEAN,STRING,SYMBOL,NIL,PAIR,PROCEDURE,VOID_VALUE,UNINITIALIZED};
struct Value {int kind;int64_t number;char *text;Value *car,*cdr;Vec params,body;char *rest;Env *env;int builtin,minimum;bool variadic;};
Value nil_value={.kind=NIL},void_value={.kind=VOID_VALUE},uninit_value={.kind=UNINITIALIZED};
Value *nil=&nil_value,*nothing=&void_value,*uninit=&uninit_value;
jmp_buf failure;char reason[8192];bool mid=false;
void *alloc(size_t n){void *p=calloc(1,n);if(!p)exit(1);return p;}
char *copy(const char*s){char*p=alloc(strlen(s)+1);strcpy(p,s);return p;}
char *format(const char*f,...){va_list a,b;va_start(a,f);va_copy(b,a);int n=vsnprintf(NULL,0,f,b);va_end(b);char*s=alloc((size_t)n+1);vsnprintf(s,(size_t)n+1,f,a);va_end(a);return s;}
_Noreturn void fail(const char*f,...){va_list a;va_start(a,f);vsnprintf(reason,sizeof reason,f,a);va_end(a);longjmp(failure,1);}
void push(Vec*a,Value*v){if(a->n==a->cap){a->cap=a->cap?a->cap*2:8;a->v=realloc(a->v,sizeof(Value*)*(size_t)a->cap);if(!a->v)exit(1);}a->v[a->n++]=v;}
Vec slice(Vec a,int start){Vec b={0};for(int i=start;i<a.n;i++)push(&b,a.v[i]);return b;}
Value *value(int k){Value*v=alloc(sizeof *v);v->kind=k;v->builtin=-1;return v;}
Value *number(int64_t n){Value*v=value(INTEGER);v->number=n;return v;}
Value *boolean(bool b){Value*v=value(BOOLEAN);v->number=b;return v;}
Value *text(int k,const char*s){Value*v=value(k);v->text=copy(s);return v;}
Value *cons(Value*a,Value*b){Value*v=value(PAIR);v->car=a;v->cdr=b;return v;}
Value *list(Vec a,Value*tail){for(int i=a.n-1;i>=0;i--)tail=cons(a.v[i],tail);return tail;}
bool unpack(Value*v,Vec*a){while(v->kind==PAIR){push(a,v->car);v=v->cdr;}return v==nil;}
bool truth(Value*v){return v->kind!=BOOLEAN||v->number;}
char *join(char*a,const char*b){return format("%s%s",a,b);}
char *repr(Value*v,bool quoted){
    if(v->kind==INTEGER)return format("%lld",(long long)v->number);if(v->kind==BOOLEAN)return v->number?"#t":"#f";if(v==nil)return "()";if(v->kind==SYMBOL)return v->text;
    if(v->kind==STRING){if(!quoted)return v->text;char*s=copy("\"");for(const char*p=v->text;*p;p++){if(*p=='\n')s=join(s,"\\n");else if(*p=='\\')s=join(s,"\\\\");else if(*p=='\"')s=join(s,"\\\"");else s=join(s,(char[]){*p,0});}return join(s,"\"");}
    if(v->kind==PROCEDURE)return v->text?format("#<procedure %s>",v->text):"#<procedure>";
    if(v->kind==PAIR){char*s=copy("(");bool first=true;while(v->kind==PAIR){if(!first)s=join(s," ");first=false;s=join(s,repr(v->car,quoted));v=v->cdr;}if(v!=nil)s=join(join(s," . "),repr(v,quoted));return join(s,")");}return "#<void>";
}
void shape(bool b,Value*x){if(!b)fail("bad syntax: %s",repr(x,true));}
bool eq(Value*a,Value*b,bool deep){if(a->kind!=b->kind)return false;if(a->kind==PAIR)return deep?eq(a->car,b->car,true)&&eq(a->cdr,b->cdr,true):a==b;if(a->kind==PROCEDURE)return a==b;if(a->kind==INTEGER||a->kind==BOOLEAN)return a->number==b->number;if(a->kind==STRING||a->kind==SYMBOL)return !strcmp(a->text,b->text);return a==b;}
Env *environment(Env*p){Env*e=alloc(sizeof *e);e->parent=p;return e;}
void bind(Env*e,char*n,Value*v){for(Binding*b=e->frame;b;b=b->next)if(!strcmp(b->name,n)){b->value=v;return;}Binding*b=alloc(sizeof *b);b->name=n;b->value=v;b->next=e->frame;e->frame=b;}
Binding *find(Env*e,char*n){for(;e;e=e->parent)for(Binding*b=e->frame;b;b=b->next)if(!strcmp(b->name,n))return b;fail("unbound variable: %s",n);}
Value *lookup(Env*e,char*n){Value*v=find(e,n)->value;if(v==uninit)fail("uninitialized variable: %s",n);return v;}
Value *evaluate(Value*,Env*);Value *call(Value*,Vec);
Value *body(Vec a,Env*e){Value*v=nothing;for(int i=0;i<a.n;i++)v=evaluate(a.v[i],e);return v;}
bool distinct(Vec names){for(int i=0;i<names.n;i++)for(int j=0;j<i;j++)if(!strcmp(names.v[i]->text,names.v[j]->text))return false;return true;}
bool parameters(Value*v,Vec*p,char**r){while(v->kind==PAIR){if(v->car->kind!=SYMBOL)return false;push(p,v->car);v=v->cdr;}if(v!=nil&&v->kind!=SYMBOL)return false;Vec all=*p;if(v!=nil){all=slice(*p,0);push(&all,v);*r=v->text;}return distinct(all);}
Value *closure(Vec p,char*r,Vec b,Env*e,char*n){Value*v=value(PROCEDURE);v->params=p;v->rest=r;v->body=b;v->env=e;v->text=n;v->minimum=p.n;v->variadic=r!=NULL;return v;}
bool bindings(Value*v,Vec*names,Vec*exprs,bool unique){Vec a={0};if(!unpack(v,&a))return false;for(int i=0;i<a.n;i++){Vec b={0};if(!unpack(a.v[i],&b)||b.n!=2||b.v[0]->kind!=SYMBOL)return false;push(names,b.v[0]);push(exprs,b.v[1]);}return !unique||distinct(*names);}
Value *evaluate(Value*x,Env*e){
    if(x->kind==SYMBOL)return lookup(e,x->text);if(x->kind!=PAIR){shape(x!=nil,x);return x;}Vec a={0};shape(unpack(x,&a),x);int n=a.n;char*h=a.v[0]->kind==SYMBOL?a.v[0]->text:"";
    if(!strcmp(h,"quote")){shape(n==2,x);return a.v[1];}if(!strcmp(h,"if")){shape(n==3||n==4,x);return truth(evaluate(a.v[1],e))?evaluate(a.v[2],e):n==4?evaluate(a.v[3],e):nothing;}
    if(!strcmp(h,"begin"))return body(slice(a,1),e);
    if(!strcmp(h,"lambda")){Vec p={0};char*r=NULL;shape(n>=3&&parameters(a.v[1],&p,&r),x);return closure(p,r,slice(a,2),e,NULL);}
    if(!strcmp(h,"define")){
        if(n>1&&a.v[1]->kind==SYMBOL){shape(n==3,x);Value*v=evaluate(a.v[2],e);if(v->kind==PROCEDURE&&v->builtin<0&&!v->text)v->text=a.v[1]->text;bind(e,a.v[1]->text,v);}
        else{Vec p={0};char*r=NULL;shape(n>=3&&a.v[1]->kind==PAIR&&a.v[1]->car->kind==SYMBOL&&parameters(a.v[1]->cdr,&p,&r),x);char*name=a.v[1]->car->text;bind(e,name,closure(p,r,slice(a,2),e,name));}return nothing;
    }
    if(!strcmp(h,"set!")){shape(n==3&&a.v[1]->kind==SYMBOL,x);Value*v=evaluate(a.v[2],e);find(e,a.v[1]->text)->value=v;return nothing;}
    if(!strcmp(h,"let")||!strcmp(h,"let*")||!strcmp(h,"letrec")){
        bool named=!strcmp(h,"let")&&n>1&&a.v[1]->kind==SYMBOL;int at=named?2:1;Vec names={0},exprs={0};shape(n>=at+2&&bindings(a.v[at],&names,&exprs,strcmp(h,"let*")!=0),x);Env*s=environment(e);
        if(!strcmp(h,"let*")){if(names.n)s=e;for(int i=0;i<names.n;i++){Value*v=evaluate(exprs.v[i],s);s=environment(s);bind(s,names.v[i]->text,v);}}
        else if(!strcmp(h,"letrec")){for(int i=0;i<names.n;i++)bind(s,names.v[i]->text,uninit);for(int i=0;i<names.n;i++){Value*v=evaluate(exprs.v[i],s);bind(s,names.v[i]->text,v);}}
        else{Vec vs={0};for(int i=0;i<names.n;i++)push(&vs,evaluate(exprs.v[i],e));if(named){Value*p=closure(names,NULL,slice(a,3),s,a.v[1]->text);bind(s,a.v[1]->text,p);return call(p,vs);}for(int i=0;i<names.n;i++)bind(s,names.v[i]->text,vs.v[i]);}return body(slice(a,at+1),s);
    }
    if(!strcmp(h,"cond")){
        for(int i=1;i<n;i++){Vec c={0};shape(unpack(a.v[i],&c)&&c.n>0,x);if(c.v[0]->kind==SYMBOL&&!strcmp(c.v[0]->text,"else"))shape(c.n>=2&&i==n-1,x);}
        for(int i=1;i<n;i++){Vec c={0};unpack(a.v[i],&c);if(c.v[0]->kind==SYMBOL&&!strcmp(c.v[0]->text,"else"))return body(slice(c,1),e);Value*v=evaluate(c.v[0],e);if(truth(v))return c.n==1?v:body(slice(c,1),e);}return nothing;
    }
    if(!strcmp(h,"and")){Value*v=boolean(true);for(int i=1;i<n;i++){v=evaluate(a.v[i],e);if(!truth(v))break;}return v;}
    if(!strcmp(h,"or")){for(int i=1;i<n;i++){Value*v=evaluate(a.v[i],e);if(truth(v))return v;}return boolean(false);}
    if(!strcmp(h,"when")||!strcmp(h,"unless")){shape(n>=3,x);return truth(evaluate(a.v[1],e))==(!strcmp(h,"when"))?body(slice(a,2),e):nothing;}
    Value*f=evaluate(a.v[0],e);Vec args={0};for(int i=1;i<n;i++)push(&args,evaluate(a.v[i],e));if(f->kind!=PROCEDURE)fail("not a procedure: %s",repr(f,true));return call(f,args);
}
void write_text(char*s){fputs(s,stdout);size_t n=strlen(s);if(n)mid=s[n-1]!='\n';}void line(char*s){if(mid)write_text("\n");write_text(s);write_text("\n");}
Value *expect(char*n,Value*v,char*k){Vec z={0};bool ok=!strcmp(k,"integer")?v->kind==INTEGER:!strcmp(k,"pair")?v->kind==PAIR:!strcmp(k,"string")?v->kind==STRING:!strcmp(k,"procedure")?v->kind==PROCEDURE:unpack(v,&z);if(!ok)fail("%s: expected %s, got %s",n,k,repr(v,true));return v;}
Vec aslist(char*n,Value*v){expect(n,v,"list");Vec z={0};unpack(v,&z);return z;}
const char*names[]={"+","*","-","quotient","remainder","modulo","abs","min","max","gcd","=","<",">","<=",">=","not","eq?","equal?","null?","pair?","list?","number?","symbol?","procedure?","cons","car","cdr","cadr","list","length","append","reverse","list-ref","map","filter","fold-left","apply","string-append","number->string","display","newline","error"};
const int minimum[]={0,0,1,2,2,2,1,1,1,0,1,1,1,1,1,1,2,2,1,1,1,1,1,1,2,1,1,1,0,1,0,1,2,2,2,3,2,0,1,1,0,1};
bool variable(int i){return i==0||i==1||i==2||i==7||i==8||i==9||(i>=10&&i<=14)||i==28||i==30||i==33||i==35||i==36||i==37||i==41;}
Value *builtin(int id,Vec a){char*n=(char*)names[id];
    if(id<=14){for(int i=0;i<a.n;i++)expect(n,a.v[i],"integer");int64_t v=a.n?a.v[0]->number:0;
        if(id<=1){v=id?1:0;for(int i=0;i<a.n;i++)v=id?v*a.v[i]->number:v+a.v[i]->number;return number(v);}if(id==2){if(a.n==1)return number(-v);for(int i=1;i<a.n;i++)v-=a.v[i]->number;return number(v);}
        if(id>=3&&id<=5){int64_t b=a.v[1]->number;if(!b)fail("%s: division by zero",n);int64_t q=v/b,r=v%b;if(id==3)return number(q);if(id==5&&r&&((r<0)!=(b<0)))r+=b;return number(r);}if(id==6)return number(v<0?-v:v);
        if(id==7||id==8){for(int i=1;i<a.n;i++)if(id==7?a.v[i]->number<v:a.v[i]->number>v)v=a.v[i]->number;return number(v);}if(id==9){v=0;for(int i=0;i<a.n;i++){int64_t b=a.v[i]->number;if(b<0)b=-b;while(b){int64_t r=v%b;v=b;b=r;}}return number(v);}
        bool ok=true;for(int i=1;i<a.n;i++){int64_t l=a.v[i-1]->number,r=a.v[i]->number;ok=ok&&(id==10?l==r:id==11?l<r:id==12?l>r:id==13?l<=r:l>=r);}return boolean(ok);
    }
    if(id==15)return boolean(!truth(a.v[0]));if(id==16||id==17)return boolean(eq(a.v[0],a.v[1],id==17));
    if(id>=18&&id<=23){Value*v=a.v[0];Vec z={0};return boolean(id==18?v==nil:id==19?v->kind==PAIR:id==20?unpack(v,&z):id==21?v->kind==INTEGER:id==22?v->kind==SYMBOL:v->kind==PROCEDURE);}
    if(id==24)return cons(a.v[0],a.v[1]);if(id>=25&&id<=27){Value*p=expect(n,a.v[0],"pair");return id==25?p->car:id==26?p->cdr:expect(n,p->cdr,"pair")->car;}if(id==28)return list(a,nil);
    if(id==29||id==31||id==32){Vec z=aslist(n,a.v[0]);if(id==29)return number(z.n);if(id==31){Value*v=nil;for(int i=0;i<z.n;i++)v=cons(z.v[i],v);return v;}int64_t k=expect(n,a.v[1],"integer")->number;if(k<0||k>=z.n)fail("list-ref: index out of range: %lld",(long long)k);return z.v[k];}
    if(id==30){if(!a.n)return nil;Vec z={0};for(int i=0;i<a.n-1;i++){Vec b=aslist(n,a.v[i]);for(int j=0;j<b.n;j++)push(&z,b.v[j]);}return list(z,a.v[a.n-1]);}
    if(id>=33&&id<=36){Value*f=expect(n,a.v[0],"procedure");if(id==36){Vec z={0};for(int i=1;i<a.n-1;i++)push(&z,a.v[i]);Vec b=aslist(n,a.v[a.n-1]);for(int i=0;i<b.n;i++)push(&z,b.v[i]);return call(f,z);}int first=id==35?2:1,count=1000000,ln=a.n-first;Vec*ls=alloc(sizeof(Vec)*(size_t)ln);for(int i=0;i<ln;i++){ls[i]=aslist(n,a.v[first+i]);if(ls[i].n<count)count=ls[i].n;}Vec out={0};Value*acc=a.v[1];for(int i=0;i<count;i++){Vec args={0};if(id==35)push(&args,acc);for(int j=0;j<ln;j++)push(&args,ls[j].v[i]);Value*v=call(f,args);if(id==34){if(truth(v))push(&out,ls[0].v[i]);}else if(id==33)push(&out,v);else acc=v;}return id==35?acc:list(out,nil);}
    if(id==37){char*s=copy("");for(int i=0;i<a.n;i++)s=join(s,expect(n,a.v[i],"string")->text);return text(STRING,s);}if(id==38)return text(STRING,repr(expect(n,a.v[0],"integer"),true));
    if(id==39){write_text(repr(a.v[0],false));return nothing;}if(id==40){write_text("\n");return nothing;}char*s=expect(n,a.v[0],"string")->text;for(int i=1;i<a.n;i++)s=join(join(s," "),repr(a.v[i],true));fail("%s",s);
}
Value *call(Value*f,Vec a){if(a.n<f->minimum||(!f->variadic&&a.n!=f->minimum))fail("%s: wrong number of arguments (expected %s%d, got %d)",f->text?f->text:"lambda",f->variadic?"at least ":"",f->minimum,a.n);if(f->builtin>=0)return builtin(f->builtin,a);Env*e=environment(f->env);for(int i=0;i<f->params.n;i++)bind(e,f->params.v[i]->text,a.v[i]);if(f->variadic)bind(e,f->rest,list(slice(a,f->minimum),nil));return body(f->body,e);}
typedef struct {char **lines;int count,row,col;} Reader;
void skip(Reader*r){r->row++;r->col=0;}bool end(Reader*r){while(r->row<r->count){char*s=r->lines[r->row];while(s[r->col]==' ')r->col++;if(s[r->col]&&s[r->col]!=';')return false;skip(r);}return true;}
typedef struct {char kind;Value*v;} Token;
Token token(Reader*r){if(end(r))fail("unexpected end of input");char*s=r->lines[r->row],c=s[r->col++];if(strchr("()'",c))return (Token){c,NULL};if(c=='"'){char*v=copy("");while(s[r->col]){c=s[r->col++];if(c=='"')return (Token){'v',text(STRING,v)};if(c=='\\'){if(!s[r->col])break;c=s[r->col++];if(c!='"'&&c!='\\'&&c!='n')fail("bad escape");if(c=='n')c='\n';}v=join(v,(char[]){c,0});}fail("unterminated string");}
    int start=r->col-1;while(s[r->col]&&!strchr(" ()'\";",s[r->col]))r->col++;char*a=alloc((size_t)(r->col-start)+1);memcpy(a,s+start,(size_t)(r->col-start));if(!strcmp(a,"."))return (Token){'.',NULL};int i=(a[0]=='+'||a[0]=='-')?1:0;bool integer=a[i]!=0;for(;a[i];i++)integer=integer&&a[i]>='0'&&a[i]<='9';if(integer)return (Token){'v',number(strtoll(a,NULL,10))};if(!strcmp(a,"#t")||!strcmp(a,"#f"))return (Token){'v',boolean(a[1]=='t')};if(a[0]=='#')fail("bad token: %s",a);return (Token){'v',text(SYMBOL,a)};
}
Value *datum(Reader*);Value *from(Reader*r,Token t){if(t.kind=='v')return t.v;if(t.kind=='\''){Vec a={0};push(&a,text(SYMBOL,"quote"));push(&a,datum(r));return list(a,nil);}if(t.kind!='(')fail("unexpected %c",t.kind);Vec a={0};while(true){t=token(r);if(t.kind==')')return list(a,nil);if(t.kind=='.'&&a.n){Value*tail=datum(r);if(token(r).kind!=')')fail("expected )");return list(a,tail);}push(&a,from(r,t));}}
Value *datum(Reader*r){Token t=token(r);return from(r,t);}
int main(void){Reader*r=alloc(sizeof *r);r->lines=alloc(sizeof(char*)*3000);char s[256];while(fgets(s,sizeof s,stdin)){s[strcspn(s,"\r\n")]=0;if(!strcmp(s,"(exit)"))break;r->lines[r->count++]=copy(s);}Env*e=environment(NULL);for(int i=0;i<42;i++){Value*p=text(PROCEDURE,names[i]);p->builtin=i;p->minimum=minimum[i];p->variadic=variable(i);bind(e,p->text,p);}while(!end(r)){Value*x;if(setjmp(failure)){line(format("Error: read: %s",reason));if(!strcmp(reason,"unexpected end of input"))break;skip(r);continue;}x=datum(r);if(setjmp(failure)){line(format("Error: %s",reason));continue;}Value*v=evaluate(x,e);if(v!=nothing)line(repr(v,true));}if(mid)write_text("\n");return 0;}
