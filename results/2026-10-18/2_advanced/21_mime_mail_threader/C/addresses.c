#include "mail.h"

typedef struct { Tokens tokens; int position; bool error; } Parser;
static int peek(const Parser *parser) { return parser->position < parser->tokens.count ? parser->tokens.items[parser->position].kind : 0; }
static bool expect(Parser *parser, int kind) {
    if (peek(parser) != kind) return false;
    ++parser->position;
    return true;
}
static bool dot_atom(Token *tokens, int count) {
    if (!count || count % 2 == 0) return false;
    for (int i = 0; i < count; ++i) if (tokens[i].kind != (i % 2 ? '.' : WORD)) return false;
    return true;
}
static char *address_string(Token *local, int local_count, Token *domain, int domain_count) {
    if (!dot_atom(local, local_count) || !dot_atom(domain, domain_count)) return NULL;
    Text text = {0};
    for (int i = 0; i < local_count; ++i) text_add(&text, "%s", local[i].text);
    text_add(&text, "@");
    for (int i = 0; i < domain_count; ++i) text_add(&text, "%s", domain[i].text);
    return lowercase(text.data);
}
static char *display_name(Parser *parser, Token *phrase, int count) {
    Text text = {0};
    bool previous = false;
    for (int i = 0; i < count; ++i) {
        DecodedWord word = {phrase[i].text, false, false};
        if (phrase[i].kind == WORD) word = decode_word(phrase[i].text);
        if (i && phrase[i].spaced && !(word.decoded && previous)) text_add(&text, " ");
        text_add(&text, "%s", word.text);
        previous = word.decoded;
        parser->error |= word.error;
    }
    return collapse_whitespace(text.data ? text.data : "");
}
static bool parse_address(Parser *parser, bool in_group, Address *result) {
    int phrase_start = parser->position;
    while (peek(parser) == WORD || peek(parser) == QUOTED || peek(parser) == '.') ++parser->position;
    int phrase_count = parser->position - phrase_start;
    Token *phrase = parser->tokens.items + phrase_start;
    if (peek(parser) == '<') {
        ++parser->position;
        int local_start = parser->position;
        while (peek(parser) == WORD || peek(parser) == '.') ++parser->position;
        int local_count = parser->position - local_start;
        if (!expect(parser, '@')) return false;
        int domain_start = parser->position;
        while (peek(parser) == WORD || peek(parser) == '.') ++parser->position;
        int domain_count = parser->position - domain_start;
        if (!expect(parser, '>')) return false;
        char *address = address_string(parser->tokens.items + local_start, local_count, parser->tokens.items + domain_start, domain_count);
        if (!address) return false;
        result->mailbox = (Mailbox){display_name(parser, phrase, phrase_count), address};
        return true;
    }
    if (peek(parser) == '@') {
        ++parser->position;
        int domain_start = parser->position;
        while (peek(parser) == WORD || peek(parser) == '.') ++parser->position;
        char *address = address_string(phrase, phrase_count, parser->tokens.items + domain_start, parser->position - domain_start);
        if (!address) return false;
        result->mailbox = (Mailbox){"", address};
        return true;
    }
    if (peek(parser) == ':' && phrase_count && !in_group) {
        ++parser->position;
        result->group = true;
        result->members = allocate((size_t)parser->tokens.count * sizeof(Mailbox));
        if (peek(parser) != ';') {
            while (true) {
                Address member = {0};
                if (!parse_address(parser, true, &member)) return false;
                result->members[result->count++] = member.mailbox;
                if (peek(parser) != ',') break;
                ++parser->position;
            }
        }
        return expect(parser, ';');
    }
    return false;
}

Addresses parse_addresses(const char *value) {
    Addresses result = {0};
    Tokens tokens = tokenize(value, false);
    if (!tokens.valid || !tokens.count) return result;
    Parser parser = {tokens, 0, false};
    result.items = allocate((size_t)tokens.count * sizeof(Address));
    while (true) {
        if (!parse_address(&parser, false, &result.items[result.count])) return result;
        ++result.count;
        if (peek(&parser) != ',') break;
        ++parser.position;
    }
    if (parser.position != tokens.count) return result;
    result.valid = true;
    result.encoding_error = parser.error;
    return result;
}
