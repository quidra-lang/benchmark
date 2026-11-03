#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int64_t Money;
typedef struct { char text[32]; } Text;
typedef enum { ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE, CONTRA_ASSET } AccountType;
typedef enum { JOURNAL, RECURRING, REVERSAL, CLOSING, REOPEN, DEPRECIATION, INTEREST, WRITEOFF } Category;

static const char *TYPE_NAMES[] = {"ASSET", "LIABILITY", "EQUITY", "REVENUE", "EXPENSE", "CONTRA_ASSET"};
static const char *CATEGORY_NAMES[] = {"journal", "recurring", "reversal", "closing", "reopen", "depreciation", "interest", "writeoff"};

typedef struct {
    char code[7], name[25];
    AccountType type;
    int index;
    bool active;
} Account;

typedef struct { Money debit, credit; } Totals;
typedef struct {
    char code[7];
    Account *account;
    Money amount;
    int partner;
    bool debit;
} Line;

typedef struct Lines {
    Line *items;
    size_t count, capacity;
    Totals amount, accounts[200];
    int used[200], used_count;
    struct Lines *next;
} Lines;

typedef struct Entry {
    char id[21], memo[25];
    int date, sequence;
    Category category;
    Lines *lines;
    struct Entry *reverses, *reversed_by;
} Entry;

typedef struct {
    char name[9], memo[25];
    Lines *lines;
    int uses;
} Template;

typedef struct {
    char key[9], date[11], memo[25];
    bool journal;
    Lines *lines;
} Draft;

typedef struct { int date; Entry *entry; } CloseRecord;
typedef struct {
    Account accounts[200];
    Account *account_order[200];
    int account_count;
    Entry **entries, **ordered;
    size_t entry_count, entry_capacity, ordered_capacity;
    bool order_dirty;
    Template templates[50];
    int template_count;
    char partners[1000][13];
    int partner_count;
    Draft draft;
    bool has_draft;
    CloseRecord closes[1000];
    int close_count, close_counter, depreciation_counter, interest_counter, writeoff_counter;
    Lines *line_storage;
} Book;

typedef struct { Entry *entry; Money original, remaining; } OpenItem;
typedef struct {
    OpenItem *items;
    size_t head, count, capacity;
    Money unapplied;
} OpenItems;
typedef struct { int index; const char *name; } Partner;
typedef struct { Partner items[1000]; int count; } Partners;

static void *allocate(size_t count, size_t size) {
    void *result = calloc(count, size);
    if (!result) exit(EXIT_FAILURE);
    return result;
}

static void *resize(void *memory, size_t size) {
    void *result = realloc(memory, size);
    if (!result) exit(EXIT_FAILURE);
    return result;
}

static bool fail(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    fputs("ERROR ", stdout);
    vprintf(format, arguments);
    putchar('\n');
    va_end(arguments);
    return false;
}

static Money minimum(Money left, Money right) { return left < right ? left : right; }
static Money absolute(Money value) { return value < 0 ? -value : value; }
static int normal_sign(const Account *account) { return account->type == ASSET || account->type == EXPENSE ? 1 : -1; }
static AccountType type_class(AccountType type) { return type == CONTRA_ASSET ? ASSET : type; }
static bool prefix(const char *start, const char *text) { return strncmp(start, text, strlen(start)) == 0; }

static Text money(Money cents) {
    Text result;
    Money value = absolute(cents);
    snprintf(result.text, sizeof result.text, "%s%" PRId64 ".%02" PRId64,
             cents < 0 ? "-" : "", value / 100, value % 100);
    return result;
}

static Money parse_money(const char *text) {
    return strtoll(text, NULL, 10) * 100 + strtoll(strchr(text, '.') + 1, NULL, 10);
}

static bool leap(int year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }
static int month_days(int year, int month) {
    static const int days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return days[month - 1] + (month == 2 && leap(year));
}

static int day_number(int year, int month, int day) {
    int result = day - 1;
    for (int y = 2000; y < year; y++) result += 365 + leap(y);
    for (int m = 1; m < month; m++) result += month_days(year, m);
    return result;
}

static void date_parts(int number, int *year, int *month, int *day) {
    *year = 2000;
    while (number >= 365 + leap(*year)) {
        number -= 365 + leap(*year);
        (*year)++;
    }
    *month = 1;
    while (number >= month_days(*year, *month)) {
        number -= month_days(*year, *month);
        (*month)++;
    }
    *day = number + 1;
}

static Text date_text(int number) {
    Text result;
    int year, month, day;
    date_parts(number, &year, &month, &day);
    snprintf(result.text, sizeof result.text, "%04d-%02d-%02d", year, month, day);
    return result;
}

static bool check_date(const char *text, int *number) {
    int year = atoi(text), month = atoi(text + 5), day = atoi(text + 8);
    if (year < 2000 || year > 2099 || month < 1 || month > 12 || day < 1 || day > month_days(year, month)) {
        return fail("invalid date %s", text);
    }
    *number = day_number(year, month, day);
    return true;
}

static bool check_range(const char *first, const char *last, int *start, int *end) {
    if (!check_date(first, start) || !check_date(last, end)) return false;
    return *start <= *end || fail("invalid range %s %s", first, last);
}

