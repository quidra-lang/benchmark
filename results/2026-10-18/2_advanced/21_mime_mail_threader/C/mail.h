#ifndef MAIL_H
#define MAIL_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <errno.h>

typedef long long Integer;
typedef struct { char **items; int count, capacity; } Lines;
typedef struct { char *data; size_t size, capacity; } Text;
typedef struct { int number; char *text; } SourceLine;
typedef struct { SourceLine *items; int count; } SourceLines;
typedef struct { char *name, *value; } Field;
typedef struct { Field *fields; int count; int *invalid, invalid_count; } Header;
enum TokenKind { WORD = 256, QUOTED };
typedef struct { int kind; char *text; bool spaced; } Token;
typedef struct { Token *items; int count; bool valid; } Tokens;
typedef struct { char *text; bool decoded, error; } DecodedWord;
typedef struct { char *text; bool error; } Decoded;
typedef struct { unsigned char *data; size_t size; bool valid; } Bytes;
typedef struct { char *name, *value; } Parameter;
typedef struct { char *type, *subtype; Parameter *items; int count; bool valid; } Parameters;
typedef struct { char *name, *address; } Mailbox;
typedef struct { bool group; Mailbox mailbox; Mailbox *members; int count; } Address;
typedef struct { Address *items; int count; bool valid, encoding_error; } Addresses;
typedef struct { Integer seconds; char *error; bool valid; } Date;
typedef struct Entity Entity;
typedef struct { Entity **items; int count, capacity; } Entities;
struct Entity {
    char *number, *type, *subtype, *disposition, *filename, *content;
    Parameters parameters; bool split; Entities children;
};
typedef struct Message {
    int number, thread, depth; Lines problems, to, cc, references;
    Mailbox *sender; char *subject, *base_subject, *id; bool reply;
    Date date; Entity *body; struct Message *parent;
} Message;
typedef struct Container Container;
typedef struct { Container **items; int count, capacity; } Containers;
struct Container { char *id, *subject; Message *message; Container *parent; Containers children; };
void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
char *slice(const char *text, size_t start, size_t length);
char *lowercase(const char *text);
bool equal_case(const char *first, const char *second);
bool whitespace(char character);
char *strip(const char *text);
char *rstrip(const char *text);
Lines split_text(const char *text, char separator);
Lines split_words(const char *text);
char *collapse_whitespace(const char *text);
char *join(Lines lines, const char *separator);
Header parse_fields(SourceLines lines);
char *header_value(const Header *header, const char *name);
int header_count(const Header *header, const char *name);
char *remove_comments(const char *text);
Tokens tokenize(const char *text, bool mime);
DecodedWord decode_word(const char *word);
Decoded decode_unstructured(const char *text);
Parameters parse_parameters(const char *text, bool with_subtype);
char *parameter(const Parameters *parameters, const char *name);
Bytes strict_base64(const char *text);
char *decode_base64_body(const char *text);
Decoded decode_quoted_printable(const char *text);
int hex_value(char character);
Addresses parse_addresses(const char *value);
Date parse_date(const char *value);
char *format_utc(Integer seconds);
int compare_messages(const Message *first, const Message *second);
Containers build_threads(Message *messages, int count);
char *root_subject(const Container *root);
#endif
