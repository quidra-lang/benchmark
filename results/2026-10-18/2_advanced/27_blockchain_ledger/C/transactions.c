#include "ledger.h"
static char *vformat(const char *pattern, va_list args) {
    va_list measure;
    va_copy(measure, args);
    int length = vsnprintf(NULL, 0, pattern, measure);
    va_end(measure);
    char *text = malloc((size_t)length + 1);
    vsnprintf(text, (size_t)length + 1, pattern, args);
    return text;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *text = vformat(pattern, args);
    va_end(args);
    return text;
}
void append(Text *text, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *part = vformat(pattern, args);
    va_end(args);
    size_t length = strlen(part);
    if (text->length + length + 1 > text->capacity) {
        text->capacity = (text->length + length + 1) * 2;
        text->data = realloc(text->data, text->capacity);
    }
    memcpy(text->data + text->length, part, length + 1);
    text->length += length;
    free(part);
}
char *copy_text(const char *text) {
    size_t size = strlen(text) + 1;
    char *result = malloc(size);
    memcpy(result, text, size);
    return result;
}
char *read_line(FILE *file) {
    Text text = {0};
    int c;
    while ((c = fgetc(file)) != EOF && c != '\n')
        append(&text, "%c", c);
    if (c == EOF && !text.length)
        return NULL;
    if (!text.data)
        return copy_text("");
    return text.data;
}
char **split(char *text, char delimiter, int *count) {
    *count = 1;
    for (char *p = text; *p; ++p)
        if (*p == delimiter)
            ++*count;
    char **fields = malloc((size_t)*count * sizeof *fields);
    fields[0] = text;
    int next = 1;
    for (char *p = text; *p; ++p)
        if (*p == delimiter) {
            *p = 0;
            fields[next++] = p + 1;
        }
    return fields;
}
bool same_reference(Reference a, Reference b) {
    return a.index == b.index && !strcmp(a.id, b.id);
}
Coin *find_coin(Utxo *utxo, Reference reference) {
    for (int i = 0; i < utxo->count; ++i)
        if (same_reference(utxo->items[i].reference, reference))
            return utxo->items + i;
    return NULL;
}
bool mature(Coin coin, int height, int maturity) {
    return !coin.coinbase || coin.height == 0 || height >= coin.height + maturity;
}
Integer output_total(Transaction *tx) {
    Integer sum = 0;
    for (int i = 0; i < tx->output_count; ++i)
        sum += tx->outputs[i].amount;
    return sum;
}
Transaction *parse_transaction(const char *text) {
    Transaction *tx = calloc(1, sizeof *tx);
    tx->text = copy_text(text);
    tx->id = digest(text);
    tx->coinbase_height = -1;
    int count;
    char **parts = split(copy_text(text), ';', &count);
    int output_count;
    char **outputs = split(parts[1] + 4, ',', &output_count);
    tx->output_count = output_count;
    tx->outputs = malloc((size_t)output_count * sizeof *tx->outputs);
    for (int i = 0; i < output_count; ++i) {
        int n;
        char **pair = split(outputs[i], ':', &n);
        tx->outputs[i] = (Output){pair[0], strtoll(pair[1], NULL, 10)};
        free(pair);
    }
    if (!strncmp(parts[0], "cb=", 3))
        tx->coinbase_height = atoi(parts[0] + 3);
    else {
        const char *marker = strstr(text, ";sig=");
        size_t body_size = (size_t)(marker - text);
        tx->body = malloc(body_size + 1);
        memcpy(tx->body, text, body_size);
        tx->body[body_size] = 0;
        char **inputs = split(parts[0] + 3, ',', &tx->input_count);
        tx->inputs = malloc((size_t)tx->input_count * sizeof *tx->inputs);
        for (int i = 0; i < tx->input_count; ++i) {
            int n;
            char **pair = split(inputs[i], ':', &n);
            tx->inputs[i] = (Reference){pair[0], atoi(pair[1])};
            free(pair);
        }
        tx->signatures = split(parts[2] + 4, ',', &count);
        free(inputs);
    }
    free(outputs);
    free(parts);
    return tx;
}
static void outputs_text(Text *text, Output *outputs, int count) {
    for (int i = 0; i < count; ++i)
        append(text, "%s%s:%" PRId64, i ? "," : "", outputs[i].address, outputs[i].amount);
}
Transaction *payment(Reference *inputs, int n, Output *outputs, int k, const char *secret) {
    Text body = {0};
    append(&body, "in=");
    for (int i = 0; i < n; ++i)
        append(&body, "%s%s:%d", i ? "," : "", inputs[i].id, inputs[i].index);
    append(&body, ";out=");
    outputs_text(&body, outputs, k);
    Text text = {0};
    append(&text, "%s;sig=", body.data);
    for (int i = 0; i < n; ++i)
        append(&text, "%s%s", i ? "," : "", sign_transaction(secret, i, body.data));
    Transaction *tx = parse_transaction(text.data);
    free(text.data);
    free(body.data);
    return tx;
}
Transaction *coinbase(int height, Output *outputs, int count) {
    Text text = {0};
    append(&text, "cb=%d;out=", height);
    outputs_text(&text, outputs, count);
    Transaction *tx = parse_transaction(text.data);
    free(text.data);
    return tx;
}
const char *check_transaction(Transaction *tx, Utxo *utxo, Reference *spent, int spent_count, int height,
                              Wallets wallets, int maturity, Integer *fee) {
    *fee = 0;
    for (int i = 0; i < tx->output_count; ++i)
        if (!owner(wallets, tx->outputs[i].address) || tx->outputs[i].amount == 0)
            return "bad-output";
    Integer total = 0;
    for (int i = 0; i < tx->input_count; ++i) {
        Reference ref = tx->inputs[i];
        for (int j = 0; j < spent_count; ++j)
            if (same_reference(ref, spent[j]))
                return "double-spend";
        for (int j = 0; j < i; ++j)
            if (same_reference(ref, tx->inputs[j]))
                return "double-spend";
        Coin *coin = find_coin(utxo, ref);
        if (!coin)
            return "missing-input";
        if (!mature(*coin, height, maturity))
            return "immature";
        if (strcmp(tx->signatures[i], sign_transaction(owner(wallets, coin->address)->secret, i, tx->body)))
            return "bad-sig";
        total += coin->amount;
    }
    if (total < output_total(tx))
        return "overspend";
    *fee = total - output_total(tx);
    return NULL;
}
void apply_transaction(Utxo *utxo, Transaction *tx, int height) {
    for (int i = 0; i < tx->input_count; ++i) {
        Coin *coin = find_coin(utxo, tx->inputs[i]);
        if (coin) {
            int at = (int)(coin - utxo->items);
            memmove(coin, coin + 1, (size_t)(utxo->count - at - 1) * sizeof *coin);
            --utxo->count;
        }
    }
    for (int i = 0; i < tx->output_count; ++i) {
        Coin coin = {
            {tx->id, i}, tx->outputs[i].address, tx->outputs[i].amount, height, tx->coinbase_height >= 0};
        Coin *old = find_coin(utxo, coin.reference);
        if (old) {
            *old = coin;
            continue;
        }
        if (utxo->count == utxo->capacity) {
            utxo->capacity = utxo->capacity ? utxo->capacity * 2 : 16;
            utxo->items = realloc(utxo->items, (size_t)utxo->capacity * sizeof *utxo->items);
        }
        utxo->items[utxo->count++] = coin;
    }
}
Utxo copy_utxo(Utxo source) {
    Utxo result = {NULL, source.count, source.count};
    result.items = malloc((size_t)source.count * sizeof *result.items);
    memcpy(result.items, source.items, (size_t)source.count * sizeof *result.items);
    return result;
}
