#include "prolog.h"
static VariableName *named(Names *names,Term *variable,int create) {
    for(int i=0;i<names->count;++i)if(names->items[i].variable==variable)return &names->items[i];
    if(!create)return NULL;
    VariableName *items=make((size_t)(names->count+1)*sizeof *items);
    if(names->count)memcpy(items,names->items,(size_t)names->count*sizeof *items);
    names->items=items;
    VariableName *entry=&items[names->count++];
    entry->variable=variable;
    return entry;
}
static char *atom_name(const char *name,int quoted) {
    if(!quoted)return copy_string(name);
    int plain=!strcmp(name,"[]")||!strcmp(name,"!")||!strcmp(name,";");
    if(*name>='a'&&*name<='z') {
        plain=1;
        for(const char *p=name;*p;++p)if(!isalnum((unsigned char)*p)&&*p!='_')plain=0;
    }
    int symbols=*name&&strcmp(name,".");
    for(const char *p=name;*p;++p)if(!symbol_character(*p))symbols=0;
    if(plain||symbols)return copy_string(name);
    Buffer b= {
        0
    };
    add_text(&b,"'");
    for(const char *p=name;*p;++p) {
        if(*p=='\\')add_text(&b,"\\\\");
        else if(*p=='\'')add_text(&b,"\\'");
        else if(*p=='\n')add_text(&b,"\\n");
        else if(*p=='\t')add_text(&b,"\\t");
        else add_bytes(&b,p,1);
    }
    add_text(&b,"'");
    return b.text;
}
char *write_term(Term *term,int quoted,int limit,int operand,Names *names) {
    Term *t=dereference(term);
    Buffer b= {
        0
    };
    if(t->kind==TERM_VARIABLE) {
        VariableName *entry=named(names,t,1);
        if(!entry->name) {
            if(!names->next)names->next=1;
            char text[40];
            sprintf(text,"_G%d",names->next++);
            entry->name=copy_string(text);
        }
        return entry->name;
    }
    if(t->kind==TERM_INTEGER) {
        add_format(&b,"%lld",t->integer);
        return b.text;
    }
    if(t->kind==TERM_ATOM) {
        char *name=atom_name(t->name,quoted);
        if(operand&&(infix_operator(t->name)||prefix_priority(t->name))) {
            add_format(&b,"(%s)",name);
            return b.text;
        }
        return name;
    }
    if(is_term(t,".",2)) {
        add_text(&b,"[");
        int first=1;
        Term *tail=t;
        while(is_term(tail,".",2)) {
            tail=dereference(tail);
            if(!first)add_text(&b,",");
            add_text(&b,write_term(tail->args[0],quoted,999,0,names));
            first=0;
            tail=dereference(tail->args[1]);
        }
        if(!empty_list(tail)) {
            add_text(&b,"|");
            add_text(&b,write_term(tail,quoted,999,0,names));
        }
        add_text(&b,"]");
        return b.text;
    }
    const Operator *op=t->arity==2?infix_operator(t->name):NULL;
    int prefix=t->arity==1?prefix_priority(t->name):0;
    if(op) {
        char *left=write_term(t->args[0],quoted,op->left,1,names),*right=write_term(t->args[1],quoted,op->right,1,names);
        if(op->priority>limit)add_text(&b,"(");
        add_text(&b,left);
        if(!strcmp(t->name,","))add_text(&b,",");
        else if(isalpha((unsigned char)*t->name))add_format(&b," %s ",t->name);
        else {
            size_t n=strlen(left);
            if(n&&symbol_character(left[n-1]))add_text(&b," ");
            add_text(&b,t->name);
            if(*right&&symbol_character(*right))add_text(&b," ");
        }
        add_text(&b,right);
        if(op->priority>limit)add_text(&b,")");
        return b.text;
    }
    if(prefix) {
        char *arg=write_term(t->args[0],quoted,prefix,1,names);
        if(prefix>limit)add_text(&b,"(");
        add_text(&b,t->name);
        if(*arg&&(symbol_character(*arg)||isdigit((unsigned char)*arg)||*arg=='('))add_text(&b," ");
        add_text(&b,arg);
        if(prefix>limit)add_text(&b,")");
        return b.text;
    }
    add_text(&b,atom_name(t->name,quoted));
    add_text(&b,"(");
    for(int i=0;i<t->arity;++i) {
        if(i)add_text(&b,",");
        add_text(&b,write_term(t->args[i],quoted,999,0,names));
    }
    add_text(&b,")");
    return b.text;
}
char *indicator_string(const char *name,int arity) {
    Names names= {
        0
    };
    return write_term(indicator(name,arity),1,1200,0,&names);
}
static const char *files[]= {
    "prelude.pl","program.pl"
};
typedef struct {
    Database database;
    int counts[2][3];
    Predicate *last[2];
    FILE *reports;
    char **undefined;
    int nu;
}
Consultant;
static void warning(Consultant *c,int file,int line,const char *text) {
    fprintf(c->reports,"%s:%d: warning: %s\n",files[file],line,text);
    ++c->counts[file][2];
}
static void consult_clause(Consultant *c,Term *term,Reader *reader,int file,int line) {
    Term *head=term,*body=NULL;
    if(is_term(term,":-",2)) {
        head=term->args[0];
        body=term->args[1];
    }
    Term *error=NULL;
    if(head->kind==TERM_VARIABLE)error=atom("instantiation_error");
    else if(head->kind==TERM_INTEGER)error=type_error("callable",head);
    else if(control(head->name,head->arity)||builtin_predicate(head->name,head->arity))error=ternary("permission_error",atom("modify"),atom("static_procedure"),indicator(head->name,head->arity));
    else if(body) {
        int valid=1;
        Term *converted=convert_goal(body,&valid);
        if(!valid)error=type_error("callable",body);
        else body=converted;
    }
    if(error) {
        Names names= {
            0
        };
        fprintf(c->reports,"%s:%d: error: %s\n",files[file],line,write_term(error,1,1200,0,&names));
        ++c->counts[file][1];
        return;
    }
    Predicate *p=predicate(&c->database,head->name,head->arity,1);
    char *id=indicator_string(p->name,p->arity);
    if(file==1&&p->count&&p->clauses[0]->file==0) {
        Buffer b= {
            0
        };
        add_format(&b,"redefining prelude procedure %s",id);
        warning(c,file,line,b.text);
        p->count=0;
    }
    int samefile=p->count&&p->clauses[p->count-1]->file==file;
    if(samefile&&c->last[file]!=p&&!p->warned[file]) {
        Buffer b= {
            0
        };
        add_format(&b,"clauses of %s are not together",id);
        warning(c,file,line,b.text);
        p->warned[file]=1;
    }
    Clause *clause=make(sizeof *clause);
    *clause=(Clause) {
        head,body,file,line
    };
    add_clause(p,clause);
    c->last[file]=p;
    ++c->counts[file][0];
    for(int kind=0;kind<2;++kind) {
        Buffer vars= {
            0
        };
        int n=0;
        for(int i=0;i<reader->nv;++i) {
            ReadVariable *v=&reader->variables[i];
            int match=kind?strlen(v->name)>=2&&*v->name=='_'&&v->occurrences>=2:*v->name!='_'&&v->occurrences==1;
            if(match) {
                if(n++)add_text(&vars,", ");
                add_text(&vars,v->name);
            }
        }
        if(n) {
            Buffer message= {
                0
            };
            add_format(&message,"%s%s",kind?"variables starting with _ occur more than once: ":"singleton variables: ",vars.text);
            warning(c,file,line,message.text);
        }
    }
}
static void consult_file(Consultant *c,const char *source,int file) {
    Reader reader=tokenize(source,1);
    while(reader.at<reader.count&&reader.tokens[reader.at].kind!=TOKEN_EOF) {
        int line=reader.tokens[reader.at].line;
        Term *term=read_clause(&reader,0);
        if(term)consult_clause(c,term,&reader,file,line);
        else {
            Token t=reader.tokens[reader.error_at];
            fprintf(c->reports,"%s:%d:%d: syntax error: %s\n",files[file],t.line,t.column,reader.error);
            ++c->counts[file][1];
            if(t.kind!=TOKEN_EOF) {
                const char *start=source;
                for(int l=1;l<t.line;++l) {
                    const char *next=strchr(start,'\n');
                    if(!next)break;
                    start=next+1;
                }
                const char *end=strchr(start,'\n');
                if(!end)end=start+strlen(start);
                fputs("    ",c->reports);
                fwrite(start,1,(size_t)(end-start),c->reports);
                fprintf(c->reports,"\n%*s^\n",t.column+3,"");
            }
            reader.at=reader.error_at;
            while(reader.at<reader.count&&reader.tokens[reader.at].kind!=TOKEN_END&&reader.tokens[reader.at].kind!=TOKEN_EOF)++reader.at;
            if(reader.tokens[reader.at].kind==TOKEN_END)++reader.at;
        }
    }
}
static void undefined_goals(Consultant *c,Term *goal,Predicate *from,Clause *clause) {
    goal=dereference(goal);
    if(goal->kind==TERM_VARIABLE||goal->kind==TERM_INTEGER)return;
    const char *name=goal->name;
    int arity=goal->arity;
    if(arity==2&&(!strcmp(name,",")||!strcmp(name,";")||!strcmp(name,"->"))) {
        undefined_goals(c,goal->args[0],from,clause);
        undefined_goals(c,goal->args[1],from,clause);
        return;
    }
    if(arity==1&&(!strcmp(name,"\\+")||!strcmp(name,"call"))) {
        undefined_goals(c,goal->args[0],from,clause);
        return;
    }
    if(arity==3&&!strcmp(name,"findall")) {
        undefined_goals(c,goal->args[1],from,clause);
        return;
    }
    if(arity==3&&!strcmp(name,"catch")) {
        undefined_goals(c,goal->args[0],from,clause);
        undefined_goals(c,goal->args[2],from,clause);
        return;
    }
    if(control(name,arity)||builtin_predicate(name,arity)||predicate(&c->database,name,arity,0))return;
    char *id=indicator_string(name,arity);
    for(int i=0;i<c->nu;++i)if(!strcmp(c->undefined[i],id))return;
    char **items=make((size_t)(c->nu+1)*sizeof *items);
    if(c->nu)memcpy(items,c->undefined,(size_t)c->nu*sizeof *items);
    c->undefined=items;
    items[c->nu++]=id;
    Buffer text= {
        0
    };
    add_format(&text,"undefined procedure %s called from %s",id,indicator_string(from->name,from->arity));
    warning(c,clause->file,clause->line,text.text);
}
static void count_variables(Term *term,Names *names) {
    term=dereference(term);
    if(term->kind==TERM_VARIABLE) {
        ++named(names,term,1)->count;
        return;
    }
    if(term->kind==TERM_COMPOUND)for(int i=0;i<term->arity;++i)count_variables(term->args[i],names);
}
static void listing(FILE *f,Database *database) {
    for(int p=0;p<database->count;++p) {
        if(p)fputc('\n',f);
        Predicate *pred=database->predicates[p];
        for(int c=0;c<pred->count;++c) {
            Clause *clause=pred->clauses[c];
            Names names= {
                0
            };
            count_variables(clause->head,&names);
            if(clause->body)count_variables(clause->body,&names);
            int next=0;
            for(int v=0;v<names.count;++v) {
                if(names.items[v].count==1)names.items[v].name="_";
                else {
                    char name[40];
                    if(next<26)sprintf(name,"%c",'A'+next);
                    else sprintf(name,"%c%d",'A'+next%26,next/26);
                    names.items[v].name=copy_string(name);
                    ++next;
                }
            }
            fprintf(f,"%s",write_term(clause->head,1,1200,0,&names));
            if(!clause->body) {
                fputs(".\n",f);
                continue;
            }
            fputs(" :-\n",f);
            Term *body=clause->body;
            while(is_term(body,",",2)) {
                fprintf(f,"    %s,\n",write_term(body->args[0],1,999,0,&names));
                body=body->args[1];
            }
            fprintf(f,"    %s.\n",write_term(body,1,999,0,&names));
        }
    }
}
static char *answer(Reader *reader) {
    Names names= {
        0
    };
    for(int i=0;i<reader->nv;++i)if(*reader->variables[i].name!='_') {
        Term *value=dereference(reader->variables[i].term);
        if(value->kind==TERM_VARIABLE&&!named(&names,value,0))named(&names,value,1)->name=reader->variables[i].name;
    }
    Buffer out= {
        0
    };
    int count=0;
    for(int i=0;i<reader->nv;++i) {
        ReadVariable v=reader->variables[i];
        if(*v.name=='_')continue;
        Term *value=dereference(v.term);
        char *item=NULL;
        if(value->kind==TERM_VARIABLE) {
            const char *last=NULL;
            for(int j=0;j<i;++j)if(*reader->variables[j].name!='_'&&dereference(reader->variables[j].term)==value)last=reader->variables[j].name;
            if(last) {
                Buffer b= {
                    0
                };
                add_format(&b,"%s = %s",last,v.name);
                item=b.text;
            }
        }
        else {
            Buffer b= {
                0
            };
            add_format(&b,"%s = %s",v.name,write_term(value,1,699,1,&names));
            item=b.text;
        }
        if(item) {
            if(count++)add_text(&out,", ");
            add_text(&out,item);
        }
    }
    return out.text?out.text:copy_string("true");
}
typedef struct {
    char *name,*display;
    int arity;
    long long calls,tries;
}
Profile;
static Profile **profiles=NULL;
static int profile_count=0;
static char *heap_string(const char *s) {
    char *p=malloc(strlen(s)+1);
    if(!p)exit(EXIT_FAILURE);
    strcpy(p,s);
    return p;
}
static Profile *profile(const char *name,int arity) {
    for(int i=0;i<profile_count;++i)if(profiles[i]->arity==arity&&!strcmp(profiles[i]->name,name))return profiles[i];
    Profile *p=calloc(1,sizeof *p);
    if(!p)exit(EXIT_FAILURE);
    p->name=heap_string(name);
    p->display=heap_string(indicator_string(name,arity));
    p->arity=arity;
    Profile **new=realloc(profiles,(size_t)(profile_count+1)*sizeof *new);
    if(!new)exit(EXIT_FAILURE);
    profiles=new;
    profiles[profile_count++]=p;
    return p;
}
enum {
    CP_ALT,CP_CLAUSES,CP_BETWEEN,CP_LENGTH,CP_CATCH,CP_FINDALL
};
enum {
    MARK_NONE,MARK_ITE,MARK_NAF,MARK_EXIT,MARK_COLLECT
};
typedef struct Choice Choice;
typedef struct Goal Goal;
struct Goal {
    Term *term;
    int marker,barrier,height;
    Choice *context,*choice;
    Goal *next;
};
struct Choice {
    int kind,trail,next,count,barrier;
    Goal *resume;
    Choice *context;
    Term *goal,*a,*b,*c;
    Clause **clauses;
    long long value,high,base;
    Term **results;
    int nresults,capacity;
};
typedef struct {
    Database *database;
    Goal *goals;
    Choice **choices;
    int height,capacity;
    Trail trail;
    Buffer output;
    long long solutions,inferences,created,backtracks;
    int ended,limited,exhausted;
    Term *uncaught;
}
Machine;
static Goal *push_goal(Term *term,int barrier,Choice *context,Goal *next) {
    Goal *g=make(sizeof *g);
    g->term=term;
    g->barrier=barrier;
    g->context=context;
    g->next=next;
    return g;
}
static Goal *marker(int kind,int height,Choice *choice,int barrier,Choice *context,Goal *next) {
    Goal *g=push_goal(NULL,barrier,context,next);
    g->marker=kind;
    g->height=height;
    g->choice=choice;
    return g;
}
static Choice *choice(Machine *m,int kind,Goal *resume) {
    Choice *c=make(sizeof *c);
    c->kind=kind;
    c->trail=m->trail.count;
    c->resume=resume;
    if(m->height==m->capacity) {
        int capacity=m->capacity?m->capacity*2:64;
        Choice **p=realloc(m->choices,(size_t)capacity*sizeof *p);
        if(!p)exit(EXIT_FAILURE);
        m->choices=p;
        m->capacity=capacity;
    }
    m->choices[m->height++]=c;
    ++m->created;
    return c;
}
static int inference(Machine *m,const char *name,int arity) {
    if(m->inferences==20000) {
        m->limited=m->ended=1;
        return 0;
    }
    ++m->inferences;
    ++profile(name,arity)->calls;
    return 1;
}
static Term *fault(Term *error,const char *name,int arity) {
    return binary("error",error,indicator(name,arity));
}
static int try_clause(Machine *m,Term *goal,Clause *clause,int barrier,Choice *context,Goal *continuation) {
    ++profile(goal->name,goal->arity)->tries;
    Term *body;
    Term *head=copy_pair(clause->head,clause->body,&body);
    if(!unify(&m->trail,head,goal))return 0;
    m->goals=body?push_goal(body,barrier,context,continuation):continuation;
    return 1;
}
static Term *fresh_list(long long n) {
    Term *tail=atom("[]");
    while(n-->0)tail=binary(".",fresh(),tail);
    return tail;
}
static int backtrack(Machine *m) {
    for(;;) {
        ++m->backtracks;
        for(;;) {
            if(!m->height) {
                m->ended=m->exhausted=1;
                return 0;
            }
            Choice *c=m->choices[m->height-1];
            undo(&m->trail,c->trail);
            if(c->kind==CP_ALT) {
                --m->height;
                m->goals=c->resume;
                return 1;
            }
            if(c->kind==CP_CATCH) {
                --m->height;
                continue;
            }
            if(c->kind==CP_CLAUSES) {
                Clause *next=c->clauses[c->next++];
                if(c->next==c->count)--m->height;
                if(try_clause(m,c->goal,next,c->barrier,c->context,c->resume))return 1;
                break;
            }
            if(c->kind==CP_FINDALL) {
                --m->height;
                if(unify(&m->trail,list(c->results,c->nresults,NULL),c->a)) {
                    m->goals=c->resume;
                    return 1;
                }
                break;
            }
            const char *name=c->kind==CP_BETWEEN?"between":"length";
            int arity=c->kind==CP_BETWEEN?3:2;
            if(!inference(m,name,arity))return 0;
            int success;
            if(c->kind==CP_BETWEEN) {
                long long value=c->value;
                if(value==c->high)--m->height;
                else ++c->value;
                success=unify(&m->trail,c->a,integer(value));
            }
            else {
                long long length=c->value++;
                success=unify(&m->trail,c->a,fresh_list(length-c->base))&&unify(&m->trail,c->b,integer(length));
            }
            if(success) {
                m->goals=c->resume;
                return 1;
            }
            break;
        }
    }
}
static void exception(Machine *m,Term *raised,Choice *context) {
    Term *ball=copy_term(raised);
    Choice *c=context;
    while(c) {
        int index=-1;
        for(int i=0;i<m->height;++i)if(m->choices[i]==c) {
            index=i;
            break;
        }
        if(index<0) {
            m->uncaught=ball;
            m->ended=1;
            return;
        }
        m->height=index;
        undo(&m->trail,c->trail);
        int mark=m->trail.count;
        if(unify(&m->trail,copy_term(ball),c->a)) {
            m->goals=push_goal(unary("call",c->b),m->height,c->context,c->resume);
            return;
        }
        undo(&m->trail,mark);
        c=c->context;
    }
    m->uncaught=ball;
    m->ended=1;
}
static int execute_goal(Machine *m,Goal *entry) {
    Goal *continuation=m->goals;
    int barrier=entry->barrier;
    Choice *context=entry->context;
    if(entry->marker) {
        if(entry->marker==MARK_ITE) {
            m->height=entry->height;
            return 1;
        }
        if(entry->marker==MARK_NAF) {
            m->height=entry->height;
            return 0;
        }
        if(entry->marker==MARK_EXIT) {
            if(m->height&&m->choices[m->height-1]==entry->choice)--m->height;
            return 1;
        }
        Choice *c=entry->choice;
        if(c->nresults==c->capacity) {
            int capacity=c->capacity?2*c->capacity:8;
            Term **items=make((size_t)capacity*sizeof *items);
            if(c->nresults)memcpy(items,c->results,(size_t)c->nresults*sizeof *items);
            c->results=items;
            c->capacity=capacity;
        }
        c->results[c->nresults++]=copy_term(c->b);
        return 0;
    }
    Term *g=dereference(entry->term);
    const char *name=g->name;
    int arity=g->arity;
    Term *a=arity?g->args[0]:NULL,*b=arity>1?g->args[1]:NULL,*c=arity>2?g->args[2]:NULL;
    if(is_term(g,",",2)) {
        m->goals=push_goal(a,barrier,context,push_goal(b,barrier,context,continuation));
        return 1;
    }
    if(is_term(g,"!",0)) {
        m->height=barrier;
        return 1;
    }
    if(is_term(g,";",2)) {
        int h=m->height;
        choice(m,CP_ALT,push_goal(b,barrier,context,continuation));
        if(is_term(a,"->",2)) {
            a=dereference(a);
            m->goals=push_goal(a->args[0],h+1,context,marker(MARK_ITE,h,NULL,barrier,context,push_goal(a->args[1],barrier,context,continuation)));
        }
        else m->goals=push_goal(a,barrier,context,continuation);
        return 1;
    }
    if(is_term(g,"->",2)) {
        int h=m->height;
        m->goals=push_goal(a,h,context,marker(MARK_ITE,h,NULL,barrier,context,push_goal(b,barrier,context,continuation)));
        return 1;
    }
    if(is_term(g,"\\+",1)) {
        int h=m->height;
        choice(m,CP_ALT,continuation);
        m->goals=push_goal(unary("call",a),barrier,context,marker(MARK_NAF,h,NULL,barrier,context,continuation));
        return 1;
    }
    if(!strcmp(name,"call")&&arity>=1&&arity<=8) {
        Term *target=dereference(a);
        Term *error=NULL;
        if(target->kind==TERM_VARIABLE)error=atom("instantiation_error");
        else if(target->kind==TERM_INTEGER)error=type_error("callable",target);
        if(error) {
            exception(m,fault(error,name,arity),context);
            return 1;
        }
        if(arity>1) {
            int count=target->arity+arity-1;
            Term **args=make((size_t)count*sizeof *args);
            if(target->arity)memcpy(args,target->args,(size_t)target->arity*sizeof *args);
            memcpy(args+target->arity,g->args+1,(size_t)(arity-1)*sizeof *args);
            target=compound(target->name,count,args);
        }
        int valid=1;
        Term *converted=convert_goal(target,&valid);
        if(!valid) {
            exception(m,fault(type_error("callable",target),name,arity),context);
            return 1;
        }
        m->goals=push_goal(converted,m->height,context,continuation);
        return 1;
    }
    if(is_term(g,"catch",3)) {
        Choice *f=choice(m,CP_CATCH,continuation);
        f->a=b;
        f->b=c;
        f->context=context;
        m->goals=push_goal(unary("call",a),barrier,f,marker(MARK_EXIT,0,f,barrier,context,continuation));
        return 1;
    }
    if(!inference(m,name,arity))return 1;
    if(is_term(g,"findall",3)) {
        Choice *f=choice(m,CP_FINDALL,continuation);
        f->a=c;
        f->b=a;
        m->goals=push_goal(unary("call",b),barrier,context,marker(MARK_COLLECT,0,f,barrier,context,NULL));
        return 1;
    }
    if(is_term(g,"throw",1)) {
        Term *ball=dereference(a);
        exception(m,ball->kind==TERM_VARIABLE?fault(atom("instantiation_error"),"throw",1):ball,context);
        return 1;
    }
    BuiltinState state= {
        .trail=&m->trail,.output=&m->output
    };
    int success=0;
    if(is_term(g,"between",3)) {
        Term *low=dereference(a),*high=dereference(b),*value=dereference(c);
        if(integer_check(&state,low)&&integer_check(&state,high)) {
            if(value->kind!=TERM_VARIABLE&&value->kind!=TERM_INTEGER)state.error=type_error("integer",value);
            else if(value->kind==TERM_INTEGER)success=low->integer<=value->integer&&value->integer<=high->integer;
            else if(low->integer<=high->integer) {
                if(low->integer<high->integer) {
                    Choice *f=choice(m,CP_BETWEEN,continuation);
                    f->a=c;
                    f->value=low->integer+1;
                    f->high=high->integer;
                }
                success=unify(&m->trail,c,integer(low->integer));
            }
        }
    }
    else if(is_term(g,"length",2)) {
        Term *length=dereference(b);
        if(length->kind!=TERM_VARIABLE&&length->kind!=TERM_INTEGER)state.error=type_error("integer",length);
        else if(length->kind==TERM_INTEGER&&length->integer<0)state.error=domain_error("not_less_than_zero",length);
        else {
            Term **items,*tail;
            int n=list_items(a,&items,&tail);
            if(empty_list(tail))success=unify(&m->trail,b,integer(n));
            else if(tail->kind!=TERM_VARIABLE)state.error=type_error("list",a);
            else if(length->kind==TERM_INTEGER) {
                if(length->integer>=n)success=unify(&m->trail,tail,fresh_list(length->integer-n));
            }
            else {
                Choice *f=choice(m,CP_LENGTH,continuation);
                f->a=tail;
                f->b=b;
                f->base=n;
                f->value=n+1;
                success=unify(&m->trail,tail,atom("[]"))&&unify(&m->trail,b,integer(n));
            }
        }
    }
    else if(builtin_predicate(name,arity))success=deterministic(&state,g);
    else {
        Predicate *p=predicate(m->database,name,arity,0);
        if(!p) {
            Term *id=indicator(name,arity);
            exception(m,fault(binary("existence_error",atom("procedure"),id),name,arity),context);
            return 1;
        }
        int count;
        Clause **candidates=candidate_clauses(p,g,&count);
        if(!count)return 0;
        int h=m->height;
        if(count>=2) {
            Choice *f=choice(m,CP_CLAUSES,continuation);
            f->goal=g;
            f->clauses=candidates;
            f->count=count;
            f->next=1;
            f->barrier=h;
            f->context=context;
        }
        return try_clause(m,g,candidates[0],h,context,continuation);
    }
    if(state.error) {
        exception(m,fault(state.error,name,arity),context);
        return 1;
    }
    return success;
}
static void run_query(Machine *m,Reader *reader,Term *query,int limit,FILE *answers) {
    m->goals=push_goal(unary("call",query),0,NULL,NULL);
    while(!m->ended) {
        if(!m->goals) {
            ++m->solutions;
            char *text=answer(reader);
            if(m->solutions==limit||!m->height) {
                fprintf(answers,"%s.\n",text);
                m->ended=1;
                break;
            }
            fprintf(answers,"%s ;\n",text);
            backtrack(m);
        }
        else {
            Goal *entry=m->goals;
            m->goals=entry->next;
            if(!execute_goal(m,entry)&&!m->ended)backtrack(m);
        }
    }
    if(m->limited)fputs("inference limit exceeded\n",answers);
    else if(m->uncaught) {
        Names names= {
            0
        };
        fprintf(answers,"uncaught exception: %s\n",write_term(m->uncaught,1,1200,0,&names));
    }
    else if(m->exhausted)fputs("false.\n",answers);
}
static int profile_order(const void *a,const void *b) {
    Profile *x=*(Profile*const*)a,*y=*(Profile*const*)b;
    if(x->calls!=y->calls)return x->calls>y->calls?-1:1;
    return strcmp(x->display,y->display);
}
int main(void) {
    FILE *consult=fopen("output/consult.txt","w"),*listing_file=fopen("output/listing.txt","w"),*answers=fopen("output/answers.txt","w"),*writes=fopen("output/write_output.txt","w"),*stats=fopen("output/stats.txt","w");
    if(!consult||!listing_file||!answers||!writes||!stats)return EXIT_FAILURE;
    Consultant c= {
        .reports=consult
    };
    consult_file(&c,file_text("input/prelude.pl"),0);
    consult_file(&c,file_text("input/program.pl"),1);
    int clauses=0;
    for(int p=0;p<c.database.count;++p) {
        Predicate *pred=c.database.predicates[p];
        clauses+=pred->count;
        for(int j=0;j<pred->count;++j)if(pred->clauses[j]->body)undefined_goals(&c,pred->clauses[j]->body,pred,pred->clauses[j]);
    }
    for(int f=0;f<2;++f)fprintf(consult,"%s: clauses=%d errors=%d warnings=%d\n",files[f],c.counts[f][0],c.counts[f][1],c.counts[f][2]);
    fprintf(consult,"database: predicates=%d clauses=%d\n",c.database.count,clauses);
    listing(listing_file,&c.database);
    FILE *queries=fopen("input/queries.txt","r");
    if(!queries)return EXIT_FAILURE;
    long long totals[4]= {
        0
    };
    int number=0;
    for(;;) {
        Memory *mark=memory;
        char *line=line_read(queries);
        if(!line) {
            release_to(mark);
            break;
        }
        ++number;
        fprintf(answers,"%s\n",line);
        fprintf(writes,"== query %d ==\n",number);
        char *body=strstr(line,"?- ")+3;
        int limit=isdigit((unsigned char)*line)?atoi(line):INT_MAX;
        Reader reader=tokenize(body,(int)(body-line)+1);
        Term *query=read_clause(&reader,1);
        if(!query) {
            Token t=reader.tokens[reader.error_at];
            fprintf(answers,"syntax error at column %d: %s\n",t.column,reader.error);
            fprintf(stats,"query %d: syntax error\n",number);
        }
        else {
            Machine machine= {
                .database=&c.database
            };
            run_query(&machine,&reader,query,limit,answers);
            if(machine.output.length) {
                fwrite(machine.output.text,1,machine.output.length,writes);
                if(machine.output.text[machine.output.length-1]!='\n')fputc('\n',writes);
            }
            fprintf(stats,"query %d: solutions=%lld inferences=%lld choicepoints=%lld backtracks=%lld\n",number,machine.solutions,machine.inferences,machine.created,machine.backtracks);
            totals[0]+=machine.solutions;
            totals[1]+=machine.inferences;
            totals[2]+=machine.created;
            totals[3]+=machine.backtracks;
            undo(&machine.trail,0);
            free(machine.trail.variables);
            free(machine.choices);
        }
        release_to(mark);
    }
    fprintf(stats,"total: solutions=%lld inferences=%lld choicepoints=%lld backtracks=%lld\n== profile ==\n",totals[0],totals[1],totals[2],totals[3]);
    qsort(profiles,(size_t)profile_count,sizeof *profiles,profile_order);
    for(int i=0;i<profile_count;++i) {
        Profile *p=profiles[i];
        if(p->calls) {
            fprintf(stats,"%s calls=%lld",p->display,p->calls);
            if(predicate(&c.database,p->name,p->arity,0))fprintf(stats," tries=%lld",p->tries);
            fputc('\n',stats);
        }
        free(p->name);
        free(p->display);
        free(p);
    }
    free(profiles);
    fclose(queries);
    fclose(consult);
    fclose(listing_file);
    fclose(answers);
    fclose(writes);
    fclose(stats);
    release_to(NULL);
    return 0;
}
