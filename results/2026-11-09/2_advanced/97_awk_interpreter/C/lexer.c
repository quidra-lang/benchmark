#include "awk.h"
void *mem_new(size_t n) {
    void *p=calloc(n?n:1,1);
    if(!p)exit(EXIT_FAILURE);
    return p;
}
void *mem_resize(void *p,size_t n) {
    void *q=realloc(p,n?n:1);
    if(!q)exit(EXIT_FAILURE);
    return q;
}
char *str_copy(const char *s) {
    char *p=mem_new(strlen(s)+1);
    strcpy(p,s);
    return p;
}
void buffer_add(Buffer *b,const char *s,size_t n) {
    if(b->length+n+1>b->capacity) {
        b->capacity=(b->length+n+1)*2;
        b->data=mem_resize(b->data,b->capacity);
    }
    memcpy(b->data+b->length,s,n);
    b->length+=n;
    b->data[b->length]=0;
}
void buffer_text(Buffer *b,const char *s) {
    buffer_add(b,s,strlen(s));
}
char *read_line(FILE *f) {
    Buffer b= {
        0
    };
    int c;
    while((c=fgetc(f))!=EOF&&c!='\n') {
        char x=(char)c;
        buffer_add(&b,&x,1);
    }
    if(c==EOF&&!b.length) {
        free(b.data);
        return NULL;
    }
    return b.data?b.data:str_copy("");
}
static int member(const char *s,const char *list) {
    char *copy=str_copy(list),*p=strtok(copy," ");
    int yes=0;
    while(p) {
        if(!strcmp(p,s))yes=1;
        p=strtok(NULL," ");
    }
    free(copy);
    return yes;
}
Tokens lex(const char *s) {
    Tokens result= {
        0
    };
    int i=0,line=1,col=1;
    while(s[i]) {
        char c=s[i];
        if(c==' ') {
            ++i;
            ++col;
            continue;
        }
        if(c=='\\'&&s[i+1]=='\n') {
            i+=2;
            ++line;
            col=1;
            continue;
        }
        if(c=='#') {
            while(s[i]&&s[i]!='\n') {
                ++i;
                ++col;
            }
            continue;
        }
        Token t= {
            .pos= {
                line,col
            }
        };
        int start=i;
        if(c=='\n') {
            t.kind=T_NL;
            t.text=str_copy("\n");
            ++i;
            ++line;
            col=1;
        }
        else if(isdigit((unsigned char)c)) {
            while(isdigit((unsigned char)s[i])) {
                ++i;
                ++col;
            }
            t.kind=T_NUMBER;
        }
        else if(isalpha((unsigned char)c)||c=='_') {
            while(isalnum((unsigned char)s[i])||s[i]=='_') {
                ++i;
                ++col;
            }
            t.kind=T_NAME;
        }
        else if(c=='"') {
            Buffer b= {
                0
            };
            ++i;
            ++col;
            int closed=0;
            while(s[i]&&s[i]!='\n') {
                if(s[i]=='"') {
                    ++i;
                    ++col;
                    closed=1;
                    break;
                }
                char v=s[i++];
                ++col;
                if(v=='\\') {
                    Position p= {
                        line,col-1
                    };
                    v=s[i];
                    if(v=='n')v='\n';
                    else if(v=='t')v='\t';
                    else if(v!='\\'&&v!='"'&&v!='/') {
                        result.failed=1;
                        result.error=p;
                        break;
                    }
                    ++i;
                    ++col;
                }
                buffer_add(&b,&v,1);
            }
            if(!result.failed&&!closed) {
                result.failed=1;
                result.error=t.pos;
            }
            t.kind=T_STRING;
            t.text=b.data?b.data:str_copy("");
        }
        else {
            static const char *symbols[]= {
                "+=","-=","*=","/=","%=","^=","==","<=",">=","!=","++","--","&&","||",">>",NULL
            };
            int length=0;
            for(int k=0;symbols[k];++k)if(!strncmp(s+i,symbols[k],2))length=2;
            if(!length&&strchr("+-*/%^!><?:=()[]{},;$",c))length=1;
            if(!length) {
                result.failed=1;
                result.error=t.pos;
                break;
            }
            i+=length;
            col+=length;
            t.kind=T_SYMBOL;
        }
        if(result.failed) {
            free(t.text);
            break;
        }
        if(!t.text) {
            t.text=mem_new((size_t)(i-start)+1);
            memcpy(t.text,s+start,(size_t)(i-start));
        }
        if(t.kind==T_NUMBER)t.number=strtoll(t.text,NULL,10);
        if(t.kind==T_NAME) {
            if(member(t.text,"BEGIN END function if else while for do break continue next exit return delete in getline print printf"))t.kind=T_KEYWORD;
            else if(member(t.text,"length substr index split sprintf toupper tolower close int"))t.kind=T_BUILTIN;
            else if(s[i]=='(')t.kind=T_FUNCTION;
        }
        result.tokens=mem_resize(result.tokens,(size_t)(result.count+1)*sizeof *result.tokens);
        result.tokens[result.count++]=t;
    }
    Token eof= {
        .kind=T_EOF,.text=str_copy(""),.pos= {
            line,1
        }
    };
    result.tokens=mem_resize(result.tokens,(size_t)(result.count+1)*sizeof *result.tokens);
    result.tokens[result.count++]=eof;
    return result;
}
