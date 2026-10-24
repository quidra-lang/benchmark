#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_WAREHOUSES 20
#define MAX_ITEMS 100
#define MAX_RECORDS 2000

typedef int64_t Amount;

enum Category {
    RECEIVED, RETURNED, ADJUSTED_IN, ADJUSTED_OUT,
    SHIPPED, WRITTEN_DOWN, EXPIRED, RECALLED
};

static const char *category_names[] = {
    "received", "returned", "adjusted-in", "adjusted-out",
    "shipped", "written-down", "expired", "recalled"
};

static const char *lot_kinds[] = {
    "receive", "adjust", "return", "count"
};

static const char *card_kinds[] = {
    "receive", "ship", "fill", "transfer-out", "transfer-in",
    "adjust", "return", "count", "writedown", "expire", "recall"
};

enum CardKind {
    CARD_RECEIVE, CARD_SHIP, CARD_FILL, CARD_TRANSFER_OUT,
    CARD_TRANSFER_IN, CARD_ADJUST, CARD_RETURN, CARD_COUNT,
    CARD_WRITEDOWN, CARD_EXPIRE, CARD_RECALL
};

typedef struct {
    char code[9];
} Warehouse;

typedef struct {
    char code[13];
    char name[21];
    int level;
    Amount last_cost;
    int received_cost;
} Item;

typedef struct {
    int item;
    int day;
    Amount quantity;
    Amount cost;
    int warehouse;
    int kind;
    Amount removed;
} Lot;

typedef struct {
    int warehouse;
    int item;
    int lot;
    Amount quantity;
    Amount cost;
    int active;
} Stock;

typedef struct {
    int lot;
    Amount quantity;
    Amount cost;
} Part;

typedef struct {
    Part *entries;
    size_t length;
    size_t capacity;
} PartList;

typedef struct {
    int warehouse;
    int item;
    int day;
    Amount price;
    Amount ordered;
    Amount shipped;
    Amount backorder;
    Amount cancelled;
    Amount returned;
    Amount revenue;
    Amount cogs;
    PartList issues;
} Order;

typedef struct {
    int item;
    int day;
    int kind;
    int warehouse;
    Amount quantity;
    Amount value;
} CardEntry;

typedef struct {
    Amount quantity;
    Amount value;
} Total;

static Warehouse warehouses[MAX_WAREHOUSES];
static Item items[MAX_ITEMS];
static Lot lots[MAX_RECORDS];
static Order orders[MAX_RECORDS];
static Stock *stocks;
static CardEntry *cards;
static Total totals[8];
static int warehouse_count;
static int item_count;
static int lot_count;
static int order_count;
static size_t stock_count;
static size_t stock_capacity;
static size_t card_count;
static size_t card_capacity;
static int current_day = 1;

static void *grow(void *data, size_t *capacity, size_t length, size_t bytes) {
    if (length >= *capacity) {
        size_t target = *capacity == 0 ? 32 : 2 * *capacity;
        void *next = realloc(data, bytes * target);
        if (!next) {
            fputs("out of memory\n", stderr);
            exit(EXIT_FAILURE);
        }
        data = next;
        *capacity = target;
    }
    return data;
}

static const char *money(Amount value) {
    static char buffers[16][64];
    static unsigned int cursor;
    char *text = buffers[(cursor++) % 16];
    const char *sign = value < 0 ? "-" : "";
    Amount absolute = value < 0 ? -value : value;
    snprintf(text, 64, "%s%" PRId64 ".%02" PRId64,
             sign, absolute / 100, absolute % 100);
    return text;
}

static const char *signed_quantity(Amount value) {
    static char buffers[16][48];
    static unsigned int cursor;
    char *text = buffers[(cursor++) % 16];
    if (value > 0) snprintf(text, 48, "+%" PRId64, value);
    else snprintf(text, 48, "%" PRId64, value);
    return text;
}

static const char *signed_money(Amount value) {
    static char buffers[16][64];
    static unsigned int cursor;
    char *text = buffers[(cursor++) % 16];
    if (value > 0) snprintf(text, 64, "+%s", money(value));
    else snprintf(text, 64, "%s", money(value));
    return text;
}

static const char *margin(Amount profit, Amount revenue) {
    static char buffers[16][64];
    static unsigned int cursor;
    char *text = buffers[(cursor++) % 16];
    Amount absolute = profit < 0 ? -profit : profit;
    Amount tenths;
    if (revenue == 0) {
        strcpy(text, "n/a");
        return text;
    }
    tenths = absolute * 1000 / revenue;
    snprintf(text, 64, "%s%" PRId64 ".%" PRId64 "%%",
             profit < 0 && tenths != 0 ? "-" : "", tenths / 10, tenths % 10);
    return text;
}

static Amount parse_money(const char *text) {
    const char *point = strchr(text, '.');
    return atoll(text) * 100 + atoll(point + 1);
}

static int warehouse_index(const char *code) {
    int i;
    for (i = 0; i < warehouse_count; ++i)
        if (strcmp(warehouses[i].code, code) == 0) return i;
    return -1;
}

static int item_index(const char *code) {
    int i;
    for (i = 0; i < item_count; ++i)
        if (strcmp(items[i].code, code) == 0) return i;
    return -1;
}

static int require_warehouse(const char *code) {
    int index = warehouse_index(code);
    if (index < 0) printf("ERROR unknown warehouse %s\n", code);
    return index;
}

