#include "ledger.h"
Wallets read_wallets(void) {
    Wallets wallets = {0};
    FILE *file = fopen("input/wallets.txt", "r");
    char *line;
    while ((line = read_line(file))) {
        int count;
        char **fields = split(line, ' ', &count);
        wallets.items = realloc(wallets.items, (size_t)(wallets.count + 1) * sizeof *wallets.items);
        Wallet wallet = {fields[0], fields[1], digest(format("addr:%s", fields[1]))};
        wallet.address[16] = 0;
        wallets.items[wallets.count++] = wallet;
        free(fields);
    }
    fclose(file);
    return wallets;
}
Wallet *owner(Wallets wallets, const char *address) {
    for (int i = 0; i < wallets.count; ++i)
        if (!strcmp(wallets.items[i].address, address))
            return wallets.items + i;
    return NULL;
}
Wallet *named_wallet(Wallets wallets, const char *name) {
    for (int i = 0; i < wallets.count; ++i)
        if (!strcmp(wallets.items[i].name, name))
            return wallets.items + i;
    return NULL;
}
char *sign_transaction(const char *secret, int index, const char *body) {
    char *result = digest(format("%s:%d:%s", secret, index, body));
    result[16] = 0;
    return result;
}
