#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef long long Amount;

enum { HOURLY, SALARIED, COMMISSION };
enum {
    STATE, SUPP, SSRATE, MEDRATE, ADDMED, UIRATE, MATCH,
    MATCHMAX, GARNCAP, SSBASE, ADDBASE, UIBASE, RETIRECAP,
    ALLOWANCE, NIGHT, SETTING_COUNT
};
enum {
    REG, OT, DBL, NIGHTMIN, PTOMIN, ACCRUED, SALARY, LEAVE_DAYS,
    LEAVE_DEDUCTION, SALES_AMOUNT, COMMISSION_AMOUNT, EARNINGS,
    BONUS_AMOUNT, GROSS, RETIREMENT, HEALTH, FEDERAL, SUPPLEMENTAL,
    STATE_TAX, SOCIAL, MEDICARE, GARNISHMENT, NET, EMPLOYER_SOCIAL,
    EMPLOYER_MEDICARE, UNEMPLOYMENT, RETIRE_MATCH, EMPLOYER,
    W, Y, F, J, FIELD_COUNT, GARNISH_BALANCE, PTO_BALANCE, STUB_FIELDS
};

static const char *setting_names[SETTING_COUNT] = {
    "STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED", "UIRATE",
    "MATCH", "MATCHMAX", "GARNCAP", "SSBASE", "ADDBASE", "UIBASE",
    "RETIRECAP", "ALLOWANCE", "NIGHT"
};
static const char *kind_names[] = {"HOURLY", "SALARIED", "COMMISSION"};
static const char *kind_errors[] = {"not hourly", "not salaried", "not commission"};
static const char *weekdays[] = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
static const char *pay_fields[] = {
    "earnings", "bonus", "gross", "retirement", "health", "federal",
    "supplemental", "state", "social-security", "medicare"
};
static const int pay_indexes[] = {
    EARNINGS, BONUS_AMOUNT, GROSS, RETIREMENT, HEALTH, FEDERAL,
    SUPPLEMENTAL, STATE_TAX, SOCIAL, MEDICARE
};

typedef struct Shift {
    int start, end;
    struct Shift *next;
} Shift;

typedef struct {
    Amount rate, balance;
} Garnish;

typedef struct {
    Amount v[STUB_FIELDS];
} Stub;

typedef struct {
    Stub stub;
    char department[9];
    int exists;
} Stored;

typedef struct {
    int id, kind, active, allowances, periods, garnishes, capacity;
    char department[9];
    Amount base, retirement, health, extra, bonus, pto_balance;
    Shift *shifts[365];
    int pto[365], leave[365];
    Amount sales[28];
    Garnish *orders;
    Amount ytd[FIELD_COUNT];
    Stored stubs[28];
} Employee;

typedef struct {
    Amount bound, rate;
} Bracket;

typedef struct {
    Bracket rows[1002];
    int count;
} Table;

typedef struct {
    Amount worked, values[5];
} Daily;

typedef struct {
    Amount values[5], weekly_ot;
} Week;

typedef struct {
    char name[9];
    Stub sum;
    int count;
} Department;

static Amount settings[SETTING_COUNT] = {
    500, 2200, 620, 145, 90, 270, 5000, 600, 2500,
    16860000, 20000000, 700000, 2300000, 15000, 100
};
static Table brackets, tiers;
static Employee *employees[10000];
static int holidays[365];
static int closed_periods = 0;

static Amount minimum(Amount a, Amount b) { return a < b ? a : b; }
static Amount maximum(Amount a, Amount b) { return a > b ? a : b; }
static Amount cents(const char *text) {
    const char *point = strchr(text, '.');
    return atoll(text) * 100 + (point ? atoll(point + 1) : 0);
}
static int period_of(int day) { return (day - 1) / 14 + 1; }
static const char *weekday(int day) { return weekdays[(day - 1) % 7]; }

static const char *money(Amount value) {
    static char buffer[64][64];
    static int used = 0;
    char *target = buffer[used++ % 64];
    snprintf(target, 64, "%lld.%02lld", value / 100, value % 100);
    return target;
}
static const char *rate_text(Amount value) {
    static char buffer[32][64];
    static int used = 0;
    char *target = buffer[used++ % 32];
    snprintf(target, 64, "%lld.%02lld%%", value / 100, value % 100);
    return target;
}
static const char *duration(Amount minutes) {
    static char buffer[32][64];
    static int used = 0;
    char *target = buffer[used++ % 32];
    snprintf(target, 64, "%lld:%02lld", minutes / 60, minutes % 60);
    return target;
}
static const char *clock_text(int minutes) {
    static char buffer[32][16];
    static int used = 0;
    char *target = buffer[used++ % 32];
    snprintf(target, 16, "%02d:%02d", minutes / 60, minutes % 60);
    return target;
}
static int valid_clock(const char *text, int *time) {
    int hour = 0, minute = 0;
    sscanf(text, "%d:%d", &hour, &minute);
    if (hour > 23 || minute > 59) {
        printf("ERROR invalid time %s\n", text);
        return 0;
    }
    *time = hour * 60 + minute;
    return 1;
}