static int months_after(int date, int months) {
    int year, month, day;
    date_parts(date, &year, &month, &day);
    int total = month - 1 + months;
    year += total / 12;
    month = total % 12 + 1;
    if (day > month_days(year, month)) day = month_days(year, month);
    return day_number(year, month, day);
}

static bool check_open(const Book *book, int date) {
    return book->close_count == 0 || date > book->closes[book->close_count - 1].date ||
        fail("period closed %s", date_text(date).text);
}

static Text closed_text(const Book *book) {
    if (book->close_count) return date_text(book->closes[book->close_count - 1].date);
    Text result = {"none"};
    return result;
}

static Account *find_account(const Book *book, const char *code) {
    int low = 0, high = book->account_count;
    while (low < high) {
        int middle = (low + high) / 2;
        int comparison = strcmp(book->account_order[middle]->code, code);
        if (comparison < 0) low = middle + 1;
        else if (comparison > 0) high = middle;
        else return book->account_order[middle];
    }
    return NULL;
}

static Account *require_account(const Book *book, const char *code) {
    Account *account = find_account(book, code);
    if (!account) fail("unknown account %s", code);
    return account;
}

static Account *require_type(const Book *book, const char *code, AccountType type) {
    Account *account = require_account(book, code);
    if (account && account->type != type) {
        fail("wrong type %s %s", code, TYPE_NAMES[type]);
        return NULL;
    }
    return account;
}

static bool require_active(const Account *account) {
    return account->active || fail("inactive account %s", account->code);
}

static Account *parent_account(const Book *book, const Account *account) {
    Account *parent = NULL;
    for (int i = 0; i < book->account_count; i++) {
        Account *candidate = book->account_order[i];
        if (candidate != account && prefix(candidate->code, account->code) &&
            (!parent || strlen(candidate->code) > strlen(parent->code))) parent = candidate;
    }
    return parent;
}

static const char *parent_code(const Book *book, const Account *account) {
    Account *parent = parent_account(book, account);
    return parent ? parent->code : "none";
}

static int partner_index(Book *book, const char *name) {
    for (int i = 0; i < book->partner_count; i++) if (strcmp(book->partners[i], name) == 0) return i;
    int index = book->partner_count++;
    strcpy(book->partners[index], name);
    return index;
}

static Lines *new_lines(Book *book) {
    Lines *lines = allocate(1, sizeof *lines);
    lines->next = book->line_storage;
    book->line_storage = lines;
    return lines;
}

static void add_account_total(Lines *lines, const Line *line) {
    int index = line->account->index;
    Totals *total = &lines->accounts[index];
    if (total->debit == 0 && total->credit == 0) lines->used[lines->used_count++] = index;
    if (line->debit) total->debit += line->amount;
    else total->credit += line->amount;
}

static void append_line(Lines *lines, Line line) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? lines->capacity * 2 : 4;
        lines->items = resize(lines->items, lines->capacity * sizeof *lines->items);
    }
    lines->items[lines->count++] = line;
    if (line.debit) lines->amount.debit += line.amount;
    else lines->amount.credit += line.amount;
    if (line.account) add_account_total(lines, &line);
}

static void generated_line(Lines *lines, bool debit, Account *account, Money amount, int partner) {
    Line line = {.account = account, .amount = amount, .partner = partner, .debit = debit};
    strcpy(line.code, account->code);
    append_line(lines, line);
}

static bool validate_lines(const Book *book, Draft *draft) {
    Lines *lines = draft->lines;
    if (lines->count < 2) return fail("too few lines %s", draft->key);
    for (size_t i = 0; i < lines->count; i++) {
        Line *line = &lines->items[i];
        Account *account = require_account(book, line->code);
        if (!account) return false;
        if (draft->journal && !require_active(account)) return false;
        if (line->amount == 0) return fail("zero amount %s", line->code);
        line->account = account;
        add_account_total(lines, line);
    }
    if (lines->amount.debit != lines->amount.credit) {
        return fail("unbalanced %s debit %s credit %s", draft->key,
                    money(lines->amount.debit).text, money(lines->amount.credit).text);
    }
    return true;
}

static Entry *find_entry(const Book *book, const char *id) {
    for (size_t i = 0; i < book->entry_count; i++) if (strcmp(book->entries[i]->id, id) == 0) return book->entries[i];
    return NULL;
}

static Template *find_template(Book *book, const char *name) {
    for (int i = 0; i < book->template_count; i++) if (strcmp(book->templates[i].name, name) == 0) return &book->templates[i];
    return NULL;
}

static Entry *post(Book *book, const char *id, int date, Category category, const char *memo, Lines *lines) {
    Entry *entry = allocate(1, sizeof *entry);
    strcpy(entry->id, id);
    strcpy(entry->memo, memo);
    entry->date = date;
    entry->category = category;
    entry->lines = lines;
    entry->sequence = (int) book->entry_count + 1;
    if (book->entry_count == book->entry_capacity) {
        book->entry_capacity = book->entry_capacity ? book->entry_capacity * 2 : 16;
        book->entries = resize(book->entries, book->entry_capacity * sizeof *book->entries);
    }
    book->entries[book->entry_count++] = entry;
    book->order_dirty = true;
    return entry;
}

static bool active_lines(const Lines *lines) {
    for (size_t i = 0; i < lines->count; i++) if (!require_active(lines->items[i].account)) return false;
    return true;
}

