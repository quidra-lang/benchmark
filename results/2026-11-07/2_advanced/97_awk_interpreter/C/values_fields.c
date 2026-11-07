#include "awk.h"
static Text *text_new(const char *s) {
    Text *t=mem_new(sizeof *t+strlen(s)+1);
    t->refs=1;
    strcpy(t->data,s);
    return t;
}
Value number(long long n) {
    return (Value) {
        .kind=1,.number=n
    };
}
Value string(const char *s) {
    return (Value) {
        .kind=2,.text=text_new(s)
    };
}
Value value_copy(Value v) {
    if(v.text)++v.text->refs;
    return v;
}
void value_free(Value v) {
    if(v.text&&!--v.text->refs)free(v.text);
}
static int whitespace(int c) {
    return c==' '||c=='\t'||c=='\n';
}
static long long parse_number(const char *s) {
    while(whitespace(*s))++s;
    int sign=1;
    if(*s=='+'||*s=='-') {
        if(*s=='-')sign=-1;
        ++s;
    }
    long long n=0;
    while(isdigit((unsigned char)*s))n=n*10+*s++-'0';
    return sign*n;
}
Value input_value(const char *s) {
    Value v=string(s);
    const char *p=s;
    while(whitespace(*p))++p;
    if(*p=='+'||*p=='-')++p;
    const char *start=p;
    while(isdigit((unsigned char)*p))++p;
    int digits=p>start;
    while(whitespace(*p))++p;
    if(digits&&!*p) {
        v.kind=3;
        v.number=parse_number(s);
    }
    return v;
}
long long numeric(Value v) {
    return v.kind==0?0:v.kind==1||v.kind==3?v.number:parse_number(v.text->data);
}
char *textual(Value v) {
    if(v.kind==0)return str_copy("");
    if(v.text)return str_copy(v.text->data);
    char text[40];
    sprintf(text,"%lld",v.number);
    return str_copy(text);
}
int truth(Value v) {
    return v.kind==1||v.kind==3?v.number!=0:v.kind==2&&*v.text->data;
}
int compare(Value a,Value b) {
    if(a.kind!=2&&b.kind!=2) {
        long long x=numeric(a),y=numeric(b);
        return (x>y)-(x<y);
    }
    char *x=textual(a),*y=textual(b);
    int n=strcmp(x,y);
    free(x);
    free(y);
    return n;
}
void value_write(FILE *f,Value v) {
    if(!v.kind) {
        fputs("(uninitialized)",f);
        return;
    }
    if(v.kind==1) {
        fprintf(f,"%lld",v.number);
        return;
    }
    fputc('"',f);
    for(const unsigned char *s=(const unsigned char*)v.text->data;*s;++s) {
        if(*s=='"'||*s=='\\') {
            fputc('\\',f);
            fputc(*s,f);
        }
        else if(*s=='\n')fputs("\\n",f);
        else if(*s=='\t')fputs("\\t",f);
        else if(*s<32||*s>126)fprintf(f,"\\%03o",*s);
        else fputc(*s,f);
    }
    fputc('"',f);
    if(v.kind==3)fputs(" (strnum)",f);
}
static void piece(char ***items,int *count,const char *s,size_t n) {
    *items=mem_resize(*items,(size_t)(*count+1)*sizeof **items);
    char *p=mem_new(n+1);
    memcpy(p,s,n);
    (*items)[(*count)++]=p;
}
char **split_string(const char *s,const char *sep,int *count) {
    char **items=NULL;
    *count=0;
    if(!strcmp(sep," ")) {
        while(*s) {
            while(whitespace(*s))++s;
            const char *start=s;
            while(*s&&!whitespace(*s))++s;
            if(s>start)piece(&items,count,start,(size_t)(s-start));
        }
    }
    else if(!*sep) {
        for(;*s;++s)piece(&items,count,s,1);
    }
    else if(*s) {
        const char *start=s,*found;
        size_t length=strlen(sep);
        while((found=strstr(start,sep))) {
            piece(&items,count,start,(size_t)(found-start));
            start=found+length;
        }
        piece(&items,count,start,strlen(start));
    }
    return items;
}
static int integer_key(const char *s) {
    if(!strcmp(s,"0"))return 1;
    if(*s=='-')++s;
    if(*s<'1'||*s>'9')return 0;
    while(isdigit((unsigned char)*s))++s;
    return !*s;
}
int key_compare(const void *a,const void *b) {
    const char *x=*(const char*const*)a,*y=*(const char*const*)b;
    int ix=integer_key(x),iy=integer_key(y);
    if(ix!=iy)return ix?-1:1;
    if(ix) {
        long long nx=strtoll(x,NULL,10),ny=strtoll(y,NULL,10);
        return (nx>ny)-(nx<ny);
    }
    return strcmp(x,y);
}
void array_clear(Array *a) {
    for(int i=0;i<a->count;++i) {
        free(a->items[i]->key);
        value_free(a->items[i]->value);
        free(a->items[i]);
    }
    free(a->items);
    a->items=NULL;
    a->count=a->capacity=0;
}
Element *array_element(Array *a,const char *key,int create) {
    for(int i=0;i<a->count;++i)if(!strcmp(a->items[i]->key,key))return a->items[i];
    if(!create)return NULL;
    if(a->count==a->capacity) {
        a->capacity=a->capacity?2*a->capacity:8;
        a->items=mem_resize(a->items,(size_t)a->capacity*sizeof *a->items);
    }
    Element *e=mem_new(sizeof *e);
    e->key=str_copy(key);
    a->items[a->count++]=e;
    return e;
}
void array_delete(Array *a,const char *key) {
    for(int i=0;i<a->count;++i)if(!strcmp(a->items[i]->key,key)) {
        Element *e=a->items[i];
        free(e->key);
        value_free(e->value);
        free(e);
        memmove(a->items+i,a->items+i+1,(size_t)(a->count-i-1)*sizeof *a->items);
        --a->count;
        return;
    }
}
static char *special(Runtime *r,const char *name) {
    return textual(global_symbol(r,name)->global.value);
}
void set_record(Runtime *r,const char *s) {
    value_free(r->record);
    r->record=input_value(s);
    for(int i=0;i<r->nf;++i)value_free(r->fields[i]);
    free(r->fields);
    char *sep=special(r,"FS");
    int count;
    char **pieces=split_string(s,sep,&count);
    free(sep);
    r->fields=mem_new((size_t)count*sizeof *r->fields);
    r->nf=count;
    for(int i=0;i<count;++i) {
        r->fields[i]=input_value(pieces[i]);
        free(pieces[i]);
    }
    free(pieces);
}
void rebuild_record(Runtime *r) {
    char *sep=special(r,"OFS");
    Buffer b= {
        0
    };
    for(int i=0;i<r->nf;++i) {
        if(i)buffer_text(&b,sep);
        char *text=textual(r->fields[i]);
        buffer_text(&b,text);
        free(text);
    }
    value_free(r->record);
    r->record=input_value(b.data?b.data:"");
    free(b.data);
    free(sep);
}
void set_nf(Runtime *r,long long n,Position p) {
    if(n<0) {
        runtime_error(r,p,"negative NF");
        return;
    }
    for(int i=(int)n;i<r->nf;++i)value_free(r->fields[i]);
    r->fields=mem_resize(r->fields,(size_t)n*sizeof *r->fields);
    for(int i=r->nf;i<n;++i)r->fields[i]=string("");
    r->nf=(int)n;
    rebuild_record(r);
}
Value field_value(Runtime *r,long long index,Position p) {
    if(index<0) {
        runtime_error(r,p,"negative field index");
        return (Value) {
            0
        };
    }
    if(!index)return value_copy(r->record);
    return index<=r->nf?value_copy(r->fields[index-1]):(Value) {
        0
    };
}
void store_field(Runtime *r,long long index,Value v,Position p) {
    if(index<0) {
        runtime_error(r,p,"negative field index");
        return;
    }
    if(!index) {
        char *s=textual(v);
        set_record(r,s);
        free(s);
        return;
    }
    if(index>r->nf) {
        int old=r->nf;
        r->fields=mem_resize(r->fields,(size_t)index*sizeof *r->fields);
        for(int i=old;i<index;++i)r->fields[i]=string("");
        r->nf=(int)index;
    }
    value_free(r->fields[index-1]);
    r->fields[index-1]=value_copy(v);
    rebuild_record(r);
}