static Employee *require_employee(const char *text, int active, int kind) {
    int id = atoi(text);
    Employee *employee = id >= 1 && id <= 9999 ? employees[id] : NULL;
    if (!employee) {
        printf("ERROR unknown employee %s\n", text);
        return NULL;
    }
    if (active && !employee->active) {
        printf("ERROR terminated employee %s\n", text);
        return NULL;
    }
    if (kind >= 0 && employee->kind != kind) {
        printf("ERROR %s %s\n", kind_errors[kind], text);
        return NULL;
    }
    return employee;
}

static int checked_day(const char *text, int *value) {
    int day = atoi(text);
    if (day < 1 || day > 364) {
        printf("ERROR invalid day %s\n", text);
        return 0;
    }
    if (period_of(day) <= closed_periods) {
        printf("ERROR period closed %d\n", period_of(day));
        return 0;
    }
    *value = day;
    return 1;
}

static int checked_period(const char *text, int *value) {
    int period = atoi(text);
    if (period < 1 || period > 26) {
        printf("ERROR invalid period %s\n", text);
        return 0;
    }
    *value = period;
    return 1;
}

static int checked_rate(const char *text, Amount *value) {
    *value = cents(text);
    if (*value > 10000) {
        printf("ERROR invalid rate %s\n", text);
        return 0;
    }
    return 1;
}

static int checked_amount(const char *text, Amount *value) {
    *value = cents(text);
    if (*value == 0) {
        puts("ERROR invalid amount");
        return 0;
    }
    return 1;
}

static int setting_index(const char *text) {
    for (int i = 0; i < SETTING_COUNT; ++i)
        if (!strcmp(text, setting_names[i])) return i;
    return -1;
}

static void set_bracket(Table *table, Amount lower, Amount rate, int *replaced) {
    int i = 0;
    while (i < table->count && table->rows[i].bound < lower) ++i;
    if (i < table->count && table->rows[i].bound == lower) {
        *replaced = 1;
        table->rows[i].rate = rate;
    } else {
        *replaced = 0;
        memmove(table->rows + i + 1, table->rows + i,
                (table->count - i) * sizeof(Bracket));
        table->rows[i].bound = lower;
        table->rows[i].rate = rate;
        ++table->count;
    }
}

static Amount progressive(const Table *table, Amount value) {
    Amount numerator = 0;
    for (int i = 0; i < table->count; ++i) {
        Amount lower = table->rows[i].bound;
        if (lower >= value) break;
        Amount upper = i + 1 < table->count ?
                       minimum(value, table->rows[i + 1].bound) : value;
        numerator += table->rows[i].rate * (upper - lower);
    }
    return numerator / 10000;
}

static Daily daily(const Employee *employee, int day) {
    Daily result = {0};
    if (day < 1 || day > 364) return result;
    for (const Shift *shift = employee->shifts[day]; shift; shift = shift->next) {
        int start = shift->start, end = shift->end;
        result.worked += end - start;
        result.values[3] += maximum(0, minimum(end, 360) - start);
        result.values[3] += maximum(0, end - maximum(start, 1320));
    }
    result.values[4] = employee->pto[day];
    if (day % 7 == 0 || holidays[day]) {
        result.values[2] = result.worked;
    } else {
        result.values[0] = minimum(result.worked, 480);
        result.values[1] = minimum(maximum(result.worked - 480, 0), 240);
        result.values[2] = maximum(result.worked - 720, 0);
    }
    return result;
}

static Week weekly(const Employee *employee, int week) {
    Week result = {0};
    for (int day = 7 * week - 6; day <= 7 * week; ++day) {
        Daily today = daily(employee, day);
        for (int i = 0; i < 5; ++i) result.values[i] += today.values[i];
    }
    result.weekly_ot = maximum(0, result.values[0] - 2400);
    result.values[0] -= result.weekly_ot;
    result.values[1] += result.weekly_ot;
    return result;
}

static void breakdown(const Employee *employee, int period, Amount values[5]) {
    Week first = weekly(employee, 2 * period - 1);
    Week second = weekly(employee, 2 * period);
    for (int i = 0; i < 5; ++i) values[i] = first.values[i] + second.values[i];
}

