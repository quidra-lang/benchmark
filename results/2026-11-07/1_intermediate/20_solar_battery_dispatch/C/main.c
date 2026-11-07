#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_DAYS 31
#define MAX_HOURS (MAX_DAYS * 24)
#define MAX_PERIODS 6
#define MAX_PROFILES 10
#define MAX_ARGS 64


typedef int64_t Money;

enum Setting {
    CAPACITY, INITIAL, CHARGE, DISCHARGE, CEFF, DEFF, RESERVE, COST,
    EXPORT, FEEDIN, FIXED, DEMAND, PVSCALE, SETTING_COUNT
};
static const char *settingNames[SETTING_COUNT] = {
    "CAPACITY", "INITIAL", "CHARGE", "DISCHARGE", "CEFF", "DEFF", "RESERVE",
    "COST", "EXPORT", "FEEDIN", "FIXED", "DEMAND", "PVSCALE"
};
static const Money settingMinimum[SETTING_COUNT] = {1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0};
static const Money settingMaximum[SETTING_COUNT] = {
    100000, 100, 20000, 20000, 100, 100, 100, 100000,
    100000, 10000, 100000, 100000, 300
};
static const char *flowNames[8] = {
    "PV>LOAD", "PV>BATTERY", "PV>GRID", "PV>CURTAIL",
    "BATTERY>LOAD", "BATTERY>GRID", "GRID>LOAD", "GRID>BATTERY"
};
static const char *dayNames[7] = {"MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"};

typedef struct { Money values[SETTING_COUNT]; } Settings;
typedef struct { char name[11]; Money price; } Price;

typedef struct {
    int kind;
    char name[11];
    Money values[24];
} Profile;

typedef struct {
    Settings initial;
    Price prices[MAX_PERIODS];
    int priceCount;
    int dayCount;
    Money loads[MAX_HOURS], pv[MAX_HOURS];
    int periods[MAX_HOURS], weekend[MAX_DAYS];
    char days[MAX_DAYS][4];
} Data;

enum Method { SELF, TOU, PEAKSHAVE, BACKUP, EXPORTPEAK };
typedef struct { enum Method method; Money parameter; } Strategy;

typedef struct {
    int index, day, hour, period;
    Money load, pv, soc, flows[8], charge, discharge;
    Money imported, exported, curtailed, drawn, shortfall, loss;
    Money importCost, exportIncome, netCost;
} Hour;

typedef struct {
    int count;
    Money load, pv, charge, discharge, imported, exported, curtailed;
    Money drawn, shortfall, loss, importCost, exportIncome, netCost;
    Money flows[8];
} Totals;

typedef struct {
    Strategy strategy;
    Settings settings;
    Money prices[MAX_PERIODS];
    Money startSoc, reserve, endSoc, peak, demandCharge, bill;
    Hour hours[MAX_HOURS];
    Totals daily[MAX_DAYS], byPeriod[MAX_PERIODS], total;
} Result;

static Data data;
static Settings settings;
static Money prices[MAX_PERIODS];
static Result current, reference, trial;
static bool hasCurrent = false;

static Money value(const char *text) { return strtoll(text, NULL, 10); }
static Money min(Money a, Money b) { return a < b ? a : b; }
static Money max(Money a, Money b) { return a > b ? a : b; }
static Money min3(Money a, Money b, Money c) { return min(min(a, b), c); }
static Money ceiling(Money a, Money b) { return (a + b - 1) / b; }
static Money gcd(Money a, Money b) {
    while (b) { Money t = b; b = a % b; a = t; }
    return a;
}

static const char *money(Money amount) {
    static char buffers[16][36];
    static int next = 0;
    char *buffer = buffers[next++ % 16];
    Money positive = amount < 0 ? -amount : amount;
    snprintf(buffer, 36, "%s%lld.%02lld", amount < 0 ? "-" : "",
             (long long)(positive / 100), (long long)(positive % 100));
    return buffer;
}
static const char *percentage(Money numerator, Money denominator) {
    static char buffers[16][36];
    static int next = 0;
    char *buffer = buffers[next++ % 16];
    Money fraction = denominator ? numerator * 10000 / denominator : 0;
    snprintf(buffer, 36, "%lld.%02lld", (long long)(fraction / 100),
             (long long)(fraction % 100));
    return buffer;
}
static void bar(char output[23], int width) {
    output[0] = '|';
    for (int i = 0; i < 20; ++i) output[i + 1] = i < width ? '#' : '.';
    output[21] = '|';
    output[22] = '\0';
}
static void error(const char *message) { printf("ERROR %s\n", message); }
static void requireArgumentError(void) { error("wrong number of arguments"); }