static Entry *reverse_entry(Book *book, Entry *original, int date, Category category, const char *memo) {
    Lines *lines = new_lines(book);
    for (size_t i = 0; i < original->lines->count; i++) {
        Line line = original->lines->items[i];
        line.debit = !line.debit;
        append_line(lines, line);
    }
    char id[21];
    snprintf(id, sizeof id, "%s-R", original->id);
    Entry *entry = post(book, id, date, category, memo, lines);
    original->reversed_by = entry;
    entry->reverses = original;
    return entry;
}

static int compare_entries(const void *left, const void *right) {
    const Entry *a = *(Entry *const *) left, *b = *(Entry *const *) right;
    return a->date != b->date ? a->date - b->date : a->sequence - b->sequence;
}

static Entry **posting_order(Book *book) {
    if (book->order_dirty) {
        if (book->ordered_capacity < book->entry_count) {
            book->ordered_capacity = book->entry_count;
            book->ordered = resize(book->ordered, book->ordered_capacity * sizeof *book->ordered);
        }
        memcpy(book->ordered, book->entries, book->entry_count * sizeof *book->ordered);
        qsort(book->ordered, book->entry_count, sizeof *book->ordered, compare_entries);
        book->order_dirty = false;
    }
    return book->ordered;
}

static Totals account_totals(const Book *book, const Account *account, int start, int end) {
    Totals result = {0};
    for (size_t i = 0; i < book->entry_count; i++) {
        const Entry *entry = book->entries[i];
        if (entry->date < start || entry->date > end) continue;
        Totals amount = entry->lines->accounts[account->index];
        result.debit += amount.debit;
        result.credit += amount.credit;
    }
    return result;
}

static Money balance(const Book *book, const Account *account, int end) {
    Totals total = account_totals(book, account, 0, end);
    return normal_sign(account) * (total.debit - total.credit);
}

static void all_totals(const Book *book, int start, int end, bool income, Totals result[200]) {
    memset(result, 0, 200 * sizeof *result);
    for (size_t i = 0; i < book->entry_count; i++) {
        const Entry *entry = book->entries[i];
        if (entry->date < start || entry->date > end || (income && (entry->category == CLOSING || entry->category == REOPEN))) continue;
        const Lines *lines = entry->lines;
        for (int j = 0; j < lines->used_count; j++) {
            int index = lines->used[j];
            result[index].debit += lines->accounts[index].debit;
            result[index].credit += lines->accounts[index].credit;
        }
    }
}

static Money daily_sum(const Book *book, const Account *account, int start, int end) {
    int days = end - start + 1;
    Money *changes = allocate((size_t) days, sizeof *changes);
    Money running = 0, total = 0;
    int sign = normal_sign(account);
    for (size_t i = 0; i < book->entry_count; i++) {
        const Entry *entry = book->entries[i];
        if (entry->date > end) continue;
        Totals amount = entry->lines->accounts[account->index];
        Money change = sign * (amount.debit - amount.credit);
        if (entry->date < start) running += change;
        else changes[entry->date - start] += change;
    }
    for (int day = 0; day < days; day++) {
        running += changes[day];
        total += running;
    }
    free(changes);
    return total;
}

static int compare_partners(const void *left, const void *right) {
    const Partner *a = left, *b = right;
    return strcmp(a->name, b->name);
}

static Partners account_partners(const Book *book, const Account *account, int date) {
    bool seen[1000] = {false};
    for (size_t i = 0; i < book->entry_count; i++) {
        const Entry *entry = book->entries[i];
        if (entry->date > date) continue;
        for (size_t j = 0; j < entry->lines->count; j++) {
            const Line *line = &entry->lines->items[j];
            if (line->account == account && line->partner >= 0) seen[line->partner] = true;
        }
    }
    Partners result = {.count = 0};
    for (int i = 0; i < book->partner_count; i++) {
        if (seen[i]) result.items[result.count++] = (Partner) {i, book->partners[i]};
    }
    qsort(result.items, (size_t) result.count, sizeof *result.items, compare_partners);
    return result;
}

static void append_item(OpenItems *items, OpenItem item) {
    if (items->count == items->capacity) {
        if (items->head) {
            items->count -= items->head;
            memmove(items->items, items->items + items->head, items->count * sizeof *items->items);
            items->head = 0;
        } else {
            items->capacity = items->capacity ? items->capacity * 2 : 8;
            items->items = resize(items->items, items->capacity * sizeof *items->items);
        }
    }
    items->items[items->count++] = item;
}

static OpenItems open_items(Book *book, const Account *account, int partner, int date) {
    OpenItems result = {0};
    Entry **ordered = posting_order(book);
    for (size_t i = 0; i < book->entry_count; i++) {
        Entry *entry = ordered[i];
        if (entry->date > date) break;
        Totals total = entry->lines->accounts[account->index];
        if (total.debit == 0 && total.credit == 0) continue;
        for (size_t j = 0; j < entry->lines->count; j++) {
            const Line *line = &entry->lines->items[j];
            if (line->account != account || line->partner != partner) continue;
            Money value = normal_sign(account) * (line->debit ? line->amount : -line->amount);
            if (value > 0) {
                Money applied = minimum(value, result.unapplied);
                result.unapplied -= applied;
                if (value > applied) append_item(&result, (OpenItem) {entry, value, value - applied});
            } else {
                Money payment = -value;
                while (payment > 0 && result.head < result.count) {
                    OpenItem *item = &result.items[result.head];
                    Money applied = minimum(payment, item->remaining);
                    payment -= applied;
                    item->remaining -= applied;
                    if (item->remaining == 0) result.head++;
                }
                result.unapplied += payment;
            }
        }
    }
    return result;
}

