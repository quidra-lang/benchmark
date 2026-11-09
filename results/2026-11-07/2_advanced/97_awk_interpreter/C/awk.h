#ifndef AWK_H
#define AWK_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include <stdarg.h>
#include <setjmp.h>
typedef struct { int line,column; } Position;
typedef struct { char *data; size_t length,capacity; } Buffer;
void *mem_new(size_t n);
void *mem_resize(void *p,size_t n);
char *str_copy(const char *s);
void buffer_add(Buffer *b,const char *s,size_t n);
void buffer_text(Buffer *b,const char *s);
char *read_line(FILE *f);
typedef struct Text { size_t refs; char data[]; } Text;
typedef struct { int kind; long long number; Text *text; } Value;
Value number(long long n);
Value string(const char *s);
Value input_value(const char *s);
Value value_copy(Value v);
void value_free(Value v);
long long numeric(Value v);
char *textual(Value v);
int truth(Value v);
int compare(Value a,Value b);
void value_write(FILE *f,Value v);
char **split_string(const char *s,const char *separator,int *count);
int key_compare(const void *a,const void *b);
typedef struct { char *key; Value value; } Element;
typedef struct { Element **items; int count,capacity; } Array;
typedef struct { Value value; Array *array; int own_array; } Variable;
typedef struct Symbol { char *name; int parameter,array; Variable global; } Symbol;
typedef struct Token { int kind; char *text; long long number; Position pos; } Token;
enum { T_EOF,T_NL,T_NUMBER,T_STRING,T_NAME,T_FUNCTION,T_BUILTIN,T_KEYWORD,T_SYMBOL };
typedef struct { Token *tokens; int count; Position error; int failed; } Tokens;
Tokens lex(const char *source);
enum { E_NUMBER,E_STRING,E_VAR,E_ARRAY,E_FIELD,E_GROUP,E_UNARY,E_BINARY,E_COND,E_ASSIGN,E_INC,E_CALL,E_BUILTIN,E_GETLINE,E_IN };
typedef struct Expr Expr;
struct Expr { int kind,postfix; Token token; char *op; Expr *a,*b,*c; Expr **args; int count; Symbol *symbol; struct Function *function; };
enum { S_BLOCK,S_EMPTY,S_EXPR,S_IF,S_WHILE,S_DO,S_FOR,S_FORIN,S_PRINT,S_PRINTF,S_DELETE,S_NEXT,S_BREAK,S_CONTINUE,S_EXIT,S_RETURN };
typedef struct Statement Statement;
struct Statement { int kind,append; Token token,second; Expr *a,*b,*c,*redirect; Statement *body,*otherwise; Statement **children; int count; Expr **args; int nargs; Symbol *symbol,*array; };
typedef struct Function { Token token; Token *params; Symbol **symbols; int np; Statement *body; long long calls,depth,current; } Function;
typedef struct { Token token; int kind,inside; Expr *start,*end; Statement *action; long long count; } Rule;
typedef struct { Function **functions; int nf; Rule **rules; int nr; Position error; int failed; unsigned char *statement_lines; int lines; } Syntax;
Syntax parse(Tokens tokens,int lines);
typedef struct { char *name,*value; int option,assignment; long long records; } Operand;
typedef struct { char *name; FILE *file; int opened,ever; long long reads; } InputStream;
typedef struct { char *name; Buffer content; int open; long long writes; } OutputStream;
typedef struct { Operand *args; int count,next,current; FILE *main_file; InputStream **inputs; int ni; OutputStream **outputs; int no; Buffer standard; long long writes; } Streams;
Streams read_args(void);
int valid_filename(const char *name);
char *getline_file(Streams *s,const char *name,int *status);
int close_stream(Streams *s,const char *name);
void output_string(Streams *s,const char *name,int append,const char *text);
void write_streams(Streams *s);
typedef struct Frame { Function *function; Variable *locals; struct Frame *parent; } Frame;
enum { FLOW_NORMAL,FLOW_BREAK,FLOW_CONTINUE,FLOW_NEXT,FLOW_EXIT,FLOW_RETURN };
typedef struct Runtime { Syntax syntax; Symbol **globals; int ng; Frame *frame; Streams streams; Value record,*fields,result; int nf,phase,flow; long long status,*line_counts; Position error; char *message; } Runtime;
Symbol *global_symbol(Runtime *r,const char *name);
Variable *variable(Runtime *r,Symbol *s);
void runtime_error(Runtime *r,Position p,const char *message);
void array_clear(Array *a);
Element *array_element(Array *a,const char *key,int create);
void array_delete(Array *a,const char *key);
void set_record(Runtime *r,const char *s);
void rebuild_record(Runtime *r);
void set_nf(Runtime *r,long long n,Position p);
Value field_value(Runtime *r,long long index,Position p);
void store_field(Runtime *r,long long index,Value v,Position p);
Value evaluate(Runtime *r,Expr *e);
void execute(Runtime *r,Statement *s);
Value builtin(Runtime *r,Expr *e);
char *format_values(Runtime *r,Position pos,Value *args,int count);
Value simple_builtin(Runtime *r,Expr *e,Value *args);
#endif