static void deduct(Stub *stub, int field, Amount amount, Amount *remaining) {
    stub->v[field] = minimum(amount, *remaining);
    *remaining -= stub->v[field];
}

static int calculate(const Employee *employee, int period, Stub *stub, Amount *post_balances) {
    memset(stub, 0, sizeof(*stub));
    Amount *v = stub->v;
    if (employee->kind == HOURLY) {
        breakdown(employee, period, v);
        Amount weighted = 2 * (v[REG] + v[PTOMIN]) +
                          3 * v[OT] + 4 * v[DBL];
        v[EARNINGS] = (weighted * employee->base +
                       2 * v[NIGHTMIN] * settings[NIGHT]) / 120;
    } else if (employee->kind == SALARIED) {
        if (employee->active) {
            v[SALARY] = employee->base / 26;
            for (int day = 1; day <= 364; ++day)
                if (employee->leave[day] && period_of(day) == period && !holidays[day])
                    ++v[LEAVE_DAYS];
            v[LEAVE_DEDUCTION] = v[LEAVE_DAYS] * (employee->base / 260);
            v[EARNINGS] = v[SALARY] - v[LEAVE_DEDUCTION];
        }
    } else {
        v[SALES_AMOUNT] = employee->sales[period];
        v[COMMISSION_AMOUNT] = progressive(&tiers, v[SALES_AMOUNT]);
        v[EARNINGS] = v[COMMISSION_AMOUNT] + (employee->active ? employee->base : 0);
    }
    v[BONUS_AMOUNT] = employee->bonus;
    v[GROSS] = v[EARNINGS] + v[BONUS_AMOUNT];
    if (v[GROSS] == 0) return 0;

    Amount remaining = v[GROSS];
    Amount room = maximum(0, settings[RETIRECAP] - employee->ytd[RETIREMENT]);
    deduct(stub, RETIREMENT, minimum(v[GROSS] * employee->retirement / 10000, room),
           &remaining);
    deduct(stub, HEALTH, employee->health, &remaining);
    v[W] = remaining;
    Amount base_taxable = maximum(0, v[EARNINGS] - v[RETIREMENT] - v[HEALTH]);
    Amount allowance_taxable = maximum(0, base_taxable -
                                      employee->allowances * settings[ALLOWANCE]);
    deduct(stub, FEDERAL, progressive(&brackets, allowance_taxable) + employee->extra,
           &remaining);
    deduct(stub, SUPPLEMENTAL, (v[W] - base_taxable) * settings[SUPP] / 10000,
           &remaining);
    deduct(stub, STATE_TAX, v[W] * settings[STATE] / 10000, &remaining);

    v[F] = v[GROSS] - v[HEALTH];
    v[Y] = minimum(v[F], maximum(0, settings[SSBASE] - employee->ytd[Y]));
    Amount additional = maximum(0, minimum(v[F],
                          employee->ytd[F] + v[F] - settings[ADDBASE]));
    deduct(stub, SOCIAL, v[Y] * settings[SSRATE] / 10000, &remaining);
    deduct(stub, MEDICARE, v[F] * settings[MEDRATE] / 10000 +
                          additional * settings[ADDMED] / 10000, &remaining);

    Amount disposable = remaining;
    Amount cap = disposable * settings[GARNCAP] / 10000;
    for (int i = 0; i < employee->garnishes; ++i) {
        Garnish order = employee->orders[i];
        Amount amount = minimum(disposable * order.rate / 10000,
                        minimum(order.balance, cap - v[GARNISHMENT]));
        v[GARNISHMENT] += amount;
        post_balances[i] = order.balance - amount;
        v[GARNISH_BALANCE] += post_balances[i];
    }
    v[NET] = remaining - v[GARNISHMENT];
    v[EMPLOYER_SOCIAL] = v[Y] * settings[SSRATE] / 10000;
    v[EMPLOYER_MEDICARE] = v[F] * settings[MEDRATE] / 10000;
    v[J] = minimum(v[F], maximum(0, settings[UIBASE] - employee->ytd[J]));
    v[UNEMPLOYMENT] = v[J] * settings[UIRATE] / 10000;
    Amount match_base = minimum(v[RETIREMENT], v[GROSS] * settings[MATCHMAX] / 10000);
    v[RETIRE_MATCH] = match_base * settings[MATCH] / 10000;
    v[EMPLOYER] = v[EMPLOYER_SOCIAL] + v[EMPLOYER_MEDICARE] +
                  v[UNEMPLOYMENT] + v[RETIRE_MATCH];
    if (employee->kind == HOURLY)
        v[ACCRUED] = minimum(960 - employee->pto_balance,
                            (v[REG] + v[OT] + v[DBL]) / 20);
    v[PTO_BALANCE] = employee->pto_balance + v[ACCRUED];
    return 1;
}