static int require_item(const char *code) {
    int index = item_index(code);
    if (index < 0) printf("ERROR unknown item %s\n", code);
    return index;
}

static int require_pair(const char *warehouse, const char *item, int *w, int *s) {
    *w = require_warehouse(warehouse);
    if (*w < 0) return 0;
    *s = require_item(item);
    return *s >= 0;
}

static int require_quantity(Amount quantity) {
    if (quantity == 0) {
        puts("ERROR invalid quantity");
        return 0;
    }
    return 1;
}

static Order *require_order(const char *text) {
    Amount number = atoll(text);
    if (number < 1 || number > order_count) {
        printf("ERROR unknown order %s\n", text);
        return NULL;
    }
    return &orders[number - 1];
}

static Lot *require_lot(const char *text) {
    Amount number = atoll(text);
    if (number < 1 || number > lot_count) {
        printf("ERROR unknown lot %s\n", text);
        return NULL;
    }
    return &lots[number - 1];
}

static void append_part(PartList *list, Part part) {
    list->entries = grow(list->entries, &list->capacity, list->length, sizeof(Part));
    list->entries[list->length++] = part;
}

static void append_card(int item, int kind, int warehouse, Amount quantity, Amount value) {
    CardEntry entry = {item, current_day, kind, warehouse, quantity, value};
    cards = grow(cards, &card_capacity, card_count, sizeof(CardEntry));
    cards[card_count++] = entry;
}

static void accumulate(int category, Amount quantity, Amount value) {
    totals[category].quantity += quantity;
    totals[category].value += value;
}

static Amount onhand(int warehouse, int item) {
    Amount quantity = 0;
    size_t i;
    for (i = 0; i < stock_count; ++i)
        if (stocks[i].active && stocks[i].warehouse == warehouse &&
            stocks[i].item == item)
            quantity += stocks[i].quantity;
    return quantity;
}

static Amount stock_value(int warehouse, int item) {
    Amount value = 0;
    size_t i;
    for (i = 0; i < stock_count; ++i)
        if (stocks[i].active && stocks[i].warehouse == warehouse &&
            stocks[i].item == item)
            value += stocks[i].quantity * stocks[i].cost;
    return value;
}

static Amount item_onhand(int item) {
    Amount quantity = 0;
    int warehouse;
    for (warehouse = 0; warehouse < warehouse_count; ++warehouse)
        quantity += onhand(warehouse, item);
    return quantity;
}

static Amount item_backorder(int item) {
    Amount quantity = 0;
    int i;
    for (i = 0; i < order_count; ++i)
        if (orders[i].item == item) quantity += orders[i].backorder;
    return quantity;
}

static int require_stock(int warehouse, int item, Amount quantity) {
    Amount available = onhand(warehouse, item);
    if (available < quantity) {
        printf("ERROR insufficient stock %s %s %" PRId64 "\n",
               warehouses[warehouse].code, items[item].code, available);
        return 0;
    }
    return 1;
}

static void add_stock(int warehouse, int lot, Amount quantity, Amount cost) {
    size_t i;
    for (i = 0; i < stock_count; ++i)
        if (stocks[i].active && stocks[i].warehouse == warehouse && stocks[i].lot == lot) {
            stocks[i].quantity += quantity;
            return;
        }
    stocks = grow(stocks, &stock_capacity, stock_count, sizeof(Stock));
    stocks[stock_count++] = (Stock){
        warehouse, lots[lot].item, lot, quantity, cost, 1
    };
}

static int create_lot(int warehouse, int item, int day, Amount quantity,
                      Amount cost, int kind) {
    int number = lot_count++;
    lots[number] = (Lot){item, day, quantity, cost, warehouse, kind, 0};
    add_stock(warehouse, number, quantity, cost);
    return number;
}

static int earlier_stock(const Stock *first, const Stock *second) {
    const Lot *a = &lots[first->lot], *b = &lots[second->lot];
    return a->day < b->day || (a->day == b->day && first->lot < second->lot);
}

static Amount issue(int warehouse, int item, Amount quantity, PartList *parts) {
    Amount cost = 0;
    while (quantity > 0) {
        Stock *chosen = NULL;
        size_t i;
        for (i = 0; i < stock_count; ++i) {
            Stock *candidate = &stocks[i];
            if (!candidate->active || candidate->warehouse != warehouse ||
                candidate->item != item)
                continue;
            if (!chosen || earlier_stock(candidate, chosen)) chosen = candidate;
        }
        {
            Amount taken = chosen->quantity < quantity ? chosen->quantity : quantity;
            append_part(parts, (Part){chosen->lot, taken, chosen->cost});
            cost += taken * chosen->cost;
            chosen->quantity -= taken;
            quantity -= taken;
            if (chosen->quantity == 0) chosen->active = 0;
        }
    }
    return cost;
}

static void remove_parts(const PartList *parts) {
    size_t i;
    for (i = 0; i < parts->length; ++i)
        lots[parts->entries[i].lot].removed += parts->entries[i].quantity;
}

