#include "prolog.h"
static Operator operators[]= {
    {
        ":-",1200,1199,1199,0
    }, {
        ";",1100,1099,1100,0
    }, {
        "->",1050,1049,1050,0
    }, {
        ",",1000,999,1000,0
    }, {
        "=",700,699,699,0
    }, {
        "\\=",700,699,699,0
    }, {
        "==",700,699,699,0
    }, {
        "\\==",700,699,699,0
    }, {
        "is",700,699,699,0
    }, {
        "=:=",700,699,699,0
    }, {
        "=\\=",700,699,699,0
    }, {
        "<",700,699,699,0
    }, {
        ">",700,699,699,0
    }, {
        "=<",700,699,699,0
    }, {
        ">=",700,699,699,0
    }, {
        "=..",700,699,699,0
    }, {
        "+",500,500,499,0
    }, {
        "-",500,500,499,200
    }, {
        "*",400,400,399,0
    }, {
        "/",400,400,399,0
    }, {
        "//",400,400,399,0
    }, {
        "mod",400,400,399,0
    }, {
        "rem",400,400,399,0
    }
};
const Operator *infix_operator(const char *name) {
    for(size_t i=0;i<sizeof operators/sizeof *operators;++i)if(!strcmp(name,operators[i].name))return &operators[i];
    return NULL;
}
int prefix_priority(const char *name) {
    return !strcmp(name,"\\+")?900:!strcmp(name,"-")?200:0;
}
int symbol_character(int c) {
    return c&&strchr("+-*/\\^<>=~:.?@#&$",c)!=NULL;
}
static void token_add(Reader *r,Token t,int *capacity) {
    if(r->count==*capacity) {
        int n=*capacity?*capacity*2:64;
        Token *p=make((size_t)n*sizeof *p);
        if(r->count)memcpy(p,r->tokens,(size_t)r->count*sizeof *p);
        r->tokens=p;
        *capacity=n;
    }
    r->tokens[r->count++]=t;
}
Reader tokenize(const char *s,int column) {
    Reader r= {
        0
    };
    int i=0,line=1,col=column,whitespace=1,capacity=0;
    while(s[i]) {
        if(s[i]==' '||s[i]=='\n') {
            whitespace=1;
            if(s[i++]=='\n') {
                ++line;
                col=1;
            }
            else ++col;
            continue;
        }
        if(s[i]=='%') {
            whitespace=1;
            while(s[i]&&s[i]!='\n') {
                ++i;
                ++col;
            }
            continue;
        }
        Token t= {
            .line=line,.column=col,.space=whitespace
        };
        whitespace=0;
        int start=i;
        char c=s[i];
        if(isdigit((unsigned char)c)) {
            long long n=0;
            while(isdigit((unsigned char)s[i])) {
                if(n<=INT32_MAX)n=10*n+s[i]-'0';
                ++i;
                ++col;
            }
            if(n>INT32_MAX) {
                t.kind=TOKEN_INVALID;
                t.name=copy_string("integer too large");
            }
            else {
                t.kind=TOKEN_INTEGER;
                t.integer=n;
            }
        }
        else if(isalpha((unsigned char)c)||c=='_') {
            while(isalnum((unsigned char)s[i])||s[i]=='_') {
                ++i;
                ++col;
            }
            t.kind=c>='a'&&c<='z'?TOKEN_NAME:TOKEN_VARIABLE;
        }
        else if(symbol_character(c)) {
            while(symbol_character(s[i])) {
                ++i;
                ++col;
            }
            t.kind=i-start==1&&c=='.'&&(!s[i]||s[i]==' '||s[i]=='\n'||s[i]=='%')?TOKEN_END:TOKEN_NAME;
        }
        else if(c=='!'||c==';') {
            t.kind=TOKEN_NAME;
            ++i;
            ++col;
        }
        else if(strchr(",|()[]",c)) {
            t.kind=TOKEN_PUNCT;
            ++i;
            ++col;
        }
        else if(c=='\'') {
            Buffer name= {
                0
            };
            ++i;
            ++col;
            int closed=0,bad=0;
            while(s[i]&&s[i]!='\n') {
                char ch=s[i];
                if(ch=='\''&&s[i+1]=='\'') {
                    add_bytes(&name,"'",1);
                    i+=2;
                    col+=2;
                }
                else if(ch=='\'') {
                    ++i;
                    ++col;
                    closed=1;
                    break;
                }
                else if(ch=='\\') {
                    ++i;
                    ++col;
                    if(!s[i]||s[i]=='\n')continue;
                    ch=s[i++];
                    ++col;
                    if(ch=='n')ch='\n';
                    else if(ch=='t')ch='\t';
                    else if(ch!='\\'&&ch!='\'')bad=1;
                    add_bytes(&name,&ch,1);
                }
                else {
                    add_bytes(&name,&ch,1);
                    ++i;
                    ++col;
                }
            }
            if(!closed) {
                t.kind=TOKEN_INVALID;
                t.name=copy_string("unterminated quoted atom");
            }
            else if(bad) {
                t.kind=TOKEN_INVALID;
                t.name=copy_string("undefined escape sequence");
            }
            else {
                t.kind=TOKEN_QUOTED;
                t.name=name.text?name.text:copy_string("");
            }
        }
        else {
            t.kind=TOKEN_INVALID;
            char text[40];
            sprintf(text,"illegal character '%c'",c);
            t.name=copy_string(text);
            ++i;
            ++col;
        }
        t.text=make((size_t)(i-start)+1);
        memcpy(t.text,s+start,(size_t)(i-start));
        if(!t.name)t.name=t.text;
        token_add(&r,t,&capacity);
    }
    Token eof= {
        .kind=TOKEN_EOF,.line=line,.column=col,.space=whitespace,.text="",.name=""
    };
    token_add(&r,eof,&capacity);
    return r;
}
static Token *peek(Reader *r) {
    return &r->tokens[r->at<r->count?r->at:r->count-1];
}
static void syntax_error(Reader *r,int at,const char *message) {
    r->error_at=at;
    Token t=r->tokens[at];
    if(message)r->error=copy_string(message);
    else if(t.kind==TOKEN_INVALID)r->error=t.name;
    else if(t.kind==TOKEN_EOF)r->error=copy_string("unexpected end of file");
    else if(t.kind==TOKEN_END)r->error=copy_string("unexpected end of clause");
    else if(t.kind==TOKEN_NAME&&infix_operator(t.name))r->error=copy_string("operator priority clash");
    else {
        Buffer b= {
            0
        };
        add_format(&b,"unexpected \"%s\"",t.text);
        r->error=b.text;
    }
    longjmp(r->failure,1);
}
static void expect(Reader *r,const char *name) {
    int at=r->at;
    Token *t=peek(r);
    if(t->kind!=TOKEN_PUNCT||strcmp(t->name,name))syntax_error(r,at,NULL);
    ++r->at;
}
static Term *read_variable(Reader *r,Token t) {
    if(strcmp(t.name,"_"))for(int i=0;i<r->nv;++i)if(!strcmp(r->variables[i].name,t.name)) {
        ++r->variables[i].occurrences;
        return r->variables[i].term;
    }
    ReadVariable *vars=make((size_t)(r->nv+1)*sizeof *vars);
    if(r->nv)memcpy(vars,r->variables,(size_t)r->nv*sizeof *vars);
    r->variables=vars;
    Term *v=fresh();
    vars[r->nv++]=(ReadVariable) {
        t.name,v,1
    };
    return v;
}
static Term *read_term(Reader *r,int limit,int *priority);
static int starts_term(Token *t) {
    return t->kind==TOKEN_INTEGER||t->kind==TOKEN_VARIABLE||t->kind==TOKEN_QUOTED||(t->kind==TOKEN_PUNCT&&(!strcmp(t->name,"(")||!strcmp(t->name,"[")))||(t->kind==TOKEN_NAME&&(!infix_operator(t->name)||prefix_priority(t->name)));
}
static void add_argument(Term ***args,int *n,Term *term) {
    Term **items=make((size_t)(*n+1)*sizeof *items);
    if(*n)memcpy(items,*args,(size_t)*n*sizeof *items);
    *args=items;
    items[(*n)++]=term;
}
static Term *primary(Reader *r,int limit,int *priority) {
    int at=r->at++;
    Token t=r->tokens[at];
    *priority=0;
    if(t.kind==TOKEN_INTEGER)return integer(t.integer);
    if(t.kind==TOKEN_VARIABLE)return read_variable(r,t);
    if(t.kind==TOKEN_PUNCT&&!strcmp(t.name,"(")) {
        int p;
        Term *inside=read_term(r,1200,&p);
        expect(r,")");
        return inside;
    }
    if(t.kind==TOKEN_PUNCT&&!strcmp(t.name,"[")) {
        if(peek(r)->kind==TOKEN_PUNCT&&!strcmp(peek(r)->name,"]")) {
            ++r->at;
            return atom("[]");
        }
        Term **elements=NULL;
        int n=0,p;
        add_argument(&elements,&n,read_term(r,999,&p));
        while(peek(r)->kind==TOKEN_PUNCT&&!strcmp(peek(r)->name,",")) {
            ++r->at;
            add_argument(&elements,&n,read_term(r,999,&p));
        }
        Term *tail=atom("[]");
        if(peek(r)->kind==TOKEN_PUNCT&&!strcmp(peek(r)->name,"|")) {
            ++r->at;
            tail=read_term(r,999,&p);
        }
        expect(r,"]");
        return list(elements,n,tail);
    }
    if(t.kind==TOKEN_NAME||t.kind==TOKEN_QUOTED) {
        Token *next=peek(r);
        if(next->kind==TOKEN_PUNCT&&!strcmp(next->name,"(")&&!next->space) {
            ++r->at;
            Term **args=NULL;
            int n=0,p;
            add_argument(&args,&n,read_term(r,999,&p));
            while(peek(r)->kind==TOKEN_PUNCT&&!strcmp(peek(r)->name,",")) {
                ++r->at;
                add_argument(&args,&n,read_term(r,999,&p));
            }
            expect(r,")");
            return compound(t.name,n,args);
        }
        if(t.kind==TOKEN_NAME&&!strcmp(t.name,"-")&&next->kind==TOKEN_INTEGER&&!next->space) {
            ++r->at;
            return integer(-next->integer);
        }
        int p=t.kind==TOKEN_NAME?prefix_priority(t.name):0;
        if(p&&starts_term(next)) {
            if(p>limit)syntax_error(r,at,"operator priority clash");
            int rp;
            Term *arg=read_term(r,p,&rp);
            *priority=p;
            return unary(t.name,arg);
        }
        return atom(t.name);
    }
    syntax_error(r,at,NULL);
    return NULL;
}
static Term *read_term(Reader *r,int limit,int *priority) {
    Term *term=primary(r,limit,priority);
    for(;;) {
        Token *t=peek(r);
        const Operator *op=(t->kind==TOKEN_NAME||(t->kind==TOKEN_PUNCT&&!strcmp(t->name,",")))?infix_operator(t->name):NULL;
        if(!op||op->priority>limit||*priority>op->left)break;
        ++r->at;
        int p;
        Term *right=read_term(r,op->right,&p);
        term=binary(op->name,term,right);
        *priority=op->priority;
    }
    return term;
}
void reader_reset_variables(Reader *r) {
    r->variables=NULL;
    r->nv=0;
    r->error=NULL;
    r->error_at=-1;
}
Term *read_clause(Reader *r,int query) {
    reader_reset_variables(r);
    if(setjmp(r->failure))return NULL;
    int p;
    Term *term=read_term(r,1200,&p);
    int end=r->at++;
    if(r->tokens[end].kind!=TOKEN_END)syntax_error(r,end,NULL);
    if(query&&peek(r)->kind!=TOKEN_EOF)syntax_error(r,r->at,NULL);
    return term;
}