static void hours_parts(const Amount *v) {
    printf("reg %s ot %s dbl %s night %s pto %s",
           duration(v[0]), duration(v[1]), duration(v[2]),
           duration(v[3]), duration(v[4]));
}

static void stub_block(const Employee *employee, const Stub *stub, int indent) {
    const Amount *v = stub->v;
    if (employee->kind == HOURLY) {
        printf("%*shours ", indent, "");
        hours_parts(v);
        putchar('\n');
        printf("%*spto accrued %s balance %s\n", indent, "",
               duration(v[ACCRUED]), duration(v[PTO_BALANCE]));
    } else if (employee->kind == SALARIED) {
        printf("%*ssalary %s leave %lld deduction %s\n", indent, "",
               money(v[SALARY]), v[LEAVE_DAYS], money(v[LEAVE_DEDUCTION]));
    } else {
        printf("%*ssales %s commission %s\n", indent, "",
               money(v[SALES_AMOUNT]), money(v[COMMISSION_AMOUNT]));
    }
    for (int i = 0; i < 10; ++i)
        printf("%*s%s %s\n", indent, "", pay_fields[i], money(v[pay_indexes[i]]));
    printf("%*sgarnishment %s balance %s\n", indent, "",
           money(v[GARNISHMENT]), money(v[GARNISH_BALANCE]));
    printf("%*snet %s\n", indent, "", money(v[NET]));
    printf("%*semployer social-security %s medicare %s unemployment %s match %s\n",
           indent, "", money(v[EMPLOYER_SOCIAL]), money(v[EMPLOYER_MEDICARE]),
           money(v[UNEMPLOYMENT]), money(v[RETIRE_MATCH]));
}

static void print_stub(const Employee *employee, int period, const Stub *stub,
                       const char *department) {
    printf("  STUB %d %s %s period %d\n", employee->id, department,
           kind_names[employee->kind], period);
    stub_block(employee, stub, 4);
}

static void show_hours(const Employee *employee, int period) {
    printf("HOURS %d period %d\n", employee->id, period);
    int found = 0;
    for (int day = 14 * period - 13; day <= 14 * period; ++day) {
        if (!employee->shifts[day] && employee->pto[day] == 0) continue;
        Daily values = daily(employee, day);
        printf("  day %d %s", day, weekday(day));
        if (holidays[day]) printf(" holiday");
        for (Shift *s = employee->shifts[day]; s; s = s->next)
            printf(" %s-%s", clock_text(s->start), clock_text(s->end));
        printf(" total %s ", duration(values.worked));
        hours_parts(values.values);
        putchar('\n');
        found = 1;
    }
    if (!found) puts("  (none)");
    for (int week = 2 * period - 1; week <= 2 * period; ++week) {
        Week values = weekly(employee, week);
        printf("  week %d ", week);
        hours_parts(values.values);
        printf(" weekly-ot %s\n", duration(values.weekly_ot));
    }
    Amount values[5];
    breakdown(employee, period, values);
    printf("  total ");
    hours_parts(values);
    putchar('\n');
}

static void add_stub(Stub *target, const Stub *source) {
    for (int i = 0; i < FIELD_COUNT; ++i)
        target->v[i] += source->v[i];
}

static void print_run(int period) {
    closed_periods = period;
    printf("RUN %d days %d-%d\n", period, 14 * period - 13, 14 * period);
    Stub sum = {0};
    int paid = 0, skipped = 0;
    for (int id = 1; id <= 9999; ++id) {
        Employee *employee = employees[id];
        if (!employee) continue;
        Stub stub;
        Amount *balances = calloc((size_t)employee->garnishes + 1, sizeof(Amount));
        int has_pay = calculate(employee, period, &stub, balances);
        if (!has_pay) {
            if (employee->active) ++skipped;
            free(balances);
            continue;
        }
        print_stub(employee, period, &stub, employee->department);
        employee->bonus = 0;
        employee->pto_balance = stub.v[PTO_BALANCE];
        for (int i = 0; i < employee->garnishes; ++i)
            employee->orders[i].balance = balances[i];
        for (int i = 0; i < FIELD_COUNT; ++i)
            employee->ytd[i] += stub.v[i];
        ++employee->periods;
        Stored *saved = &employee->stubs[period];
        saved->stub = stub;
        strcpy(saved->department, employee->department);
        saved->exists = 1;
        add_stub(&sum, &stub);
        ++paid;
        free(balances);
    }
    printf("  TOTAL paid %d skipped %d gross %s deductions %s net %s employer %s\n",
           paid, skipped, money(sum.v[GROSS]), money(sum.v[GROSS] - sum.v[NET]),
           money(sum.v[NET]), money(sum.v[EMPLOYER]));
}

