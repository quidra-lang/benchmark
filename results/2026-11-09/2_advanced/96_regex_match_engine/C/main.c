#include "regex.h"
enum {
    N_CHAR, N_ANY, N_CLASS, N_ASSERT, N_REF, N_GROUP, N_LOOK, N_CAT, N_ALT, N_REP
};
typedef struct {
    Pattern *pattern;
    int position;
}
Parser;
typedef struct {
    long long min, max;
    Charset first;
    int nullable;
}
Properties;
typedef struct {
    char *name, *text;
}
Subject;
typedef struct {
    int reference;
    char *text;
}
Part;
typedef struct {
    Part *data;
    int count, valid;
}
Template;
void *checked_alloc(size_t n) {
    void *p = calloc(n ? n : 1, 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}
void *checked_realloc(void *p, size_t n) {
    void *q = realloc(p, n ? n : 1);
    if (!q) exit(EXIT_FAILURE);
    return q;
}
char *duplicate(const char *s) {
    size_t n = strlen(s)+1;
    char *r = checked_alloc(n);
    memcpy(r, s, n);
    return r;
}
char *read_line(FILE *f) {
    Buffer b = {
        0
    };
    int c;
    while ((c = fgetc(f)) != EOF && c != '\n') {
        char x = (char)c;
        append_bytes(&b, &x, 1);
    }
    if (c == EOF && !b.length) {
        free(b.data);
        return NULL;
    }
    if (!b.data) b.data = duplicate("");
    return b.data;
}
void append_bytes(Buffer *b, const char *s, size_t n) {
    if (b->length+n+1 > b->capacity) {
        b->capacity = (b->length+n+1)*2;
        b->data = checked_realloc(b->data, b->capacity);
    }
    memcpy(b->data+b->length, s, n);
    b->length += n;
    b->data[b->length] = 0;
}
void append_text(Buffer *b, const char *s) {
    append_bytes(b, s, strlen(s));
}
static Node *node(int type) {
    Node *n = checked_alloc(sizeof *n);
    n->type = type;
    return n;
}
static void child(Node *n, Node *c) {
    n->child = checked_realloc(n->child, (size_t)(n->count+1)*sizeof *n->child);
    n->child[n->count++] = c;
}
static void parse_error(Parser *r, const char *message, int column) {
    if (!r->pattern->error) {
        r->pattern->error = duplicate(message);
        r->pattern->error_column = column;
    }
}
static char next(Parser *r) {
    return r->pattern->text[r->position];
}
static int quantifier(int c) {
    return c == '*' || c == '+' || c == '?' || c == '{';
}
static char *read_name(Parser *r) {
    int start = r->position;
    if (isalpha((unsigned char)next(r)) || next(r) == '_') {
        ++r->position;
        while (isalnum((unsigned char)next(r)) || next(r) == '_') ++r->position;
    }
    int len = r->position-start;
    if (!len || next(r) != '>') {
        parse_error(r, "invalid group name", r->position+1);
        return duplicate("");
    }
    char *name = checked_alloc((size_t)len+1);
    memcpy(name, r->pattern->text+start, (size_t)len);
    ++r->position;
    return name;
}
static Node *alternation(Parser *r);
static int class_item(Parser *r, Charset *set, int *single) {
    int c = (unsigned char)next(r);
    ++r->position;
    if (c == '\\') {
        int column = r->position;
        c = (unsigned char)next(r);
        if (!c) {
            parse_error(r, "trailing backslash", column);
            return 0;
        }
        ++r->position;
        if (strchr("dDwWsS", c)) {
            *set = predefined(c);
            *single = -1;
            return 1;
        }
        if (c == 'n') c = '\n';
        else if (c == 't') c = '\t';
        else if (isalnum(c)) {
            parse_error(r, "invalid escape", column);
            return 0;
        }
    }
    set->bit[c] = 1;
    *single = c;
    return 1;
}
static Node *element(Parser *r) {
    int col = r->position+1;
    int c = (unsigned char)next(r);
    ++r->position;
    Node *n;
    if (c == '(') {
        int kind = 0, group = 0;
        char *name = NULL;
        if (next(r) == '?') {
            ++r->position;
            c = next(r);
            if (c == ':' || c == '=' || c == '!' || c == '<') {
                ++r->position;
                kind = c;
            }
            else {
                parse_error(r, "invalid group", col);
                return node(N_CAT);
            }
        }
        if (kind == '<') {
            int namecol = r->position+1;
            name = read_name(r);
            for (int k = 1; k <= r->pattern->groups; ++k) if (r->pattern->names[k] && !strcmp(name, r->pattern->names[k])) parse_error(r, "duplicate group name", namecol);
        }
        if (r->pattern->error) {
            free(name);
            return node(N_CAT);
        }
        if (!kind || kind == '<') {
            group = ++r->pattern->groups;
            r->pattern->names[group] = name;
        }
        Node *body = alternation(r);
        if (r->pattern->error) return body;
        if (next(r) != ')') {
            parse_error(r, "missing )", col);
            return body;
        }
        ++r->position;
        if (kind == ':') return body;
        n = node(group ? N_GROUP : N_LOOK);
        n->value = group ? group : kind == '=' ? L_AHEAD : L_NOT;
        child(n, body);
        return n;
    }
    if (c == '[') {
        n = node(N_CLASS);
        n->neg = next(r) == '^';
        if (n->neg) ++r->position;
        if (next(r) == ']') {
            parse_error(r, "empty class", r->position+1);
            return n;
        }
        while (!r->pattern->error) {
            if (!next(r)) {
                parse_error(r, "missing ]", col);
                break;
            }
            if (next(r) == ']') {
                ++r->position;
                break;
            }
            Charset s = {
                {
                    0
                }
            };
            int a;
            if (!class_item(r, &s, &a)) break;
            if (next(r) == '-' && r->pattern->text[r->position+1] && r->pattern->text[r->position+1] != ']') {
                int dash = ++r->position;
                if (a < 0) {
                    parse_error(r, "invalid range", dash);
                    break;
                }
                Charset t = {
                    {
                        0
                    }
                };
                int b;
                if (!class_item(r, &t, &b)) break;
                if (b < a) {
                    parse_error(r, "invalid range", dash);
                    break;
                }
                for (int k = a; k <= b; ++k) n->set.bit[k] = 1;
            }
            else for (int k = 0; k < 128; ++k) n->set.bit[k] |= s.bit[k];
        }
        return n;
    }
    if (c == '\\') {
        c = (unsigned char)next(r);
        if (!c) {
            parse_error(r, "trailing backslash", col);
            return node(N_CAT);
        }
        ++r->position;
        if (strchr("dDwWsS", c)) {
            n = node(N_CLASS);
            n->set = predefined(tolower(c));
            n->neg = isupper(c) != 0;
            return n;
        }
        if (c == 'b' || c == 'B') {
            n = node(N_ASSERT);
            n->value = c == 'b' ? A_WORD : A_NOTWORD;
            return n;
        }
        if (c >= '1' && c <= '9') {
            n = node(N_REF);
            n->value = c-'0';
            n->column = col;
            while (isdigit((unsigned char)next(r))) {
                n->value = 10*n->value+next(r)-'0';
                ++r->position;
            }
            return n;
        }
        if (c == 'k' && next(r) == '<') {
            ++r->position;
            n = node(N_REF);
            n->reference = read_name(r);
            n->column = col;
            return n;
        }
        if (c == 'n') c = '\n';
        else if (c == 't') c = '\t';
        else if (isalnum(c)) {
            parse_error(r, "invalid escape", col);
            return node(N_CAT);
        }
        n = node(N_CHAR);
        n->value = c;
        return n;
    }
    if (c == '.') return node(N_ANY);
    if (c == '^' || c == '$') {
        n = node(N_ASSERT);
        n->value = c == '^' ? A_BOL : A_EOL;
        return n;
    }
    n = node(N_CHAR);
    n->value = c;
    return n;
}
static Node *quantified(Parser *r) {
    if (quantifier(next(r))) {
        parse_error(r, "nothing to repeat", r->position+1);
        return node(N_CAT);
    }
    Node *e = element(r);
    if (r->pattern->error || !quantifier(next(r))) return e;
    if (e->type == N_ASSERT || e->type == N_LOOK) {
        parse_error(r, "nothing to repeat", r->position+1);
        return e;
    }
    int col = r->position+1, c = next(r);
    ++r->position;
    Node *n = node(N_REP);
    child(n, e);
    n->max = -1;
    if (c == '+') n->min = 1;
    else if (c == '?') n->max = 1;
    else if (c == '{') {
        if (!isdigit((unsigned char)next(r))) {
            parse_error(r, "invalid quantifier", col);
            return n;
        }
        while (isdigit((unsigned char)next(r))) {
            n->min = 10*n->min+next(r)-'0';
            ++r->position;
        }
        n->max = n->min;
        if (next(r) == ',') {
            ++r->position;
            n->max = 0;
            if (next(r) == '}') n->max = -1;
            else {
                if (!isdigit((unsigned char)next(r))) {
                    parse_error(r, "invalid quantifier", col);
                    return n;
                }
                while (isdigit((unsigned char)next(r))) {
                    n->max = 10*n->max+next(r)-'0';
                    ++r->position;
                }
            }
        }
        if (next(r) != '}') parse_error(r, "invalid quantifier", col);
        else {
            ++r->position;
            if (n->min > 100 || n->max > 100) parse_error(r, "quantifier too large", col);
            else if (n->max >= 0 && n->min > n->max) parse_error(r, "quantifier range out of order", col);
        }
    }
    if (r->pattern->error) return n;
    if (next(r) == '?' || next(r) == '+') {
        n->mode = next(r) == '?' ? 1 : 2;
        ++r->position;
    }
    if (quantifier(next(r))) parse_error(r, "nested quantifier", r->position+1);
    return n;
}
static Node *concatenation(Parser *r) {
    Node *n = node(N_CAT);
    while (next(r) && next(r) != '|' && next(r) != ')' && !r->pattern->error) child(n, quantified(r));
    if (n->count == 1) {
        Node *only = n->child[0];
        free(n->child);
        free(n);
        return only;
    }
    return n;
}
static Node *alternation(Parser *r) {
    Node *n = node(N_ALT);
    child(n, concatenation(r));
    while (!r->pattern->error && next(r) == '|') {
        ++r->position;
        child(n, concatenation(r));
    }
    if (n->count == 1) {
        Node *only = n->child[0];
        free(n->child);
        free(n);
        return only;
    }
    return n;
}
static void references(Parser *r, Node *n) {
    if (n->type == N_REF && !r->pattern->error) {
        if (n->reference) {
            for (int k = 1; k <= r->pattern->groups; ++k) if (r->pattern->names[k] && !strcmp(n->reference, r->pattern->names[k])) n->value = k;
            if (!n->value) parse_error(r, "unknown group name", n->column);
        }
        else if (n->value > r->pattern->groups) parse_error(r, "invalid group reference", n->column);
    }
    for (int k = 0; k < n->count; ++k) references(r, n->child[k]);
}
static int emit(Pattern *p, int op, int x, int y, int kind) {
    if (p->size == p->capacity) {
        p->capacity = p->capacity ? 2*p->capacity : 32;
        p->code = checked_realloc(p->code, (size_t)p->capacity*sizeof *p->code);
    }
    p->code[p->size] = (Instruction) {
        .op=op,.x=x,.y=y,.kind=kind
    };
    if (op == I_BACKREF || op == I_LOOK) p->compatible = 0;
    return p->size++;
}
static void compile(Pattern *p, Node *n) {
    switch (n->type) {
        case N_CHAR: emit(p,I_CHAR,n->value,0,0);
        break;
        case N_ANY: emit(p,I_ANY,0,0,0);
        break;
        case N_CLASS: {
            int i=emit(p,I_CLASS,0,0,0);
            p->code[i].set=n->set;
            p->code[i].neg=n->neg;
            break;
        }
        case N_ASSERT: emit(p,I_ASSERT,0,0,n->value);
        break;
        case N_REF: emit(p,I_BACKREF,n->value,0,0);
        break;
        case N_GROUP: emit(p,I_SAVE,2*n->value,0,0);
        compile(p,n->child[0]);
        emit(p,I_SAVE,2*n->value+1,0,0);
        break;
        case N_LOOK: {
            int i=emit(p,I_LOOK,0,0,n->value);
            compile(p,n->child[0]);
            emit(p,I_MATCH,0,0,0);
            p->code[i].x=p->size;
            break;
        }
        case N_CAT: for(int k=0;k<n->count;++k) compile(p,n->child[k]);
        break;
        case N_ALT: {
            int *jumps=checked_alloc((size_t)n->count*sizeof *jumps);
            for(int k=0;k<n->count;++k) {
                if(k==n->count-1) compile(p,n->child[k]);
                else {
                    int i=emit(p,I_SPLIT,p->size+1,0,0);
                    compile(p,n->child[k]);
                    jumps[k]=emit(p,I_JMP,0,0,0);
                    p->code[i].y=p->size;
                }
            }
            for(int k=0;k<n->count-1;++k) p->code[jumps[k]].x=p->size;
            free(jumps);
            break;
        }
        case N_REP: {
            if(n->mode==2) {
                int i=emit(p,I_LOOK,0,0,L_ATOMIC);
                Node greedy=*n;
                greedy.mode=0;
                compile(p,&greedy);
                emit(p,I_MATCH,0,0,0);
                p->code[i].x=p->size;
                break;
            }
            Node *e=n->child[0];
            int split, a, z;
            if(n->max<0 && !n->min) {
                split=emit(p,I_SPLIT,0,0,0);
                a=p->size;
                compile(p,e);
                emit(p,I_JMP,split,0,0);
                z=p->size;
                p->code[split].x=n->mode?z:a;
                p->code[split].y=n->mode?a:z;
            }
            else if(n->max<0) {
                for(int k=0;k<n->min-1;++k) compile(p,e);
                a=p->size;
                compile(p,e);
                split=emit(p,I_SPLIT,0,0,0);
                z=p->size;
                p->code[split].x=n->mode?z:a;
                p->code[split].y=n->mode?a:z;
            }
            else {
                for(int k=0;k<n->min;++k) compile(p,e);
                int *splits=checked_alloc((size_t)(n->max-n->min)*sizeof *splits);
                for(int k=0;k<n->max-n->min;++k) {
                    split=emit(p,I_SPLIT,0,0,0);
                    splits[k]=split;
                    a=p->size;
                    compile(p,e);
                    if(n->mode) p->code[split].y=a;
                    else p->code[split].x=a;
                }
                for(int k=0;k<n->max-n->min;++k) {
                    if(n->mode) p->code[splits[k]].x=p->size;
                    else p->code[splits[k]].y=p->size;
                }
                free(splits);
            }
            break;
        }
    }
}
static Properties properties(Pattern *p, Node *n) {
    Properties r= {
        0
    };
    r.nullable=1;
    if(n->type==N_CHAR || n->type==N_ANY || n->type==N_CLASS) {
        r.min=r.max=1;
        r.nullable=0;
        for(int c=0;c<128;++c) r.first.bit[c]=(unsigned char)(n->type==N_CHAR?equal_character(p,c,n->value):n->type==N_ANY?p->dotall||c!='\n':class_character(p,n->set,n->neg,c));
    }
    else if(n->type==N_REF) {
        r.max=-1;
        memset(r.first.bit,1,128);
    }
    else if(n->type==N_GROUP || n->type==N_REP) {
        r=properties(p,n->child[0]);
        if(n->type==N_REP) {
            r.min*=n->min;
            r.max=r.max==0?0:r.max<0||n->max<0?-1:r.max*n->max;
            r.nullable=r.nullable||!n->min;
            if(!n->max) {
                memset(r.first.bit,0,128);
                r.nullable=1;
            }
        }
    }
    else if(n->type==N_CAT || n->type==N_ALT) {
        r.nullable=n->type==N_CAT;
        for(int k=0;k<n->count;++k) {
            Properties a=properties(p,n->child[k]);
            if(n->type==N_CAT) {
                r.min+=a.min;
                r.max=r.max<0||a.max<0?-1:r.max+a.max;
            }
            else {
                if(!k||a.min<r.min)r.min=a.min;
                if(r.max<0||a.max<0)r.max=-1;
                else if(a.max>r.max)r.max=a.max;
            }
            if(n->type==N_ALT || r.nullable) for(int c=0;c<128;++c)r.first.bit[c]|=a.first.bit[c];
            r.nullable=n->type==N_CAT?r.nullable&&a.nullable:r.nullable||a.nullable;
        }
    }
    return r;
}
static char *decode(const char *s) {
    Buffer b= {
        0
    };
    for(size_t k=1;s[k]&&s[k]!='"';++k) {
        char c=s[k];
        if(c=='\\') {
            c=s[++k];
            if(c=='n')c='\n';
            else if(c=='t')c='\t';
        }
        append_bytes(&b,&c,1);
    }
    return b.data?b.data:duplicate("");
}
static void push_match(Matches *m,Capture c) {
    if(m->count==m->capacity) {
        m->capacity=m->capacity?m->capacity*2:8;
        m->data=checked_realloc(m->data,(size_t)m->capacity*sizeof *m->data);
    }
    m->data[m->count++]=c;
}
static Matches run(const Pattern *p,const char *s,int full,int scan,int pike,Meter *meter) {
    Matches matches= {
        0
    };
    int start=0,n=(int)strlen(s);
    while(start<=n) {
        Capture c;
        int found=pike?pike_search(p,s,start,full,meter,&c):backtrack_search(p,s,start,full,meter,&c);
        if(!found||meter->aborted)break;
        push_match(&matches,c);
        if(!scan)break;
        start=c.cap[1]+(c.cap[0]==c.cap[1]);
    }
    return matches;
}
static int named_group(Pattern *p,const char *s) {
    for(int k=1;k<=p->groups;++k)if(p->names[k]&&!strcmp(p->names[k],s))return k;
    return -1;
}
static Template parse_template(Pattern *p,const char *s) {
    Template t= {
        .valid=1
    };
    for(int k=0;s[k]&&t.valid;) {
        Part part= {
            .reference=-1
        };
        if(s[k]!='$') {
            part.text=checked_alloc(2);
            part.text[0]=s[k++];
        }
        else if(s[k+1]=='$') {
            part.text=duplicate("$");
            k+=2;
        }
        else if(isdigit((unsigned char)s[k+1])) {
            part.reference=s[k+1]-'0';
            k+=2;
        }
        else if(s[k+1]=='{') {
            int end=k+2;
            while(s[end]&&s[end]!='}')++end;
            if(!s[end]) {
                t.valid=0;
                break;
            }
            char *name=checked_alloc((size_t)(end-k-1));
            memcpy(name,s+k+2,(size_t)(end-k-2));
            int digits=*name!=0;
            for(int j=0;name[j];++j)if(!isdigit((unsigned char)name[j]))digits=0;
            part.reference=digits?atoi(name):named_group(p,name);
            free(name);
            k=end+1;
            if(part.reference<0)t.valid=0;
        }
        else {
            t.valid=0;
            break;
        }
        if(part.reference>p->groups)t.valid=0;
        t.data=checked_realloc(t.data,(size_t)(t.count+1)*sizeof *t.data);
        t.data[t.count++]=part;
    }
    return t;
}
static void match_lines(FILE *f,Pattern *p,const char *s,Capture c) {
    fprintf(f,"match %d-%d ",c.cap[0],c.cap[1]);
    quote(f,s+c.cap[0],(size_t)(c.cap[1]-c.cap[0]));
    fputc('\n',f);
    for(int k=1;k<=p->groups;++k) {
        fprintf(f,"group %d ",k);
        int a=c.cap[2*k],b=c.cap[2*k+1];
        if(a<0||b<0)fputs("-\n",f);
        else {
            fprintf(f,"%d-%d ",a,b);
            quote(f,s+a,(size_t)(b-a));
            fputc('\n',f);
        }
    }
}
static void program_listing(FILE *f,Pattern *p) {
    Properties v=properties(p,p->root);
    fprintf(f,"=== %s\nflags=%s groups=%d names=",p->name,p->flags,p->groups);
    int any=0;
    for(int k=1;k<=p->groups;++k)if(p->names[k]) {
        fprintf(f,"%s%s:%d",any?",":"",p->names[k],k);
        any=1;
    }
    if(!any)fputc('-',f);
    fprintf(f," length=%lld..",v.min);
    if(v.max<0)fputs("inf",f);
    else fprintf(f,"%lld",v.max);
    fputs(" first=",f);
    any=0;
    for(int c=0;c<128;++c)any|=v.first.bit[c];
    if(any)display_set(f,v.first,0);
    else fputc('-',f);
    fprintf(f," pike=%s size=%d\n",p->compatible?"yes":"no",p->size);
    for(int i=0;i<p->size;++i) {
        fprintf(f,"%d ",i);
        display_instruction(f,p->code[i]);
        fputc('\n',f);
    }
}
static void free_node(Node *n) {
    for(int k=0;k<n->count;++k)free_node(n->child[k]);
    free(n->reference);
    free(n->child);
    free(n);
}
int main(void) {
    FILE *pf=fopen("input/patterns.txt","r"),*sf=fopen("input/subjects.txt","r"),*cf=fopen("input/commands.txt","r");
    FILE *rf=fopen("output/results.txt","w"),*lf=fopen("output/programs.txt","w"),*tf=fopen("output/steps.csv","w"),*ef=fopen("output/errors.txt","w");
    if(!pf||!sf||!cf||!rf||!lf||!tf||!ef)return EXIT_FAILURE;
    Pattern *patterns=NULL;
    Subject *subjects=NULL;
    int np=0,ns=0,errors=0,listings=0;
    char *line;
    while((line=read_line(pf))) {
        patterns=checked_realloc(patterns,(size_t)(np+1)*sizeof *patterns);
        Pattern *p=&patterns[np++];
        memset(p,0,sizeof *p);
        char *a=strchr(line,' ');
        *a++=0;
        char *b=strchr(a,' ');
        *b++=0;
        p->name=duplicate(line);
        p->flags=duplicate(a);
        p->text=duplicate(b);
        p->insensitive=strchr(a,'i')!=NULL;
        p->multiline=strchr(a,'m')!=NULL;
        p->dotall=strchr(a,'s')!=NULL;
        Parser r= {
            p,0
        };
        p->root=alternation(&r);
        if(!p->error&&next(&r))parse_error(&r,"unmatched )",r.position+1);
        if(!p->error)references(&r,p->root);
        if(p->error) {
            ++errors;
            fprintf(ef,"%s: %s at column %d\n  %s\n  %*s^\n",p->name,p->error,p->error_column,p->text,p->error_column-1,"");
        }
        else {
            p->compatible=1;
            emit(p,I_SAVE,0,0,0);
            compile(p,p->root);
            emit(p,I_SAVE,1,0,0);
            emit(p,I_MATCH,0,0,0);
        }
        free(line);
    }
    if(!errors)fputs("no errors\n",ef);
    while((line=read_line(sf))) {
        subjects=checked_realloc(subjects,(size_t)(ns+1)*sizeof *subjects);
        char *a=strchr(line,' ');
        *a++=0;
        subjects[ns++]=(Subject) {
            duplicate(line),decode(a)
        };
        free(line);
    }
    fputs("command,engine,steps\n",tf);
    int command=0;
    while((line=read_line(cf))) {
        ++command;
        fprintf(rf,"#%d %s\n",command,line);
        char *copy=duplicate(line),*words[4]= {
            0
        };
        int nw=0;
        char *cursor=copy;
        while(nw<4&&cursor) {
            words[nw++]=cursor;
            char *space=strchr(cursor,' ');
            if(space) {
                *space=0;
                cursor=space+1;
            }
            else cursor=NULL;
        }
        int replace=!strcmp(words[0],"REPLACE"),list=!strcmp(words[0],"LIST");
        const char *pn=words[replace?2:1];
        Pattern *p=NULL;
        for(int i=0;i<np;++i)if(!strcmp(patterns[i].name,pn))p=&patterns[i];
        if(p->error) {
            fputs("invalid pattern\n",rf);
            free(copy);
            free(line);
            continue;
        }
        if(list) {
            fprintf(rf,"instructions %d\n",p->size);
            program_listing(lf,p);
            ++listings;
            free(copy);
            free(line);
            continue;
        }
        const char *sn=words[replace?3:2],*s="";
        for(int i=0;i<ns;++i)if(!strcmp(subjects[i].name,sn))s=subjects[i].text;
        Template tmpl= {
            0
        };
        char *template_text=NULL;
        if(replace) {
            template_text=decode(cursor);
            tmpl=parse_template(p,template_text);
        }
        if(replace&&!tmpl.valid)fputs("invalid template\n",rf);
        else {
            int full=!strcmp(words[0],"MATCH"),scan=!strcmp(words[0],"FINDALL")||!strcmp(words[0],"SPLIT")||(replace&&!strcmp(words[1],"ALL"));
            Meter bt= {
                0
            },pk= {
                0
            };
            Matches a=run(p,s,full,scan,0,&bt),b= {
                0
            };
            fprintf(tf,"%d,backtrack,%ld\n",command,bt.steps);
            if(p->compatible) {
                b=run(p,s,full,scan,1,&pk);
                fprintf(tf,"%d,pike,%ld\n",command,pk.steps);
            }
            int mismatch=0;
            if(p->compatible&&!bt.aborted) {
                mismatch=a.count!=b.count;
                for(int k=0;k<a.count&&!mismatch;++k)for(int j=0;j<2*p->groups+2;++j)if(a.data[k].cap[j]!=b.data[k].cap[j])mismatch=1;
            }
            Matches result=bt.aborted?b:a;
            if(mismatch)fputs("MISMATCH\n",rf);
            else if(bt.aborted&&!p->compatible)fputs("TOO_MANY_STEPS\n",rf);
            else {
                fprintf(rf,"engine %s\n",p->compatible?(bt.aborted?"pike (backtrack: TOO_MANY_STEPS)":"both"):"backtrack");
                if(!strcmp(words[0],"MATCH")||!strcmp(words[0],"SEARCH")) {
                    if(!result.count)fputs("no match\n",rf);
                    else match_lines(rf,p,s,result.data[0]);
                }
                else if(!strcmp(words[0],"FINDALL")) {
                    fprintf(rf,"matches %d\n",result.count);
                    for(int k=0;k<result.count;++k)match_lines(rf,p,s,result.data[k]);
                }
                else if(replace) {
                    Buffer out= {
                        0
                    };
                    int previous=0;
                    for(int k=0;k<result.count;++k) {
                        Capture c=result.data[k];
                        append_bytes(&out,s+previous,(size_t)(c.cap[0]-previous));
                        for(int j=0;j<tmpl.count;++j) {
                            Part t=tmpl.data[j];
                            if(t.reference<0)append_text(&out,t.text);
                            else {
                                int x=c.cap[2*t.reference],y=c.cap[2*t.reference+1];
                                if(x>=0&&y>=0)append_bytes(&out,s+x,(size_t)(y-x));
                            }
                        }
                        previous=c.cap[1];
                    }
                    append_text(&out,s+previous);
                    fprintf(rf,"replacements %d\nresult ",result.count);
                    quote(rf,out.data,out.length);
                    fputc('\n',rf);
                    free(out.data);
                }
                else {
                    fprintf(rf,"pieces %d\npiece ",result.count+1);
                    int previous=0;
                    for(int k=0;k<=result.count;++k) {
                        int end=k<result.count?result.data[k].cap[0]:(int)strlen(s);
                        quote(rf,s+previous,(size_t)(end-previous));
                        fputc('\n',rf);
                        if(k==result.count)break;
                        Capture c=result.data[k];
                        for(int j=1;j<=p->groups;++j) {
                            fprintf(rf,"group %d ",j);
                            int x=c.cap[2*j],y=c.cap[2*j+1];
                            if(x<0||y<0)fputc('-',rf);
                            else quote(rf,s+x,(size_t)(y-x));
                            fputc('\n',rf);
                        }
                        previous=c.cap[1];
                        fputs("piece ",rf);
                    }
                }
            }
            free(a.data);
            free(b.data);
        }
        for(int i=0;i<tmpl.count;++i)free(tmpl.data[i].text);
        free(tmpl.data);
        free(template_text);
        free(copy);
        free(line);
    }
    if(!listings)fputs("no programs\n",lf);
    for(int i=0;i<np;++i) {
        Pattern *p=&patterns[i];
        free_node(p->root);
        free(p->code);
        free(p->name);
        free(p->flags);
        free(p->text);
        free(p->error);
        for(int k=1;k<=p->groups;++k)free(p->names[k]);
    }
    for(int i=0;i<ns;++i) {
        free(subjects[i].name);
        free(subjects[i].text);
    }
    free(patterns);
    free(subjects);
    fclose(pf);
    fclose(sf);
    fclose(cf);
    fclose(rf);
    fclose(lf);
    fclose(tf);
    fclose(ef);
    return 0;
}