static int tokenize(char *line, char *tokens[MAX_ARGS]) {
    int count = 0;
    for (char *token = strtok(line, " \t\r\n"); token && count < MAX_ARGS;
         token = strtok(NULL, " \t\r\n")) tokens[count++] = token;
    return count;
}
static void inputTokens(char *tokens[MAX_ARGS], int *count) {
    static char line[4096];
    if (!fgets(line, sizeof(line), stdin)) exit(1);
    *count = tokenize(line, tokens);
}
static int periodIndex(const char *name) {
    for (int i = 0; i < data.priceCount; ++i)
        if (!strcmp(name, data.prices[i].name)) return i;
    return -1;
}
static int settingIndex(const char *name) {
    for (int i = 0; i < SETTING_COUNT; ++i)
        if (!strcmp(name, settingNames[i])) return i;
    return -1;
}
static void periodHours(char *tokens[MAX_ARGS], int n, int hours[24]) {
    for (int i = 1; i < n; i += 2) {
        int start = (int)value(tokens[i]);
        int end = i + 2 < n ? (int)value(tokens[i + 2]) : 24;
        int period = periodIndex(tokens[i + 1]);
        for (int h = start; h < end; ++h) hours[h] = period;
    }
}

static void readData(void) {
    char *tokens[MAX_ARGS];
    int n;
    inputTokens(tokens, &n);
    for (int i = 0; i < 8; ++i) data.initial.values[i] = value(tokens[i + 1]);
    inputTokens(tokens, &n);
    for (int i = 0; i < 4; ++i) data.initial.values[i + 8] = value(tokens[i + 1]);
    data.initial.values[PVSCALE] = 100;
    inputTokens(tokens, &n);
    data.priceCount = (int)value(tokens[1]);
    for (int i = 0; i < data.priceCount; ++i) {
        inputTokens(tokens, &n);
        strcpy(data.prices[i].name, tokens[0]);
        data.prices[i].price = value(tokens[1]);
    }
    int weekday[24], weekend[24];
    inputTokens(tokens, &n);
    periodHours(tokens, n, weekday);
    inputTokens(tokens, &n);
    periodHours(tokens, n, weekend);
    inputTokens(tokens, &n);
    int profileCount = (int)value(tokens[1]);
    Profile profiles[MAX_PROFILES];
    for (int i = 0; i < profileCount; ++i) {
        inputTokens(tokens, &n);
        profiles[i].kind = !strcmp(tokens[0], "LOAD") ? 0 : 1;
        strcpy(profiles[i].name, tokens[1]);
        for (int h = 0; h < 24; ++h) profiles[i].values[h] = value(tokens[h + 2]);
    }
    inputTokens(tokens, &n);
    data.dayCount = (int)value(tokens[1]);
    for (int day = 0; day < data.dayCount; ++day) {
        inputTokens(tokens, &n);
        Profile *load = NULL, *pv = NULL;
        for (int i = 0; i < profileCount; ++i) {
            if (!profiles[i].kind && !strcmp(profiles[i].name, tokens[0])) load = &profiles[i];
            if (profiles[i].kind && !strcmp(profiles[i].name, tokens[2])) pv = &profiles[i];
        }
        Money loadPct = value(tokens[1]), pvPct = value(tokens[3]);
        for (int h = 0; h < 24; ++h) {
            data.loads[24 * day + h] = load->values[h] * loadPct / 100;
            data.pv[24 * day + h] = pv->values[h] * pvPct / 100;
        }
    }
    int holidays[MAX_DAYS + 1] = {0};
    inputTokens(tokens, &n);
    for (int i = 2; i < n; ++i) holidays[(int)value(tokens[i])] = 1;
    inputTokens(tokens, &n);
    int overrides = (int)value(tokens[1]);
    for (int i = 0; i < overrides; ++i) {
        inputTokens(tokens, &n);
        int index = ((int)value(tokens[0]) - 1) * 24 + (int)value(tokens[1]);
        data.loads[index] = value(tokens[2]);
        data.pv[index] = value(tokens[3]);
    }
    for (int day = 1; day <= data.dayCount; ++day) {
        int holiday = holidays[day];
        int isWeekend = holiday || (day - 1) % 7 >= 5;
        data.weekend[day - 1] = isWeekend;
        strcpy(data.days[day - 1], holiday ? "HOL" : dayNames[(day - 1) % 7]);
        for (int hour = 0; hour < 24; ++hour)
            data.periods[(day - 1) * 24 + hour] = isWeekend ? weekend[hour] : weekday[hour];
    }
    settings = data.initial;
    for (int i = 0; i < data.priceCount; ++i) prices[i] = data.prices[i].price;
}

