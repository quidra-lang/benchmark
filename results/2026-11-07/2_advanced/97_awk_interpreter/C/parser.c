#include "awk.h"
typedef struct {
    Tokens tokens;
    int at,loops,in_function,phase,output,depth;
    Syntax result;
    jmp_buf failure;
}
Parser;
static Token *peek(Parser *p) {
    return &p->tokens.tokens[p->at];
}
static int is(Parser *p,const char *s) {
    return !strcmp(peek(p)->text,s);
}
static void fail(Parser *p,Token t) {
    p->result.failed=1;
    p->result.error=t.pos;
    longjmp(p->failure,1);
}
static Token take(Parser *p) {
    return p->tokens.tokens[p->at++];
}
static int accept(Parser *p,const char *s) {
    if(is(p,s)) {
        ++p->at;
        return 1;
    }
    return 0;
}
static Token expect(Parser *p,const char *s) {
    if(!is(p,s))fail(p,*peek(p));
    return take(p);
}
static void newlines(Parser *p) {
    while(peek(p)->kind==T_NL)++p->at;
}
static Token name(Parser *p) {
    if(peek(p)->kind!=T_NAME)fail(p,*peek(p));
    return take(p);
}
static Expr *expression(Parser *p);
static Statement *statement(Parser *p);
static Expr *expr(int kind,Token t) {
    Expr *e=mem_new(sizeof *e);
    e->kind=kind;
    e->token=t;
    return e;
}
static void argument(Expr *e,Expr *a) {
    e->args=mem_resize(e->args,(size_t)(e->count+1)*sizeof *e->args);
    e->args[e->count++]=a;
}
static void expression_list(Parser *p,Expr *e) {
    argument(e,expression(p));
    while(accept(p,",")) {
        newlines(p);
        argument(e,expression(p));
    }
}
static int lvalue(Expr *e) {
    return e->kind==E_VAR||e->kind==E_ARRAY||e->kind==E_FIELD;
}
static Expr *atom(Parser *p);
static Expr *prefix_increment(Parser *p) {
    Token t=take(p);
    Expr *e=expr(E_INC,t);
    e->op=t.text;
    e->a=atom(p);
    if(!lvalue(e->a))fail(p,e->a->token);
    return e;
}
static Expr *atom(Parser *p) {
    Token t=take(p);
    Expr *e;
    if(t.kind==T_NUMBER)return expr(E_NUMBER,t);
    if(t.kind==T_STRING)return expr(E_STRING,t);
    if(t.kind==T_NAME) {
        e=expr(E_VAR,t);
        if(accept(p,"[")) {
            e->kind=E_ARRAY;
            ++p->depth;
            expression_list(p,e);
            expect(p,"]");
            --p->depth;
        }
        return e;
    }
    if(!strcmp(t.text,"$")) {
        e=expr(E_FIELD,t);
        if(is(p,"++")||is(p,"--"))e->a=prefix_increment(p);
        else e->a=atom(p);
        return e;
    }
    if(!strcmp(t.text,"(")) {
        e=expr(E_GROUP,t);
        ++p->depth;
        expression_list(p,e);
        expect(p,")");
        --p->depth;
        if(e->count==1) {
            e->a=e->args[0];
            free(e->args);
            e->args=NULL;
            e->count=0;
        }
        else {
            e->kind=E_IN;
            expect(p,"in");
            e->token=name(p);
        }
        return e;
    }
    if(t.kind==T_FUNCTION||t.kind==T_BUILTIN) {
        e=expr(t.kind==T_FUNCTION?E_CALL:E_BUILTIN,t);
        if(accept(p,"(")) {
            ++p->depth;
            if(!is(p,")"))expression_list(p,e);
            expect(p,")");
            --p->depth;
        }
        else if(strcmp(t.text,"length"))fail(p,*peek(p));
        if(t.kind==T_BUILTIN) {
            int n=e->count,valid=!strcmp(t.text,"length")?n<=1:!strcmp(t.text,"substr")?n==2||n==3:!strcmp(t.text,"index")?n==2:!strcmp(t.text,"split")?(n==2||n==3)&&e->args[1]->kind==E_VAR:!strcmp(t.text,"sprintf")?n>=1:n==1;
            if(!valid)fail(p,t);
        }
        return e;
    }
    if(!strcmp(t.text,"getline")) {
        e=expr(E_GETLINE,t);
        if(peek(p)->kind==T_NAME||is(p,"$")) {
            e->a=atom(p);
            if(!lvalue(e->a))fail(p,e->a->token);
        }
        if(accept(p,"<"))e->b=atom(p);
        return e;
    }
    fail(p,t);
    return NULL;
}
static Expr *postfix(Parser *p) {
    if(is(p,"++")||is(p,"--"))return prefix_increment(p);
    Expr *e=atom(p);
    if(lvalue(e)&&(is(p,"++")||is(p,"--"))) {
        Token t=take(p);
        Expr *x=expr(E_INC,t);
        x->op=t.text;
        x->postfix=1;
        x->a=e;
        e=x;
    }
    return e;
}
static Expr *binary(Expr *a,Expr *b,Token t) {
    Expr *e=expr(E_BINARY,t);
    e->op=t.text;
    e->a=a;
    e->b=b;
    return e;
}
static Expr *unary(Parser *p) {
    if(is(p,"!")||is(p,"-")||is(p,"+")) {
        Token t=take(p);
        Expr *e=expr(E_UNARY,t);
        e->op=t.text;
        e->a=unary(p);
        return e;
    }
    Expr *e=postfix(p);
    if(is(p,"^")) {
        Token t=take(p);
        e=binary(e,unary(p),t);
    }
    return e;
}
static Expr *multiply(Parser *p) {
    Expr *e=unary(p);
    while(is(p,"*")||is(p,"/")||is(p,"%")) {
        Token t=take(p);
        e=binary(e,unary(p),t);
    }
    return e;
}
static Expr *add(Parser *p) {
    Expr *e=multiply(p);
    while(is(p,"+")||is(p,"-")) {
        Token t=take(p);
        e=binary(e,multiply(p),t);
    }
    return e;
}
static int concat_start(Parser *p) {
    int k=peek(p)->kind;
    return k==T_NUMBER||k==T_STRING||k==T_NAME||k==T_FUNCTION||k==T_BUILTIN||is(p,"$")||is(p,"(")||is(p,"++")||is(p,"--");
}
static Expr *concat(Parser *p) {
    Expr *e=add(p);
    while(concat_start(p)) {
        Token t=*peek(p);
        t.text="concat";
        e=binary(e,add(p),t);
    }
    return e;
}
static Expr *comparison(Parser *p) {
    Expr *e=concat(p);
    while(is(p,"<")||is(p,"<=")||is(p,"==")||is(p,"!=")||is(p,">=")||(is(p,">")&&!(p->output&&!p->depth))) {
        Token t=take(p);
        e=binary(e,concat(p),t);
    }
    return e;
}
static Expr *in_expr(Parser *p) {
    Expr *e=comparison(p);
    while(accept(p,"in")) {
        Token t=name(p);
        Expr *x=expr(E_IN,t);
        argument(x,e);
        e=x;
    }
    return e;
}
static Expr *and_expr(Parser *p) {
    Expr *e=in_expr(p);
    while(is(p,"&&")) {
        Token t=take(p);
        newlines(p);
        e=binary(e,in_expr(p),t);
    }
    return e;
}
static Expr *or_expr(Parser *p) {
    Expr *e=and_expr(p);
    while(is(p,"||")) {
        Token t=take(p);
        newlines(p);
        e=binary(e,and_expr(p),t);
    }
    return e;
}
static Expr *conditional(Parser *p) {
    Expr *e=or_expr(p);
    if(is(p,"?")) {
        Token t=take(p);
        Expr *x=expr(E_COND,t);
        x->a=e;
        x->b=conditional(p);
        expect(p,":");
        x->c=conditional(p);
        e=x;
    }
    return e;
}
static Expr *expression(Parser *p) {
    Expr *e=conditional(p);
    if(lvalue(e)&&(is(p,"=")||is(p,"+=")||is(p,"-=")||is(p,"*=")||is(p,"/=")||is(p,"%=")||is(p,"^="))) {
        Token t=take(p);
        Expr *x=expr(E_ASSIGN,t);
        x->op=t.text;
        x->a=e;
        x->b=expression(p);
        e=x;
    }
    return e;
}
static Statement *stmt(int kind,Token t) {
    Statement *s=mem_new(sizeof *s);
    s->kind=kind;
    s->token=t;
    return s;
}
static void terminator(Parser *p) {
    if(is(p,";")||peek(p)->kind==T_NL)take(p);
    else if(!is(p,"}"))fail(p,*peek(p));
}
static Statement *block(Parser *p) {
    Statement *s=stmt(S_BLOCK,expect(p,"{"));
    while(!is(p,"}")) {
        if(peek(p)->kind==T_EOF)fail(p,*peek(p));
        if(peek(p)->kind==T_NL||accept(p,";")) {
            if(peek(p)->kind==T_NL)take(p);
            continue;
        }
        Statement *child=statement(p);
        s->children=mem_resize(s->children,(size_t)(s->count+1)*sizeof *s->children);
        s->children[s->count++]=child;
    }
    expect(p,"}");
    return s;
}
static Expr *paren_condition(Parser *p) {
    expect(p,"(");
    ++p->depth;
    Expr *e=expression(p);
    expect(p,")");
    --p->depth;
    return e;
}
static Statement *loop_body(Parser *p) {
    newlines(p);
    ++p->loops;
    Statement *s=statement(p);
    --p->loops;
    return s;
}
static int end_simple(Parser *p) {
    return is(p,";")||peek(p)->kind==T_NL||is(p,"}")||peek(p)->kind==T_EOF;
}
static Statement *statement(Parser *p) {
    Token t=*peek(p);
    Statement *s;
    if(is(p,"{"))return block(p);
    if(accept(p,";"))return stmt(S_EMPTY,t);
    if(accept(p,"if")) {
        s=stmt(S_IF,t);
        s->a=paren_condition(p);
        newlines(p);
        s->body=statement(p);
        newlines(p);
        if(accept(p,"else")) {
            newlines(p);
            s->otherwise=statement(p);
        }
    }
    else if(accept(p,"while")) {
        s=stmt(S_WHILE,t);
        s->a=paren_condition(p);
        s->body=loop_body(p);
    }
    else if(accept(p,"do")) {
        s=stmt(S_DO,t);
        s->body=loop_body(p);
        newlines(p);
        expect(p,"while");
        s->a=paren_condition(p);
        terminator(p);
    }
    else if(accept(p,"for")) {
        expect(p,"(");
        ++p->depth;
        int at=p->at;
        if(at+3<p->tokens.count&&p->tokens.tokens[at].kind==T_NAME&&!strcmp(p->tokens.tokens[at+1].text,"in")&&p->tokens.tokens[at+2].kind==T_NAME&&!strcmp(p->tokens.tokens[at+3].text,")")) {
            s=stmt(S_FORIN,t);
            s->a=expr(E_VAR,name(p));
            expect(p,"in");
            s->second=name(p);
            expect(p,")");
        }
        else {
            s=stmt(S_FOR,t);
            if(!is(p,";"))s->a=expression(p);
            expect(p,";");
            newlines(p);
            if(!is(p,";"))s->b=expression(p);
            expect(p,";");
            newlines(p);
            if(!is(p,")"))s->c=expression(p);
            expect(p,")");
        }
        --p->depth;
        s->body=loop_body(p);
    }
    else {
        take(p);
        if(!strcmp(t.text,"print")||!strcmp(t.text,"printf")) {
            s=stmt(!strcmp(t.text,"print")?S_PRINT:S_PRINTF,t);
            int enclosed=0;
            if(is(p,"(")) {
                int nesting=0,end=p->at;
                for(;end<p->tokens.count;++end) {
                    if(!strcmp(p->tokens.tokens[end].text,"("))++nesting;
                    else if(!strcmp(p->tokens.tokens[end].text,")")&&!--nesting)break;
                }
                if(end+1<p->tokens.count) {
                    Token next=p->tokens.tokens[end+1];
                    enclosed=next.kind==T_NL||next.kind==T_EOF||!strcmp(next.text,";")||!strcmp(next.text,"}")||!strcmp(next.text,">")||!strcmp(next.text,">>");
                }
            }
            Expr list= {
                0
            };
            if(enclosed) {
                take(p);
                ++p->depth;
                expression_list(p,&list);
                expect(p,")");
                --p->depth;
            }
            else if(!end_simple(p)&&!is(p,">")&&!is(p,">>")) {
                p->output=1;
                expression_list(p,&list);
                p->output=0;
            }
            if(s->kind==S_PRINTF&&!list.count)fail(p,*peek(p));
            s->args=list.args;
            s->nargs=list.count;
            if(is(p,">")||is(p,">>")) {
                Token redir=take(p);
                s->append=!strcmp(redir.text,">>");
                s->redirect=concat(p);
                s->second=redir;
            }
        }
        else if(!strcmp(t.text,"delete")) {
            s=stmt(S_DELETE,t);
            s->a=atom(p);
            if(s->a->kind!=E_VAR&&s->a->kind!=E_ARRAY)fail(p,s->a->token);
        }
        else if(!strcmp(t.text,"next")) {
            s=stmt(S_NEXT,t);
            if(!p->in_function&&p->phase)fail(p,t);
        }
        else if(!strcmp(t.text,"break")||!strcmp(t.text,"continue")) {
            s=stmt(!strcmp(t.text,"break")?S_BREAK:S_CONTINUE,t);
            if(!p->loops)fail(p,t);
        }
        else if(!strcmp(t.text,"exit")||!strcmp(t.text,"return")) {
            s=stmt(!strcmp(t.text,"exit")?S_EXIT:S_RETURN,t);
            if(s->kind==S_RETURN&&!p->in_function)fail(p,t);
            if(!end_simple(p))s->a=expression(p);
        }
        else {
            --p->at;
            s=stmt(S_EXPR,t);
            s->a=expression(p);
        }
        terminator(p);
    }
    p->result.statement_lines[t.pos.line]=1;
    return s;
}
Syntax parse(Tokens tokens,int lines) {
    Parser *p=mem_new(sizeof *p);
    p->tokens=tokens;
    p->result.lines=lines;
    p->result.statement_lines=mem_new((size_t)lines+2);
    if(setjmp(p->failure))return p->result;
    while(peek(p)->kind!=T_EOF) {
        if(peek(p)->kind==T_NL||accept(p,";")) {
            if(peek(p)->kind==T_NL)take(p);
            continue;
        }
        Token t=*peek(p);
        if(accept(p,"function")) {
            Function *f=mem_new(sizeof *f);
            if(peek(p)->kind!=T_NAME&&peek(p)->kind!=T_FUNCTION)fail(p,*peek(p));
            f->token=take(p);
            expect(p,"(");
            if(!is(p,")")) {
                do {
                    newlines(p);
                    Token param=name(p);
                    f->params=mem_resize(f->params,(size_t)(f->np+1)*sizeof *f->params);
                    f->params[f->np++]=param;
                }
                while(accept(p,","));
            }
            expect(p,")");
            newlines(p);
            p->in_function=1;
            f->body=block(p);
            p->in_function=0;
            p->result.functions=mem_resize(p->result.functions,(size_t)(p->result.nf+1)*sizeof *p->result.functions);
            p->result.functions[p->result.nf++]=f;
        }
        else {
            Rule *r=mem_new(sizeof *r);
            r->token=t;
            if(accept(p,"BEGIN")) {
                r->kind=1;
                p->phase=1;
                r->action=block(p);
                p->phase=0;
            }
            else if(accept(p,"END")) {
                r->kind=2;
                p->phase=2;
                r->action=block(p);
                p->phase=0;
            }
            else if(is(p,"{")) {
                r->kind=0;
                r->action=block(p);
            }
            else {
                r->kind=3;
                r->start=expression(p);
                if(accept(p,",")) {
                    newlines(p);
                    r->end=expression(p);
                    r->kind=4;
                }
                if(is(p,"{"))r->action=block(p);
                else if(peek(p)->kind!=T_NL&&peek(p)->kind!=T_EOF&&!is(p,";"))fail(p,*peek(p));
            }
            p->result.rules=mem_resize(p->result.rules,(size_t)(p->result.nr+1)*sizeof *p->result.rules);
            p->result.rules[p->result.nr++]=r;
        }
    }
    return p->result;
}