static Amount fulfil(Order *order, Amount quantity, int kind) {
    PartList parts = {0};
    Amount cost;
    size_t i;
    if (quantity == 0) return 0;
    cost = issue(order->warehouse, order->item, quantity, &parts);
    for (i = 0; i < parts.length; ++i)
        append_part(&order->issues, parts.entries[i]);
    order->shipped += quantity;
    order->backorder -= quantity;
    order->revenue += quantity * order->price;
    order->cogs += cost;
    accumulate(SHIPPED, quantity, cost);
    append_card(order->item, kind, order->warehouse, -quantity, -cost);
    free(parts.entries);
    return cost;
}

static void allocate_backorders(int warehouse, int item) {
    Amount available = onhand(warehouse, item);
    int i;
    for (i = 0; i < order_count && available > 0; ++i) {
        Order *order = &orders[i];
        Amount filled, cost, revenue;
        if (order->warehouse != warehouse || order->item != item ||
            order->backorder == 0)
            continue;
        filled = available < order->backorder ? available : order->backorder;
        cost = fulfil(order, filled, CARD_FILL);
        revenue = filled * order->price;
        available -= filled;
        printf("  FILL order %d qty %" PRId64 " revenue %s cogs %s profit %s backorder %" PRId64 "\n",
               i + 1, filled, money(revenue), money(cost), money(revenue - cost),
               order->backorder);
    }
}

static int by_warehouse_code(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return strcmp(warehouses[a].code, warehouses[b].code);
}

static int by_item_code(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return strcmp(items[a].code, items[b].code);
}

static void warehouse_order(int *result) {
    int i;
    for (i = 0; i < warehouse_count; ++i) result[i] = i;
    qsort(result, (size_t)warehouse_count, sizeof(int), by_warehouse_code);
}

static void item_order(int *result) {
    int i;
    for (i = 0; i < item_count; ++i) result[i] = i;
    qsort(result, (size_t)item_count, sizeof(int), by_item_code);
}

static void day_command(const char *text) {
    int day = atoi(text);
    if (day <= current_day) printf("ERROR invalid day %s\n", text);
    else {
        current_day = day;
        printf("DAY %d\n", current_day);
    }
}

static void warehouse_command(const char *code) {
    if (warehouse_index(code) >= 0) {
        printf("ERROR duplicate warehouse %s\n", code);
        return;
    }
    strcpy(warehouses[warehouse_count++].code, code);
    printf("WAREHOUSE %s\n", code);
}

static void item_command(const char *code, const char *level, const char *name) {
    int index = item_index(code);
    const char *action = index >= 0 ? "updated" : "added";
    if (index < 0) {
        index = item_count++;
        memset(&items[index], 0, sizeof(Item));
        strcpy(items[index].code, code);
    }
    items[index].level = atoi(level);
    strcpy(items[index].name, name);
    printf("ITEM %s %s %s level %d\n", code, action, name, items[index].level);
}

static void receive_command(char **a) {
    int warehouse, item, lot;
    Amount quantity, cost;
    int day;
    if (!require_pair(a[0], a[1], &warehouse, &item)) return;
    quantity = atoll(a[2]);
    cost = parse_money(a[3]);
    day = atoi(a[4]);
    if (!require_quantity(quantity)) return;
    if (day > current_day) {
        printf("ERROR future day %s\n", a[4]);
        return;
    }
    lot = create_lot(warehouse, item, day, quantity, cost, 0);
    items[item].last_cost = cost;
    items[item].received_cost = 1;
    accumulate(RECEIVED, quantity, quantity * cost);
    append_card(item, CARD_RECEIVE, warehouse, quantity, quantity * cost);
    printf("RECEIVE %s %s lot %d qty %" PRId64 " cost %s day %d value %s\n",
           a[0], a[1], lot + 1, quantity, money(cost), day, money(quantity * cost));
    allocate_backorders(warehouse, item);
}

static void ship_command(char **a) {
    int warehouse, item, index;
    Amount quantity, price, filled, cost;
    Order *order;
    if (!require_pair(a[0], a[1], &warehouse, &item)) return;
    quantity = atoll(a[2]);
    price = parse_money(a[3]);
    if (!require_quantity(quantity)) return;
    index = order_count++;
    order = &orders[index];
    memset(order, 0, sizeof(*order));
    order->warehouse = warehouse;
    order->item = item;
    order->day = current_day;
    order->price = price;
    order->ordered = quantity;
    order->backorder = quantity;
    filled = onhand(warehouse, item);
    if (filled > quantity) filled = quantity;
    cost = fulfil(order, filled, CARD_SHIP);
    printf("SHIP order %d %s %s shipped %" PRId64 " revenue %s cogs %s profit %s backorder %" PRId64 "\n",
           index + 1, a[0], a[1], filled, money(order->revenue),
           money(cost), money(order->revenue - cost), order->backorder);
}

static void cancel_command(const char *number) {
    Order *order = require_order(number);
    if (!order) return;
    if (order->backorder == 0) {
        printf("ERROR no backorder %s\n", number);
        return;
    }
    order->cancelled += order->backorder;
    order->backorder = 0;
    printf("CANCEL order %ld qty %" PRId64 "\n",
           (long)(order - orders) + 1, order->cancelled);
}

