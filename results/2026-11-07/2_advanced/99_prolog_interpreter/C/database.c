#include "prolog.h"
Predicate *predicate(Database *d,const char *name,int arity,int create) {
    for(int i=0;i<d->count;++i)if(d->predicates[i]->arity==arity&&!strcmp(d->predicates[i]->name,name))return d->predicates[i];
    if(!create)return NULL;
    Predicate *p=make(sizeof *p);
    p->name=copy_string(name);
    p->arity=arity;
    Predicate **items=make((size_t)(d->count+1)*sizeof *items);
    if(d->count)memcpy(items,d->predicates,(size_t)d->count*sizeof *items);
    d->predicates=items;
    items[d->count++]=p;
    return p;
}
void add_clause(Predicate *p,Clause *c) {
    Clause **items=make((size_t)(p->count+1)*sizeof *items);
    if(p->count)memcpy(items,p->clauses,(size_t)p->count*sizeof *items);
    p->clauses=items;
    items[p->count++]=c;
}
static int same_kind(Term *a,Term *b) {
    a=dereference(a);
    b=dereference(b);
    if(a->kind==TERM_VARIABLE||b->kind==TERM_VARIABLE)return 1;
    if(a->kind!=b->kind)return 0;
    if(a->kind==TERM_INTEGER)return a->integer==b->integer;
    return !strcmp(a->name,b->name)&&(a->kind==TERM_ATOM||a->arity==b->arity);
}
Clause **candidate_clauses(Predicate *p,Term *goal,int *count) {
    Clause **result=make((size_t)p->count*sizeof *result);
    *count=0;
    for(int i=0;i<p->count;++i)if(!p->arity||same_kind(goal->args[0],p->clauses[i]->head->args[0]))result[(*count)++]=p->clauses[i];
    return result;
}
int control(const char *name,int arity) {
    return ((!strcmp(name,",")||!strcmp(name,";")||!strcmp(name,"->"))&&arity==2)||(!strcmp(name,"!")&&!arity)||(!strcmp(name,"\\+")&&arity==1)||(!strcmp(name,"call")&&arity>=1&&arity<=8)||(!strcmp(name,"catch")&&arity==3);
}
int builtin_predicate(const char *name,int arity) {
    static const struct {
        const char *name;
        int arity;
    }
    builtins[]= {
        {
            "true",0
        }, {
            "fail",0
        }, {
            "false",0
        }, {
            "=",2
        }, {
            "\\=",2
        }, {
            "==",2
        }, {
            "\\==",2
        }, {
            "var",1
        }, {
            "nonvar",1
        }, {
            "atom",1
        }, {
            "number",1
        }, {
            "integer",1
        }, {
            "atomic",1
        }, {
            "compound",1
        }, {
            "callable",1
        }, {
            "is_list",1
        }, {
            "is",2
        }, {
            "=:=",2
        }, {
            "=\\=",2
        }, {
            "<",2
        }, {
            ">",2
        }, {
            "=<",2
        }, {
            ">=",2
        }, {
            "functor",3
        }, {
            "arg",3
        }, {
            "=..",2
        }, {
            "copy_term",2
        }, {
            "atom_length",2
        }, {
            "atom_chars",2
        }, {
            "write",1
        }, {
            "writeq",1
        }, {
            "nl",0
        }, {
            "findall",3
        }, {
            "throw",1
        }, {
            "between",3
        }, {
            "length",2
        }
    };
    for(size_t i=0;i<sizeof builtins/sizeof *builtins;++i)if(arity==builtins[i].arity&&!strcmp(name,builtins[i].name))return 1;
    return 0;
}
Term *convert_goal(Term *goal,int *valid) {
    goal=dereference(goal);
    if(goal->kind==TERM_VARIABLE)return unary("call",goal);
    if(goal->kind==TERM_INTEGER) {
        *valid=0;
        return goal;
    }
    if((!strcmp(goal->name,",")||!strcmp(goal->name,";")||!strcmp(goal->name,"->"))&&goal->arity==2) {
        Term *a=convert_goal(goal->args[0],valid),*b=convert_goal(goal->args[1],valid);
        return binary(goal->name,a,b);
    }
    return goal;
}