static Stub sum_period(int period, int *count) {
    Stub sum = {0};
    *count = 0;
    for (int id = 1; id <= 9999; ++id) {
        Employee *employee = employees[id];
        if (!employee || !employee->stubs[period].exists) continue;
        add_stub(&sum, &employee->stubs[period].stub);
        ++*count;
    }
    return sum;
}

static void journal(int period) {
    int count;
    Stub sum = sum_period(period, &count);
    const Amount *v = sum.v;
    Amount debit[3] = {
        v[GROSS],
        v[EMPLOYER_SOCIAL] + v[EMPLOYER_MEDICARE] + v[UNEMPLOYMENT],
        v[RETIRE_MATCH]
    };
    Amount credit[8] = {
        v[RETIREMENT] + v[RETIRE_MATCH], v[HEALTH],
        v[FEDERAL] + v[SUPPLEMENTAL], v[STATE_TAX],
        v[SOCIAL] + v[MEDICARE] + v[EMPLOYER_SOCIAL] + v[EMPLOYER_MEDICARE],
        v[UNEMPLOYMENT], v[GARNISHMENT], v[NET]
    };
    static const char *debit_names[] = {"wages", "employer-tax", "retirement-match"};
    static const char *credit_names[] = {
        "retirement", "health", "federal", "state", "fica",
        "unemployment", "garnishment", "net-pay"
    };
    Amount debit_total = 0, credit_total = 0;
    printf("JOURNAL %d stubs %d\n", period, count);
    for (int i = 0; i < 3; ++i) {
        printf("  debit %s %s\n", debit_names[i], money(debit[i]));
        debit_total += debit[i];
    }
    for (int i = 0; i < 8; ++i) {
        printf("  credit %s %s\n", credit_names[i], money(credit[i]));
        credit_total += credit[i];
    }
    printf("  total debit %s credit %s\n", money(debit_total), money(credit_total));
}

static void report_line(const char *department, const Stub *sum, int count) {
    const Amount *v = sum->v;
    Amount taxes = v[FEDERAL] + v[SUPPLEMENTAL] + v[STATE_TAX] +
                   v[SOCIAL] + v[MEDICARE];
    printf("  %s stubs %d gross %s pretax %s taxes %s garnishment %s net %s employer %s\n",
           department, count, money(v[GROSS]),
           money(v[RETIREMENT] + v[HEALTH]), money(taxes),
           money(v[GARNISHMENT]), money(v[NET]), money(v[EMPLOYER]));
}
static int compare_department(const void *a, const void *b) {
    return strcmp(((const Department *)a)->name, ((const Department *)b)->name);
}
static void report(void) {
    Department departments[1002] = {0};
    Stub total = {0};
    int count = 0, n = 0;
    for (int id = 1; id <= 9999; ++id) {
        Employee *employee = employees[id];
        if (!employee) continue;
        for (int period = 1; period <= 26; ++period) {
            Stored *saved = &employee->stubs[period];
            if (!saved->exists) continue;
            int index = 0;
            while (index < n && strcmp(departments[index].name, saved->department))
                ++index;
            if (index == n) {
                strcpy(departments[n].name, saved->department);
                ++n;
            }
            add_stub(&departments[index].sum, &saved->stub);
            ++departments[index].count;
            add_stub(&total, &saved->stub);
            ++count;
        }
    }
    qsort(departments, n, sizeof(departments[0]), compare_department);
    printf("REPORT period %d\n", closed_periods);
    for (int i = 0; i < n; ++i)
        report_line(departments[i].name, &departments[i].sum, departments[i].count);
    report_line("total", &total, count);
}

static void ytd(const Employee *employee) {
    Stub totals = {0};
    memcpy(totals.v, employee->ytd, sizeof(employee->ytd));
    totals.v[PTO_BALANCE] = employee->pto_balance;
    for (int i = 0; i < employee->garnishes; ++i)
        totals.v[GARNISH_BALANCE] += employee->orders[i].balance;
    printf("YTD %d %s %s %s periods %d\n", employee->id,
           employee->department, kind_names[employee->kind],
           employee->active ? "active" : "terminated", employee->periods);
    stub_block(employee, &totals, 2);
    printf("  wages federal %s social-security %s medicare %s unemployment %s\n",
           money(totals.v[W]), money(totals.v[Y]),
           money(totals.v[F]), money(totals.v[J]));
    printf("  retirement-room %s pending-bonus %s\n",
           money(maximum(0, settings[RETIRECAP] - totals.v[RETIREMENT])),
           money(employee->bonus));
}