static void transfer_command(char **a) {
    int source = require_warehouse(a[0]), destination, item;
    Amount quantity, cost;
    PartList parts = {0};
    size_t i;
    if (source < 0) return;
    destination = require_warehouse(a[1]);
    if (destination < 0) return;
    if (source == destination) {
        printf("ERROR same warehouse %s\n", a[0]);
        return;
    }
    item = require_item(a[2]);
    if (item < 0) return;
    quantity = atoll(a[3]);
    if (!require_quantity(quantity) || !require_stock(source, item, quantity)) return;
    cost = issue(source, item, quantity, &parts);
    for (i = 0; i < parts.length; ++i)
        add_stock(destination, parts.entries[i].lot, parts.entries[i].quantity,
                  parts.entries[i].cost);
    append_card(item, CARD_TRANSFER_OUT, source, -quantity, -cost);
    append_card(item, CARD_TRANSFER_IN, destination, quantity, cost);
    printf("TRANSFER %s -> %s %s qty %" PRId64 " value %s lots %zu\n",
           a[0], a[1], a[2], quantity, money(cost), parts.length);
    free(parts.entries);
    allocate_backorders(destination, item);
}

static void adjust_command(char **a) {
    int warehouse, item;
    Amount quantity, cost;
    PartList parts = {0};
    if (!require_pair(a[0], a[1], &warehouse, &item)) return;
    quantity = atoll(a[2] + 1);
    if (!require_quantity(quantity)) return;
    if (a[2][0] == '+') {
        int lot = create_lot(warehouse, item, current_day, quantity, parse_money(a[3]), 1);
        cost = lots[lot].cost;
        accumulate(ADJUSTED_IN, quantity, quantity * cost);
        append_card(item, CARD_ADJUST, warehouse, quantity, quantity * cost);
        printf("ADJUST %s %s +%" PRId64 " lot %d value %s\n",
               a[0], a[1], quantity, lot + 1, money(quantity * cost));
        allocate_backorders(warehouse, item);
    } else {
        if (!require_stock(warehouse, item, quantity)) return;
        cost = issue(warehouse, item, quantity, &parts);
        remove_parts(&parts);
        accumulate(ADJUSTED_OUT, quantity, cost);
        append_card(item, CARD_ADJUST, warehouse, -quantity, -cost);
        printf("ADJUST %s %s -%" PRId64 " value %s\n",
               a[0], a[1], quantity, money(cost));
        free(parts.entries);
    }
}

static void return_command(char **a) {
    Order *order = require_order(a[0]);
    Amount quantity, cost, available;
    int lot;
    if (!order) return;
    quantity = atoll(a[1]);
    cost = parse_money(a[2]);
    if (!require_quantity(quantity)) return;
    available = order->shipped - order->returned;
    if (quantity > available) {
        printf("ERROR return exceeds shipped %s %" PRId64 "\n", a[0], available);
        return;
    }
    lot = create_lot(order->warehouse, order->item, current_day, quantity, cost, 2);
    order->returned += quantity;
    order->revenue -= quantity * order->price;
    order->cogs -= quantity * cost;
    accumulate(RETURNED, quantity, quantity * cost);
    append_card(order->item, CARD_RETURN, order->warehouse, quantity, quantity * cost);
    printf("RETURN order %ld %s %s qty %" PRId64 " lot %d refund %s value %s\n",
           (long)(order - orders) + 1, warehouses[order->warehouse].code,
           items[order->item].code, quantity, lot + 1, money(quantity * order->price),
           money(quantity * cost));
    allocate_backorders(order->warehouse, order->item);
}

static void count_command(char **a) {
    int warehouse, item;
    Amount actual, held, delta, cost;
    PartList parts = {0};
    if (!require_pair(a[0], a[1], &warehouse, &item)) return;
    actual = atoll(a[2]);
    held = onhand(warehouse, item);
    if (actual == held) {
        printf("COUNT %s %s qty %" PRId64 " ok\n", a[0], a[1], actual);
    } else if (actual < held) {
        delta = held - actual;
        cost = issue(warehouse, item, delta, &parts);
        remove_parts(&parts);
        accumulate(ADJUSTED_OUT, delta, cost);
        append_card(item, CARD_COUNT, warehouse, -delta, -cost);
        printf("COUNT %s %s qty %" PRId64 " -> %" PRId64 " shortage %" PRId64 " value %s\n",
               a[0], a[1], held, actual, delta, money(cost));
        free(parts.entries);
    } else {
        int lot;
        delta = actual - held;
        cost = items[item].received_cost ? items[item].last_cost : 0;
        lot = create_lot(warehouse, item, current_day, delta, cost, 3);
        accumulate(ADJUSTED_IN, delta, delta * cost);
        append_card(item, CARD_COUNT, warehouse, delta, delta * cost);
        printf("COUNT %s %s qty %" PRId64 " -> %" PRId64 " surplus %" PRId64 " lot %d value %s\n",
               a[0], a[1], held, actual, delta, lot + 1, money(delta * cost));
        allocate_backorders(warehouse, item);
    }
}

static void market_command(char **a) {
    int item = require_item(a[0]);
    Amount price, quantity = 0, loss = 0;
    int count = 0, order[MAX_WAREHOUSES], k;
    size_t i;
    if (item < 0) return;
    price = parse_money(a[1]);
    warehouse_order(order);
    for (k = 0; k < warehouse_count; ++k) {
        int warehouse = order[k];
        Amount warehouse_loss = 0;
        for (i = 0; i < stock_count; ++i) {
            Stock *stock = &stocks[i];
            if (stock->active && stock->warehouse == warehouse &&
                stock->item == item && stock->cost > price) {
                Amount decrease = stock->quantity * (stock->cost - price);
                warehouse_loss += decrease;
                ++count;
                quantity += stock->quantity;
                stock->cost = price;
            }
        }
        if (warehouse_loss > 0)
            append_card(item, CARD_WRITEDOWN, warehouse, 0, -warehouse_loss);
        loss += warehouse_loss;
    }
    accumulate(WRITTEN_DOWN, quantity, loss);
    printf("MARKET %s price %s lots %d qty %" PRId64 " loss %s\n",
           a[0], money(price), count, quantity, money(loss));
}