static Money section(const Book *book, const char *heading, unsigned types, int sign,
                     const Totals totals[200], bool show_earnings, Money earnings) {
    Money amounts[200] = {0}, total = show_earnings ? earnings : 0;
    for (int i = 0; i < book->account_count; i++) {
        const Account *account = &book->accounts[i];
        if (types & (1u << account->type)) {
            amounts[i] = sign * (totals[i].debit - totals[i].credit);
            total += amounts[i];
        }
    }
    printf("  %s %s\n", heading, money(total).text);
    for (int i = 0; i < book->account_count; i++) {
        const Account *top = book->account_order[i];
        if (parent_account(book, top)) continue;
        Money subtotal = 0;
        bool visible = false;
        for (int j = 0; j < book->account_count; j++) {
            const Account *account = book->account_order[j];
            if (!prefix(top->code, account->code)) continue;
            subtotal += amounts[account->index];
            visible |= amounts[account->index] != 0;
        }
        if (!visible) continue;
        printf("    %s %s %s\n", top->code, top->name, money(subtotal).text);
        for (int j = 0; j < book->account_count; j++) {
            const Account *account = book->account_order[j];
            if (prefix(top->code, account->code) && amounts[account->index] != 0) {
                printf("      %s %s %s\n", account->code, account->name, money(amounts[account->index]).text);
            }
        }
    }
    if (show_earnings) printf("    current earnings %s\n", money(earnings).text);
    return total;
}

static void aging_row(const char *name, const Money values[5]) {
    Money total = values[0] + values[1] + values[2] + values[3] - values[4];
    printf("  %s 0-30 %s 31-60 %s 61-90 %s 91+ %s unapplied %s balance %s\n", name,
           money(values[0]).text, money(values[1]).text, money(values[2]).text,
           money(values[3]).text, money(values[4]).text, money(total).text);
}

static int compare_templates(const void *left, const void *right) {
    const Template *a = *(Template *const *) left, *b = *(Template *const *) right;
    return strcmp(a->name, b->name);
}

