#include "awk.h"
Symbol *global_symbol(Runtime *r,const char *name) {
    for(int i=0;i<r->ng;++i)if(!strcmp(r->globals[i]->name,name))return r->globals[i];
    Symbol *s=mem_new(sizeof *s);
    s->name=str_copy(name);
    s->parameter=-1;
    r->globals=mem_resize(r->globals,(size_t)(r->ng+1)*sizeof *r->globals);
    r->globals[r->ng++]=s;
    return s;
}
Variable *variable(Runtime *r,Symbol *s) {
    return s->parameter<0?&s->global:&r->frame->locals[s->parameter];
}
static Function *find_function(Runtime *r,const char *name) {
    for(int i=0;i<r->syntax.nf;++i)if(!strcmp(r->syntax.functions[i]->token.text,name))return r->syntax.functions[i];
    return NULL;
}
static Symbol *resolve(Runtime *r,Function *f,const char *name) {
    if(f)for(int i=0;i<f->np;++i)if(!strcmp(f->params[i].text,name))return f->symbols[i];
    return global_symbol(r,name);
}
static int earlier(Position a,Position b) {
    return a.line<b.line||(a.line==b.line&&a.column<b.column);
}
typedef struct {
    Position pos;
    int order;
    char *message;
}
StaticError;
static void static_error(StaticError *error,Token t,int order,const char *format,...) {
    if(error->message&&!earlier(t.pos,error->pos)&&!(t.pos.line==error->pos.line&&t.pos.column==error->pos.column&&order<error->order))return;
    va_list args,copy;
    va_start(args,format);
    va_copy(copy,args);
    int n=vsnprintf(NULL,0,format,copy);
    va_end(copy);
    free(error->message);
    error->message=mem_new((size_t)n+1);
    vsnprintf(error->message,(size_t)n+1,format,args);
    va_end(args);
    error->pos=t.pos;
    error->order=order;
}
static void check_variable(Runtime *r,Function *f,Token t,Symbol **symbol,int array,StaticError *error) {
    *symbol=resolve(r,f,t.text);
    if(array)(*symbol)->array=1;
    if(find_function(r,t.text))static_error(error,t,2,"function %s used as variable",t.text);
}
static void bind_expr(Runtime *r,Function *f,Expr *e,StaticError *error) {
    if(!e)return;
    if(e->kind==E_VAR||e->kind==E_ARRAY||e->kind==E_IN)check_variable(r,f,e->token,&e->symbol,e->kind!=E_VAR,error);
    if(e->kind==E_CALL) {
        e->function=find_function(r,e->token.text);
        if(!e->function)static_error(error,e->token,3,"undefined function %s",e->token.text);
        else if(e->count>e->function->np)static_error(error,e->token,4,"too many arguments to %s",e->token.text);
    }
    bind_expr(r,f,e->a,error);
    bind_expr(r,f,e->b,error);
    bind_expr(r,f,e->c,error);
    for(int i=0;i<e->count;++i)bind_expr(r,f,e->args[i],error);
    if(e->kind==E_BUILTIN&&!strcmp(e->token.text,"split"))e->args[1]->symbol->array=1;
}
static void bind_statement(Runtime *r,Function *f,Statement *s,StaticError *error) {
    if(!s)return;
    bind_expr(r,f,s->a,error);
    bind_expr(r,f,s->b,error);
    bind_expr(r,f,s->c,error);
    bind_expr(r,f,s->redirect,error);
    for(int i=0;i<s->nargs;++i)bind_expr(r,f,s->args[i],error);
    if(s->kind==S_DELETE)s->a->symbol->array=1;
    if(s->kind==S_FORIN)check_variable(r,f,s->second,&s->array,1,error);
    bind_statement(r,f,s->body,error);
    bind_statement(r,f,s->otherwise,error);
    for(int i=0;i<s->count;++i)bind_statement(r,f,s->children[i],error);
}
static int links_expr(Expr *e) {
    if(!e)return 0;
    int changed=links_expr(e->a)|links_expr(e->b)|links_expr(e->c);
    for(int i=0;i<e->count;++i)changed|=links_expr(e->args[i]);
    if(e->kind==E_CALL&&e->function)for(int i=0;i<e->count&&i<e->function->np;++i)if(e->args[i]->kind==E_VAR) {
        Symbol *a=e->args[i]->symbol,*b=e->function->symbols[i];
        if(a->array!=b->array) {
            a->array=b->array=1;
            changed=1;
        }
    }
    return changed;
}
static int links_statement(Statement *s) {
    if(!s)return 0;
    int c=links_expr(s->a)|links_expr(s->b)|links_expr(s->c)|links_expr(s->redirect)|links_statement(s->body)|links_statement(s->otherwise);
    for(int i=0;i<s->nargs;++i)c|=links_expr(s->args[i]);
    for(int i=0;i<s->count;++i)c|=links_statement(s->children[i]);
    return c;
}
static StaticError static_checks(Runtime *r) {
    StaticError error= {
        0
    };
    for(int i=0;i<r->syntax.nf;++i) {
        Function *f=r->syntax.functions[i];
        f->symbols=mem_new((size_t)f->np*sizeof *f->symbols);
        for(int j=0;j<i;++j)if(!strcmp(f->token.text,r->syntax.functions[j]->token.text)) {
            static_error(&error,f->token,0,"function %s redefined",f->token.text);
            break;
        }
        for(int p=0;p<f->np;++p) {
            f->symbols[p]=mem_new(sizeof(Symbol));
            f->symbols[p]->name=str_copy(f->params[p].text);
            f->symbols[p]->parameter=p;
            for(int j=0;j<p;++j)if(!strcmp(f->params[j].text,f->params[p].text)) {
                static_error(&error,f->params[p],1,"duplicate parameter %s",f->params[p].text);
                break;
            }
            if(find_function(r,f->params[p].text))static_error(&error,f->params[p],2,"function %s used as variable",f->params[p].text);
        }
    }
    for(int i=0;i<r->syntax.nf;++i)bind_statement(r,r->syntax.functions[i],r->syntax.functions[i]->body,&error);
    for(int i=0;i<r->syntax.nr;++i) {
        Rule *rule=r->syntax.rules[i];
        bind_expr(r,NULL,rule->start,&error);
        bind_expr(r,NULL,rule->end,&error);
        bind_statement(r,NULL,rule->action,&error);
    }
    if(error.message)return error;
    int changed;
    do {
        changed=0;
        for(int i=0;i<r->syntax.nf;++i)changed|=links_statement(r->syntax.functions[i]->body);
        for(int i=0;i<r->syntax.nr;++i) {
            Rule *rule=r->syntax.rules[i];
            changed|=links_expr(rule->start)|links_expr(rule->end)|links_statement(rule->action);
        }
    }
    while(changed);
    return error;
}
static void global_store(Runtime *r,const char *name,Value value) {
    Variable *v=&global_symbol(r,name)->global;
    value_free(v->value);
    v->value=value_copy(value);
}
static Value symbol_value(Runtime *r,Symbol *s) {
    if(s->parameter<0&&!strcmp(s->name,"NF"))return number(r->nf);
    return value_copy(variable(r,s)->value);
}
typedef struct {
    Symbol *symbol;
    char *key;
    long long field;
    int kind;
    Position position;
}
Location;
static char *subscript(Runtime *r,Expr **args,int count) {
    char **pieces=mem_new((size_t)count*sizeof *pieces);
    for(int i=0;i<count;++i) {
        Value v=evaluate(r,args[i]);
        pieces[i]=textual(v);
        value_free(v);
    }
    Value sep=symbol_value(r,global_symbol(r,"SUBSEP"));
    char *separator=textual(sep);
    value_free(sep);
    Buffer b= {
        0
    };
    for(int i=0;i<count;++i) {
        if(i)buffer_text(&b,separator);
        buffer_text(&b,pieces[i]);
        free(pieces[i]);
    }
    free(pieces);
    free(separator);
    return b.data?b.data:str_copy("");
}
static Location location(Runtime *r,Expr *e) {
    Location l= {
        .kind=e->kind,.symbol=e->symbol,.position=e->token.pos
    };
    if(e->kind==E_ARRAY)l.key=subscript(r,e->args,e->count);
    else if(e->kind==E_FIELD) {
        Value v=evaluate(r,e->a);
        l.field=numeric(v);
        value_free(v);
        if(l.field<0)runtime_error(r,e->token.pos,"negative field index");
    }
    return l;
}
static Value load(Runtime *r,Location l) {
    if(l.kind==E_FIELD)return field_value(r,l.field,l.position);
    if(l.kind==E_ARRAY)return value_copy(array_element(variable(r,l.symbol)->array,l.key,1)->value);
    return symbol_value(r,l.symbol);
}
static void store(Runtime *r,Location l,Value v,Position pos) {
    if(r->message||r->flow)return;
    if(l.kind==E_FIELD)store_field(r,l.field,v,l.position);
    else if(l.kind==E_VAR&&l.symbol->parameter<0&&!strcmp(l.symbol->name,"NF"))set_nf(r,numeric(v),pos);
    else {
        Value *target=l.kind==E_ARRAY?&array_element(variable(r,l.symbol)->array,l.key,1)->value:&variable(r,l.symbol)->value;
        value_free(*target);
        *target=value_copy(v);
    }
}
static Value arithmetic(Runtime *r,const char *op,Value av,Value bv,Position pos) {
    long long a=numeric(av),b=numeric(bv),n=0;
    if((*op=='/'||*op=='%')&&!b)runtime_error(r,pos,"division by zero");
    else if(*op=='^'&&b<0)runtime_error(r,pos,"negative exponent");
    else if(*op=='+')n=a+b;
    else if(*op=='-')n=a-b;
    else if(*op=='*')n=a*b;
    else if(*op=='/')n=a/b;
    else if(*op=='%')n=a%b;
    else {
        n=1;
        while(b) {
            if(b&1)n*=a;
            b>>=1;
            if(b)a*=a;
        }
    }
    return number(n);
}
static char *main_record(Runtime *r) {
    Streams *s=&r->streams;
    if(r->phase==2)return NULL;
    for(;;) {
        if(s->main_file) {
            char *line=read_line(s->main_file);
            if(line) {
                ++s->args[s->current].records;
                Value nr=number(numeric(global_symbol(r,"NR")->global.value)+1),fnr=number(numeric(global_symbol(r,"FNR")->global.value)+1);
                global_store(r,"NR",nr);
                global_store(r,"FNR",fnr);
                return line;
            }
            fclose(s->main_file);
            s->main_file=NULL;
        }
        if(s->next>=s->count)return NULL;
        int i=s->next++;
        Operand *operand=&s->args[i];
        if(operand->option)continue;
        if(operand->assignment) {
            Value v=input_value(operand->value);
            global_store(r,operand->name,v);
            value_free(v);
        }
        else {
            char *path=mem_new(strlen(operand->name)+7);
            sprintf(path,"input/%s",operand->name);
            s->main_file=fopen(path,"r");
            free(path);
            if(!s->main_file)exit(EXIT_FAILURE);
            s->current=i;
            Value v=string(operand->name);
            global_store(r,"FILENAME",v);
            value_free(v);
            global_store(r,"FNR",number(0));
        }
    }
}
static Value call_function(Runtime *r,Expr *e) {
    Function *f=e->function;
    Variable *locals=mem_new((size_t)f->np*sizeof *locals);
    for(int i=0;i<f->np;++i) {
        if(f->symbols[i]->array) {
            if(i<e->count)locals[i].array=variable(r,e->args[i]->symbol)->array;
            else {
                locals[i].array=mem_new(sizeof(Array));
                locals[i].own_array=1;
            }
        }
        else if(i<e->count)locals[i].value=evaluate(r,e->args[i]);
    }
    if(r->message||r->flow) {
        for(int i=0;i<f->np;++i) {
            value_free(locals[i].value);
            if(locals[i].own_array) {
                array_clear(locals[i].array);
                free(locals[i].array);
            }
        }
        free(locals);
        return (Value) {
            0
        };
    }
    ++f->calls;
    ++f->current;
    if(f->current>f->depth)f->depth=f->current;
    Frame frame= {
        f,locals,r->frame
    };
    r->frame=&frame;
    execute(r,f->body);
    r->frame=frame.parent;
    --f->current;
    Value result= {
        0
    };
    if(r->flow==FLOW_RETURN) {
        result=r->result;
        r->result=(Value) {
            0
        };
        r->flow=FLOW_NORMAL;
    }
    for(int i=0;i<f->np;++i) {
        value_free(locals[i].value);
        if(locals[i].own_array) {
            array_clear(locals[i].array);
            free(locals[i].array);
        }
    }
    free(locals);
    return result;
}
Value builtin(Runtime *r,Expr *e) {
    const char *name=e->token.text;
    if(!strcmp(name,"length")) {
        if(!e->count) {
            char *s=textual(r->record);
            long long n=(long long)strlen(s);
            free(s);
            return number(n);
        }
        if(e->args[0]->kind==E_VAR&&e->args[0]->symbol->array)return number(variable(r,e->args[0]->symbol)->array->count);
        Value v=evaluate(r,e->args[0]);
        char *s=textual(v);
        Value result=number((long long)strlen(s));
        free(s);
        value_free(v);
        return result;
    }
    if(!strcmp(name,"split")) {
        Value first=evaluate(r,e->args[0]);
        char *s=textual(first);
        value_free(first);
        Value separator=e->count==3?evaluate(r,e->args[2]):symbol_value(r,global_symbol(r,"FS"));
        char *sep=textual(separator);
        value_free(separator);
        int n;
        char **pieces=split_string(s,sep,&n);
        Array *a=variable(r,e->args[1]->symbol)->array;
        if(!r->message&&!r->flow) {
            array_clear(a);
            for(int i=0;i<n;++i) {
                char key[40];
                sprintf(key,"%d",i+1);
                array_element(a,key,1)->value=input_value(pieces[i]);
            }
        }
        for(int i=0;i<n;++i)free(pieces[i]);
        free(pieces);
        free(s);
        free(sep);
        return number(n);
    }
    Value *args=mem_new((size_t)e->count*sizeof *args);
    for(int i=0;i<e->count;++i)args[i]=evaluate(r,e->args[i]);
    Value result= {
        0
    };
    if(!r->message&&!r->flow) {
        if(!strcmp(name,"close")) {
            char *s=textual(args[0]);
            result=number(close_stream(&r->streams,s));
            free(s);
        }
        else result=simple_builtin(r,e,args);
    }
    for(int i=0;i<e->count;++i)value_free(args[i]);
    free(args);
    return result;
}
Value evaluate(Runtime *r,Expr *e) {
    if(!e||r->message||r->flow)return (Value) {
        0
    };
    switch(e->kind) {
        case E_NUMBER:return number(e->token.number);
        case E_STRING:return string(e->token.text);
        case E_GROUP:return evaluate(r,e->a);
        case E_VAR:return symbol_value(r,e->symbol);
        case E_ARRAY:case E_FIELD: {
            Location l=location(r,e);
            Value v=(r->message||r->flow)?(Value) {
                0
            }
            :load(r,l);
            free(l.key);
            return v;
        }
        case E_ASSIGN: {
            Location l=location(r,e->a);
            Value b=evaluate(r,e->b),value=value_copy(b);
            if(r->message||r->flow) {
                value_free(value);
                value_free(b);
                free(l.key);
                return (Value){0};
            }
            if(strcmp(e->op,"=")) {
                Value a=load(r,l);
                value_free(value);
                value=arithmetic(r,e->op,a,b,e->token.pos);
                value_free(a);
            }
            store(r,l,value,e->token.pos);
            value_free(value);
            value_free(b);
            Value result=(r->message||r->flow)?(Value) {
                0
            }
            :load(r,l);
            free(l.key);
            return result;
        }
        case E_INC: {
            Location l=location(r,e->a);
            Value a=(r->message||r->flow)?(Value) {
                0
            }
            :load(r,l);
            long long old=numeric(a);
            value_free(a);
            Value v=number(old+(!strcmp(e->op,"++")?1:-1));
            store(r,l,v,e->token.pos);
            free(l.key);
            return e->postfix?number(old):v;
        }
        case E_UNARY: {
            Value a=evaluate(r,e->a);
            Value v=number(!strcmp(e->op,"!")?!truth(a):!strcmp(e->op,"-")?-numeric(a):numeric(a));
            value_free(a);
            return v;
        }
        case E_COND: {
            Value c=evaluate(r,e->a);
            int yes=truth(c);
            value_free(c);
            return evaluate(r,yes?e->b:e->c);
        }
        case E_BINARY: {
            Value a=evaluate(r,e->a);
            if(!strcmp(e->op,"&&")&&!truth(a)) {
                value_free(a);
                return number(0);
            }
            if(!strcmp(e->op,"||")&&truth(a)) {
                value_free(a);
                return number(1);
            }
            Value b=evaluate(r,e->b),result= {
                0
            };
            if(!strcmp(e->op,"&&")||!strcmp(e->op,"||"))result=number(truth(b));
            else if(!strcmp(e->op,"concat")) {
                char *x=textual(a),*y=textual(b);
                Buffer out= {
                    0
                };
                buffer_text(&out,x);
                buffer_text(&out,y);
                result=string(out.data);
                free(x);
                free(y);
                free(out.data);
            }
            else if(strchr("<>!=",*e->op)) {
                int c=compare(a,b);
                result=number(!strcmp(e->op,"<")?c<0:!strcmp(e->op,"<=")?c<=0:!strcmp(e->op,">")?c>0:!strcmp(e->op,">=")?c>=0:!strcmp(e->op,"==")?c==0:c!=0);
            }
            else result=arithmetic(r,e->op,a,b,e->token.pos);
            value_free(a);
            value_free(b);
            return result;
        }
        case E_IN: {
            char *key=subscript(r,e->args,e->count);
            Value v=number(array_element(variable(r,e->symbol)->array,key,0)!=NULL);
            free(key);
            return v;
        }
        case E_CALL:return call_function(r,e);
        case E_BUILTIN:return builtin(r,e);
        case E_GETLINE: {
            char *line=NULL;
            int status=0;
            if(e->b) {
                Value name=evaluate(r,e->b);
                char *text=textual(name);
                value_free(name);
                if(!r->message&&!r->flow)line=getline_file(&r->streams,text,&status);
                free(text);
            }
            else {
                line=main_record(r);
                status=line?1:0;
            }
            if(line) {
                if(e->a) {
                    Location l=location(r,e->a);
                    Value v=input_value(line);
                    store(r,l,v,e->token.pos);
                    value_free(v);
                    free(l.key);
                }
                else set_record(r,line);
                free(line);
            }
            return number(status);
        }
    }
    return (Value) {
        0
    };
}
static int condition(Runtime *r,Expr *e) {
    Value v=evaluate(r,e);
    int result=truth(v);
    value_free(v);
    return result;
}
static void discard(Runtime *r,Expr *e) {
    Value v=evaluate(r,e);
    value_free(v);
}
static int loop_flow(Runtime *r) {
    if(r->flow==FLOW_BREAK) {
        r->flow=FLOW_NORMAL;
        return 1;
    }
    if(r->flow==FLOW_CONTINUE)r->flow=FLOW_NORMAL;
    return r->message||r->flow;
}
static void print_statement(Runtime *r,Statement *s) {
    int n=s->nargs?s->nargs:1;
    Value *values=mem_new((size_t)n*sizeof *values);
    if(s->nargs)for(int i=0;i<n;++i)values[i]=evaluate(r,s->args[i]);
    else values[0]=value_copy(r->record);
    char *text=NULL;
    if(!r->message&&!r->flow) {
        if(s->kind==S_PRINTF)text=format_values(r,s->token.pos,values,n);
        else {
            Buffer b= {
                0
            };
            Value ofs=symbol_value(r,global_symbol(r,"OFS")),ors=symbol_value(r,global_symbol(r,"ORS"));
            char *sep=textual(ofs),*end=textual(ors);
            value_free(ofs);
            value_free(ors);
            for(int i=0;i<n;++i) {
                if(i)buffer_text(&b,sep);
                char *v=textual(values[i]);
                buffer_text(&b,v);
                free(v);
            }
            buffer_text(&b,end);
            text=b.data?b.data:str_copy("");
            free(sep);
            free(end);
        }
    }
    for(int i=0;i<n;++i)value_free(values[i]);
    free(values);
    char *destination=NULL;
    if(s->redirect&&!r->message&&!r->flow) {
        Value v=evaluate(r,s->redirect);
        destination=textual(v);
        value_free(v);
        if(!valid_filename(destination)||!strcmp(destination,"stdout.txt")||!strcmp(destination,"stats.txt"))runtime_error(r,s->second.pos,"invalid output file name");
    }
    if(!r->message&&!r->flow)output_string(&r->streams,destination,s->append,text);
    free(text);
    free(destination);
}
void execute(Runtime *r,Statement *s) {
    if(!s||r->message||r->flow)return;
    if(s->kind!=S_BLOCK&&s->kind!=S_EMPTY)++r->line_counts[s->token.pos.line];
    switch(s->kind) {
        case S_EMPTY:break;
        case S_BLOCK:for(int i=0;i<s->count&&!r->flow&&!r->message;++i)execute(r,s->children[i]);
        break;
        case S_EXPR:discard(r,s->a);
        break;
        case S_IF:execute(r,condition(r,s->a)?s->body:s->otherwise);
        break;
        case S_WHILE:while(condition(r,s->a)&&!r->message&&!r->flow) {
            execute(r,s->body);
            if(loop_flow(r))break;
        }
        break;
        case S_DO:do {
            execute(r,s->body);
            if(loop_flow(r))break;
        }
        while(condition(r,s->a)&&!r->message&&!r->flow);
        break;
        case S_FOR:discard(r,s->a);
        while((!s->b||condition(r,s->b))&&!r->message&&!r->flow) {
            execute(r,s->body);
            if(loop_flow(r))break;
            discard(r,s->c);
        }
        break;
        case S_FORIN: {
            Array *array=variable(r,s->array)->array;
            int n=array->count;
            char **keys=mem_new((size_t)n*sizeof *keys);
            for(int i=0;i<n;++i)keys[i]=str_copy(array->items[i]->key);
            qsort(keys,(size_t)n,sizeof *keys,key_compare);
            for(int i=0;i<n&&!r->message&&!r->flow;++i) {
                Location l=location(r,s->a);
                Value v=input_value(keys[i]);
                store(r,l,v,s->a->token.pos);
                value_free(v);
                free(l.key);
                execute(r,s->body);
                if(loop_flow(r))break;
            }
            for(int i=0;i<n;++i)free(keys[i]);
            free(keys);
            break;
        }
        case S_PRINT:case S_PRINTF:print_statement(r,s);
        break;
        case S_DELETE: {
            Array *a=variable(r,s->a->symbol)->array;
            if(s->a->kind==E_VAR)array_clear(a);
            else {
                char *key=subscript(r,s->a->args,s->a->count);
                if(!r->message&&!r->flow)array_delete(a,key);
                free(key);
            }
            break;
        }
        case S_NEXT:if(r->phase)runtime_error(r,s->token.pos,"next used in BEGIN or END");
        else r->flow=FLOW_NEXT;
        break;
        case S_BREAK:r->flow=FLOW_BREAK;
        break;
        case S_CONTINUE:r->flow=FLOW_CONTINUE;
        break;
        case S_EXIT:if(s->a) {
            Value v=evaluate(r,s->a);
            if(!r->message&&!r->flow)r->status=numeric(v);
            value_free(v);
        }
        if(!r->message)r->flow=FLOW_EXIT;
        break;
        case S_RETURN: {
            Value v=evaluate(r,s->a);
            if(!r->message&&!r->flow) {
                value_free(r->result);
                r->result=v;
                r->flow=FLOW_RETURN;
            }
            else value_free(v);
            break;
        }
    }
}
static void initialize(Runtime *r) {
    const char *names[]= {
        "FILENAME","FNR","FS","NF","NR","OFS","ORS","SUBSEP"
    };
    for(int i=0;i<8;++i)global_symbol(r,names[i]);
    Value v=string(" ");
    global_store(r,"FS",v);
    global_store(r,"OFS",v);
    value_free(v);
    v=string("\n");
    global_store(r,"ORS",v);
    value_free(v);
    v=string("\034");
    global_store(r,"SUBSEP",v);
    value_free(v);
    v=string("");
    global_store(r,"FILENAME",v);
    value_free(v);
    global_store(r,"NR",number(0));
    global_store(r,"FNR",number(0));
    r->record=string("");
    for(int i=0;i<r->ng;++i)if(r->globals[i]->array) {
        r->globals[i]->global.array=mem_new(sizeof(Array));
        r->globals[i]->global.own_array=1;
    }
    r->line_counts=mem_new(((size_t)r->syntax.lines+2)*sizeof *r->line_counts);
    for(int i=0;i<r->streams.count;++i)if(r->streams.args[i].option) {
        Operand *a=&r->streams.args[i];
        Value value=input_value(a->value);
        global_store(r,a->name,value);
        value_free(value);
    }
}
static void run(Runtime *r) {
    r->phase=1;
    for(int i=0;i<r->syntax.nr&&!r->message&&!r->flow;++i)if(r->syntax.rules[i]->kind==1) {
        ++r->syntax.rules[i]->count;
        execute(r,r->syntax.rules[i]->action);
    }
    int process=0;
    for(int i=0;i<r->syntax.nr;++i)if(r->syntax.rules[i]->kind!=1)process=1;
    r->phase=0;
    while(process&&!r->message&&!r->flow) {
        char *line=main_record(r);
        if(!line)break;
        set_record(r,line);
        free(line);
        for(int i=0;i<r->syntax.nr&&!r->message&&!r->flow;++i) {
            Rule *rule=r->syntax.rules[i];
            if(rule->kind==1||rule->kind==2)continue;
            int match=1;
            if(rule->kind==3)match=condition(r,rule->start);
            else if(rule->kind==4) {
                if(!rule->inside)rule->inside=condition(r,rule->start);
                match=rule->inside;
                if(match&&condition(r,rule->end))rule->inside=0;
            }
            if(match&&!r->message&&!r->flow) {
                ++rule->count;
                if(rule->action)execute(r,rule->action);
                else {
                    Value v=symbol_value(r,global_symbol(r,"ORS"));
                    char *text=textual(r->record),*end=textual(v);
                    value_free(v);
                    Buffer b= {
                        0
                    };
                    buffer_text(&b,text);
                    buffer_text(&b,end);
                    output_string(&r->streams,NULL,0,b.data);
                    free(text);
                    free(end);
                    free(b.data);
                }
            }
        }
        if(r->flow==FLOW_NEXT)r->flow=FLOW_NORMAL;
    }
    if(!r->message) {
        r->flow=FLOW_NORMAL;
        r->phase=2;
        for(int i=0;i<r->syntax.nr&&!r->message&&!r->flow;++i)if(r->syntax.rules[i]->kind==2) {
            ++r->syntax.rules[i]->count;
            execute(r,r->syntax.rules[i]->action);
        }
    }
}
static int symbol_order(const void *a,const void *b) {
    return strcmp((*(Symbol*const*)a)->name,(*(Symbol*const*)b)->name);
}
static void statistics(FILE *f,Runtime *r) {
    if(r->message)fprintf(f,"status: runtime error at %d:%d: %s\n",r->error.line,r->error.column,r->message);
    else fprintf(f,"status: exit %lld\n",r->status);
    fputs("[inputs]\n",f);
    for(int i=0;i<r->streams.count;++i) {
        Operand *a=&r->streams.args[i];
        if(!a->assignment)fprintf(f,"%s records=%lld\n",a->name,a->records);
    }
    fputs("[getline]\n",f);
    for(int i=0;i<r->streams.ni;++i) {
        InputStream *s=r->streams.inputs[i];
        if(s->ever)fprintf(f,"%s reads=%lld\n",s->name,s->reads);
        else fprintf(f,"%s missing\n",s->name);
    }
    fputs("[rules]\n",f);
    const char *kinds[]= {
        "all","BEGIN","END","pattern","range"
    };
    for(int i=0;i<r->syntax.nr;++i) {
        Rule *rule=r->syntax.rules[i];
        fprintf(f,"%d:%d %s count=%lld\n",rule->token.pos.line,rule->token.pos.column,kinds[rule->kind],rule->count);
    }
    fputs("[functions]\n",f);
    for(int i=0;i<r->syntax.nf;++i) {
        Function *fn=r->syntax.functions[i];
        fprintf(f,"%s calls=%lld depth=%lld\n",fn->token.text,fn->calls,fn->depth);
    }
    fprintf(f,"[outputs]\nstdout.txt writes=%lld bytes=%zu\n",r->streams.writes,r->streams.standard.length);
    for(int i=0;i<r->streams.no;++i) {
        OutputStream *out=r->streams.outputs[i];
        fprintf(f,"%s writes=%lld bytes=%zu\n",out->name,out->writes,out->content.length);
    }
    fputs("[lines]\n",f);
    for(int i=1;i<=r->syntax.lines;++i)if(r->syntax.statement_lines[i])fprintf(f,"%d count=%lld\n",i,r->line_counts[i]);
    fputs("[globals]\n",f);
    qsort(r->globals,(size_t)r->ng,sizeof *r->globals,symbol_order);
    for(int i=0;i<r->ng;++i) {
        Symbol *s=r->globals[i];
        fprintf(f,"%s = ",s->name);
        if(s->array)fprintf(f,"array (%d)",s->global.array->count);
        else if(!strcmp(s->name,"NF"))value_write(f,number(r->nf));
        else value_write(f,s->global.value);
        fputc('\n',f);
    }
}
int main(void) {
    FILE *source=fopen("input/program.awk","r");
    if(!source)return EXIT_FAILURE;
    Buffer text= {
        0
    };
    char chunk[4096];
    size_t n;
    while((n=fread(chunk,1,sizeof chunk,source)))buffer_add(&text,chunk,n);
    fclose(source);
    int lines=0;
    for(size_t i=0;i<text.length;++i)lines+=text.data[i]=='\n';
    Tokens tokens=lex(text.data?text.data:"");
    Runtime r= {
        0
    };
    FILE *stats=fopen("output/stats.txt","w"),*standard=fopen("output/stdout.txt","w");
    if(!stats||!standard)return EXIT_FAILURE;
    fclose(standard);
    if(tokens.failed) {
        fprintf(stats,"status: syntax error at %d:%d\n",tokens.error.line,tokens.error.column);
        fclose(stats);
        return 0;
    }
    r.syntax=parse(tokens,lines);
    if(r.syntax.failed) {
        fprintf(stats,"status: syntax error at %d:%d\n",r.syntax.error.line,r.syntax.error.column);
        fclose(stats);
        return 0;
    }
    StaticError error=static_checks(&r);
    if(error.message) {
        fprintf(stats,"status: error at %d:%d: %s\n",error.pos.line,error.pos.column,error.message);
        fclose(stats);
        free(error.message);
        return 0;
    }
    r.streams=read_args();
    initialize(&r);
    run(&r);
    write_streams(&r.streams);
    statistics(stats,&r);
    fclose(stats);
    return 0;
}