static void recall_command(const char *text) {
    Lot *lot = require_lot(text);
    int warehouse_ordered[MAX_WAREHOUSES], k;
    int number, item;
    Amount quantity = 0, value = 0;
    size_t i;
    if (!lot) return;
    number = (int)(lot - lots);
    item = lot->item;
    for (i = 0; i < stock_count; ++i)
        if (stocks[i].active && stocks[i].lot == number) {
            quantity += stocks[i].quantity;
            value += stocks[i].quantity * stocks[i].cost;
        }
    if (!quantity) {
        printf("ERROR nothing to recall %s\n", text);
        return;
    }
    lot->removed += quantity;
    accumulate(RECALLED, quantity, value);
    printf("RECALL lot %d %s qty %" PRId64 " value %s\n",
           number + 1, items[item].code, quantity, money(value));
    warehouse_order(warehouse_ordered);
    for (k = 0; k < warehouse_count; ++k) {
        int warehouse = warehouse_ordered[k];
        Amount warehouse_qty = 0, warehouse_value = 0;
        for (i = 0; i < stock_count; ++i) {
            Stock *stock = &stocks[i];
            if (stock->active && stock->lot == number && stock->warehouse == warehouse) {
                warehouse_qty += stock->quantity;
                warehouse_value += stock->quantity * stock->cost;
                stock->active = 0;
            }
        }
        if (warehouse_qty) {
            append_card(item, CARD_RECALL, warehouse, -warehouse_qty, -warehouse_value);
            printf("  %s qty %" PRId64 " value %s\n",
                   warehouses[warehouse].code, warehouse_qty, money(warehouse_value));
        }
    }
}

static void expire_command(const char *text) {
    int days = atoi(text);
    int item_indices[MAX_ITEMS], warehouse_indices[MAX_WAREHOUSES], a, b;
    Amount total_quantity = 0, total_value = 0;
    size_t i;
    item_order(item_indices);
    warehouse_order(warehouse_indices);
    printf("EXPIRE %d\n", days);
    for (a = 0; a < item_count; ++a) {
        int item = item_indices[a];
        for (b = 0; b < warehouse_count; ++b) {
            int warehouse = warehouse_indices[b], expired_lots = 0;
            Amount quantity = 0, value = 0;
            for (i = 0; i < stock_count; ++i) {
                Stock *stock = &stocks[i];
                if (!stock->active || stock->item != item ||
                    stock->warehouse != warehouse ||
                    current_day - lots[stock->lot].day <= days)
                    continue;
                ++expired_lots;
                quantity += stock->quantity;
                value += stock->quantity * stock->cost;
                lots[stock->lot].removed += stock->quantity;
                stock->active = 0;
            }
            if (expired_lots) {
                accumulate(EXPIRED, quantity, value);
                append_card(item, CARD_EXPIRE, warehouse, -quantity, -value);
                total_quantity += quantity;
                total_value += value;
                printf("  %s %s lots %d qty %" PRId64 " value %s\n",
                       items[item].code, warehouses[warehouse].code,
                       expired_lots, quantity, money(value));
            }
        }
    }
    printf("  total qty %" PRId64 " value %s\n", total_quantity, money(total_value));
}

static void value_command(int selected_warehouse) {
    int item_indices[MAX_ITEMS], warehouse_indices[MAX_WAREHOUSES];
    int a, b, count = warehouse_count;
    Amount total_quantity = 0, total_value = 0;
    if (selected_warehouse >= 0) {
        warehouse_indices[0] = selected_warehouse;
        count = 1;
        printf("VALUE %s\n", warehouses[selected_warehouse].code);
    } else {
        warehouse_order(warehouse_indices);
        puts("VALUE");
    }
    item_order(item_indices);
    for (a = 0; a < item_count; ++a) {
        int item = item_indices[a];
        Amount quantity = 0, value = 0;
        for (b = 0; b < count; ++b) {
            int warehouse = warehouse_indices[b];
            quantity += onhand(warehouse, item);
            value += stock_value(warehouse, item);
        }
        if (!quantity) continue;
        printf("  %s qty %" PRId64 " value %s avg %s\n",
               items[item].code, quantity, money(value), money(value / quantity));
        if (selected_warehouse < 0) {
            for (b = 0; b < count; ++b) {
                int warehouse = warehouse_indices[b];
                Amount held = onhand(warehouse, item);
                if (held)
                    printf("    %s qty %" PRId64 " value %s\n",
                           warehouses[warehouse].code, held, money(stock_value(warehouse, item)));
            }
        }
        total_quantity += quantity;
        total_value += value;
    }
    printf("  total qty %" PRId64 " value %s\n", total_quantity, money(total_value));
}

static int compare_fifo_stock(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return earlier_stock(&stocks[a], &stocks[b]) ? -1 :
           earlier_stock(&stocks[b], &stocks[a]) ? 1 : 0;
}

