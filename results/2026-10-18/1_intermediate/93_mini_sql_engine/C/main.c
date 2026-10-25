#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h>
#include <setjmp.h>
#include <inttypes.h>

static jmp_buf failure;

static void **arena;

static int allocations, arena_capacity;

static void *allocate(size_t size) {
    void *p = calloc(1, size ? size : 1);
    if (!p) exit(1);
    if (allocations == arena_capacity) {
        arena_capacity = arena_capacity ? arena_capacity * 2 : 256;
        arena = realloc(arena, (size_t)arena_capacity * sizeof(*arena));
        if (!arena) exit(1);
    }
    arena[allocations++] = p;
    return p;
}

static void clear_arena(void) {
    for (int i = 0; i < allocations; i++) free(arena[i]);
    allocations = 0;
}

static char *slice(const char *s, size_t n) {
    char *p = allocate(n + 1);
    memcpy(p, s, n);
    return p;
}

static char *copy(const char *s) {
    return slice(s, strlen(s));
}

static char *format(const char *pattern, ...) {
    va_list args, again;
    va_start(args, pattern);
    va_copy(again, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    char *s = allocate((size_t)n + 1);
    vsnprintf(s, (size_t)n + 1, pattern, again);
    va_end(again);
    return s;
}

static void error(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    fputs("ERROR: ", stdout);
    vprintf(pattern, args);
    putchar('\n');
    va_end(args);
    longjmp(failure, 1);
}
#define VECTOR(T, Name) typedef struct { T *v; int n, capacity; } Name
#define APPEND(a, x) do { if ((a).n == (a).capacity) { int cap = (a).capacity ? (a).capacity * 2 : 8; void *p = allocate((size_t)cap * sizeof(*(a).v)); if ((a).n) memcpy(p, (a).v, (size_t)(a).n * sizeof(*(a).v)); (a).v = p; (a).capacity = cap; } (a).v[(a).n++] = (x); } while (0)

typedef enum {
    NULL_VALUE, INTEGER_VALUE, TEXT_VALUE
} Type;

typedef struct {
    Type type;
    int64_t integer;
    char *text;
} Value;

static Value null_value(void) {
    return (Value){
        0,0,NULL
    };
}

static Value integer(int64_t n) {
    return (Value){
        INTEGER_VALUE,n,NULL
    };
}

static Value text(char *s) {
    return (Value){
        TEXT_VALUE,0,s
    };
}

static char *written(Value v) {
    return v.type == NULL_VALUE ? "NULL" : v.type == TEXT_VALUE ? v.text : format("%" PRId64, v.integer);
}

static int compare(Value a, Value b) {
    if (a.type == NULL_VALUE || b.type == NULL_VALUE) return (a.type != NULL_VALUE) - (b.type != NULL_VALUE);
    if (a.type == INTEGER_VALUE) return (a.integer > b.integer) - (a.integer < b.integer);
    int c = strcmp(a.text,b.text);
    return (c > 0) - (c < 0);
}

static int equal(Value a, Value b) {
    return a.type == b.type && compare(a,b) == 0;
}

static int truth(Value v) {
    return v.type != NULL_VALUE && v.integer != 0;
}

static Value logical_not(Value v) {
    return v.type == NULL_VALUE ? v : integer(!truth(v));
}

static int is(const char *a, const char *b) {
    return strcmp(a,b) == 0;
}

static int member(const char *s, const char *list) {
    size_t n = strlen(s);
    for (const char *p = list; *p;) {
        const char *q = strchr(p,' ');
        size_t len = q ? (size_t)(q-p) : strlen(p);
        if (len == n && !strncmp(s,p,n)) return 1;
        p += len;
        if (*p) p++;
    }
    return 0;
}

static const char *reserved = "SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT";

static const char *aggregates = "COUNT SUM MIN MAX AVG";

static const char *comparisons = "= <> != < <= > >=";

typedef struct {
    char kind;
    char *text, *key;
} Token;
VECTOR(Token, Tokens);

static Tokens tokens;

static int position;

static void tokenize(const char *s) {
    tokens = (Tokens){
        0
    };
    for (size_t i = 0; s[i];) {
        if (s[i] == ' ' || s[i] == '\n') {
            i++;
            continue;
        }
        if (s[i] == '-' && s[i+1] == '-') {
            while (s[i] && s[i] != '\n') i++;
            continue;
        }
        size_t start = i;
        char kind = 's';
        if (s[i] == '\'') {
            i++;
            while (s[i] != '\'') i++;
            i++;
            kind = 't';
        }
        else if (isdigit((unsigned char)s[i])) {
            while (isdigit((unsigned char)s[i])) i++;
            kind = 'i';
        }
        else if (isalpha((unsigned char)s[i]) || s[i] == '_') {
            while (isalnum((unsigned char)s[i]) || s[i] == '_') i++;
            kind = 'n';
        }
        else if (s[i+1] && ((s[i] == '<' && (s[i+1] == '>' || s[i+1] == '=')) || (s[i] == '!' && s[i+1] == '=') || (s[i] == '>' && s[i+1] == '=') || (s[i] == '|' && s[i+1] == '|'))) i += 2;
        else if (strchr("(),.;*/%+-=<>",s[i])) i++;
        else error("unexpected character '%c'",s[i]);
        char *raw = slice(s+start,i-start), *key = raw;
        if (kind == 'n') {
            char *upper = copy(raw);
            for (char *p = upper; *p; p++) *p = (char)toupper((unsigned char)*p);
            if (member(upper,reserved)) {
                kind = 'k';
                key = upper;
            }
        }
        APPEND(tokens,((Token){
            kind,raw,key
        }));
    }
    position = 0;
}

static Token peek(void) {
    return tokens.v[position < tokens.n ? position : tokens.n-1];
}

static Token take(void) {
    Token t = peek();
    position++;
    return t;
}

static int at(const char *key) {
    Token t = peek();
    return (t.kind == 's' || t.kind == 'k') && is(t.key,key);
}

static int at_any(const char *keys) {
    Token t = peek();
    return (t.kind == 's' || t.kind == 'k') && member(t.key,keys);
}

static int accept(const char *key) {
    if (!at(key)) return 0;
    position++;
    return 1;
}

static void syntax(void) {
    error("syntax error at '%s'",peek().text);
}

static void expect(const char *key) {
    if (!accept(key)) syntax();
}

static char *parse_name(void) {
    if (peek().kind != 'n') syntax();
    return take().text;
}

static int parse_integer(void) {
    if (peek().kind != 'i') syntax();
    return (int)strtol(take().text,NULL,10);
}

typedef struct Expr Expr;
VECTOR(Expr *, Expressions);

struct Expr {
    char kind;
    char *op, *table, *column, *written;
    Value literal;
    Expressions children;
    int index, negated, distinct;
};

static Expr *expression(char kind, char *op) {
    Expr *e = allocate(sizeof(*e));
    e->kind=kind;
    e->op=op;
    e->index=-1;
    return e;
}

static Expr *unary(char *op, Expr *child) {
    Expr *e=expression('u',op);
    APPEND(e->children,child);
    return e;
}

static Expr *binary(char *op, Expr *left, Expr *right) {
    Expr *e=expression('b',op);
    APPEND(e->children,left);
    APPEND(e->children,right);
    return e;
}

static Expr *parse_expr(void);

static Expr *parse_column(void) {
    char *n=parse_name();
    Expr *e=expression('c',NULL);
    e->column=n;
    e->written=n;
    if (accept(".")) {
        e->table=n;
        e->column=parse_name();
        e->written=format("%s.%s",n,e->column);
    }
    return e;
}

static Expressions expression_list(void) {
    Expressions list={
        0
    };
    do {
        APPEND(list,parse_expr());
    } while (accept(","));
    return list;
}

static Expr *parse_primary(void) {
    if (peek().kind == 'i') {
        Expr *e=expression('l',NULL);
        e->literal=integer(strtoll(take().text,NULL,10));
        return e;
    }
    if (peek().kind == 't') {
        Expr *e=expression('l',NULL);
        char *s=take().text;
        e->literal=text(slice(s+1,strlen(s)-2));
        return e;
    }
    if (accept("NULL")) return expression('l',NULL);
    if (peek().kind == 'n') return parse_column();
    if (at_any(aggregates)) {
        char *name=take().key;
        Expr *e=expression('a',name);
        expect("(");
        if (!(is(name,"COUNT") && accept("*"))) {
            e->distinct=accept("DISTINCT");
            APPEND(e->children,parse_expr());
        }
        expect(")");
        return e;
    }
    if (accept("(")) {
        Expr *e=parse_expr();
        expect(")");
        return e;
    }
    syntax();
    return NULL;
}

static Expr *parse_unary(void) {
    return accept("-") ? unary("-",parse_unary()) : parse_primary();
}

static Expr *parse_binary(const char *ops, Expr *(*operand)(void)) {
    Expr *e=operand();
    while (at_any(ops)) {
        char *op=take().key;
        Expr *right=operand();
        e=binary(op,e,right);
    }
    return e;
}

static Expr *parse_multiplicative(void) {
    return parse_binary("* / %",parse_unary);
}

static Expr *parse_additive(void) {
    return parse_binary("+ - ||",parse_multiplicative);
}

static Expr *parse_comparison(void) {
    Expr *left=parse_additive(), *e=NULL;
    if (at_any(comparisons)) {
        char *op=take().key;
        return binary(op,left,parse_additive());
    }
    if (accept("IS")) {
        e=expression('z',NULL);
        e->negated=accept("NOT");
        expect("NULL");
        APPEND(e->children,left);
        return e;
    }
    int negated=accept("NOT");
    if (accept("IN")) {
        e=expression('i',NULL);
        APPEND(e->children,left);
        expect("(");
        Expressions items=expression_list();
        for (int i=0;i<items.n;i++) APPEND(e->children,items.v[i]);
        expect(")");
    } else if (accept("BETWEEN")) {
        e=expression('r',NULL);
        APPEND(e->children,left);
        APPEND(e->children,parse_additive());
        expect("AND");
        APPEND(e->children,parse_additive());
    } else if (accept("LIKE")) {
        e=expression('p',NULL);
        APPEND(e->children,left);
        APPEND(e->children,parse_additive());
    }
    else if (negated) syntax();
    if (!e) return left;
    e->negated=negated;
    return e;
}

static Expr *parse_not(void) {
    return accept("NOT") ? unary("NOT",parse_not()) : parse_comparison();
}

static Expr *parse_and(void) {
    return parse_binary("AND",parse_not);
}

static Expr *parse_expr(void) {
    return parse_binary("OR",parse_and);
}

static char *parse_alias(void) {
    if (accept("AS")) return parse_name();
    return peek().kind == 'n' ? take().text : NULL;
}

typedef struct {
    char *name;
    Type type;
    int not_null, keys;
} Column;
VECTOR(Column, Columns);
VECTOR(char *, Names);

typedef struct {
    char *name, *alias;
} TableRef;

static TableRef parse_table_ref(void) {
    char *name=parse_name();
    return (TableRef){
        name,parse_alias()
    };
}

typedef struct {
    TableRef table;
    int outer;
    Expr *condition;
} Join;
VECTOR(Join, Joins);

typedef struct {
    Expr *expr;
    char *alias, *heading;
} Item;
VECTOR(Item, Items);

typedef struct {
    Expr *expr;
    int start, count, descending;
} Order;
VECTOR(Order, Orders);

typedef struct {
    char *name;
    Expr *expr;
} Assignment;
VECTOR(Assignment, Assignments);
VECTOR(Expressions, Tuples);

typedef struct {
    char *command, *name;
    Columns columns;
    Names names;
    int specified_names, distinct, star, limit, offset;
    Tuples tuples;
    Assignments assignments;
    Expr *where, *having;
    TableRef source;
    Joins joins;
    Items items;
    Expressions grouping;
    Orders orders;
} Statement;

static Expr *parse_clause(const char *key) {
    return accept(key) ? parse_expr() : NULL;
}

static char *heading(int start, int end) {
    size_t length=1;
    for (int i=start;i<end;i++) length+=strlen(tokens.v[i].text)+1;
    char *s=allocate(length);
    for (int i=start;i<end;i++) {
        if (i>start && tokens.v[i-1].kind != 's' && tokens.v[i].kind != 's') strcat(s," ");
        strcat(s,tokens.v[i].text);
    }
    return s;
}

static Statement parse_statement(void) {
    Statement s={
        0
    };
    s.command="";
    s.limit=-1;
    if (accept("CREATE")) {
        s.command="CREATE";
        expect("TABLE");
        s.name=parse_name();
        expect("(");
        do {
            char *name=parse_name();
            if (!at_any("INT TEXT")) syntax();
            Type type=is(take().key,"INT") ? INTEGER_VALUE : TEXT_VALUE;
            int keys=0, nn=0;
            while (at_any("PRIMARY NOT")) {
                if (accept("PRIMARY")) {
                    expect("KEY");
                    keys++;
                } else {
                    expect("NOT");
                    expect("NULL");
                    nn=1;
                }
            }
            APPEND(s.columns,((Column){
                name,type,nn || keys>0,keys
            }));
        } while (accept(","));
        expect(")");
    } else if (accept("DROP")) {
        s.command="DROP";
        expect("TABLE");
        s.name=parse_name();
    }
    else if (accept("INSERT")) {
        s.command="INSERT";
        expect("INTO");
        s.name=parse_name();
        if (accept("(")) {
            s.specified_names=1;
            do {
                APPEND(s.names,parse_name());
            } while (accept(","));
            expect(")");
        }
        expect("VALUES");
        do {
            expect("(");
            APPEND(s.tuples,expression_list());
            expect(")");
        } while (accept(","));
    } else if (accept("UPDATE")) {
        s.command="UPDATE";
        s.name=parse_name();
        expect("SET");
        do {
            char *name=parse_name();
            expect("=");
            Expr *e=parse_expr();
            APPEND(s.assignments,((Assignment){
                name,e
            }));
        } while (accept(","));
        s.where=parse_clause("WHERE");
    } else if (accept("DELETE")) {
        s.command="DELETE";
        expect("FROM");
        s.name=parse_name();
        s.where=parse_clause("WHERE");
    }
    else if (accept("SELECT")) {
        s.command="SELECT";
        s.distinct=accept("DISTINCT");
        s.star=accept("*");
        if (!s.star) do {
            int start=position;
            Expr *e=parse_expr();
            int end=position;
            char *alias=parse_alias();
            char *h=alias ? alias : e->kind == 'c' && tokens.v[start].kind == 'n' ? e->column : heading(start,end);
            APPEND(s.items,((Item){
                e,alias,h
            }));
        } while (accept(","));
        expect("FROM");
        s.source=parse_table_ref();
        while (at_any("JOIN INNER LEFT")) {
            int outer=accept("LEFT");
            accept(outer ? "OUTER" : "INNER");
            expect("JOIN");
            TableRef ref=parse_table_ref();
            expect("ON");
            Expr *condition=parse_expr();
            APPEND(s.joins,((Join){
                ref,outer,condition
            }));
        }
        s.where=parse_clause("WHERE");
        if (accept("GROUP")) {
            expect("BY");
            do {
                APPEND(s.grouping,parse_column());
            } while (accept(","));
        }
        s.having=parse_clause("HAVING");
        if (accept("ORDER")) {
            expect("BY");
            do {
                int start=position;
                Expr *e=parse_expr();
                int count=position-start, desc=accept("DESC");
                if (!desc) accept("ASC");
                APPEND(s.orders,((Order){
                    e,start,count,desc
                }));
            } while (accept(","));
        }
        if (accept("LIMIT")) {
            s.limit=parse_integer();
            if (accept("OFFSET")) s.offset=parse_integer();
        }
    } else if (accept("EXIT")) s.command="EXIT";
    expect(";");
    return s;
}
VECTOR(Value *, Rows);

typedef struct {
    char *name;
    Columns columns;
    Rows rows;
} Table;

static Table *database[20];

static int table_count;

static Table *lookup(char *name) {
    for (int i=0;i<table_count;i++) if (is(database[i]->name,name)) return database[i];
    error("unknown table %s",name);
    return NULL;
}

static int column_index(Table *t, char *name) {
    for (int i=0;i<t->columns.n;i++) if (is(t->columns.v[i].name,name)) return i;
    return -1;
}

static char *persist_string(const char *s) {
    size_t n=strlen(s)+1;
    char *p=malloc(n);
    if (!p) exit(1);
    memcpy(p,s,n);
    return p;
}

static Table *persist_table(Table *t) {
    Table *p=calloc(1,sizeof(*p));
    if (!p) exit(1);
    p->name=persist_string(t->name);
    p->columns.n=t->columns.n;
    p->columns.v=calloc((size_t)p->columns.n,sizeof(Column));
    p->rows.n=t->rows.n;
    p->rows.v=calloc((size_t)p->rows.n,sizeof(Value *));
    if (!p->columns.v || (!p->rows.v && p->rows.n)) exit(1);
    for (int i=0;i<p->columns.n;i++) {
        p->columns.v[i]=t->columns.v[i];
        p->columns.v[i].name=persist_string(t->columns.v[i].name);
    }
    for (int i=0;i<p->rows.n;i++) {
        p->rows.v[i]=malloc((size_t)p->columns.n*sizeof(Value));
        if (!p->rows.v[i]) exit(1);
        for (int j=0;j<p->columns.n;j++) {
            p->rows.v[i][j]=t->rows.v[i][j];
            if (p->rows.v[i][j].type == TEXT_VALUE) p->rows.v[i][j].text=persist_string(p->rows.v[i][j].text);
        }
    }
    return p;
}

static void destroy_table(Table *t) {
    free(t->name);
    for (int i=0;i<t->columns.n;i++) free(t->columns.v[i].name);
    for (int i=0;i<t->rows.n;i++) {
        for (int j=0;j<t->columns.n;j++) if (t->rows.v[i][j].type == TEXT_VALUE) free(t->rows.v[i][j].text);
        free(t->rows.v[i]);
    }
    free(t->columns.v);
    free(t->rows.v);
    free(t);
}

static void replace_table(Table *original, Table *modified) {
    Table *saved=persist_table(modified);
    for (int i=0;i<table_count;i++) if (database[i] == original) {
        database[i]=saved;
        destroy_table(original);
        return;
    }
}

typedef struct {
    char *name;
    Table *table;
    int offset;
} Entry;
VECTOR(Entry, Entries);

typedef struct {
    Entries entries;
    int width;
} Scope;

static void add_scope(Scope *scope, char *name, Table *table) {
    for (int i=0;i<scope->entries.n;i++) if (is(scope->entries.v[i].name,name)) error("duplicate table name %s",name);
    APPEND(scope->entries,((Entry){
        name,table,scope->width
    }));
    scope->width+=table->columns.n;
}

static Type resolve(Expr *e, Scope *scope) {
    int count=0, found_table=0;
    Type type=NULL_VALUE;
    for (int i=0;i<scope->entries.n;i++) {
        Entry entry=scope->entries.v[i];
        if (e->table && !is(e->table,entry.name)) continue;
        found_table=1;
        int j=column_index(entry.table,e->column);
        if (j>=0) {
            count++;
            e->index=entry.offset+j;
            type=entry.table->columns.v[j].type;
        }
    }
    if (e->table && !found_table) error("unknown table %s",e->table);
    if (!count) error("unknown column %s",e->written);
    if (count>1) error("ambiguous column %s",e->column);
    return type;
}

static void require(Type a, Type b, const char *op) {
    if (a != b && a != NULL_VALUE && b != NULL_VALUE) error("type mismatch for %s",op);
}

static Type check(Expr *e, Scope *scope, int allowed, Expressions *grouped, int inside) {
    if (e->kind == 'l') return e->literal.type;
    if (e->kind == 'c') {
        Type t=resolve(e,scope);
        if (grouped && !inside) {
            int found=0;
            for (int i=0;i<grouped->n;i++) if (grouped->v[i]->index == e->index) found=1;
            if (!found) error("column %s is not grouped",e->written);
        }
        return t;
    }
    if (e->kind == 'a') {
        if (!allowed || inside) error("misuse of aggregate %s",e->op);
        if (!e->children.n) return INTEGER_VALUE;
        Type t=check(e->children.v[0],scope,allowed,grouped,1);
        if (member(e->op,"SUM AVG")) require(t,INTEGER_VALUE,e->op);
        return member(e->op,"MIN MAX") ? t : INTEGER_VALUE;
    }
    Type *types=allocate((size_t)e->children.n*sizeof(Type));
    for (int i=0;i<e->children.n;i++) types[i]=check(e->children.v[i],scope,allowed,grouped,inside);
    if (e->kind == 'u') require(types[0],INTEGER_VALUE,e->op);
    else if (e->kind == 'b') {
        if (member(e->op,comparisons)) require(types[0],types[1],e->op);
        else {
            Type t=is(e->op,"||") ? TEXT_VALUE : INTEGER_VALUE;
            require(types[0],t,e->op);
            require(types[1],t,e->op);
            return t;
        }
    } else if (e->kind == 'i' || e->kind == 'r') {
        for (int i=1;i<e->children.n;i++) require(types[i],types[0],e->kind == 'i' ? "IN" : "BETWEEN");
    } else if (e->kind == 'p') {
        require(types[0],TEXT_VALUE,"LIKE");
        require(types[1],TEXT_VALUE,"LIKE");
    }
    return INTEGER_VALUE;
}

static void condition(Expr *e, Scope *scope, const char *clause, int allowed, Expressions *grouped) {
    if (e) require(check(e,scope,allowed,grouped,0),INTEGER_VALUE,clause);
}

static int has_aggregate(Expr *e) {
    if (e->kind == 'a') return 1;
    for (int i=0;i<e->children.n;i++) if (has_aggregate(e->children.v[i])) return 1;
    return 0;
}

static Value operation(char *op, Value a, Value b) {
    if (is(op,"AND")) return (a.type != NULL_VALUE && !a.integer) || (b.type != NULL_VALUE && !b.integer) ? integer(0) : a.type == NULL_VALUE || b.type == NULL_VALUE ? null_value() : integer(1);
    if (is(op,"OR")) return truth(a) || truth(b) ? integer(1) : a.type == NULL_VALUE || b.type == NULL_VALUE ? null_value() : integer(0);
    if (a.type == NULL_VALUE || b.type == NULL_VALUE) return null_value();
    if (is(op,"+")) return integer(a.integer+b.integer);
    if (is(op,"-")) return integer(a.integer-b.integer);
    if (is(op,"*")) return integer(a.integer*b.integer);
    if (is(op,"/")) return b.integer ? integer(a.integer/b.integer) : null_value();
    if (is(op,"%")) return b.integer ? integer(a.integer%b.integer) : null_value();
    if (is(op,"||")) return text(format("%s%s",a.text,b.text));
    int c=compare(a,b);
    if (is(op,"=")) return integer(c==0);
    if (is(op,"!=") || is(op,"<>")) return integer(c!=0);
    if (is(op,"<")) return integer(c<0);
    if (is(op,"<=")) return integer(c<=0);
    if (is(op,">")) return integer(c>0);
    return integer(c>=0);
}

static int like_match(char *s, char *pattern) {
    size_t n=strlen(s);
    unsigned char *matched=allocate(n+1);
    matched[0]=1;
    for (char *p=pattern; *p; p++) {
        if (*p == '%') {
            for (size_t i=1;i<=n;i++) matched[i]=matched[i] || matched[i-1];
        }
        else {
            for (size_t i=n;i>0;i--) matched[i]=matched[i-1] && (*p == '_' || *p == s[i-1]);
            matched[0]=0;
        }
    }
    return matched[n];
}

static Value evaluate(Expr *e, Value *row, Rows *group) {
    if (e->kind == 'l') return e->literal;
    if (e->kind == 'c') return row[e->index];
    if (e->kind == 'a') {
        if (!e->children.n) return integer(group->n);
        Value *values=allocate((size_t)group->n*sizeof(Value));
        int n=0;
        for (int i=0;i<group->n;i++) {
            Value v=evaluate(e->children.v[0],group->v[i],NULL);
            if (v.type == NULL_VALUE) continue;
            int seen=0;
            if (e->distinct) for (int j=0;j<n;j++) if (equal(v,values[j])) seen=1;
            if (!seen) values[n++]=v;
        }
        if (is(e->op,"COUNT")) return integer(n);
        if (!n) return null_value();
        Value result=values[0];
        int64_t sum=0;
        for (int i=0;i<n;i++) {
            sum+=values[i].integer;
            if ((is(e->op,"MIN") && compare(values[i],result)<0) || (is(e->op,"MAX") && compare(values[i],result)>0)) result=values[i];
        }
        if (member(e->op,"MIN MAX")) return result;
        return integer(is(e->op,"AVG") ? sum/n : sum);
    }
    Value *v=allocate((size_t)e->children.n*sizeof(Value));
    for (int i=0;i<e->children.n;i++) v[i]=evaluate(e->children.v[i],row,group);
    if (e->kind == 'u') return is(e->op,"NOT") ? logical_not(v[0]) : v[0].type == NULL_VALUE ? null_value() : integer(-v[0].integer);
    if (e->kind == 'b') return operation(e->op,v[0],v[1]);
    Value result=null_value();
    if (e->kind == 'z') result=integer(v[0].type == NULL_VALUE);
    else if (e->kind == 'i' && v[0].type != NULL_VALUE) {
        result=integer(0);
        int unknown=0, matched=0;
        for (int i=1;i<e->children.n;i++) {
            if (v[i].type == NULL_VALUE) unknown=1;
            else if (equal(v[0],v[i])) matched=1;
        }
        result=matched ? integer(1) : unknown ? null_value() : integer(0);
    } else if (e->kind == 'r') result=operation("AND",operation(">=",v[0],v[1]),operation("<=",v[0],v[2]));
    else if (e->kind == 'p' && v[0].type != NULL_VALUE && v[1].type != NULL_VALUE) result=integer(like_match(v[0].text,v[1].text));
    return e->negated ? logical_not(result) : result;
}

static int *targets(Names names, Table *t) {
    int *indices=allocate((size_t)names.n*sizeof(int));
    for (int i=0;i<names.n;i++) {
        int index=column_index(t,names.v[i]);
        if (index<0) error("unknown column %s",names.v[i]);
        for (int j=0;j<i;j++) if (indices[j]==index) error("duplicate column %s",names.v[i]);
        indices[i]=index;
    }
    return indices;
}

static void constraints(Table *t, int *indices, int n) {
    int key=-1;
    for (int j=0;j<t->columns.n;j++) if (t->columns.v[j].keys) key=j;
    for (int a=0;a<n;a++) {
        int i=indices[a];
        for (int j=0;j<t->columns.n;j++) if (t->columns.v[j].not_null && t->rows.v[i][j].type == NULL_VALUE) error("NULL value in column %s",t->columns.v[j].name);
        if (key>=0) for (int j=0;j<t->rows.n;j++) if (i!=j && equal(t->rows.v[i][key],t->rows.v[j][key])) error("duplicate primary key %s",written(t->rows.v[i][key]));
    }
}

static int equal_rows(Value *a, Value *b, int n) {
    for (int i=0;i<n;i++) if (!equal(a[i],b[i])) return 0;
    return 1;
}

typedef struct {
    Value *values, *keys;
    int ordinal;
} Result;
VECTOR(Result, Results);

static Orders sort_orders;

static int result_compare(const void *left, const void *right) {
    const Result *a=left, *b=right;
    for (int i=0;i<sort_orders.n;i++) {
        int c=compare(a->keys[i],b->keys[i]);
        if (c) return sort_orders.v[i].descending ? -c : c;
    }
    return (a->ordinal>b->ordinal)-(a->ordinal<b->ordinal);
}

static void print_separator(int *widths, int n) {
    putchar('+');
    for (int i=0;i<n;i++) {
        for (int j=0;j<widths[i]+2;j++) putchar('-');
        putchar('+');
    } putchar('\n');
}

static void print_table(Items items, Type *types, Results results, int offset, int limit) {
    int start=offset<results.n ? offset : results.n, n=results.n-start;
    if (limit>=0 && n>limit) n=limit;
    int *widths=allocate((size_t)items.n*sizeof(int));
    for (int j=0;j<items.n;j++) widths[j]=(int)strlen(items.v[j].heading);
    for (int i=start;i<start+n;i++) for (int j=0;j<items.n;j++) {
        int len=(int)strlen(written(results.v[i].values[j]));
        if (len>widths[j]) widths[j]=len;
    }
    print_separator(widths,items.n);
    putchar('|');
    for (int j=0;j<items.n;j++) printf(" %-*s |",widths[j],items.v[j].heading);
    putchar('\n');
    print_separator(widths,items.n);
    for (int i=start;i<start+n;i++) {
        putchar('|');
        for (int j=0;j<items.n;j++) printf(types[j] == INTEGER_VALUE ? " %*s |" : " %-*s |",widths[j],written(results.v[i].values[j]));
        putchar('\n');
    }
    print_separator(widths,items.n);
    printf("(%d %s)\n",n,n==1 ? "row" : "rows");
}

static void execute_select(Statement *s) {
    Scope scope={
        0
    };
    Table **tables=allocate((size_t)(s->joins.n+1)*sizeof(Table *));
    for (int i=0;i<=s->joins.n;i++) {
        TableRef r=i ? s->joins.v[i-1].table : s->source;
        tables[i]=lookup(r.name);
        add_scope(&scope,r.alias ? r.alias : r.name,tables[i]);
        if (i) condition(s->joins.v[i-1].condition,&scope,"ON",0,NULL);
    }
    condition(s->where,&scope,"WHERE",0,NULL);
    for (int i=0;i<s->grouping.n;i++) resolve(s->grouping.v[i],&scope);
    int aggregate=s->grouping.n>0 || s->having;
    for (int i=0;i<s->items.n;i++) if (has_aggregate(s->items.v[i].expr)) aggregate=1;
    for (int i=0;i<s->orders.n;i++) if (has_aggregate(s->orders.v[i].expr)) aggregate=1;
    Expressions *grouped=aggregate ? &s->grouping : NULL;
    if (s->star) for (int i=0;i<scope.entries.n;i++) {
        Entry entry=scope.entries.v[i];
        for (int j=0;j<entry.table->columns.n;j++) {
            Column c=entry.table->columns.v[j];
            Expr *e=expression('c',NULL);
            e->table=entry.name;
            e->column=c.name;
            e->written=c.name;
            APPEND(s->items,((Item){
                e,NULL,c.name
            }));
        }
    }
    Type *types=allocate((size_t)s->items.n*sizeof(Type));
    for (int i=0;i<s->items.n;i++) types[i]=check(s->items.v[i].expr,&scope,1,grouped,0);
    condition(s->having,&scope,"HAVING",1,grouped);
    Expressions keys={
        0
    };
    for (int i=0;i<s->orders.n;i++) {
        Order order=s->orders.v[i];
        Token first=tokens.v[order.start];
        Expr *key=NULL;
        if (order.count==1 && first.kind=='i') {
            int k=(int)strtol(first.text,NULL,10);
            if (k<1 || k>s->items.n) error("ORDER BY position %d is out of range",k);
            key=s->items.v[k-1].expr;
        }
        else if (order.count==1 && first.kind=='n') for (int j=0;j<s->items.n;j++) if (s->items.v[j].alias && is(s->items.v[j].alias,first.text)) {
            key=s->items.v[j].expr;
            break;
        }
        if (!key) {
            check(order.expr,&scope,1,grouped,0);
            key=order.expr;
        }
        APPEND(keys,key);
    }
    Rows rows=tables[0]->rows;
    int width=tables[0]->columns.n;
    for (int j=0;j<s->joins.n;j++) {
        Rows next={
            0
        };
        Join join=s->joins.v[j];
        Table *right=tables[j+1];
        for (int l=0;l<rows.n;l++) {
            int matched=0;
            for (int r=0;r<right->rows.n;r++) {
                Value *combined=allocate((size_t)(width+right->columns.n)*sizeof(Value));
                memcpy(combined,rows.v[l],(size_t)width*sizeof(Value));
                memcpy(combined+width,right->rows.v[r],(size_t)right->columns.n*sizeof(Value));
                if (truth(evaluate(join.condition,combined,NULL))) {
                    APPEND(next,combined);
                    matched=1;
                }
            }
            if (!matched && join.outer) {
                Value *combined=allocate((size_t)(width+right->columns.n)*sizeof(Value));
                memcpy(combined,rows.v[l],(size_t)width*sizeof(Value));
                APPEND(next,combined);
            }
        }
        rows=next;
        width+=right->columns.n;
    }
    if (s->where) {
        Rows filtered={
            0
        };
        for (int i=0;i<rows.n;i++) if (truth(evaluate(s->where,rows.v[i],NULL))) APPEND(filtered,rows.v[i]);
        rows=filtered;
    }
    VECTOR(Rows, Groups);
    Groups groups={
        0
    };
    Rows group_keys={
        0
    };
    if (aggregate && !s->grouping.n) APPEND(groups,rows);
    else if (aggregate) {
        for (int i=0;i<rows.n;i++) {
            Value *key=allocate((size_t)s->grouping.n*sizeof(Value));
            for (int j=0;j<s->grouping.n;j++) key[j]=rows.v[i][s->grouping.v[j]->index];
            int group=-1;
            for (int g=0;g<group_keys.n;g++) if (equal_rows(key,group_keys.v[g],s->grouping.n)) {
                group=g;
                break;
            }
            if (group<0) {
                group=groups.n;
                APPEND(group_keys,key);
                APPEND(groups,((Rows){
                    0
                }));
            }
            APPEND(groups.v[group],rows.v[i]);
        }
    } else for (int i=0;i<rows.n;i++) {
        Rows group={
            0
        };
        APPEND(group,rows.v[i]);
        APPEND(groups,group);
    }
    Results results={
        0
    };
    for (int i=0;i<groups.n;i++) {
        Rows group=groups.v[i];
        Value *row=group.n ? group.v[0] : allocate((size_t)scope.width*sizeof(Value));
        if (s->having && !truth(evaluate(s->having,row,&group))) continue;
        Result result={
            allocate((size_t)s->items.n*sizeof(Value)),allocate((size_t)keys.n*sizeof(Value)),results.n
        };
        for (int j=0;j<s->items.n;j++) result.values[j]=evaluate(s->items.v[j].expr,row,&group);
        for (int j=0;j<keys.n;j++) result.keys[j]=evaluate(keys.v[j],row,&group);
        APPEND(results,result);
    }
    if (keys.n) {
        sort_orders=s->orders;
        qsort(results.v,(size_t)results.n,sizeof(Result),result_compare);
    }
    if (s->distinct) {
        Results unique={
            0
        };
        for (int i=0;i<results.n;i++) {
            int seen=0;
            for (int j=0;j<unique.n;j++) if (equal_rows(results.v[i].values,unique.v[j].values,s->items.n)) {
                seen=1;
                break;
            } if (!seen) APPEND(unique,results.v[i]);
        } results=unique;
    }
    print_table(s->items,types,results,s->offset,s->limit);
}

static void count_message(int n, const char *verb) {
    printf("%d %s %s.\n",n,n==1 ? "row" : "rows",verb);
}

static void execute(Statement *s) {
    if (!*s->command || is(s->command,"EXIT")) return;
    if (is(s->command,"SELECT")) {
        execute_select(s);
        return;
    }
    if (is(s->command,"CREATE")) {
        for (int i=0;i<table_count;i++) if (is(database[i]->name,s->name)) error("table %s already exists",s->name);
        int keys=0;
        for (int i=0;i<s->columns.n;i++) {
            for (int j=0;j<i;j++) if (is(s->columns.v[i].name,s->columns.v[j].name)) error("duplicate column %s",s->columns.v[i].name);
            keys+=s->columns.v[i].keys;
            if (keys>1) error("multiple primary keys");
        }
        Table t={
            s->name,s->columns,{
                0
            }
        };
        database[table_count++]=persist_table(&t);
        printf("Table %s created.\n",s->name);
        return;
    }
    Table *original=lookup(s->name);
    if (is(s->command,"DROP")) {
        for (int i=0;i<table_count;i++) if (database[i]==original) {
            memmove(database+i,database+i+1,(size_t)(table_count-i-1)*sizeof(Table *));
            table_count--;
            break;
        } destroy_table(original);
        printf("Table %s dropped.\n",s->name);
        return;
    }
    Table t={
        original->name,original->columns,{
            0
        }
    };
    for (int i=0;i<original->rows.n;i++) {
        Value *row=allocate((size_t)t.columns.n*sizeof(Value));
        memcpy(row,original->rows.v[i],(size_t)t.columns.n*sizeof(Value));
        APPEND(t.rows,row);
    }
    Scope scope={
        0
    };
    add_scope(&scope,t.name,&t);
    if (is(s->command,"INSERT")) {
        Names names=s->names;
        if (!s->specified_names) for (int j=0;j<t.columns.n;j++) APPEND(names,t.columns.v[j].name);
        int *columns=targets(names,&t);
        Scope empty={
            0
        };
        for (int i=0;i<s->tuples.n;i++) {
            Expressions tuple=s->tuples.v[i];
            if (tuple.n != names.n) error("expected %d values, got %d",names.n,tuple.n);
            for (int j=0;j<tuple.n;j++) require(check(tuple.v[j],&empty,0,NULL,0),t.columns.v[columns[j]].type,format("column %s",t.columns.v[columns[j]].name));
        }
        int start=t.rows.n;
        int *checked=allocate((size_t)s->tuples.n*sizeof(int));
        for (int i=0;i<s->tuples.n;i++) {
            Value *row=allocate((size_t)t.columns.n*sizeof(Value));
            Expressions tuple=s->tuples.v[i];
            for (int j=0;j<tuple.n;j++) row[columns[j]]=evaluate(tuple.v[j],NULL,NULL);
            APPEND(t.rows,row);
            checked[i]=start+i;
        }
        constraints(&t,checked,s->tuples.n);
        replace_table(original,&t);
        count_message(s->tuples.n,"inserted");
        return;
    }
    int *assigned=NULL;
    if (is(s->command,"UPDATE")) {
        Names names={
            0
        };
        for (int i=0;i<s->assignments.n;i++) APPEND(names,s->assignments.v[i].name);
        assigned=targets(names,&t);
        for (int i=0;i<s->assignments.n;i++) require(check(s->assignments.v[i].expr,&scope,0,NULL,0),t.columns.v[assigned[i]].type,format("column %s",t.columns.v[assigned[i]].name));
    }
    condition(s->where,&scope,"WHERE",0,NULL);
    int *checked=allocate((size_t)t.rows.n*sizeof(int)), count=0;
    for (int i=0;i<t.rows.n;i++) if (!s->where || truth(evaluate(s->where,t.rows.v[i],NULL))) checked[count++]=i;
    if (is(s->command,"DELETE")) {
        Rows kept={
            0
        };
        int k=0;
        for (int i=0;i<t.rows.n;i++) {
            if (k<count && checked[k]==i) k++;
            else APPEND(kept,t.rows.v[i]);
        }
        t.rows=kept;
    } else {
        for (int k=0;k<count;k++) {
            int i=checked[k];
            Value *before=allocate((size_t)t.columns.n*sizeof(Value));
            memcpy(before,t.rows.v[i],(size_t)t.columns.n*sizeof(Value));
            for (int j=0;j<s->assignments.n;j++) t.rows.v[i][assigned[j]]=evaluate(s->assignments.v[j].expr,before,NULL);
        }
        constraints(&t,checked,count);
    }
    replace_table(original,&t);
    count_message(count,is(s->command,"DELETE") ? "deleted" : "updated");
}

static int process_statement(char *source) {
    volatile int exit_requested=0;
    if (setjmp(failure)==0) {
        tokenize(source);
        Statement s=parse_statement();
        exit_requested=is(s.command,"EXIT");
        if (!exit_requested) execute(&s);
    }
    clear_arena();
    return exit_requested;
}
int main(void) {
    size_t capacity=1024, length=0;
    char *statement=malloc(capacity);
    if (!statement) return 1;
    int c, previous=0, quoted=0, comment=0;
    while ((c=getchar()) != EOF) {
        if (length+2>capacity) {
            capacity*=2;
            statement=realloc(statement,capacity);
            if (!statement) return 1;
        }
        statement[length++]=(char)c;
        if (comment) {
            if (c=='\n') comment=0;
        }
        else if (c=='\'') quoted=!quoted;
        else if (!quoted && c=='-' && previous=='-') comment=1;
        else if (!quoted && c==';') {
            statement[length]=0;
            if (process_statement(statement)) break;
            length=0;
        }
        previous=c;
    }
    for (int i=0;i<table_count;i++) destroy_table(database[i]);
    free(statement);
    free(arena);
    return 0;
}