static int compare_top(const void *a, const void *b) {
    Employee *left = *(Employee * const *)a;
    Employee *right = *(Employee * const *)b;
    if (left->ytd[GROSS] != right->ytd[GROSS])
        return left->ytd[GROSS] > right->ytd[GROSS] ? -1 : 1;
    return left->id - right->id;
}
static void show_top(int count) {
    Employee *ranking[1002];
    int n = 0;
    for (int id = 1; id <= 9999; ++id)
        if (employees[id] && employees[id]->periods)
            ranking[n++] = employees[id];
    qsort(ranking, n, sizeof(ranking[0]), compare_top);
    printf("TOP %d\n", count);
    for (int i = 0; i < n && i < count; ++i) {
        const Employee *employee = ranking[i];
        printf("  %d %d %s gross %s net %s\n", i + 1, employee->id,
               employee->department, money(employee->ytd[GROSS]),
               money(employee->ytd[NET]));
    }
    if (!n) puts("  (none)");
}

static void show_employees(void) {
    puts("EMPLOYEES");
    int seen = 0;
    for (int id = 1; id <= 9999; ++id) {
        Employee *employee = employees[id];
        if (!employee) continue;
        seen = 1;
        printf("  %d %s %s %s %s retirement %s health %s allowances %d extra %s bonus %s\n",
               id, employee->department, kind_names[employee->kind],
               money(employee->base), employee->active ? "active" : "terminated",
               rate_text(employee->retirement), money(employee->health),
               employee->allowances, money(employee->extra), money(employee->bonus));
        for (int i = 0; i < employee->garnishes; ++i)
            printf("    garnish %d %s balance %s\n", i + 1,
                   rate_text(employee->orders[i].rate),
                   money(employee->orders[i].balance));
    }
    if (!seen) puts("  (none)");
}

static void config(void) {
    puts("CONFIG");
    for (int i = 0; i < SETTING_COUNT; ++i)
        printf("  %s %s\n", setting_names[i],
               i <= GARNCAP ? rate_text(settings[i]) : money(settings[i]));
    for (int i = 0; i < brackets.count; ++i)
        printf("  bracket %s %s\n", money(brackets.rows[i].bound),
               rate_text(brackets.rows[i].rate));
    for (int i = 0; i < tiers.count; ++i)
        printf("  tier %s %s\n", money(tiers.rows[i].bound),
               rate_text(tiers.rows[i].rate));
}

