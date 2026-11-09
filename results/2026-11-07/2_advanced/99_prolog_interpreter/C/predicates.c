#include "prolog.h"
int integer_check(BuiltinState *s,Term *t) {
    t=dereference(t);
    if(t->kind==TERM_VARIABLE)s->error=atom("instantiation_error");
    else if(t->kind!=TERM_INTEGER)s->error=type_error("integer",t);
    return !s->error;
}
static int atom_check(BuiltinState *s,Term *t) {
    t=dereference(t);
    if(t->kind==TERM_VARIABLE)s->error=atom("instantiation_error");
    else if(t->kind!=TERM_ATOM)s->error=type_error("atom",t);
    return !s->error;
}
static int proper_check(BuiltinState *s,Term *term,Term ***items,int *count) {
    Term *tail;
    *count=list_items(term,items,&tail);
    if(tail->kind==TERM_VARIABLE)s->error=atom("instantiation_error");
    else if(!empty_list(tail))s->error=type_error("list",term);
    return !s->error;
}
static long long arithmetic(BuiltinState *s,Term *t) {
    t=dereference(t);
    if(t->kind==TERM_VARIABLE) {
        s->error=atom("instantiation_error");
        return 0;
    }
    if(t->kind==TERM_INTEGER)return t->integer;
    const char *name=t->name;
    int arity=t->kind==TERM_COMPOUND?t->arity:0;
    int supported=(arity==1&&(!strcmp(name,"-")||!strcmp(name,"abs")))||(arity==2&&(!strcmp(name,"+")||!strcmp(name,"-")||!strcmp(name,"*")||!strcmp(name,"//")||!strcmp(name,"mod")||!strcmp(name,"rem")||!strcmp(name,"min")||!strcmp(name,"max")));
    if(!supported) {
        s->error=type_error("evaluable",indicator(name,arity));
        return 0;
    }
    long long a=arithmetic(s,t->args[0]);
    if(s->error)return 0;
    long long b=0;
    if(arity==2) {
        b=arithmetic(s,t->args[1]);
        if(s->error)return 0;
    }
    long long n=0;
    if(arity==1)n=!strcmp(name,"-")?-a:a<0?-a:a;
    else if(!strcmp(name,"+"))n=a+b;
    else if(!strcmp(name,"-"))n=a-b;
    else if(!strcmp(name,"*"))n=a*b;
    else if(!strcmp(name,"min"))n=a<b?a:b;
    else if(!strcmp(name,"max"))n=a>b?a:b;
    else {
        if(!b) {
            s->error=evaluation_error("zero_divisor");
            return 0;
        }
        if(!strcmp(name,"//"))n=a/b;
        else if(!strcmp(name,"rem"))n=a%b;
        else {
            n=a%b;
            if(n&&((n<0)!=(b<0)))n+=b;
        }
    }
    if(n<INT32_MIN||n>INT32_MAX)s->error=evaluation_error("int_overflow");
    return n;
}
static int u(BuiltinState *s,Term *a,Term *b) {
    return unify(s->trail,a,b);
}
int deterministic(BuiltinState *s,Term *goal) {
    const char *name=goal->name;
    int arity=goal->kind==TERM_COMPOUND?goal->arity:0;
    Term *a=arity?dereference(goal->args[0]):NULL,*b=arity>1?dereference(goal->args[1]):NULL,*c=arity>2?dereference(goal->args[2]):NULL;
    if(!strcmp(name,"true")&&!arity)return 1;
    if((!strcmp(name,"fail")||!strcmp(name,"false"))&&!arity)return 0;
    if(!strcmp(name,"=")&&arity==2)return u(s,a,b);
    if(!strcmp(name,"\\=")&&arity==2) {
        int mark=s->trail->count;
        int result=u(s,a,b);
        undo(s->trail,mark);
        return !result;
    }
    if((!strcmp(name,"==")||!strcmp(name,"\\=="))&&arity==2) {
        int result=identical(a,b);
        return !strcmp(name,"==")?result:!result;
    }
    if(arity==1) {
        if(!strcmp(name,"var"))return a->kind==TERM_VARIABLE;
        if(!strcmp(name,"nonvar"))return a->kind!=TERM_VARIABLE;
        if(!strcmp(name,"atom"))return a->kind==TERM_ATOM;
        if(!strcmp(name,"number")||!strcmp(name,"integer"))return a->kind==TERM_INTEGER;
        if(!strcmp(name,"atomic"))return a->kind==TERM_ATOM||a->kind==TERM_INTEGER;
        if(!strcmp(name,"compound"))return a->kind==TERM_COMPOUND;
        if(!strcmp(name,"callable"))return a->kind==TERM_ATOM||a->kind==TERM_COMPOUND;
        if(!strcmp(name,"is_list")) {
            Term **items,*tail;
            list_items(a,&items,&tail);
            return empty_list(tail);
        }
        if(!strcmp(name,"write")||!strcmp(name,"writeq")) {
            Names names= {
                0
            };
            add_text(s->output,write_term(a,!strcmp(name,"writeq"),1200,0,&names));
            return 1;
        }
    }
    if(!strcmp(name,"nl")&&!arity) {
        add_text(s->output,"\n");
        return 1;
    }
    if(!strcmp(name,"is")&&arity==2) {
        long long value=arithmetic(s,b);
        return !s->error&&u(s,a,integer(value));
    }
    if(arity==2&&(!strcmp(name,"=:=")||!strcmp(name,"=\\=")||!strcmp(name,"<")||!strcmp(name,">")||!strcmp(name,"=<")||!strcmp(name,">="))) {
        long long x=arithmetic(s,a);
        if(s->error)return 0;
        long long y=arithmetic(s,b);
        if(s->error)return 0;
        return !strcmp(name,"=:=")?x==y:!strcmp(name,"=\\=")?x!=y:!strcmp(name,"<")?x<y:!strcmp(name,">")?x>y:!strcmp(name,"=<")?x<=y:x>=y;
    }
    if(!strcmp(name,"functor")&&arity==3) {
        if(a->kind!=TERM_VARIABLE) {
            if(a->kind==TERM_COMPOUND)return u(s,b,atom(a->name))&&u(s,c,integer(a->arity));
            return u(s,b,a)&&u(s,c,integer(0));
        }
        if(b->kind==TERM_VARIABLE||c->kind==TERM_VARIABLE)s->error=atom("instantiation_error");
        else if(b->kind==TERM_COMPOUND)s->error=type_error("atomic",b);
        else if(c->kind!=TERM_INTEGER)s->error=type_error("integer",c);
        else if(c->integer<0)s->error=domain_error("not_less_than_zero",c);
        else if(c->integer>255)s->error=unary("representation_error",atom("max_arity"));
        if(s->error)return 0;
        if(!c->integer)return u(s,a,b);
        if(b->kind==TERM_INTEGER) {
            s->error=type_error("atom",b);
            return 0;
        }
        int n=(int)c->integer;
        Term **args=make((size_t)n*sizeof *args);
        for(int i=0;i<n;++i)args[i]=fresh();
        return u(s,a,compound(b->name,n,args));
    }
    if(!strcmp(name,"arg")&&arity==3) {
        if(a->kind==TERM_VARIABLE||b->kind==TERM_VARIABLE)s->error=atom("instantiation_error");
        else if(a->kind!=TERM_INTEGER)s->error=type_error("integer",a);
        else if(b->kind!=TERM_COMPOUND)s->error=type_error("compound",b);
        if(s->error)return 0;
        return a->integer>=1&&a->integer<=b->arity&&u(s,b->args[a->integer-1],c);
    }
    if(!strcmp(name,"=..")&&arity==2) {
        if(a->kind!=TERM_VARIABLE) {
            if(a->kind!=TERM_COMPOUND) {
                Term *items[]= {
                    a
                };
                return u(s,list(items,1,NULL),b);
            }
            Term **items=make((size_t)(a->arity+1)*sizeof *items);
            items[0]=atom(a->name);
            memcpy(items+1,a->args,(size_t)a->arity*sizeof *items);
            return u(s,list(items,a->arity+1,NULL),b);
        }
        Term **items;
        int count;
        if(!proper_check(s,b,&items,&count))return 0;
        if(!count) {
            s->error=domain_error("non_empty_list",atom("[]"));
            return 0;
        }
        Term *head=dereference(items[0]);
        if(head->kind==TERM_VARIABLE) {
            s->error=atom("instantiation_error");
            return 0;
        }
        if(count==1) {
            if(head->kind==TERM_COMPOUND) {
                s->error=type_error("atomic",head);
                return 0;
            }
            return u(s,a,head);
        }
        if(head->kind!=TERM_ATOM)s->error=type_error("atom",head);
        else if(count-1>255)s->error=unary("representation_error",atom("max_arity"));
        return !s->error&&u(s,a,compound(head->name,count-1,items+1));
    }
    if(!strcmp(name,"copy_term")&&arity==2)return u(s,copy_term(a),b);
    if(!strcmp(name,"atom_length")&&arity==2) {
        if(!atom_check(s,a))return 0;
        if(b->kind!=TERM_VARIABLE&&b->kind!=TERM_INTEGER) {
            s->error=type_error("integer",b);
            return 0;
        }
        return u(s,integer((long long)strlen(a->name)),b);
    }
    if(!strcmp(name,"atom_chars")&&arity==2) {
        if(a->kind!=TERM_VARIABLE) {
            if(!atom_check(s,a))return 0;
            int count=(int)strlen(a->name);
            Term **items=make((size_t)count*sizeof *items);
            for(int i=0;i<count;++i) {
                char text[]= {
                    a->name[i],0
                };
                items[i]=atom(text);
            }
            return u(s,b,list(items,count,NULL));
        }
        Term **items;
        int count;
        if(!proper_check(s,b,&items,&count))return 0;
        Buffer text= {
            0
        };
        for(int i=0;i<count;++i) {
            Term *item=dereference(items[i]);
            if(item->kind==TERM_VARIABLE) {
                s->error=atom("instantiation_error");
                return 0;
            }
            if(item->kind!=TERM_ATOM||strlen(item->name)!=1) {
                s->error=type_error("character",item);
                return 0;
            }
            add_text(&text,item->name);
        }
        return u(s,a,atom(text.text?text.text:""));
    }
    return 0;
}