static void lots_command(char **a) {
    int warehouse, item;
    int *indices = NULL, count = 0, capacity = 0, k, printed = 0, order;
    size_t i;
    if (!require_pair(a[0], a[1], &warehouse, &item)) return;
    printf("LOTS %s %s\n", a[0], a[1]);
    for (i = 0; i < stock_count; ++i) {
        if (stocks[i].active && stocks[i].warehouse == warehouse &&
            stocks[i].item == item) {
            if (count >= capacity) {
                capacity = capacity ? 2 * capacity : 16;
                indices = realloc(indices, sizeof(int) * (size_t)capacity);
                if (!indices) exit(EXIT_FAILURE);
            }
            indices[count++] = (int)i;
        }
    }
    qsort(indices, (size_t)count, sizeof(int), compare_fifo_stock);
    for (k = 0; k < count; ++k) {
        Stock *stock = &stocks[indices[k]];
        int day = lots[stock->lot].day;
        printf("  lot %d day %d qty %" PRId64 " cost %s value %s age %d\n",
               stock->lot + 1, day, stock->quantity, money(stock->cost),
               money(stock->quantity * stock->cost), current_day - day);
        ++printed;
    }
    free(indices);
    for (order = 0; order < order_count; ++order) {
        Order *entry = &orders[order];
        if (entry->warehouse == warehouse && entry->item == item && entry->backorder) {
            printf("  backorder order %d qty %" PRId64 "\n", order + 1, entry->backorder);
            ++printed;
        }
    }
    if (!printed) puts("  (none)");
}

static void reorder_command(void) {
    int item_indices[MAX_ITEMS], i, printed = 0;
    item_order(item_indices);
    puts("REORDER");
    for (i = 0; i < item_count; ++i) {
        int item = item_indices[i];
        Amount held = item_onhand(item), backorder = item_backorder(item);
        if (held - backorder <= items[item].level) {
            printf("  %s %s onhand %" PRId64 " backorder %" PRId64 " level %d\n",
                   items[item].code, items[item].name, held, backorder, items[item].level);
            ++printed;
        }
    }
    if (!printed) puts("  (none)");
}

static void items_command(void) {
    int item_indices[MAX_ITEMS], i;
    item_order(item_indices);
    puts("ITEMS");
    for (i = 0; i < item_count; ++i) {
        int item = item_indices[i];
        printf("  %s %s level %d onhand %" PRId64 " backorder %" PRId64 " cost %s\n",
               items[item].code, items[item].name, items[item].level,
               item_onhand(item), item_backorder(item),
               items[item].received_cost ? money(items[item].last_cost) : "none");
    }
    if (item_count == 0) puts("  (none)");
}

typedef struct {
    Amount sold;
    Amount revenue;
    Amount cogs;
    int has_order;
} Sales;

static void summaries(Sales *values) {
    int i;
    memset(values, 0, sizeof(Sales) * (size_t)item_count);
    for (i = 0; i < order_count; ++i) {
        Order *order = &orders[i];
        Sales *summary = &values[order->item];
        summary->has_order = 1;
        summary->sold += order->shipped - order->returned;
        summary->revenue += order->revenue;
        summary->cogs += order->cogs;
    }
}

static void margin_line(const char *label, Sales sales) {
    printf("  %s sold %" PRId64 " revenue %s cogs %s profit %s margin %s\n",
           label, sales.sold, money(sales.revenue), money(sales.cogs),
           money(sales.revenue - sales.cogs),
           margin(sales.revenue - sales.cogs, sales.revenue));
}

static void margin_command(void) {
    Sales values[MAX_ITEMS], total = {0};
    int indices[MAX_ITEMS], i;
    summaries(values);
    item_order(indices);
    puts("MARGIN");
    for (i = 0; i < item_count; ++i) {
        int item = indices[i];
        if (!values[item].has_order) continue;
        margin_line(items[item].code, values[item]);
        total.sold += values[item].sold;
        total.revenue += values[item].revenue;
        total.cogs += values[item].cogs;
    }
    margin_line("total", total);
}

static Sales top_values[MAX_ITEMS];

static int top_comparator(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    Amount a_profit = top_values[a].revenue - top_values[a].cogs;
    Amount b_profit = top_values[b].revenue - top_values[b].cogs;
    if (a_profit != b_profit) return a_profit > b_profit ? -1 : 1;
    if (top_values[a].revenue != top_values[b].revenue)
        return top_values[a].revenue > top_values[b].revenue ? -1 : 1;
    return strcmp(items[a].code, items[b].code);
}

static void top_command(int count) {
    int indices[MAX_ITEMS], used = 0, i;
    summaries(top_values);
    for (i = 0; i < item_count; ++i)
        if (top_values[i].has_order) indices[used++] = i;
    qsort(indices, (size_t)used, sizeof(int), top_comparator);
    printf("TOP %d\n", count);
    for (i = 0; i < count && i < used; ++i) {
        int item = indices[i];
        Amount revenue = top_values[item].revenue;
        Amount profit = revenue - top_values[item].cogs;
        printf("  %d %s profit %s revenue %s margin %s\n",
               i + 1, items[item].code, money(profit),
               money(revenue), margin(profit, revenue));
    }
    if (!used) puts("  (none)");
}