static void execute(char **a) {
    const char *command = a[0];
    if (!strcmp(command, "SET")) {
        int setting = setting_index(a[1]);
        if (setting < 0) {
            printf("ERROR unknown setting %s\n", a[1]);
            return;
        }
        Amount value;
        if (setting <= GARNCAP) {
            if (!checked_rate(a[2], &value)) return;
        } else value = cents(a[2]);
        Amount old = settings[setting];
        settings[setting] = value;
        if (setting <= GARNCAP)
            printf("SET %s %s -> %s\n", a[1], rate_text(old), rate_text(value));
        else
            printf("SET %s %s -> %s\n", a[1], money(old), money(value));
    } else if (!strcmp(command, "BRACKET") || !strcmp(command, "TIER")) {
        Amount rate;
        if (!checked_rate(a[2], &rate)) return;
        Amount lower = cents(a[1]);
        int replaced;
        set_bracket(!strcmp(command, "BRACKET") ? &brackets : &tiers,
                    lower, rate, &replaced);
        printf("%s %s %s %s\n", command, money(lower), rate_text(rate),
               replaced ? "replaced" : "added");
    } else if (!strcmp(command, "EMP")) {
        int id = atoi(a[1]);
        if (employees[id]) {
            printf("ERROR duplicate employee %s\n", a[1]);
            return;
        }
        Amount base;
        if (!checked_amount(a[4], &base)) return;
        Employee *employee = calloc(1, sizeof(*employee));
        employee->id = id;
        employee->active = 1;
        strcpy(employee->department, a[2]);
        employee->kind = !strcmp(a[3], "HOURLY") ? HOURLY :
                         !strcmp(a[3], "SALARIED") ? SALARIED : COMMISSION;
        employee->base = base;
        employees[id] = employee;
        printf("EMP %d %s %s %s\n", id, a[2], a[3], money(base));
    } else if (!strcmp(command, "RATE") || !strcmp(command, "DEPT") ||
               !strcmp(command, "BENEFIT") || !strcmp(command, "W4") ||
               !strcmp(command, "GARNISH") || !strcmp(command, "TERM") ||
               !strcmp(command, "BONUS")) {
        Employee *employee = require_employee(a[1], 1, -1);
        if (!employee) return;
        if (!strcmp(command, "RATE")) {
            Amount base;
            if (!checked_amount(a[2], &base)) return;
            printf("RATE %d %s -> %s\n", employee->id, money(employee->base), money(base));
            employee->base = base;
        } else if (!strcmp(command, "DEPT")) {
            if (!strcmp(employee->department, a[2])) {
                printf("ERROR same department %s\n", a[2]);
                return;
            }
            printf("DEPT %d %s -> %s\n", employee->id, employee->department, a[2]);
            strcpy(employee->department, a[2]);
        } else if (!strcmp(command, "BENEFIT")) {
            Amount rate;
            if (!checked_rate(a[2], &rate)) return;
            employee->retirement = rate;
            employee->health = cents(a[3]);
            printf("BENEFIT %d retirement %s health %s\n", employee->id,
                   rate_text(rate), money(employee->health));
        } else if (!strcmp(command, "W4")) {
            employee->allowances = atoi(a[2]);
            employee->extra = cents(a[3]);
            printf("W4 %d allowances %d extra %s\n", employee->id,
                   employee->allowances, money(employee->extra));
        } else if (!strcmp(command, "GARNISH")) {
            Amount rate, amount;
            if (!checked_rate(a[2], &rate) || !checked_amount(a[3], &amount)) return;
            if (employee->garnishes == employee->capacity) {
                employee->capacity = employee->capacity ? employee->capacity * 2 : 4;
                employee->orders = realloc(employee->orders,
                         sizeof(Garnish) * employee->capacity);
            }
            employee->orders[employee->garnishes].rate = rate;
            employee->orders[employee->garnishes].balance = amount;
            ++employee->garnishes;
            printf("GARNISH %d order %d %s balance %s\n", employee->id,
                   employee->garnishes, rate_text(rate), money(amount));
        } else if (!strcmp(command, "TERM")) {
            employee->active = 0;
            printf("TERM %d\n", employee->id);
        } else {
            Amount amount;
            if (!checked_amount(a[2], &amount)) return;
            employee->bonus += amount;
            printf("BONUS %d %s pending %s\n", employee->id,
                   money(amount), money(employee->bonus));
        }
    } else if (!strcmp(command, "HOLIDAY")) {
        int day;
        if (!checked_day(a[1], &day)) return;
        if (holidays[day]) {
            printf("ERROR duplicate holiday %s\n", a[1]);
            return;
        }
        holidays[day] = 1;
        printf("HOLIDAY %d %s\n", day, weekday(day));
    } else if (!strcmp(command, "TIME") || !strcmp(command, "UNTIME") ||
               !strcmp(command, "PTO") || !strcmp(command, "LEAVE") ||
               !strcmp(command, "SALES")) {
        int kind = !strcmp(command, "LEAVE") ? SALARIED :
                   !strcmp(command, "SALES") ? COMMISSION : HOURLY;
        Employee *employee = require_employee(a[1], 1, kind);
        if (!employee) return;
        int day;
        if (!checked_day(a[2], &day)) return;
        if (!strcmp(command, "TIME")) {
            int start, end;
            if (!valid_clock(a[3], &start) || !valid_clock(a[4], &end)) return;
            if (start >= end) {
                printf("ERROR invalid shift %s-%s\n", a[3], a[4]);
                return;
            }
            Amount worked = 0;
            for (Shift *shift = employee->shifts[day]; shift; shift = shift->next) {
                if (start < shift->end && shift->start < end) {
                    printf("ERROR overlapping shift %s-%s\n",
                           clock_text(shift->start), clock_text(shift->end));
                    return;
                }
                worked += shift->end - shift->start;
            }
            if (worked + end - start > 960) {
                printf("ERROR daily limit %s %s\n", a[1], a[2]);
                return;
            }
            Shift *shift = malloc(sizeof(*shift));
            shift->start = start;
            shift->end = end;
            Shift **position = &employee->shifts[day];
            while (*position && (*position)->start < start)
                position = &(*position)->next;
            shift->next = *position;
            *position = shift;
            printf("TIME %d day %d %s-%s %s\n", employee->id, day,
                   clock_text(start), clock_text(end), duration(end - start));
        } else if (!strcmp(command, "UNTIME")) {
            int start;
            if (!valid_clock(a[3], &start)) return;
            Shift **position = &employee->shifts[day];
            while (*position && (*position)->start != start)
                position = &(*position)->next;
            if (!*position) {
                printf("ERROR no shift %s %s %s\n", a[1], a[2], a[3]);
                return;
            }
            Shift *removed = *position;
            *position = removed->next;
            printf("UNTIME %d day %d %s-%s\n", employee->id, day,
                   clock_text(removed->start), clock_text(removed->end));
            free(removed);
        } else if (!strcmp(command, "PTO")) {
            int hour = 0, minute = 0;
            sscanf(a[3], "%d:%d", &hour, &minute);
            int length = hour * 60 + minute;
            if (minute > 59 || length < 1 || length > 480) {
                printf("ERROR invalid duration %s\n", a[3]);
                return;
            }
            if (employee->pto[day]) {
                printf("ERROR duplicate pto %s %s\n", a[1], a[2]);
                return;
            }
            if (length > employee->pto_balance) {
                printf("ERROR insufficient pto %s %s\n",
                       a[1], duration(employee->pto_balance));
                return;
            }
            employee->pto[day] = length;
            employee->pto_balance -= length;
            printf("PTO %d day %d %s balance %s\n", employee->id, day,
                   duration(length), duration(employee->pto_balance));
        } else if (!strcmp(command, "LEAVE")) {
            if (day % 7 == 0 || day % 7 == 6 || holidays[day]) {
                printf("ERROR not workday %s\n", a[2]);
                return;
            }
            if (employee->leave[day]) {
                printf("ERROR duplicate leave %s %s\n", a[1], a[2]);
                return;
            }
            employee->leave[day] = 1;
            printf("LEAVE %d day %d %s\n", employee->id, day, weekday(day));
        } else {
            Amount amount;
            if (!checked_amount(a[3], &amount)) return;
            int period = period_of(day);
            employee->sales[period] += amount;
            printf("SALES %d day %d %s period %d total %s\n", employee->id,
                   day, money(amount), period, money(employee->sales[period]));
        }
    } else if (!strcmp(command, "HOURS")) {
        Employee *employee = require_employee(a[1], 0, HOURLY);
        if (!employee) return;
        int period;
        if (!checked_period(a[2], &period)) return;
        show_hours(employee, period);
    } else if (!strcmp(command, "RUN")) {
        int period = atoi(a[1]);
        if (period != closed_periods + 1 || period > 26) {
            printf("ERROR invalid period %s\n", a[1]);
            return;
        }
        print_run(period);
    } else if (!strcmp(command, "PREVIEW")) {
        Employee *employee = require_employee(a[1], 0, -1);
        if (!employee) return;
        int period = closed_periods + 1;
        Stub stub;
        Amount *balances = calloc((size_t)employee->garnishes + 1, sizeof(Amount));
        int has_pay = calculate(employee, period, &stub, balances);
        printf("PREVIEW %d period %d\n", employee->id, period);
        if (has_pay) print_stub(employee, period, &stub, employee->department);
        else puts("  no pay");
        free(balances);
    } else if (!strcmp(command, "REPRINT")) {
        Employee *employee = require_employee(a[1], 0, -1);
        if (!employee) return;
        int period;
        if (!checked_period(a[2], &period)) return;
        if (!employee->stubs[period].exists) {
            printf("ERROR no stub %s %s\n", a[1], a[2]);
            return;
        }
        printf("REPRINT %d %d\n", employee->id, period);
        Stored *saved = &employee->stubs[period];
        print_stub(employee, period, &saved->stub, saved->department);
    } else if (!strcmp(command, "YTD")) {
        Employee *employee = require_employee(a[1], 0, -1);
        if (!employee) return;
        ytd(employee);
    } else if (!strcmp(command, "JOURNAL")) {
        int period = atoi(a[1]);
        if (period < 1 || period > closed_periods) {
            printf("ERROR no run %s\n", a[1]);
            return;
        }
        journal(period);
    } else if (!strcmp(command, "REPORT")) {
        report();
    } else if (!strcmp(command, "TOP")) {
        show_top(atoi(a[1]));
    } else if (!strcmp(command, "EMPLOYEES")) {
        show_employees();
    } else if (!strcmp(command, "CONFIG")) {
        config();
    }
}

int main(void) {
    int n;
    if (scanf("%d\n", &n) != 1) return 0;
    char line[4096];
    for (int i = 0; i < n && fgets(line, sizeof(line), stdin); ++i) {
        char *args[64];
        int count = 0;
        for (char *token = strtok(line, " \t\r\n");
             token && count < 64;
             token = strtok(NULL, " \t\r\n")) {
            args[count++] = token;
        }
        if (count) execute(args);
    }
    return 0;
}