static void execute(Book *book, char **words, int count) {
    const char *command = words[0];
    if (strcmp(command, "ACCOUNT") == 0) {
        if (find_account(book, words[1])) { fail("duplicate account %s", words[1]); return; }
        AccountType type = ASSET;
        while (strcmp(TYPE_NAMES[type], words[2]) != 0) type++;
        for (int i = 0; i < book->account_count; i++) {
            const Account *other = book->account_order[i];
            if ((prefix(other->code, words[1]) || prefix(words[1], other->code)) && type_class(type) != type_class(other->type)) {
                fail("class mismatch %s %s", words[1], other->code);
                return;
            }
        }
        Account *account = &book->accounts[book->account_count];
        strcpy(account->code, words[1]);
        strcpy(account->name, words[3]);
        account->type = type;
        account->index = book->account_count;
        account->active = true;
        int position = book->account_count++;
        while (position > 0 && strcmp(book->account_order[position - 1]->code, account->code) > 0) {
            book->account_order[position] = book->account_order[position - 1];
            position--;
        }
        book->account_order[position] = account;
        printf("ACCOUNT %s %s %s parent %s\n", account->code, TYPE_NAMES[type], account->name, parent_code(book, account));
    } else if (strcmp(command, "DEACTIVATE") == 0) {
        Account *account = require_account(book, words[1]);
        if (!account) return;
        if (!account->active) { fail("already inactive %s", words[1]); return; }
        Money current = balance(book, account, 36600);
        if (current != 0) { fail("nonzero balance %s %s", words[1], money(current).text); return; }
        account->active = false;
        printf("DEACTIVATE %s %s\n", account->code, account->name);
    } else if (strcmp(command, "JOURNAL") == 0 || strcmp(command, "TEMPLATE") == 0) {
        if (book->has_draft) printf("DISCARD %s lines %zu\n", book->draft.key, book->draft.lines->count);
        book->draft.journal = strcmp(command, "JOURNAL") == 0;
        strcpy(book->draft.key, words[1]);
        strcpy(book->draft.memo, words[book->draft.journal ? 3 : 2]);
        if (book->draft.journal) strcpy(book->draft.date, words[2]);
        book->draft.lines = new_lines(book);
        book->has_draft = true;
    } else if (strcmp(command, "DR") == 0 || strcmp(command, "CR") == 0) {
        if (!book->has_draft) { fail("no open entry"); return; }
        Line line = {.amount = parse_money(words[2]), .partner = count == 4 ? partner_index(book, words[3]) : -1,
                     .debit = strcmp(command, "DR") == 0};
        strcpy(line.code, words[1]);
        append_line(book->draft.lines, line);
    } else if (strcmp(command, "POST") == 0) {
        if (!book->has_draft) { fail("no open entry"); return; }
        Draft draft = book->draft;
        book->has_draft = false;
        if (draft.journal) {
            if (find_entry(book, draft.key)) { fail("duplicate entry %s", draft.key); return; }
            int date;
            if (!check_date(draft.date, &date) || !check_open(book, date) || !validate_lines(book, &draft)) return;
            Entry *entry = post(book, draft.key, date, JOURNAL, draft.memo, draft.lines);
            printf("POST %s %s lines %zu amount %s\n", entry->id, date_text(date).text, entry->lines->count, money(entry->lines->amount.debit).text);
        } else {
            if (find_template(book, draft.key)) { fail("duplicate template %s", draft.key); return; }
            if (!validate_lines(book, &draft)) return;
            Template *pattern = &book->templates[book->template_count++];
            strcpy(pattern->name, draft.key);
            strcpy(pattern->memo, draft.memo);
            pattern->lines = draft.lines;
            pattern->uses = 0;
            printf("TEMPLATE %s lines %zu amount %s\n", pattern->name, pattern->lines->count, money(pattern->lines->amount.debit).text);
        }
    } else if (strcmp(command, "DRAFT") == 0) {
        if (!book->has_draft) { fail("no open entry"); return; }
        Totals totals = book->draft.lines->amount;
        printf("DRAFT %s %s lines %zu debit %s credit %s difference %s\n", book->draft.journal ? "journal" : "template",
               book->draft.key, book->draft.lines->count, money(totals.debit).text, money(totals.credit).text, money(totals.debit - totals.credit).text);
    } else if (strcmp(command, "REVERSE") == 0) {
        Entry *entry = find_entry(book, words[1]);
        if (!entry) { fail("unknown entry %s", words[1]); return; }
        if (entry->category == REVERSAL || entry->category == CLOSING || entry->category == REOPEN) {
            fail("cannot reverse %s", words[1]); return;
        }
        if (entry->reversed_by) { fail("already reversed %s", words[1]); return; }
        int date;
        if (!check_date(words[2], &date)) return;
        if (date < entry->date) { fail("reverse before entry %s %s", words[1], date_text(entry->date).text); return; }
        if (!check_open(book, date) || !active_lines(entry->lines)) return;
        Entry *reversal = reverse_entry(book, entry, date, REVERSAL, entry->memo);
        printf("REVERSE %s entry %s %s amount %s\n", entry->id, reversal->id, date_text(date).text, money(reversal->lines->amount.debit).text);
    } else if (strcmp(command, "RECUR") == 0) {
        Template *pattern = find_template(book, words[1]);
        if (!pattern) { fail("unknown template %s", words[1]); return; }
        int date, repetitions = atoi(words[3]);
        if (!check_date(words[2], &date)) return;
        if (repetitions == 0) { fail("invalid count"); return; }
        if (!check_open(book, date) || !active_lines(pattern->lines)) return;
        printf("RECUR %s count %d\n", pattern->name, repetitions);
        for (int i = 0; i < repetitions; i++) {
            char id[21];
            snprintf(id, sizeof id, "%s-%d", pattern->name, ++pattern->uses);
            Entry *entry = post(book, id, months_after(date, i), RECURRING, pattern->memo, pattern->lines);
            printf("  POST %s %s lines %zu amount %s\n", entry->id, date_text(entry->date).text, entry->lines->count, money(entry->lines->amount.debit).text);
        }
    } else if (strcmp(command, "DEPRECIATE") == 0) {
        int date;
        if (!check_date(words[1], &date) || !check_open(book, date)) return;
        Account *asset = require_type(book, words[2], ASSET);
        if (!asset) return;
        Account *contra = require_type(book, words[3], CONTRA_ASSET);
        if (!contra) return;
        Account *expense = require_type(book, words[4], EXPENSE);
        if (!expense || !require_active(contra) || !require_active(expense)) return;
        Money cost = balance(book, asset, date), accumulated = balance(book, contra, date);
        Money amount = cost > 0 ? minimum(cost / atoi(words[5]), cost - accumulated) : 0;
        if (amount <= 0) { fail("nothing to depreciate %s", asset->code); return; }
        Lines *lines = new_lines(book);
        generated_line(lines, true, expense, amount, -1);
        generated_line(lines, false, contra, amount, -1);
        char id[21];
        snprintf(id, sizeof id, "DEP-%d", ++book->depreciation_counter);
        post(book, id, date, DEPRECIATION, "depreciation", lines);
        printf("DEPRECIATE %s entry %s %s amount %s accumulated %s book %s\n", asset->code, id, date_text(date).text,
               money(amount).text, money(accumulated + amount).text, money(cost - accumulated - amount).text);
    } else if (strcmp(command, "INTEREST") == 0) {
        Account *account = require_account(book, words[1]);
        if (!account) return;
        if (account->type != ASSET && account->type != LIABILITY) { fail("not interest bearing %s", words[1]); return; }
        Account *offset = require_type(book, words[2], account->type == ASSET ? REVENUE : EXPENSE);
        if (!offset) return;
        int start, end;
        if (!check_range(words[3], words[4], &start, &end) || !check_open(book, end) ||
            !require_active(account) || !require_active(offset)) return;
        Money sum = daily_sum(book, account, start, end);
        Money amount = sum * atoi(words[5]) / 3650000;
        if (amount <= 0) { fail("no interest %s", account->code); return; }
        Lines *lines = new_lines(book);
        generated_line(lines, true, account->type == ASSET ? account : offset, amount, -1);
        generated_line(lines, false, account->type == ASSET ? offset : account, amount, -1);
        char id[21];
        snprintf(id, sizeof id, "INT-%d", ++book->interest_counter);
        post(book, id, end, INTEREST, "interest", lines);
        printf("INTEREST %s entry %s %s days %d average %s amount %s\n", account->code, id, date_text(end).text,
               end - start + 1, money(sum / (end - start + 1)).text, money(amount).text);
    } else if (strcmp(command, "WRITEOFF") == 0) {
        int date;
        if (!check_date(words[1], &date) || !check_open(book, date)) return;
        Account *account = require_type(book, words[2], ASSET);
        if (!account) return;
        Account *expense = require_type(book, words[3], EXPENSE);
        if (!expense || !require_active(account) || !require_active(expense)) return;
        int age = atoi(words[4]), targets = 0;
        Partners partners = account_partners(book, account, date);
        Money amounts[1000] = {0}, total = 0;
        for (int i = 0; i < partners.count; i++) {
            OpenItems items = open_items(book, account, partners.items[i].index, date);
            for (size_t j = items.head; j < items.count; j++) {
                if (date - items.items[j].entry->date > age) amounts[i] += items.items[j].remaining;
            }
            free(items.items);
            if (amounts[i] > 0) { targets++; total += amounts[i]; }
        }
        if (total == 0) { fail("nothing to write off %s", account->code); return; }
        Lines *lines = new_lines(book);
        generated_line(lines, true, expense, total, -1);
        for (int i = 0; i < partners.count; i++) {
            if (amounts[i] > 0) generated_line(lines, false, account, amounts[i], partners.items[i].index);
        }
        char id[21];
        snprintf(id, sizeof id, "WO-%d", ++book->writeoff_counter);
        post(book, id, date, WRITEOFF, "writeoff", lines);
        printf("WRITEOFF %s entry %s %s partners %d amount %s\n", account->code, id, date_text(date).text, targets, money(total).text);
        for (int i = 0; i < partners.count; i++) if (amounts[i] > 0) printf("  %s %s\n", partners.items[i].name, money(amounts[i]).text);
    } else if (strcmp(command, "CLOSE") == 0) {
        int date;
        if (!check_date(words[1], &date) || !check_open(book, date)) return;
        Account *equity = require_type(book, words[2], EQUITY);
        if (!equity || !require_active(equity)) return;
        Totals totals[200];
        all_totals(book, 0, date, false, totals);
        for (int i = 0; i < book->account_count; i++) {
            Account *account = book->account_order[i];
            Totals total = totals[account->index];
            if ((account->type == REVENUE || account->type == EXPENSE) && total.debit != total.credit && !require_active(account)) return;
        }
        Lines *lines = new_lines(book);
        Money income = 0;
        for (int i = 0; i < book->account_count; i++) {
            Account *account = book->account_order[i];
            if (account->type != REVENUE && account->type != EXPENSE) continue;
            Money difference = totals[account->index].debit - totals[account->index].credit;
            if (difference != 0) generated_line(lines, difference < 0, account, absolute(difference), -1);
            income -= difference;
        }
        if (income != 0) generated_line(lines, income < 0, equity, absolute(income), -1);
        char id[21];
        snprintf(id, sizeof id, "CLOSE-%d", ++book->close_counter);
        Entry *entry = lines->count ? post(book, id, date, CLOSING, "closing", lines) : NULL;
        book->closes[book->close_count++] = (CloseRecord) {date, entry};
        if (entry) printf("CLOSE %s entry %s lines %zu net income %s\n", date_text(date).text, id, lines->count, money(income).text);
        else printf("CLOSE %s no entry\n", date_text(date).text);
    } else if (strcmp(command, "REOPEN") == 0) {
        if (book->close_count == 0) { fail("nothing to reopen"); return; }
        CloseRecord record = book->closes[book->close_count - 1];
        if (record.entry && !active_lines(record.entry->lines)) return;
        Entry *entry = record.entry ? reverse_entry(book, record.entry, record.date, REOPEN, "reopen") : NULL;
        book->close_count--;
        printf("REOPEN %s ", date_text(record.date).text);
        if (entry) printf("entry %s", entry->id);
        else fputs("no entry", stdout);
        printf(" closed %s\n", closed_text(book).text);
    } else if (strcmp(command, "LEDGER") == 0) {
        Account *account = require_account(book, words[1]);
        if (!account) return;
        int start, end;
        if (!check_range(words[2], words[3], &start, &end)) return;
        Money running = balance(book, account, start - 1);
        Totals total = {0};
        printf("LEDGER %s %s %s %s\n  opening %s\n", account->code, account->name, words[2], words[3], money(running).text);
        Entry **ordered = posting_order(book);
        for (size_t i = 0; i < book->entry_count; i++) {
            const Entry *entry = ordered[i];
            if (entry->date < start || entry->date > end) continue;
            for (size_t j = 0; j < entry->lines->count; j++) {
                const Line *line = &entry->lines->items[j];
                if (line->account != account) continue;
                if (line->debit) total.debit += line->amount;
                else total.credit += line->amount;
                running += normal_sign(account) * (line->debit ? line->amount : -line->amount);
                printf("  %s %s %s %s balance %s %s\n", date_text(entry->date).text, entry->id, line->debit ? "DR" : "CR",
                       money(line->amount).text, money(running).text, entry->memo);
            }
        }
        int days = end - start + 1;
        printf("  ending %s debits %s credits %s days %d average %s\n", money(running).text, money(total.debit).text,
               money(total.credit).text, days, money(daily_sum(book, account, start, end) / days).text);
    } else if (strcmp(command, "ACTIVITY") == 0) {
        Account *account = require_account(book, words[1]);
        if (!account) return;
        int year = atoi(words[2]);
        Totals total = {0};
        printf("ACTIVITY %s %s %s\n", account->code, account->name, words[2]);
        for (int month = 1; month <= 12; month++) {
            int start = day_number(year, month, 1), end = start + month_days(year, month) - 1;
            Totals current = account_totals(book, account, start, end);
            total.debit += current.debit;
            total.credit += current.credit;
            printf("  %04d-%02d debit %s credit %s balance %s\n", year, month, money(current.debit).text,
                   money(current.credit).text, money(balance(book, account, end)).text);
        }
        printf("  total debit %s credit %s\n", money(total.debit).text, money(total.credit).text);
    } else if (strcmp(command, "TRIAL") == 0) {
        int date;
        if (!check_date(words[1], &date)) return;
        Totals totals[200], total = {0};
        all_totals(book, 0, date, false, totals);
        printf("TRIAL %s\n", words[1]);
        for (int i = 0; i < book->account_count; i++) {
            const Account *account = book->account_order[i];
            Money difference = totals[account->index].debit - totals[account->index].credit;
            if (difference == 0) continue;
            printf("  %s %s %s %s\n", account->code, account->name, difference > 0 ? "debit" : "credit", money(absolute(difference)).text);
            if (difference > 0) total.debit += difference;
            else total.credit -= difference;
        }
        printf("  total debit %s credit %s\n", money(total.debit).text, money(total.credit).text);
    } else if (strcmp(command, "INCOME") == 0) {
        int start, end;
        if (!check_range(words[1], words[2], &start, &end)) return;
        Totals totals[200];
        all_totals(book, start, end, true, totals);
        printf("INCOME %s %s\n", words[1], words[2]);
        Money revenue = section(book, "REVENUE", 1u << REVENUE, -1, totals, false, 0);
        Money expense = section(book, "EXPENSE", 1u << EXPENSE, 1, totals, false, 0);
        printf("  NET INCOME %s\n", money(revenue - expense).text);
    } else if (strcmp(command, "BALANCE") == 0) {
        int date;
        if (!check_date(words[1], &date)) return;
        Totals totals[200];
        all_totals(book, 0, date, false, totals);
        Money earnings = 0;
        for (int i = 0; i < book->account_count; i++) {
            if (book->accounts[i].type == REVENUE || book->accounts[i].type == EXPENSE) earnings -= totals[i].debit - totals[i].credit;
        }
        printf("BALANCE %s\n", words[1]);
        Money assets = section(book, "ASSETS", (1u << ASSET) | (1u << CONTRA_ASSET), 1, totals, false, 0);
        Money liabilities = section(book, "LIABILITIES", 1u << LIABILITY, -1, totals, false, 0);
        Money equity = section(book, "EQUITY", 1u << EQUITY, -1, totals, true, earnings);
        if (assets == liabilities + equity) puts("  check ok");
        else printf("  check mismatch %s\n", money(assets - liabilities - equity).text);
    } else if (strcmp(command, "ROLLUP") == 0) {
        int date;
        if (!check_date(words[2], &date)) return;
        Totals totals[200], postings = {0};
        all_totals(book, 0, date, false, totals);
        printf("ROLLUP %s %s\n", words[1], words[2]);
        bool any = false;
        for (int i = 0; i < book->account_count; i++) {
            const Account *account = book->account_order[i];
            if (!prefix(words[1], account->code)) continue;
            any = true;
            int depth = 0;
            Money subtotal = 0;
            for (int j = 0; j < book->account_count; j++) {
                const Account *other = book->account_order[j];
                if (other != account && prefix(words[1], other->code) && prefix(other->code, account->code)) depth++;
                if (prefix(account->code, other->code)) subtotal += totals[other->index].debit - totals[other->index].credit;
            }
            Totals own = totals[account->index];
            printf("%*s%s %s own %s total %s\n", 2 * (1 + depth), "", account->code, account->name,
                   money(normal_sign(account) * (own.debit - own.credit)).text, money(normal_sign(account) * subtotal).text);
            postings.debit += own.debit;
            postings.credit += own.credit;
        }
        if (any) printf("  postings debit %s credit %s\n", money(postings.debit).text, money(postings.credit).text);
        else puts("  (none)");
    } else if (strcmp(command, "AGING") == 0 || strcmp(command, "ITEMS") == 0) {
        Account *account = require_account(book, words[1]);
        if (!account) return;
        bool aging = strcmp(command, "AGING") == 0;
        int date;
        if (!check_date(words[aging ? 2 : 3], &date)) return;
        if (aging) {
            printf("AGING %s %s %s\n", account->code, account->name, words[2]);
            Partners partners = account_partners(book, account, date);
            Money totals[5] = {0};
            for (int i = 0; i < partners.count; i++) {
                OpenItems items = open_items(book, account, partners.items[i].index, date);
                Money values[5] = {0, 0, 0, 0, items.unapplied};
                for (size_t j = items.head; j < items.count; j++) {
                    int age = date - items.items[j].entry->date;
                    int bucket = age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3;
                    values[bucket] += items.items[j].remaining;
                }
                if (items.head < items.count || items.unapplied > 0) {
                    aging_row(partners.items[i].name, values);
                    for (int j = 0; j < 5; j++) totals[j] += values[j];
                }
                free(items.items);
            }
            aging_row("total", totals);
        } else {
            printf("ITEMS %s %s %s %s\n", account->code, account->name, words[2], words[3]);
            int partner = -2;
            for (int i = 0; i < book->partner_count; i++) if (strcmp(book->partners[i], words[2]) == 0) partner = i;
            OpenItems items = open_items(book, account, partner, date);
            Money remaining = 0;
            for (size_t i = items.head; i < items.count; i++) {
                OpenItem item = items.items[i];
                remaining += item.remaining;
                printf("  %s %s amount %s open %s age %d\n", date_text(item.entry->date).text, item.entry->id,
                       money(item.original).text, money(item.remaining).text, date - item.entry->date);
            }
            printf("  unapplied %s balance %s\n", money(items.unapplied).text, money(remaining - items.unapplied).text);
            free(items.items);
        }
    } else if (strcmp(command, "ENTRY") == 0) {
        Entry *entry = find_entry(book, words[1]);
        if (!entry) { fail("unknown entry %s", words[1]); return; }
        printf("ENTRY %s %s %s %s\n", entry->id, date_text(entry->date).text, CATEGORY_NAMES[entry->category], entry->memo);
        for (size_t i = 0; i < entry->lines->count; i++) {
            const Line *line = &entry->lines->items[i];
            printf("  %s %s %s %s", line->debit ? "DR" : "CR", line->account->code, line->account->name, money(line->amount).text);
            if (line->partner >= 0) printf(" %s", book->partners[line->partner]);
            putchar('\n');
        }
        printf("  total %s\n", money(entry->lines->amount.debit).text);
        if (entry->reverses) printf("  reverses %s\n", entry->reverses->id);
        if (entry->reversed_by) printf("  reversed by %s\n", entry->reversed_by->id);
    } else if (strcmp(command, "DAYBOOK") == 0) {
        int start, end;
        if (!check_range(words[1], words[2], &start, &end)) return;
        printf("DAYBOOK %s %s\n", words[1], words[2]);
        Entry **ordered = posting_order(book);
        size_t entries = 0;
        Money total = 0;
        for (size_t i = 0; i < book->entry_count; i++) {
            const Entry *entry = ordered[i];
            if (entry->date < start || entry->date > end) continue;
            entries++;
            total += entry->lines->amount.debit;
            printf("  %s %s %s %s %s\n", date_text(entry->date).text, entry->id, CATEGORY_NAMES[entry->category], money(entry->lines->amount.debit).text, entry->memo);
        }
        printf("  total entries %zu amount %s\n", entries, money(total).text);
    } else if (strcmp(command, "ACCOUNTS") == 0) {
        puts("ACCOUNTS");
        Totals totals[200];
        all_totals(book, 0, 36600, false, totals);
        for (int i = 0; i < book->account_count; i++) {
            const Account *account = book->account_order[i];
            Totals total = totals[account->index];
            printf("  %s %s %s parent %s balance %s %s\n", account->code, TYPE_NAMES[account->type], account->name,
                   parent_code(book, account), money(normal_sign(account) * (total.debit - total.credit)).text, account->active ? "active" : "inactive");
        }
        if (book->account_count == 0) puts("  (none)");
    } else if (strcmp(command, "TEMPLATES") == 0) {
        puts("TEMPLATES");
        Template *ordered[50];
        for (int i = 0; i < book->template_count; i++) ordered[i] = &book->templates[i];
        qsort(ordered, (size_t) book->template_count, sizeof *ordered, compare_templates);
        for (int i = 0; i < book->template_count; i++) {
            const Template *pattern = ordered[i];
            printf("  %s %s lines %zu amount %s used %d\n", pattern->name, pattern->memo, pattern->lines->count, money(pattern->lines->amount.debit).text, pattern->uses);
        }
        if (book->template_count == 0) puts("  (none)");
    } else if (strcmp(command, "STATUS") == 0) {
        int inactive = 0;
        for (int i = 0; i < book->account_count; i++) inactive += !book->accounts[i].active;
        printf("STATUS accounts %d inactive %d entries %zu templates %d closed %s open %s\n", book->account_count,
               inactive, book->entry_count, book->template_count, closed_text(book).text, book->has_draft ? book->draft.key : "none");
    }
}

int main(void) {
    Book *book = allocate(1, sizeof *book);
    char line[256];
    if (!fgets(line, sizeof line, stdin)) { free(book); return 0; }
    int commands = atoi(line);
    for (int i = 0; i < commands && fgets(line, sizeof line, stdin); i++) {
        char *words[8];
        int count = 0;
        for (char *word = strtok(line, " \r\n"); word; word = strtok(NULL, " \r\n")) words[count++] = word;
        execute(book, words, count);
    }
    for (size_t i = 0; i < book->entry_count; i++) free(book->entries[i]);
    free(book->entries);
    free(book->ordered);
    while (book->line_storage) {
        Lines *lines = book->line_storage;
        book->line_storage = lines->next;
        free(lines->items);
        free(lines);
    }
    free(book);
    return 0;
}
