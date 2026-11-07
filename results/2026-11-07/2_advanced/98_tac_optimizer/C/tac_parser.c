#include "tac.h"
const char *kind_names[KIND_COUNT]= {
    "copy","bin","load","store","goto","if","param","call","return","read","print"
};
void *allocate(size_t n) {
    void *p=calloc(n?n:1,1);
    if(!p)exit(EXIT_FAILURE);
    return p;
}
void *resize(void *p,size_t n) {
    void *q=realloc(p,n?n:1);
    if(!q)exit(EXIT_FAILURE);
    return q;
}
char *string_copy(const char *s) {
    char *p=allocate(strlen(s)+1);
    strcpy(p,s);
    return p;
}
void ints_add(Ints *a,int v) {
    if(a->count==a->capacity) {
        a->capacity=a->capacity?2*a->capacity:8;
        a->data=resize(a->data,(size_t)a->capacity*sizeof *a->data);
    }
    a->data[a->count++]=v;
}
void strings_add(Strings *a,const char *s) {
    if(a->count==a->capacity) {
        a->capacity=a->capacity?2*a->capacity:8;
        a->data=resize(a->data,(size_t)a->capacity*sizeof *a->data);
    }
    a->data[a->count++]=string_copy(s);
}
void strings_format(Strings *a,const char *fmt,...) {
    va_list args,copy;
    va_start(args,fmt);
    va_copy(copy,args);
    int n=vsnprintf(NULL,0,fmt,copy);
    va_end(copy);
    char *s=allocate((size_t)n+1);
    vsnprintf(s,(size_t)n+1,fmt,args);
    va_end(args);
    strings_add(a,s);
    free(s);
}
void strings_free(Strings *a) {
    for(int i=0;i<a->count;++i)free(a->data[i]);
    free(a->data);
    memset(a,0,sizeof *a);
}
Set set_new(int n,int full) {
    Set s= {
        allocate((size_t)n),n
    };
    memset(s.bits,full?1:0,(size_t)n);
    return s;
}
Set set_copy(Set s) {
    Set r=set_new(s.size,0);
    memcpy(r.bits,s.bits,(size_t)s.size);
    return r;
}
void set_assign(Set a,Set b) {
    memcpy(a.bits,b.bits,(size_t)a.size);
}
void set_union(Set a,Set b) {
    for(int i=0;i<a.size;++i)a.bits[i]|=b.bits[i];
}
void set_intersect(Set a,Set b) {
    for(int i=0;i<a.size;++i)a.bits[i]&=b.bits[i];
}
int set_equal(Set a,Set b) {
    return !memcmp(a.bits,b.bits,(size_t)a.size);
}
int set_count(Set s) {
    int n=0;
    for(int i=0;i<s.size;++i)n+=s.bits[i]!=0;
    return n;
}
int constant(const char *s) {
    return *s=='-'||isdigit((unsigned char)*s);
}
long long operation(const char *op,long long a,long long b) {
    if(!strcmp(op,"+"))return a+b;
    if(!strcmp(op,"-"))return a-b;
    if(!strcmp(op,"*"))return a*b;
    if(!strcmp(op,"/"))return a/b;
    if(!strcmp(op,"%"))return a%b;
    if(!strcmp(op,"<"))return a<b;
    if(!strcmp(op,"<="))return a<=b;
    if(!strcmp(op,">"))return a>b;
    if(!strcmp(op,">="))return a>=b;
    if(!strcmp(op,"=="))return a==b;
    return a!=b;
}
const char *defined(const Instruction *s) {
    return s->kind==COPY||s->kind==BIN||s->kind==LOAD||s->kind==CALL||s->kind==READ?s->dest:"";
}
int used(Instruction *s,char **v) {
    int n=0;
    switch(s->kind) {
        case BIN:case IF:case STORE:if(*s->a&&!constant(s->a))v[n++]=s->a;
        if(*s->b&&!constant(s->b))v[n++]=s->b;
        break;
        case COPY:case LOAD:case PARAM:case RETURN:case PRINT:if(*s->a&&!constant(s->a))v[n++]=s->a;
        break;
        default:break;
    }
    return n;
}
int expression_equal(const Instruction *a,const Instruction *b) {
    return a->kind==b->kind&&!strcmp(a->op,b->op)&&!strcmp(a->a,b->a)&&(a->kind==LOAD||!strcmp(a->b,b->b));
}
void expression_text(const Instruction *s,char *out) {
    if(s->kind==LOAD)sprintf(out,"%s[%s]",s->op,s->a);
    else sprintf(out,"%s%s%s",s->a,s->op,s->b);
}
void instruction_text(const Instruction *s,char *out) {
    switch(s->kind) {
        case -1:sprintf(out,"%s:",s->target);
        break;
        case COPY:sprintf(out,"%s = %s",s->dest,s->a);
        break;
        case BIN:sprintf(out,"%s = %s %s %s",s->dest,s->a,s->op,s->b);
        break;
        case LOAD:sprintf(out,"%s = %s[%s]",s->dest,s->op,s->a);
        break;
        case STORE:sprintf(out,"%s[%s] = %s",s->op,s->a,s->b);
        break;
        case GOTO:sprintf(out,"goto %s",s->target);
        break;
        case IF:sprintf(out,"if %s %s %s goto %s",s->a,s->op,s->b,s->target);
        break;
        case PARAM:sprintf(out,"param %s",s->a);
        break;
        case CALL:if(*s->dest)sprintf(out,"%s = call %s %d",s->dest,s->target,s->count);
        else sprintf(out,"call %s %d",s->target,s->count);
        break;
        case RETURN:sprintf(out,"return%s%s",*s->a?" ":"",s->a);
        break;
        case READ:sprintf(out,"read %s",s->dest);
        break;
        case PRINT:sprintf(out,"print %s",s->a);
        break;
    }
}
void code_add(Function *f,Instruction s) {
    if(f->count==f->capacity) {
        f->capacity=f->capacity?2*f->capacity:16;
        f->code=resize(f->code,(size_t)f->capacity*sizeof *f->code);
    }
    f->code[f->count++]=s;
}
Function function_copy(const Function *f) {
    Function r=*f;
    r.params=allocate((size_t)f->np*sizeof *r.params);
    memcpy(r.params,f->params,(size_t)f->np*sizeof *r.params);
    r.code=allocate((size_t)f->count*sizeof *r.code);
    memcpy(r.code,f->code,(size_t)f->count*sizeof *r.code);
    r.capacity=f->count;
    return r;
}
void function_free(Function *f) {
    free(f->params);
    free(f->code);
    memset(f,0,sizeof *f);
}
static void normalize(char *s) {
    if(constant(s)) {
        long long v=strtoll(s,NULL,10);
        sprintf(s,"%lld",v);
    }
}
static void array_operand(const char *s,char *array,char *index) {
    const char *p=strchr(s,'[');
    memcpy(array,s,(size_t)(p-s));
    array[p-s]=0;
    strcpy(index,p+1);
    index[strlen(index)-1]=0;
    normalize(index);
}
Program read_program(const char *path) {
    Program p= {
        0
    };
    FILE *f=fopen(path,"r");
    if(!f)exit(EXIT_FAILURE);
    char line[256];
    Function *fn=NULL;
    while(fgets(line,sizeof line,f)) {
        char *w[128],*t=strtok(line," \r\n");
        int n=0;
        while(t) {
            w[n++]=t;
            t=strtok(NULL," \r\n");
        }
        if(!n||w[0][0]=='#')continue;
        if(!strcmp(w[0],"array")) {
            p.arrays=resize(p.arrays,(size_t)(p.na+1)*sizeof *p.arrays);
            strcpy(p.arrays[p.na].name,w[1]);
            p.arrays[p.na++].size=atoi(w[2]);
            continue;
        }
        if(!strcmp(w[0],"func")) {
            p.functions=resize(p.functions,(size_t)(p.count+1)*sizeof *p.functions);
            fn=&p.functions[p.count++];
            memset(fn,0,sizeof *fn);
            strcpy(fn->name,w[1]);
            fn->np=n-2;
            fn->params=allocate((size_t)fn->np*sizeof *fn->params);
            for(int i=0;i<fn->np;++i)strcpy(fn->params[i],w[i+2]);
            continue;
        }
        if(!strcmp(w[0],"end")) {
            fn=NULL;
            continue;
        }
        Instruction s= {
            0
        };
        if(w[0][strlen(w[0])-1]==':') {
            s.kind=-1;
            strcpy(s.target,w[0]);
            s.target[strlen(s.target)-1]=0;
        }
        else if(!strcmp(w[0],"goto")) {
            s.kind=GOTO;
            strcpy(s.target,w[1]);
        }
        else if(!strcmp(w[0],"if")) {
            s.kind=IF;
            strcpy(s.a,w[1]);
            strcpy(s.op,w[2]);
            strcpy(s.b,w[3]);
            strcpy(s.target,w[5]);
        }
        else if(!strcmp(w[0],"param")||!strcmp(w[0],"print")||!strcmp(w[0],"return")) {
            s.kind=!strcmp(w[0],"param")?PARAM:!strcmp(w[0],"print")?PRINT:RETURN;
            if(n>1)strcpy(s.a,w[1]);
        }
        else if(!strcmp(w[0],"read")) {
            s.kind=READ;
            strcpy(s.dest,w[1]);
        }
        else if(!strcmp(w[0],"call")) {
            s.kind=CALL;
            strcpy(s.target,w[1]);
            s.count=atoi(w[2]);
        }
        else if(strchr(w[0],'[')) {
            s.kind=STORE;
            array_operand(w[0],s.op,s.a);
            strcpy(s.b,w[2]);
        }
        else {
            strcpy(s.dest,w[0]);
            if(!strcmp(w[2],"call")) {
                s.kind=CALL;
                strcpy(s.target,w[3]);
                s.count=atoi(w[4]);
            }
            else if(strchr(w[2],'[')) {
                s.kind=LOAD;
                array_operand(w[2],s.op,s.a);
            }
            else if(n==3) {
                s.kind=COPY;
                strcpy(s.a,w[2]);
            }
            else {
                s.kind=BIN;
                strcpy(s.a,w[2]);
                strcpy(s.op,w[3]);
                strcpy(s.b,w[4]);
            }
        }
        normalize(s.a);
        normalize(s.b);
        code_add(fn,s);
    }
    fclose(f);
    return p;
}
Program program_copy(const Program *p) {
    Program r= {
        0
    };
    r.na=p->na;
    r.arrays=allocate((size_t)r.na*sizeof *r.arrays);
    memcpy(r.arrays,p->arrays,(size_t)r.na*sizeof *r.arrays);
    r.count=p->count;
    r.functions=allocate((size_t)r.count*sizeof *r.functions);
    for(int i=0;i<r.count;++i)r.functions[i]=function_copy(&p->functions[i]);
    return r;
}
void program_free(Program *p) {
    for(int i=0;i<p->count;++i)function_free(&p->functions[i]);
    free(p->functions);
    free(p->arrays);
}
void write_function(FILE *f,const Function *fn) {
    fprintf(f,"func %s",fn->name);
    for(int i=0;i<fn->np;++i)fprintf(f," %s",fn->params[i]);
    fputc('\n',f);
    for(int i=0;i<fn->count;++i) {
        char text[TEXT];
        instruction_text(&fn->code[i],text);
        fprintf(f,"%s%s\n",fn->code[i].kind<0?"":"    ",text);
    }
    fputs("end\n",f);
}
void write_program(FILE *f,const Program *p) {
    for(int i=0;i<p->na;++i)fprintf(f,"array %s %d\n",p->arrays[i].name,p->arrays[i].size);
    int written=0;
    for(int i=0;i<p->count;++i)if(!p->functions[i].removed) {
        if(written||p->na)fputc('\n',f);
        write_function(f,&p->functions[i]);
        written=1;
    }
}
