#include "archive.h"
static void token_push(Tokens *tokens, Token token) {
    if (tokens->count == tokens->capacity) {
        tokens->capacity = tokens->capacity ? 2 * tokens->capacity : 32;
        tokens->data = resize(tokens->data, tokens->capacity * sizeof(Token));
    }
    tokens->data[tokens->count++] = token;
}
Tokens tokenize(const Bytes *data, int offset_bits, int length_bits) {
    int window = 1 << offset_bits, lookahead = (1 << length_bits) + 2;
    Tokens out = {0};
    size_t position = 0;
    while (position < data->count) {
        int best = 0, distance = 0, maximum = (int)(data->count - position);
        if (maximum > lookahead)
            maximum = lookahead;
        int distances = position < (size_t)window ? (int)position : window;
        for (int d = 1; d <= distances; ++d) {
            int length = 0;
            while (length < maximum &&
                   data->data[position + (size_t)length] == data->data[position + (size_t)length - (size_t)d])
                ++length;
            if (length > best) {
                best = length;
                distance = d;
            }
        }
        if (best >= 3) {
            token_push(&out, (Token){0, distance, best});
            position += (size_t)best;
        } else
            token_push(&out, (Token){data->data[position++], 0, 0});
    }
    return out;
}
const char *output_match(Bytes *output, uint32_t size, int distance, int length) {
    if ((size_t)distance > output->count)
        return "bad_offset";
    if (output->count + (size_t)length > size)
        return "overrun";
    for (int i = 0; i < length; ++i)
        byte_push(output, output->data[output->count - (size_t)distance]);
    return NULL;
}
