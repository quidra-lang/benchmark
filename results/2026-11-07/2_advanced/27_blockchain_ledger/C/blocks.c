#include "ledger.h"
char *header_text(Block *block) {
    return format("%d|%s|%s|%" PRId64 "|%d|%" PRId64, block->height, block->previous, block->root,
                  block->time, block->difficulty, block->nonce);
}
void hash_header(Block *block) {
    block->hash = digest(header_text(block));
}
Integer block_size(Block *block) {
    Integer size = 0;
    for (int i = 1; i < block->count; ++i)
        size += (Integer)strlen(block->transactions[i]->text);
    return size;
}
bool proof(Block *block) {
    for (int i = 0; i < block->difficulty; ++i)
        if (block->hash[i] != '0')
            return false;
    return true;
}
Block *parse_block(char **fields, char **texts, int count) {
    Block *block = calloc(1, sizeof *block);
    block->height = atoi(fields[3]);
    block->previous = fields[4];
    block->root = fields[5];
    block->time = strtoll(fields[6], NULL, 10);
    block->difficulty = atoi(fields[7]);
    block->nonce = strtoll(fields[8], NULL, 10);
    block->count = count;
    block->transactions = malloc((size_t)count * sizeof *block->transactions);
    for (int i = 0; i < count; ++i)
        block->transactions[i] = parse_transaction(texts[i]);
    hash_header(block);
    return block;
}
Block *mine_block(int height, const char *previous, Transaction **txs, int count, Integer time,
                  int difficulty) {
    Block *block = calloc(1, sizeof *block);
    block->height = height;
    block->previous = copy_text(previous);
    block->transactions = txs;
    block->count = count;
    block->time = time;
    block->difficulty = difficulty;
    char **ids = malloc((size_t)count * sizeof *ids);
    for (int i = 0; i < count; ++i)
        ids[i] = txs[i]->id;
    block->root = merkle(ids, count);
    free(ids);
    for (;;) {
        hash_header(block);
        if (proof(block))
            break;
        free(block->hash);
        ++block->nonce;
    }
    return block;
}
const char *context_error(Block *block, Integer limit) {
    if (!proof(block))
        return "bad-pow";
    char **ids = malloc((size_t)block->count * sizeof *ids);
    for (int i = 0; i < block->count; ++i)
        ids[i] = block->transactions[i]->id;
    char *root = merkle(ids, block->count);
    free(ids);
    if (strcmp(root, block->root))
        return "bad-merkle";
    if (block->transactions[0]->coinbase_height != block->height)
        return "bad-structure";
    for (int i = 1; i < block->count; ++i)
        if (block->transactions[i]->coinbase_height >= 0)
            return "bad-structure";
    return block_size(block) > limit ? "too-large" : NULL;
}