static void tariffExtremes(const Money price[MAX_PERIODS], int *cheapest, int *peak) {
    *cheapest = *peak = 0;
    for (int i = 0; i < data.priceCount; ++i) {
        if (price[i] < price[*cheapest]) *cheapest = i;
        if (price[i] > price[*peak]) *peak = i;
    }
}
static const char *strategyName(enum Method method) {
    static const char *names[] = {"SELF", "TOU", "PEAKSHAVE", "BACKUP", "EXPORTPEAK"};
    return names[method];
}
static const char *strategyText(Strategy strategy) {
    static char buffer[50];
    if (strategy.method == SELF || strategy.method == EXPORTPEAK)
        snprintf(buffer, sizeof(buffer), "%s", strategyName(strategy.method));
    else snprintf(buffer, sizeof(buffer), "%s %lld", strategyName(strategy.method),
                  (long long)strategy.parameter);
    return buffer;
}
static bool parseStrategies(char *tokens[], int n, Strategy results[],
                            int *count, char *errorMessage) {
    *count = 0;
    for (int i = 0; i < n;) {
        char *name = tokens[i++];
        Strategy strategy = {0};
        if (!strcmp(name, "SELF")) strategy.method = SELF;
        else if (!strcmp(name, "EXPORTPEAK")) strategy.method = EXPORTPEAK;
        else {
            Money low = 0, high = 0;
            if (!strcmp(name, "TOU")) {
                strategy.method = TOU; low = 1; high = 100;
            } else if (!strcmp(name, "PEAKSHAVE")) {
                strategy.method = PEAKSHAVE; low = 0; high = 100000;
            } else if (!strcmp(name, "BACKUP")) {
                strategy.method = BACKUP; low = 0; high = 100;
            } else {
                snprintf(errorMessage, 100, "unknown strategy %s", name);
                return false;
            }
            if (i == n) {
                snprintf(errorMessage, 100, "missing parameter for %s", name);
                return false;
            }
            strategy.parameter = value(tokens[i++]);
            if (strategy.parameter < low || strategy.parameter > high) {
                snprintf(errorMessage, 100, "invalid parameter for %s", name);
                return false;
            }
        }
        results[(*count)++] = strategy;
    }
    return true;
}
static bool oneStrategy(char *tokens[], int n, Strategy *strategy) {
    char message[100];
    Strategy results[MAX_ARGS];
    int count;
    if (!parseStrategies(tokens, n, results, &count, message)) { error(message); return false; }
    if (count != 1) { requireArgumentError(); return false; }
    *strategy = results[0];
    return true;
}

static void addHour(Totals *total, const Hour *hour) {
    ++total->count;
    total->load += hour->load; total->pv += hour->pv;
    total->charge += hour->charge; total->discharge += hour->discharge;
    total->imported += hour->imported; total->exported += hour->exported;
    total->curtailed += hour->curtailed; total->drawn += hour->drawn;
    total->shortfall += hour->shortfall; total->loss += hour->loss;
    total->importCost += hour->importCost; total->exportIncome += hour->exportIncome;
    total->netCost += hour->netCost;
    for (int i = 0; i < 8; ++i) total->flows[i] += hour->flows[i];
}

static void simulate(Strategy strategy, const Settings *options,
                     const Money tariff[MAX_PERIODS], Result *result,
                     int outageFirst, int outageLast) {
    memset(result, 0, sizeof(*result));
    result->strategy = strategy;
    result->settings = *options;
    memcpy(result->prices, tariff, sizeof(result->prices));
    Money capacity = options->values[CAPACITY];
    Money ceff = options->values[CEFF], deff = options->values[DEFF];
    Money reservePct = options->values[RESERVE];
    if (strategy.method == BACKUP) reservePct = max(reservePct, strategy.parameter);
    result->reserve = capacity * reservePct / 100;
    result->startSoc = capacity * options->values[INITIAL] / 100;
    Money soc = result->startSoc;
    int cheapest, peak;
    tariffExtremes(tariff, &cheapest, &peak);
    int arbitrage = strategy.method == EXPORTPEAK &&
                    options->values[FEEDIN] > tariff[cheapest];
    int count = data.dayCount * 24;
    for (int index = 0; index < count; ++index) {
        Hour *r = &result->hours[index];
        r->index = index;
        r->day = index / 24 + 1;
        r->hour = index % 24;
        r->period = data.periods[index];
        r->load = data.loads[index];
        r->pv = data.pv[index] * options->values[PVSCALE] / 100;
        Money direct = min(r->load, r->pv);
        Money surplus = r->pv - direct;
        Money deficit = r->load - direct;
        Money pvCharge = min3(surplus, options->values[CHARGE],
                              ceiling(100 * (capacity - soc), ceff));
        soc += pvCharge * ceff / 100;
        surplus -= pvCharge;
        bool outage = index >= outageFirst && index <= outageLast;
        Money target = deficit;
        if (!outage) {
            if (strategy.method == TOU) target = r->period == peak ? deficit : 0;
            else if (strategy.method == PEAKSHAVE) target = max(0, deficit - strategy.parameter);
            else if (arbitrage && r->period == cheapest && r->period != peak) target = 0;
        }
        Money lowerBound = outage ? 0 : result->reserve;
        Money loadDrawn = min3(ceiling(100 * target, deff), options->values[DISCHARGE],
                               max(0, soc - lowerBound));
        Money loadDischarge = loadDrawn * deff / 100;
        soc -= loadDrawn;
        deficit -= loadDischarge;
        Money gridLoad = 0, shortfall = 0, pvExport = 0, curtailed = 0, gridCharge = 0;
        Money exportDrawn = 0, batteryExport = 0;
        if (outage) { shortfall = deficit; curtailed = surplus; }
        else {
            gridLoad = deficit;
            pvExport = min(surplus, options->values[EXPORT]);
            curtailed = surplus - pvExport;
            Money headroom = options->values[CHARGE] - pvCharge;
            Money chargeTarget = -1;
            if (strategy.method == TOU && r->period == cheapest && r->period != peak)
                chargeTarget = capacity * strategy.parameter / 100;
            else if (strategy.method == PEAKSHAVE && r->period == cheapest) {
                chargeTarget = capacity;
                headroom = min(headroom, max(0, strategy.parameter - gridLoad));
            } else if (strategy.method == BACKUP && r->period == cheapest)
                chargeTarget = result->reserve;
            else if (arbitrage && r->period == cheapest && r->period != peak)
                chargeTarget = capacity;
            if (chargeTarget >= 0) {
                gridCharge = min(headroom, ceiling(100 * max(0, chargeTarget - soc), ceff));
                soc += gridCharge * ceff / 100;
            }
            if (arbitrage && r->period == peak && pvCharge == 0) {
                exportDrawn = min3(ceiling(100 * (options->values[EXPORT] - pvExport), deff),
                                   options->values[DISCHARGE] - loadDrawn,
                                   max(0, soc - result->reserve));
                batteryExport = exportDrawn * deff / 100;
                soc -= exportDrawn;
            }
        }
        r->soc = soc;
        r->flows[0] = direct; r->flows[1] = pvCharge;
        r->flows[2] = pvExport; r->flows[3] = curtailed;
        r->flows[4] = loadDischarge; r->flows[5] = batteryExport;
        r->flows[6] = gridLoad; r->flows[7] = gridCharge;
        r->charge = pvCharge + gridCharge;
        r->discharge = loadDischarge + batteryExport;
        r->imported = gridLoad + gridCharge;
        r->exported = pvExport + batteryExport;
        r->curtailed = curtailed;
        r->drawn = loadDrawn + exportDrawn;
        r->shortfall = shortfall;
        r->loss = pvCharge - pvCharge * ceff / 100 + gridCharge - gridCharge * ceff / 100 +
                  loadDrawn - loadDischarge + exportDrawn - batteryExport;
        r->importCost = r->imported * tariff[r->period] / 100000;
        r->exportIncome = r->exported * options->values[FEEDIN] / 100000;
        r->netCost = r->importCost - r->exportIncome;
        addHour(&result->total, r);
        addHour(&result->daily[r->day - 1], r);
        addHour(&result->byPeriod[r->period], r);
        result->peak = max(result->peak, r->imported);
    }
    result->demandCharge = result->peak * options->values[DEMAND] / 1000;
    result->bill = result->total.netCost + options->values[FIXED] + result->demandCharge;
    result->endSoc = soc;
}