static void aging_line(const char *label, const Amount *buckets, int monetary) {
    if (monetary) {
        printf("  %s 0-30 %s 31-60 %s 61-90 %s 91+ %s\n",
               label, money(buckets[0]), money(buckets[1]),
               money(buckets[2]), money(buckets[3]));
    } else {
        printf("  %s 0-30 %" PRId64 " 31-60 %" PRId64 " 61-90 %" PRId64 " 91+ %" PRId64 "\n",
               label, buckets[0], buckets[1], buckets[2], buckets[3]);
    }
}

static void aging_command(int selected_warehouse) {
    int item_indices[MAX_ITEMS], i, item, bucket;
    int warehouse_indices[MAX_WAREHOUSES], warehouse, w, count = warehouse_count;
    Amount total_quantities[4] = {0}, total_values[4] = {0};
    size_t s;
    item_order(item_indices);
    if (selected_warehouse < 0) {
        warehouse_order(warehouse_indices);
        printf("AGING day %d\n", current_day);
    } else {
        warehouse_indices[0] = selected_warehouse;
        count = 1;
        printf("AGING %s day %d\n",
               warehouses[selected_warehouse].code, current_day);
    }
    for (i = 0; i < item_count; ++i) {
        Amount quantities[4] = {0};
        item = item_indices[i];
        for (w = 0; w < count; ++w) {
            warehouse = warehouse_indices[w];
            for (s = 0; s < stock_count; ++s) {
                Stock *stock = &stocks[s];
                int age;
                if (!stock->active || stock->item != item ||
                    stock->warehouse != warehouse) continue;
                age = current_day - lots[stock->lot].day;
                bucket = age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3;
                quantities[bucket] += stock->quantity;
                total_quantities[bucket] += stock->quantity;
                total_values[bucket] += stock->quantity * stock->cost;
            }
        }
        if (quantities[0] || quantities[1] || quantities[2] || quantities[3])
            aging_line(items[item].code, quantities, 0);
    }
    aging_line("total", total_quantities, 0);
    aging_line("value", total_values, 1);
}

static void backorders_command(void) {
    int i, printed = 0;
    puts("BACKORDERS");
    for (i = 0; i < order_count; ++i) {
        Order *order = &orders[i];
        if (order->backorder) {
            printf("  order %d %s %s qty %" PRId64 " day %d price %s\n",
                   i + 1, warehouses[order->warehouse].code,
                   items[order->item].code, order->backorder,
                   order->day, money(order->price));
            ++printed;
        }
    }
    if (!printed) puts("  (none)");
}

static void order_command(const char *text) {
    Order *order = require_order(text);
    size_t i;
    if (!order) return;
    printf("ORDER %ld %s %s day %d price %s\n",
           (long)(order - orders) + 1,
           warehouses[order->warehouse].code, items[order->item].code,
           order->day, money(order->price));
    printf("  ordered %" PRId64 " shipped %" PRId64 " backorder %" PRId64
           " cancelled %" PRId64 " returned %" PRId64 "\n",
           order->ordered, order->shipped, order->backorder,
           order->cancelled, order->returned);
    for (i = 0; i < order->issues.length; ++i) {
        Part *part = &order->issues.entries[i];
        printf("  lot %d qty %" PRId64 " cost %s\n",
               part->lot + 1, part->quantity, money(part->cost));
    }
    printf("  revenue %s cogs %s profit %s\n",
           money(order->revenue), money(order->cogs),
           money(order->revenue - order->cogs));
}

static void trace_command(const char *text) {
    Lot *lot = require_lot(text);
    int ordered[MAX_WAREHOUSES], i, w, order_number;
    size_t j, k;
    if (!lot) return;
    i = (int)(lot - lots);
    printf("TRACE lot %d %s %s %s day %d qty %" PRId64 " cost %s\n",
           i + 1, items[lot->item].code, lot_kinds[lot->kind],
           warehouses[lot->warehouse].code, lot->day, lot->quantity,
           money(lot->cost));
    warehouse_order(ordered);
    for (w = 0; w < warehouse_count; ++w) {
        int warehouse = ordered[w];
        for (j = 0; j < stock_count; ++j) {
            Stock *stock = &stocks[j];
            if (stock->active && stock->lot == i && stock->warehouse == warehouse)
                printf("  held %s qty %" PRId64 " cost %s\n",
                       warehouses[warehouse].code, stock->quantity, money(stock->cost));
        }
    }
    for (order_number = 0; order_number < order_count; ++order_number) {
        Amount quantity = 0;
        Order *order = &orders[order_number];
        for (k = 0; k < order->issues.length; ++k)
            if (order->issues.entries[k].lot == i)
                quantity += order->issues.entries[k].quantity;
        if (quantity) printf("  order %d qty %" PRId64 "\n", order_number + 1, quantity);
    }
    if (lot->removed) printf("  removed qty %" PRId64 "\n", lot->removed);
}

static void card_command(const char *code) {
    int item = require_item(code);
    Amount quantity = 0, value = 0;
    size_t i;
    int printed = 0;
    if (item < 0) return;
    printf("CARD %s %s\n", items[item].code, items[item].name);
    for (i = 0; i < card_count; ++i) {
        const CardEntry *entry = &cards[i];
        if (entry->item != item) continue;
        quantity += entry->quantity;
        value += entry->value;
        printf("  day %d %s %s %s %s balance %" PRId64 " %s\n",
               entry->day, card_kinds[entry->kind],
               warehouses[entry->warehouse].code,
               signed_quantity(entry->quantity), signed_money(entry->value),
               quantity, money(value));
        ++printed;
    }
    if (!printed) puts("  (none)");
}

