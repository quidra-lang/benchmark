#include "prolog.h"
Memory *memory=NULL;
void *make(size_t n) {
    Memory *p=calloc(1,sizeof *p+(n?n:1));
    if(!p)exit(EXIT_FAILURE);
    p->next=memory;
    memory=p;
    return p+1;
}
char *copy_string(const char *s) {
    char *p=make(strlen(s)+1);
    strcpy(p,s);
    return p;
}
void release_to(Memory *mark) {
    while(memory!=mark) {
        Memory *p=memory;
        memory=p->next;
        free(p);
    }
}
void add_bytes(Buffer *b,const char *s,size_t n) {
    if(b->length+n+1>b->capacity) {
        size_t capacity=(b->length+n+1)*2;
        char *p=make(capacity);
        if(b->length)memcpy(p,b->text,b->length);
        b->text=p;
        b->capacity=capacity;
    }
    memcpy(b->text+b->length,s,n);
    b->length+=n;
    b->text[b->length]=0;
}
void add_text(Buffer *b,const char *s) {
    add_bytes(b,s,strlen(s));
}
void add_format(Buffer *b,const char *fmt,...) {
    va_list args,copy;
    va_start(args,fmt);
    va_copy(copy,args);
    int n=vsnprintf(NULL,0,fmt,copy);
    va_end(copy);
    char *s=make((size_t)n+1);
    vsnprintf(s,(size_t)n+1,fmt,args);
    va_end(args);
    add_text(b,s);
}
char *file_text(const char *path) {
    FILE *f=fopen(path,"r");
    if(!f)exit(EXIT_FAILURE);
    Buffer b= {
        0
    };
    char chunk[4096];
    size_t n;
    while((n=fread(chunk,1,sizeof chunk,f)))add_bytes(&b,chunk,n);
    fclose(f);
    return b.text?b.text:copy_string("");
}
char *line_read(FILE *f) {
    Buffer b= {
        0
    };
    int c;
    while((c=fgetc(f))!=EOF&&c!='\n') {
        char x=(char)c;
        add_bytes(&b,&x,1);
    }
    if(c==EOF&&!b.length)return NULL;
    return b.text?b.text:copy_string("");
}
Term *integer(long long n) {
    Term *t=make(sizeof *t);
    t->kind=TERM_INTEGER;
    t->integer=n;
    return t;
}
Term *atom(const char *name) {
    Term *t=make(sizeof *t);
    t->kind=TERM_ATOM;
    t->name=copy_string(name);
    return t;
}
Term *fresh(void) {
    Term *t=make(sizeof *t);
    t->kind=TERM_VARIABLE;
    return t;
}
Term *compound(const char *name,int n,Term **args) {
    Term *t=make(sizeof *t);
    t->kind=TERM_COMPOUND;
    t->name=copy_string(name);
    t->arity=n;
    t->args=make((size_t)n*sizeof *t->args);
    memcpy(t->args,args,(size_t)n*sizeof *t->args);
    return t;
}
Term *unary(const char *name,Term *a) {
    Term *args[]= {
        a
    };
    return compound(name,1,args);
}
Term *binary(const char *name,Term *a,Term *b) {
    Term *args[]= {
        a,b
    };
    return compound(name,2,args);
}
Term *ternary(const char *name,Term *a,Term *b,Term *c) {
    Term *args[]= {
        a,b,c
    };
    return compound(name,3,args);
}
Term *dereference(Term *t) {
    while(t->kind==TERM_VARIABLE&&t->binding)t=t->binding;
    return t;
}
int is_term(Term *t,const char *name,int arity) {
    t=dereference(t);
    return (arity?t->kind==TERM_COMPOUND&&t->arity==arity:t->kind==TERM_ATOM)&&!strcmp(t->name,name);
}
int empty_list(Term *t) {
    return is_term(t,"[]",0);
}
Term *list(Term **items,int count,Term *tail) {
    Term *result=tail?tail:atom("[]");
    for(int i=count-1;i>=0;--i)result=binary(".",items[i],result);
    return result;
}
int list_items(Term *t,Term ***items,Term **tail) {
    int n=0,capacity=0;
    Term **data=NULL;
    while(is_term(t,".",2)) {
        t=dereference(t);
        if(n==capacity) {
            capacity=capacity?2*capacity:8;
            Term **p=make((size_t)capacity*sizeof *p);
            if(n)memcpy(p,data,(size_t)n*sizeof *p);
            data=p;
        }
        data[n++]=dereference(t->args[0]);
        t=t->args[1];
    }
    *items=data;
    *tail=dereference(t);
    return n;
}
static Term *copy_with(Term *t,Term ***old,Term ***new,int *n) {
    t=dereference(t);
    if(t->kind==TERM_VARIABLE) {
        for(int i=0;i<*n;++i)if((*old)[i]==t)return (*new)[i];
        Term **a=make((size_t)(*n+1)*sizeof *a),**b=make((size_t)(*n+1)*sizeof *b);
        if(*n) {
            memcpy(a,*old,(size_t)*n*sizeof *a);
            memcpy(b,*new,(size_t)*n*sizeof *b);
        }
        a[*n]=t;
        b[*n]=fresh();
        *old=a;
        *new=b;
        return b[(*n)++];
    }
    if(t->kind!=TERM_COMPOUND)return t;
    Term **args=make((size_t)t->arity*sizeof *args);
    for(int i=0;i<t->arity;++i)args[i]=copy_with(t->args[i],old,new,n);
    return compound(t->name,t->arity,args);
}
Term *copy_term(Term *t) {
    Term **a=NULL,**b=NULL;
    int n=0;
    return copy_with(t,&a,&b,&n);
}
Term *copy_pair(Term *head,Term *body,Term **new_body) {
    Term **a=NULL,**b=NULL;
    int n=0;
    Term *h=copy_with(head,&a,&b,&n);
    *new_body=body?copy_with(body,&a,&b,&n):NULL;
    return h;
}
Term *indicator(const char *name,int arity) {
    return binary("/",atom(name),integer(arity));
}
Term *type_error(const char *expected,Term *actual) {
    return binary("type_error",atom(expected),actual);
}
Term *domain_error(const char *domain,Term *actual) {
    return binary("domain_error",atom(domain),actual);
}
Term *evaluation_error(const char *name) {
    return unary("evaluation_error",atom(name));
}