static void baseline(const Settings *options, const Money tariffs[MAX_PERIODS], Result *result) {
    Settings without = *options;
    without.values[CAPACITY] = 0;
    simulate((Strategy){SELF, 0}, &without, tariffs, result, 1, 0);
}

static bool checkCount(int actual, int expected) {
    if (actual != expected) { requireArgumentError(); return false; }
    return true;
}
static bool checkCurrent(void) {
    if (!hasCurrent) { error("no run"); return false; }
    return true;
}
static bool checkedDay(const char *token, int *day) {
    *day = (int)value(token);
    if (*day < 1 || *day > data.dayCount) { error("invalid day"); return false; }
    return true;
}
static bool checkedRange(Money low, Money high, Money step, Money minimum, Money maximum) {
    if (low < minimum || high > maximum || high < low || step < 1 ||
        (high - low) / step + 1 > 20) {
        error("invalid range"); return false;
    }
    return true;
}
static bool checkNoArgs(int argc) { return checkCount(argc, 0) && checkCurrent(); }
static void barAndPrint(int count, int total, const char *prefix) {
    char graphic[23];
    bar(graphic, 20 * count / total);
    printf("%s %s %d\n", prefix, graphic, count);
}

static void execute(char *tokens[MAX_ARGS], int n) {
    if (!n) return;
    char *command = tokens[0];
    char **args = tokens + 1;
    int argc = n - 1;

    if (!strcmp(command, "RUN")) {
        Strategy strategy;
        if (!oneStrategy(args, argc, &strategy)) return;
        simulate(strategy, &settings, prices, &current, 1, 0);
        hasCurrent = true;
        printf("RUN %s bill %s import %lld export %lld soc %lld\n", strategyText(strategy),
               money(current.bill), (long long)current.total.imported,
               (long long)current.total.exported, (long long)current.endSoc);
    } else if (!strcmp(command, "SET")) {
        if (!checkCount(argc, 2)) return;
        int which = settingIndex(args[0]);
        if (which < 0) { printf("ERROR unknown parameter %s\n", args[0]); return; }
        Money number = value(args[1]);
        if (number < settingMinimum[which] || number > settingMaximum[which]) {
            printf("ERROR invalid value for %s\n", args[0]); return;
        }
        printf("SET %s %lld -> %lld\n", args[0], (long long)settings.values[which], (long long)number);
        settings.values[which] = number;
    } else if (!strcmp(command, "PRICE")) {
        if (!checkCount(argc, 2)) return;
        int which = periodIndex(args[0]);
        if (which < 0) { printf("ERROR unknown period %s\n", args[0]); return; }
        Money number = value(args[1]);
        if (number < 0 || number > 10000) {
            printf("ERROR invalid value for %s\n", args[0]); return;
        }
        Money previous = prices[which];
        prices[which] = number;
        int cheapest, peak;
        tariffExtremes(prices, &cheapest, &peak);
        printf("PRICE %s %lld -> %lld cheapest %s peak %s\n", args[0],
               (long long)previous, (long long)number,
               data.prices[cheapest].name, data.prices[peak].name);
    } else if (!strcmp(command, "RESET")) {
        if (!checkCount(argc, 0)) return;
        settings = data.initial;
        for (int i = 0; i < data.priceCount; ++i) prices[i] = data.prices[i].price;
        puts("RESET");
    } else if (!strcmp(command, "CONFIG")) {
        if (!checkCount(argc, 0)) return;
        printf("BATTERY");
        for (int i = 0; i < 8; ++i) {
            char name[16];
            strcpy(name, settingNames[i]);
            for (char *p = name; *p; ++p) if (*p >= 'A' && *p <= 'Z') *p += 'a' - 'A';
            printf(" %s %lld", name, (long long)settings.values[i]);
        }
        putchar('\n');
        printf("GRID");
        for (int i = 8; i < 12; ++i) {
            char name[16];
            strcpy(name, settingNames[i]);
            for (char *p = name; *p; ++p) if (*p >= 'A' && *p <= 'Z') *p += 'a' - 'A';
            printf(" %s %lld", name, (long long)settings.values[i]);
        }
        printf("\nSOLAR pvscale %lld\n", (long long)settings.values[PVSCALE]);
        printf("TARIFF");
        for (int i = 0; i < data.priceCount; ++i)
            printf(" %s %lld", data.prices[i].name, (long long)prices[i]);
        int cheapest, peak;
        tariffExtremes(prices, &cheapest, &peak);
        printf(" cheapest %s peak %s\n", data.prices[cheapest].name, data.prices[peak].name);
    } else if (!strcmp(command, "NOBATTERY")) {
        if (!checkCount(argc, 0)) return;
        baseline(&settings, prices, &reference);
        printf("NOBATTERY bill %s import %lld export %lld curtailed %lld peak %lld\n",
               money(reference.bill), (long long)reference.total.imported,
               (long long)reference.total.exported, (long long)reference.total.curtailed,
               (long long)reference.peak);
    } else if (!strcmp(command, "COMPARE")) {
        Strategy strategies[MAX_ARGS];
        char message[100];
        int count;
        if (!parseStrategies(args, argc, strategies, &count, message)) { error(message); return; }
        if (!count) { requireArgumentError(); return; }
        baseline(&settings, prices, &reference);
        struct CompareRow {
            Strategy strategy;
            Money bill;
            char sufficiency[36];
        } rows[10];
        for (int i = 0; i < count; ++i) {
            simulate(strategies[i], &settings, prices, &trial, 1, 0);
            rows[i].strategy = strategies[i];
            rows[i].bill = trial.bill;
            strcpy(rows[i].sufficiency,
                   percentage(max(0, trial.total.load - trial.total.imported), trial.total.load));
        }
        for (int i = 1; i < count; ++i) {
            struct CompareRow row = rows[i];
            int j = i;
            while (j > 0 && rows[j - 1].bill > row.bill) {
                rows[j] = rows[j - 1]; --j;
            }
            rows[j] = row;
        }
        printf("COMPARE baseline %s\n", money(reference.bill));
        for (int i = 0; i < count; ++i) {
            printf("%d. %s bill %s saving %s sufficiency %s%%\n", i + 1,
                   strategyText(rows[i].strategy), money(rows[i].bill),
                   money(reference.bill - rows[i].bill), rows[i].sufficiency);
        }
    } else if (!strcmp(command, "SIZE")) {
        if (!checkCount(argc, 3)) return;
        Money low = value(args[0]), high = value(args[1]), step = value(args[2]);
        if (!checkedRange(low, high, step, settingMinimum[CAPACITY], settingMaximum[CAPACITY])) return;
        baseline(&settings, prices, &reference);
        Money bestCapacity = 0, bestCost = 0, bestSaving = 0;
        for (Money capacity = low; capacity <= high; capacity += step) {
            Settings options = settings;
            options.values[CAPACITY] = capacity;
            simulate((Strategy){SELF, 0}, &options, prices, &trial, 1, 0);
            Money saving = reference.bill - trial.bill;
            Money cost = capacity * options.values[COST] / 1000;
            char payback[40] = "never";
            if (saving > 0) {
                Money tenths = 10 * cost / saving;
                snprintf(payback, sizeof(payback), "%lld.%lld", (long long)(tenths / 10),
                         (long long)(tenths % 10));
                if (!bestCapacity || cost * bestSaving < bestCost * saving) {
                    bestCapacity = capacity; bestCost = cost; bestSaving = saving;
                }
            }
            printf("SIZE %lld bill %s saving %s cost %s payback %s\n",
                   (long long)capacity, money(trial.bill), money(saving), money(cost), payback);
        }
        if (bestCapacity) printf("BEST %lld\n", (long long)bestCapacity);
        else puts("BEST none");
    } else if (!strcmp(command, "SWEEP")) {
        if (argc < 5) { requireArgumentError(); return; }
        int which = settingIndex(args[0]);
        if (which < 0) { printf("ERROR unknown parameter %s\n", args[0]); return; }
        Money low = value(args[1]), high = value(args[2]), step = value(args[3]);
        if (!checkedRange(low, high, step, settingMinimum[which], settingMaximum[which])) return;
        Strategy strategy;
        if (!oneStrategy(args + 4, argc - 4, &strategy)) return;
        Money bestValue = 0, bestBill = 0;
        bool found = false;
        for (Money number = low; number <= high; number += step) {
            Settings options = settings;
            options.values[which] = number;
            simulate(strategy, &options, prices, &trial, 1, 0);
            baseline(&options, prices, &reference);
            if (!found || trial.bill < bestBill) {
                bestValue = number; bestBill = trial.bill; found = true;
            }
            printf("SWEEP %s %lld bill %s saving %s sufficiency %s%%\n", args[0],
                   (long long)number, money(trial.bill), money(reference.bill - trial.bill),
                   percentage(max(0, trial.total.load - trial.total.imported), trial.total.load));
        }
        printf("BEST %lld\n", (long long)bestValue);
    } else if (!strcmp(command, "OUTAGE")) {
        if (!checkCount(argc, 3)) return;
        int day;
        if (!checkedDay(args[0], &day)) return;
        int start = (int)value(args[1]), end = (int)value(args[2]);
        if (start < 0 || start > end || end > 23) { error("invalid hours"); return; }
        if (!checkCurrent()) return;
        int first = (day - 1) * 24 + start, last = (day - 1) * 24 + end;
        simulate(current.strategy, &current.settings, current.prices, &trial, first, last);
        Money before = first ? trial.hours[first - 1].soc : trial.startSoc;
        printf("OUTAGE day %d hours %d-%d strategy %s soc %lld\n", day, start, end,
               strategyText(trial.strategy), (long long)before);
        puts("hour   load     pv  disch    soc  short   curt");
        Totals total = {0};
        for (int i = first; i <= last; ++i) {
            const Hour *r = &trial.hours[i];
            printf("%4d%7lld%7lld%7lld%7lld%7lld%7lld\n", r->hour,
                   (long long)r->load, (long long)r->pv, (long long)r->discharge,
                   (long long)r->soc, (long long)r->shortfall, (long long)r->curtailed);
            addHour(&total, r);
        }
        printf("TOTAL load %lld unserved %lld served %s%% bill %s\n",
               (long long)total.load, (long long)total.shortfall,
               total.load ? percentage(total.load - total.shortfall, total.load) : "100.00",
               money(trial.bill));
    } else if (!strcmp(command, "DIFF")) {
        if (argc < 2) { requireArgumentError(); return; }
        int day;
        if (!checkedDay(args[0], &day)) return;
        Strategy strategy;
        if (!oneStrategy(args + 1, argc - 1, &strategy)) return;
        if (!checkCurrent()) return;
        simulate(strategy, &current.settings, current.prices, &trial, 1, 0);
        char oldName[50], newName[50];
        snprintf(oldName, sizeof(oldName), "%s", strategyText(current.strategy));
        snprintf(newName, sizeof(newName), "%s", strategyText(strategy));
        printf("DIFF day %d %s %s vs %s\n", day, data.days[day - 1], oldName, newName);
        puts("hour   imp1   imp2   exp1   exp2   soc1   soc2");
        for (int h = 0; h < 24; ++h) {
            int i = (day - 1) * 24 + h;
            const Hour *a = &current.hours[i], *b = &trial.hours[i];
            printf("%4d%7lld%7lld%7lld%7lld%7lld%7lld\n", a->hour,
                   (long long)a->imported, (long long)b->imported,
                   (long long)a->exported, (long long)b->exported,
                   (long long)a->soc, (long long)b->soc);
        }
        Money cost1 = current.daily[day - 1].netCost;
        Money cost2 = trial.daily[day - 1].netCost;
        printf("TOTAL cost1 %s cost2 %s difference %s\n", money(cost1), money(cost2), money(cost2 - cost1));
    } else if (!strcmp(command, "HOURLY")) {
        if (!checkCount(argc, 1)) return;
        int day;
        if (!checkedDay(args[0], &day) || !checkCurrent()) return;
        printf("HOURLY day %d %s strategy %s\n", day, data.days[day - 1], strategyText(current.strategy));
        puts("hour   load     pv charge  disch    soc import export   curt");
        for (int h = 0; h < 24; ++h) {
            const Hour *r = &current.hours[(day - 1) * 24 + h];
            printf("%4d%7lld%7lld%7lld%7lld%7lld%7lld%7lld%7lld\n", r->hour,
                   (long long)r->load, (long long)r->pv, (long long)r->charge,
                   (long long)r->discharge, (long long)r->soc, (long long)r->imported,
                   (long long)r->exported, (long long)r->curtailed);
        }
        const Totals *t = &current.daily[day - 1];
        printf("%4s%7lld%7lld%7lld%7lld%7s%7lld%7lld%7lld\n", "sum",
               (long long)t->load, (long long)t->pv, (long long)t->charge,
               (long long)t->discharge, "", (long long)t->imported,
               (long long)t->exported, (long long)t->curtailed);
    } else if (!strcmp(command, "DAILY")) {
        if (!checkNoArgs(argc)) return;
        printf("DAILY strategy %s\n", strategyText(current.strategy));
        puts("day name    load      pv  import  export    curt     soc      cost");
        for (int day = 0; day < data.dayCount; ++day) {
            const Totals *t = &current.daily[day];
            printf("%3d%5s%8lld%8lld%8lld%8lld%8lld%8lld%10s\n", day + 1,
                   data.days[day], (long long)t->load, (long long)t->pv,
                   (long long)t->imported, (long long)t->exported,
                   (long long)t->curtailed, (long long)current.hours[(day + 1) * 24 - 1].soc,
                   money(t->netCost));
        }
        const Totals *t = &current.total;
        printf("TOTAL load %lld pv %lld import %lld export %lld curtailed %lld cost %s\n",
               (long long)t->load, (long long)t->pv, (long long)t->imported,
               (long long)t->exported, (long long)t->curtailed, money(t->netCost));
    } else if (!strcmp(command, "BILL")) {
        if (!checkNoArgs(argc)) return;
        printf("BILL strategy %s days %d\n", strategyText(current.strategy), data.dayCount);
        for (int i = 0; i < data.priceCount; ++i) {
            const Totals *t = &current.byPeriod[i];
            printf("IMPORT %s %lld Wh %s\n", data.prices[i].name,
                   (long long)t->imported, money(t->importCost));
        }
        printf("EXPORT %lld Wh %s\n", (long long)current.total.exported,
               money(-current.total.exportIncome));
        printf("FIXED %s\n", money(current.settings.values[FIXED]));
        printf("DEMAND %lld Wh %s\n", (long long)current.peak, money(current.demandCharge));
        printf("TOTAL %s\n", money(current.bill));
    } else if (!strcmp(command, "SAVINGS")) {
        if (!checkNoArgs(argc)) return;
        baseline(&current.settings, current.prices, &reference);
        printf("SAVINGS strategy %s\n", strategyText(current.strategy));
        for (int i = 0; i < data.priceCount; ++i) {
            Money before = reference.byPeriod[i].importCost;
            Money after = current.byPeriod[i].importCost;
            printf("%s %s -> %s saving %s\n", data.prices[i].name,
                   money(before), money(after), money(before - after));
        }
        Money before = -reference.total.exportIncome, after = -current.total.exportIncome;
        printf("EXPORT %s -> %s saving %s\n", money(before), money(after), money(before - after));
        before = reference.demandCharge; after = current.demandCharge;
        printf("DEMAND %s -> %s saving %s\n", money(before), money(after), money(before - after));
        before = reference.bill; after = current.bill;
        printf("TOTAL %s -> %s saving %s\n", money(before), money(after), money(before - after));
    } else if (!strcmp(command, "BYPERIOD")) {
        if (!checkNoArgs(argc)) return;
        printf("BYPERIOD strategy %s\n", strategyText(current.strategy));
        for (int i = 0; i < data.priceCount; ++i) {
            const Totals *t = &current.byPeriod[i];
            printf("%s hours %d load %lld pv %lld charge %lld discharge %lld import %lld export %lld\n",
                   data.prices[i].name, t->count, (long long)t->load, (long long)t->pv,
                   (long long)t->charge, (long long)t->discharge,
                   (long long)t->imported, (long long)t->exported);
        }
    } else if (!strcmp(command, "DAYTYPE")) {
        if (!checkNoArgs(argc)) return;
        printf("DAYTYPE strategy %s\n", strategyText(current.strategy));
        for (int mode = 0; mode < 2; ++mode) {
            int count = 0;
            Totals total = {0};
            for (int day = 0; day < data.dayCount; ++day) {
                if (data.weekend[day] != mode) continue;
                ++count;
                for (int h = 0; h < 24; ++h)
                    addHour(&total, &current.hours[day * 24 + h]);
            }
            printf("%s days %d load %lld pv %lld import %lld export %lld cost %s\n",
                   mode ? "WEEKEND" : "WEEKDAY", count, (long long)(total.load / count),
                   (long long)(total.pv / count), (long long)(total.imported / count),
                   (long long)(total.exported / count), money(total.netCost / count));
        }
    } else if (!strcmp(command, "PEAKS")) {
        if (!checkCount(argc, 1)) return;
        Money count = value(args[0]);
        if (count < 1) { error("invalid count"); return; }
        if (!checkCurrent()) return;
        int indexes[MAX_HOURS], used = 0;
        for (int i = 0; i < data.dayCount * 24; ++i)
            if (current.hours[i].imported > 0) indexes[used++] = i;
        for (int i = 1; i < used; ++i) {
            int chosen = indexes[i], j = i;
            Money amount = current.hours[chosen].imported;
            while (j > 0 && (current.hours[indexes[j - 1]].imported < amount ||
                   (current.hours[indexes[j - 1]].imported == amount && indexes[j - 1] > chosen))) {
                indexes[j] = indexes[j - 1];
                --j;
            }
            indexes[j] = chosen;
        }
        printf("PEAKS strategy %s\n", strategyText(current.strategy));
        for (int i = 0; i < used && i < count; ++i) {
            const Hour *r = &current.hours[indexes[i]];
            printf("%d. day %d hour %d %s import %lld load %lld soc %lld\n", i + 1,
                   r->day, r->hour, data.prices[r->period].name,
                   (long long)r->imported, (long long)r->load, (long long)r->soc);
        }
        if (!used) puts("none");
    } else if (!strcmp(command, "PROFILE")) {
        if (!checkNoArgs(argc)) return;
        printf("PROFILE strategy %s days %d\n", strategyText(current.strategy), data.dayCount);
        puts("hour   load     pv import export    soc");
        for (int h = 0; h < 24; ++h) {
            Money load = 0, pv = 0, imported = 0, exported = 0, soc = 0;
            for (int day = 0; day < data.dayCount; ++day) {
                const Hour *r = &current.hours[24 * day + h];
                load += r->load; pv += r->pv; imported += r->imported;
                exported += r->exported; soc += r->soc;
            }
            printf("%4d%7lld%7lld%7lld%7lld%7lld\n", h,
                   (long long)(load / data.dayCount), (long long)(pv / data.dayCount),
                   (long long)(imported / data.dayCount), (long long)(exported / data.dayCount),
                   (long long)(soc / data.dayCount));
        }
    } else if (!strcmp(command, "FLOWS")) {
        if (!checkNoArgs(argc)) return;
        printf("FLOWS strategy %s\n", strategyText(current.strategy));
        for (int i = 0; i < 8; ++i)
            printf("%s %lld\n", flowNames[i], (long long)current.total.flows[i]);
        printf("LOSSES %lld\nSTORED %lld\n", (long long)current.total.loss,
               (long long)(current.endSoc - current.startSoc));
    } else if (!strcmp(command, "SELFSUFF")) {
        if (!checkNoArgs(argc)) return;
        printf("SELFSUFF sufficiency %s%% consumption %s%%\n",
               percentage(max(0, current.total.load - current.total.imported), current.total.load),
               percentage(current.total.flows[0] + current.total.flows[1], current.total.pv));
    } else if (!strcmp(command, "CYCLES")) {
        if (!checkNoArgs(argc)) return;
        Money drawn = current.total.drawn, capacity = current.settings.values[CAPACITY];
        Money common = gcd(drawn, capacity), thousandths = 1000 * drawn / capacity;
        printf("CYCLES %lld/%lld %lld.%03lld drawn %lld losses %lld\n",
               (long long)(drawn / common), (long long)(capacity / common),
               (long long)(thousandths / 1000), (long long)(thousandths % 1000),
               (long long)drawn, (long long)current.total.loss);
    } else if (!strcmp(command, "USAGE")) {
        if (!checkNoArgs(argc)) return;
        int charging = 0, discharging = 0, idle = 0, full = 0;
        int low = 0, streak = 0, longest = 0, first = -1;
        for (int i = 0; i < data.dayCount * 24; ++i) {
            const Hour *r = &current.hours[i];
            if (r->charge > 0) ++charging;
            if (r->drawn > 0) ++discharging;
            if (!r->charge && !r->drawn) ++idle;
            if (r->soc == current.settings.values[CAPACITY]) ++full;
            if (r->soc <= current.reserve) {
                ++low; ++streak;
                if (streak > longest) { longest = streak; first = i - streak + 1; }
            } else streak = 0;
        }
        printf("USAGE charging %d discharging %d idle %d full %d low %d longest %d",
               charging, discharging, idle, full, low, longest);
        if (first >= 0) printf(" from day %d hour %d", current.hours[first].day, current.hours[first].hour);
        putchar('\n');
    } else if (!strcmp(command, "HISTOGRAM")) {
        if (!checkNoArgs(argc)) return;
        int bands[10] = {0};
        Money capacity = current.settings.values[CAPACITY];
        for (int i = 0; i < data.dayCount * 24; ++i)
            ++bands[(int)min(9, 10 * current.hours[i].soc / capacity)];
        printf("HISTOGRAM strategy %s\n", strategyText(current.strategy));
        for (int band = 0; band < 10; ++band) {
            char prefix[8];
            snprintf(prefix, sizeof(prefix), "%3d%%", 10 * band);
            barAndPrint(bands[band], data.dayCount * 24, prefix);
        }
    } else if (!strcmp(command, "CHART")) {
        if (!checkCount(argc, 1)) return;
        int day;
        if (!checkedDay(args[0], &day) || !checkCurrent()) return;
        Money capacity = current.settings.values[CAPACITY];
        printf("CHART day %d %s strategy %s\n", day, data.days[day - 1], strategyText(current.strategy));
        for (int h = 0; h < 24; ++h) {
            const Hour *r = &current.hours[(day - 1) * 24 + h];
            char graphic[23];
            bar(graphic, (int)(20 * r->soc / capacity));
            printf("%2d %s %s%%\n", r->hour, graphic, percentage(r->soc, capacity));
        }
    } else {
        printf("ERROR unknown command %s\n", command);
    }
}

int main(void) {
    readData();
    char line[4096];
    while (fgets(line, sizeof(line), stdin)) {
        char *tokens[MAX_ARGS];
        int n = tokenize(line, tokens);
        if (n && !strcmp(tokens[0], "END")) break;
        execute(tokens, n);
    }
    return 0;
}
