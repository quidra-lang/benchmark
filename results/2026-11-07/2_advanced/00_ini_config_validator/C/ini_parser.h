#ifndef INI_PARSER_H
#define INI_PARSER_H
#include "lexer.h"

typedef enum { ASSIGN, APPEND, UNSET, INHERIT, INCLUDE } StatementKind;
typedef struct { StatementKind kind; int line; char *target, *value; } Statement;
VECTOR(Statement, Statements);
typedef struct { char *name; Statements statements; Diagnostics diagnostics; } Document;
bool is_name(const char *text);
bool is_section_name(const char *text);
Document *parse_document(char *name, const char *text);
#endif