static void status_command(void) {
    int ordered[MAX_WAREHOUSES], i, w;
    size_t j;
    warehouse_order(ordered);
    puts("STATUS");
    for (i = 0; i < warehouse_count; ++i) {
        Amount quantity = 0, value = 0, backorder = 0;
        int skus = 0, seen[MAX_ITEMS] = {0};
        w = ordered[i];
        for (j = 0; j < stock_count; ++j) {
            Stock *stock = &stocks[j];
            if (!stock->active || stock->warehouse != w) continue;
            seen[stock->item] = 1;
            quantity += stock->quantity;
            value += stock->quantity * stock->cost;
        }
        for (j = 0; j < (size_t)item_count; ++j) skus += seen[j];
        for (j = 0; j < (size_t)order_count; ++j)
            if (orders[j].warehouse == w) backorder += orders[j].backorder;
        printf("  %s skus %d qty %" PRId64 " value %s backorder %" PRId64 "\n",
               warehouses[w].code, skus, quantity, money(value), backorder);
    }
    if (!warehouse_count) puts("  (none)");
}

static void summary_command(void) {
    Amount quantity = 0, value = 0, backorder = 0;
    int i, open = 0;
    size_t j;
    puts("SUMMARY");
    for (i = 0; i < 8; ++i)
        printf("  %s qty %" PRId64 " value %s\n",
               category_names[i], totals[i].quantity, money(totals[i].value));
    for (j = 0; j < stock_count; ++j) {
        if (!stocks[j].active) continue;
        quantity += stocks[j].quantity;
        value += stocks[j].quantity * stocks[j].cost;
    }
    for (i = 0; i < order_count; ++i) {
        if (orders[i].backorder) ++open;
        backorder += orders[i].backorder;
    }
    printf("  on-hand qty %" PRId64 " value %s\n", quantity, money(value));
    printf("  orders %d open %d backorder %" PRId64 "\n", order_count, open, backorder);
}

static void execute(char *line) {
    char *tokens[8];
    char *command;
    int count = 0;
    char *token = strtok(line, " ");
    if (!token) return;
    command = token;
    while ((token = strtok(NULL, " ")) != NULL)
        tokens[count++] = token;
    if (strcmp(command, "DAY") == 0) day_command(tokens[0]);
    else if (strcmp(command, "WAREHOUSE") == 0) warehouse_command(tokens[0]);
    else if (strcmp(command, "ITEM") == 0)
        item_command(tokens[0], tokens[1], tokens[2]);
    else if (strcmp(command, "RECEIVE") == 0) receive_command(tokens);
    else if (strcmp(command, "SHIP") == 0) ship_command(tokens);
    else if (strcmp(command, "CANCEL") == 0) cancel_command(tokens[0]);
    else if (strcmp(command, "TRANSFER") == 0) transfer_command(tokens);
    else if (strcmp(command, "ADJUST") == 0) adjust_command(tokens);
    else if (strcmp(command, "RETURN") == 0) return_command(tokens);
    else if (strcmp(command, "COUNT") == 0) count_command(tokens);
    else if (strcmp(command, "MARKET") == 0) market_command(tokens);
    else if (strcmp(command, "RECALL") == 0) recall_command(tokens[0]);
    else if (strcmp(command, "EXPIRE") == 0) expire_command(tokens[0]);
    else if (strcmp(command, "VALUE") == 0) {
        int warehouse = -1;
        if (count && (warehouse = require_warehouse(tokens[0])) < 0) return;
        value_command(warehouse);
    } else if (strcmp(command, "LOTS") == 0) lots_command(tokens);
    else if (strcmp(command, "REORDER") == 0) reorder_command();
    else if (strcmp(command, "ITEMS") == 0) items_command();
    else if (strcmp(command, "MARGIN") == 0) margin_command();
    else if (strcmp(command, "TOP") == 0) top_command(atoi(tokens[0]));
    else if (strcmp(command, "AGING") == 0) {
        int warehouse = -1;
        if (count && (warehouse = require_warehouse(tokens[0])) < 0) return;
        aging_command(warehouse);
    } else if (strcmp(command, "BACKORDERS") == 0) backorders_command();
    else if (strcmp(command, "ORDER") == 0) order_command(tokens[0]);
    else if (strcmp(command, "TRACE") == 0) trace_command(tokens[0]);
    else if (strcmp(command, "CARD") == 0) card_command(tokens[0]);
    else if (strcmp(command, "STATUS") == 0) status_command();
    else if (strcmp(command, "SUMMARY") == 0) summary_command();
}

int main(void) {
    char line[1024];
    int count, i;
    if (!fgets(line, sizeof(line), stdin)) return 0;
    count = atoi(line);
    for (i = 0; i < count; ++i) {
        if (!fgets(line, sizeof(line), stdin)) break;
        line[strcspn(line, "\r\n")] = '\0';
        execute(line);
    }
    for (i = 0; i < order_count; ++i) free(orders[i].issues.entries);
    free(cards);
    free(stocks);
    return 0;
}
