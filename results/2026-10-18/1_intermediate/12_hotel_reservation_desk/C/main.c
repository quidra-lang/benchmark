#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ROOMS 50
#define MAX_RESERVATIONS 300
#define MAX_COMMANDS 1000
#define MAX_DAYS 36526
#define MAX_NIGHTS 30

enum { BOOKED, INHOUSE, CHECKEDOUT, CANCELLED, NOSHOW };

typedef struct {
    int number;
    char type[9];
    int64_t rate;
    bool clean;
} Room;

typedef struct {
    int start, end;
    int percentage;
} Season;

typedef struct {
    int day, room;
    int64_t rate;
} Night;

typedef struct {
    char item[17];
    int64_t amount;
} Extra;

typedef struct {
    int64_t lodging, discount, penalty, extras, tax, total;
} Bill;

typedef struct {
    char id[9], guest[17];
    int room, arrival, departure;
    Night nights[MAX_NIGHTS];
    int night_count;
    int status;
    Extra extras[MAX_COMMANDS];
    int extra_count;
    int64_t deposit, paid, fee;
    int posting;
    bool has_penalty;
    int penalty_day;
    int64_t penalty_rate;
    Bill bill;
} Reservation;

typedef struct {
    char id[9], guest[17], type[9];
    int arrival, departure;
} Waiting;

static const char *types[] = {"SINGLE", "DOUBLE", "SUITE"};
static const char *status_names[] = {
    "booked", "inhouse", "checkedout", "cancelled", "noshow"
};
static const char *weekdays[] = {
    "SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI"
};

static Room rooms[MAX_ROOMS];
static int room_count;
static Season seasons[MAX_COMMANDS];
static int season_count;
static Reservation reservations[MAX_RESERVATIONS];
static int reservation_count;
static Waiting waitlist[MAX_RESERVATIONS];
static int waiting_count;
static char used_ids[MAX_RESERVATIONS][9];
static int used_count;
static unsigned char blocked[MAX_ROOMS][MAX_DAYS];
static short occupied[MAX_ROOMS][MAX_DAYS];
static int64_t occupied_rate[MAX_ROOMS][MAX_DAYS];
static int today;

static bool leap(int year) {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

static void month_lengths(int year, int days[12]) {
    const int normal[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    memcpy(days, normal, sizeof normal);
    if (leap(year)) days[1] = 29;
}

static int day_number(const char *text) {
    int year, month, day;
    if (sscanf(text, "%4d-%2d-%2d", &year, &month, &day) != 3 ||
        year < 2000 || year > 2099 || month < 1 || month > 12)
        return -1;
    int days[12];
    month_lengths(year, days);
    if (day < 1 || day > days[month - 1]) return -1;
    int number = 0;
    for (int y = 2000; y < year; ++y) number += leap(y) ? 366 : 365;
    for (int m = 0; m < month - 1; ++m) number += days[m];
    return number + day - 1;
}

static const char *date_text(int day) {
    static char buffers[32][16];
    static unsigned index;
    char *buffer = buffers[(index++) % 32];
    int year = 2000, days[12];
    while (day >= (leap(year) ? 366 : 365)) {
        day -= leap(year) ? 366 : 365;
        ++year;
    }
    month_lengths(year, days);
    int month = 0;
    while (day >= days[month]) {
        day -= days[month];
        ++month;
    }
    snprintf(buffer, 16, "%04d-%02d-%02d", year, month + 1, day + 1);
    return buffer;
}

static const char *date_weekday(int day) {
    static char buffers[32][24];
    static unsigned index;
    char *buffer = buffers[(index++) % 32];
    snprintf(buffer, 24, "%s %s", date_text(day), weekdays[day % 7]);
    return buffer;
}

static int64_t cents(const char *text) {
    int64_t whole = 0;
    while (*text != '.') {
        whole = whole * 10 + (*text - '0');
        ++text;
    }
    return whole * 100 + (text[1] - '0') * 10 + (text[2] - '0');
}

static const char *money(int64_t value) {
    static char buffers[64][48];
    static unsigned index;
    char *buffer = buffers[(index++) % 64];
    snprintf(buffer, 48, "%lld.%02lld",
             (long long)(value / 100), (long long)(value % 100));
    return buffer;
}

static const char *deposit_text(const Reservation *reservation, int64_t total) {
    static char buffers[16][160];
    static unsigned index;
    char *buffer = buffers[(index++) % 16];
    snprintf(buffer, 160, "deposit %s %s %s", money(reservation->deposit),
             total >= reservation->deposit ? "due" : "refund",
             money(total >= reservation->deposit ? total - reservation->deposit
                                                  : reservation->deposit - total));
    return buffer;
}

static bool date_checked(const char *text, int *value) {
    *value = day_number(text);
    if (*value < 0) {
        printf("ERROR invalid date %s\n", text);
        return false;
    }
    return true;
}

static bool stay_checked(const char *first, const char *last,
                         int *arrival, int *departure) {
    if (!date_checked(first, arrival) || !date_checked(last, departure)) return false;
    if (*arrival < today) {
        printf("ERROR past date %s\n", first);
        return false;
    }
    if (*departure <= *arrival) {
        printf("ERROR invalid range %s %s\n", first, last);
        return false;
    }
    if (*departure - *arrival > 30) {
        printf("ERROR too long %d\n", *departure - *arrival);
        return false;
    }
    return true;
}

static bool period_checked(const char *first, const char *last,
                           bool restrict_past, bool limit, int *start, int *end) {
    if (!date_checked(first, start) || !date_checked(last, end)) return false;
    if (restrict_past && *start < today) {
        printf("ERROR past date %s\n", first);
        return false;
    }
    if (*end < *start) {
        printf("ERROR invalid range %s %s\n", first, last);
        return false;
    }
    if (limit && *end - *start + 1 > 31) {
        printf("ERROR too long %d\n", *end - *start + 1);
        return false;
    }
    return true;
}

static int room_index(int number) {
    for (int i = 0; i < room_count; ++i)
        if (rooms[i].number == number) return i;
    return -1;
}

static int require_room(const char *text) {
    int index = room_index(atoi(text));
    if (index < 0) printf("ERROR unknown room %s\n", text);
    return index;
}

static bool require_type(const char *type) {
    for (int i = 0; i < 3; ++i) {
        if (strcmp(type, types[i]) == 0) return true;
    }
    printf("ERROR invalid type %s\n", type);
    return false;
}

static bool duplicate_id(const char *id) {
    for (int i = 0; i < used_count; ++i) {
        if (strcmp(id, used_ids[i]) == 0) {
            printf("ERROR duplicate reservation %s\n", id);
            return true;
        }
    }
    return false;
}

static int reservation_index(const char *id) {
    for (int i = 0; i < reservation_count; ++i) {
        if (strcmp(id, reservations[i].id) == 0) return i;
    }
    return -1;
}

static int require_reservation(const char *id, int status) {
    int index = reservation_index(id);
    if (index < 0) {
        printf("ERROR unknown reservation %s\n", id);
        return -1;
    }
    if (status >= 0 && reservations[index].status != status) {
        printf("ERROR invalid status %s %s\n",
               id, status_names[reservations[index].status]);
        return -1;
    }
    return index;
}

static void use_id(const char *id) {
    strcpy(used_ids[used_count++], id);
}

static int64_t night_rate(const Room *room, int day) {
    int percentage = 100;
    for (int i = season_count - 1; i >= 0; --i) {
        if (seasons[i].start <= day && day <= seasons[i].end) {
            percentage = seasons[i].percentage;
            break;
        }
    }
    return room->rate * percentage / 100;
}

static void price_nights(Reservation *reservation, int room,
                         int arrival, int departure) {
    reservation->night_count = 0;
    for (int day = arrival; day < departure; ++day) {
        Night *night = &reservation->nights[reservation->night_count++];
        night->day = day;
        night->room = room;
        night->rate = night_rate(&rooms[room], day);
    }
}

static int64_t lodging(const Reservation *reservation) {
    int64_t total = 0;
    for (int i = 0; i < reservation->night_count; ++i)
        total += reservation->nights[i].rate;
    return total;
}

static void occupy(const Reservation *reservation, int index, int first) {
    for (int i = 0; i < reservation->night_count; ++i) {
        const Night *night = &reservation->nights[i];
        if (first < 0 || night->day >= first) {
            occupied[night->room][night->day] = (short)(index + 1);
            occupied_rate[night->room][night->day] = night->rate;
        }
    }
}

static void release_nights(const Reservation *reservation, int first) {
    for (int i = 0; i < reservation->night_count; ++i) {
        const Night *night = &reservation->nights[i];
        if (first < 0 || night->day >= first) {
            occupied[night->room][night->day] = 0;
            occupied_rate[night->room][night->day] = 0;
        }
    }
}

static int first_unavailable(int room, int arrival, int departure, int except_res) {
    for (int day = arrival; day < departure; ++day) {
        if (blocked[room][day]) return day;
        int index = occupied[room][day] - 1;
        if (index >= 0 && index != except_res) return day;
    }
    return -1;
}

static int free_room(const char *type, int arrival, int departure, int except_res) {
    int result = -1;
    for (int i = 0; i < room_count; ++i) {
        if (strcmp(type, rooms[i].type) == 0 &&
            first_unavailable(i, arrival, departure, except_res) < 0 &&
            (result < 0 || rooms[i].number < rooms[result].number))
            result = i;
    }
    return result;
}

static int inhouse(int room) {
    for (int i = 0; i < reservation_count; ++i) {
        if (reservations[i].room == room && reservations[i].status == INHOUSE)
            return i;
    }
    return -1;
}

static int64_t guest_total(const char *guest) {
    int64_t total = 0;
    for (int i = 0; i < reservation_count; ++i) {
        if (strcmp(reservations[i].guest, guest) == 0)
            total += reservations[i].paid;
    }
    return total;
}

static const char *tier(const char *guest) {
    int64_t points = guest_total(guest) / 100;
    return points >= 2000 ? "GOLD" : points >= 500 ? "SILVER" : "BRONZE";
}

static Bill calculate_bill(const Reservation *reservation) {
    Bill bill = {0};
    bill.lodging = lodging(reservation);
    const char *level = tier(reservation->guest);
    int percentage = strcmp(level, "GOLD") == 0 ? 10 :
                     strcmp(level, "SILVER") == 0 ? 5 : 0;
    bill.discount = bill.lodging * percentage / 100;
    bill.penalty = reservation->has_penalty ? reservation->penalty_rate : 0;
    for (int i = 0; i < reservation->extra_count; ++i)
        bill.extras += reservation->extras[i].amount;
    int64_t subtotal = bill.lodging - bill.discount + bill.penalty + bill.extras;
    bill.tax = subtotal / 10;
    bill.total = subtotal + bill.tax;
    return bill;
}

static void create_reservation(const char *id, const char *guest,
                               int room, int arrival, int departure, bool indent) {
    int index = reservation_count++;
    Reservation *reservation = &reservations[index];
    strcpy(reservation->id, id);
    strcpy(reservation->guest, guest);
    reservation->room = room;
    reservation->arrival = arrival;
    reservation->departure = departure;
    reservation->status = BOOKED;
    price_nights(reservation, room, arrival, departure);
    use_id(id);
    occupy(reservation, index, -1);
    printf("%sBOOK %s %s room %d %s %s -> %s nights %d total %s\n",
           indent ? "  " : "", id, guest, rooms[room].number, rooms[room].type,
           date_text(arrival), date_text(departure), departure - arrival,
           money(lodging(reservation)));
}

static void check_out(int index, int day, bool indent) {
    Reservation *reservation = &reservations[index];
    if (day < reservation->departure) {
        for (int i = 0; i < reservation->night_count; ++i) {
            if (reservation->nights[i].day == day) {
                reservation->has_penalty = true;
                reservation->penalty_day = day;
                reservation->penalty_rate = reservation->nights[i].rate;
                break;
            }
        }
        release_nights(reservation, day);
        int keep = 0;
        while (keep < reservation->night_count &&
               reservation->nights[keep].day < day) ++keep;
        reservation->night_count = keep;
        reservation->departure = day;
    }
    reservation->bill = calculate_bill(reservation);
    Bill bill = reservation->bill;
    reservation->paid = bill.total;
    reservation->status = CHECKEDOUT;
    reservation->posting = day;
    rooms[reservation->room].clean = false;
    printf("%sCHECKOUT %s nights %d lodging %s discount %s penalty %s "
           "extras %s tax %s total %s %s\n",
           indent ? "  " : "", reservation->id, reservation->night_count,
           money(bill.lodging), money(bill.discount), money(bill.penalty),
           money(bill.extras), money(bill.tax), money(bill.total),
           deposit_text(reservation, bill.total));
}

static void process_waitlist(void) {
    int keep = 0;
    for (int i = 0; i < waiting_count; ++i) {
        Waiting entry = waitlist[i];
        if (entry.arrival < today) {
            printf("  WAITLIST %s expired\n", entry.id);
            continue;
        }
        int room = free_room(entry.type, entry.arrival, entry.departure, -1);
        if (room >= 0) {
            create_reservation(entry.id, entry.guest, room,
                               entry.arrival, entry.departure, true);
        } else {
            waitlist[keep++] = entry;
        }
    }
    waiting_count = keep;
}

static int room_sort(const void *a, const void *b) {
    int i = *(const int *)a, j = *(const int *)b;
    return (rooms[i].number > rooms[j].number) - (rooms[i].number < rooms[j].number);
}

static int id_sort(const void *a, const void *b) {
    int i = *(const int *)a, j = *(const int *)b;
    return strcmp(reservations[i].id, reservations[j].id);
}

static int arrival_sort(const void *a, const void *b) {
    int i = *(const int *)a, j = *(const int *)b;
    if (reservations[i].arrival != reservations[j].arrival)
        return (reservations[i].arrival > reservations[j].arrival) -
               (reservations[i].arrival < reservations[j].arrival);
    return id_sort(a, b);
}

static int departure_sort(const void *a, const void *b) {
    int i = *(const int *)a, j = *(const int *)b;
    if (reservations[i].departure != reservations[j].departure)
        return (reservations[i].departure > reservations[j].departure) -
               (reservations[i].departure < reservations[j].departure);
    return id_sort(a, b);
}

static void room_order(int indices[MAX_ROOMS]) {
    for (int i = 0; i < room_count; ++i) indices[i] = i;
    qsort(indices, room_count, sizeof indices[0], room_sort);
}

static void occupancy_parts(const int *indices, int count, int day) {
    int count_blocked = 0, count_occupied = 0;
    for (int i = 0; i < count; ++i) {
        int room = indices[i];
        count_blocked += blocked[room][day] != 0;
        count_occupied += occupied[room][day] != 0;
    }
    int available = count - count_blocked;
    printf("rooms %d blocked %d occupied %d rate ", count, count_blocked, count_occupied);
    if (available > 0) printf("%d%%", count_occupied * 100 / available);
    else printf("n/a");
}

typedef struct {
    int64_t available, occupied, revenue;
} Metrics;

static Metrics daily_values(int day) {
    Metrics m = {room_count, 0, 0};
    for (int r = 0; r < room_count; ++r) {
        m.available -= blocked[r][day] != 0;
        m.occupied += occupied[r][day] != 0;
        m.revenue += occupied_rate[r][day];
    }
    return m;
}

static void metrics_parts(Metrics m) {
    printf("sold %lld/%lld rate ", (long long)m.occupied, (long long)m.available);
    if (m.available > 0)
        printf("%lld%%", (long long)(m.occupied * 100 / m.available));
    else printf("n/a");
    printf(" revenue %s adr ", money(m.revenue));
    if (m.occupied > 0) printf("%s", money(m.revenue / m.occupied));
    else printf("n/a");
    printf(" revpar ");
    if (m.available > 0) printf("%s", money(m.revenue / m.available));
    else printf("n/a");
}

static void command(const char *cmd, char **a) {
    if (strcmp(cmd, "ROOM") == 0) {
        int number = atoi(a[0]);
        if (room_index(number) >= 0) {
            printf("ERROR duplicate room %d\n", number);
            return;
        }
        if (!require_type(a[1])) return;
        Room *room = &rooms[room_count++];
        room->number = number;
        strcpy(room->type, a[1]);
        room->rate = cents(a[2]);
        room->clean = true;
        printf("ROOM %d %s %s\n", number, room->type, money(room->rate));
    } else if (strcmp(cmd, "RATE") == 0) {
        int room = require_room(a[0]);
        if (room < 0) return;
        int64_t previous = rooms[room].rate;
        rooms[room].rate = cents(a[1]);
        printf("RATE %s %s -> %s\n", a[0], money(previous), money(rooms[room].rate));
    } else if (strcmp(cmd, "SEASON") == 0) {
        int first, last;
        if (!period_checked(a[0], a[1], false, false, &first, &last)) return;
        seasons[season_count++] = (Season){first, last, atoi(a[2])};
        printf("SEASON %d %s -> %s %s%%\n", season_count, a[0], a[1], a[2]);
    } else if (strcmp(cmd, "BLOCK") == 0 || strcmp(cmd, "UNBLOCK") == 0) {
        int room = require_room(a[0]), first, last;
        if (room < 0 || !period_checked(a[1], a[2], true, true, &first, &last)) return;
        bool adding = strcmp(cmd, "BLOCK") == 0;
        if (adding) {
            for (int day = first; day <= last; ++day) {
                if (occupied[room][day]) {
                    printf("ERROR room unavailable %s %s\n", a[0], date_text(day));
                    return;
                }
            }
        }
        int changed = 0;
        for (int day = first; day <= last; ++day) {
            if (adding) {
                changed += !blocked[room][day];
                blocked[room][day] = 1;
            } else {
                changed += blocked[room][day] != 0;
                blocked[room][day] = 0;
            }
        }
        printf("%s %s %s -> %s %s %d\n", cmd, a[0], a[1], a[2],
               adding ? "added" : "removed", changed);
    } else if (strcmp(cmd, "CLEAN") == 0) {
        int room = require_room(a[0]);
        if (room < 0) return;
        if (rooms[room].clean) {
            printf("ERROR already clean %s\n", a[0]);
            return;
        }
        rooms[room].clean = true;
        printf("CLEAN %s\n", a[0]);
    } else if (strcmp(cmd, "TODAY") == 0) {
        int day;
        if (!date_checked(a[0], &day)) return;
        if (day < today) {
            printf("ERROR past date %s\n", a[0]);
            return;
        }
        printf("TODAY %s\n", date_weekday(day));
        int indices[MAX_RESERVATIONS], count = 0;
        for (int i = 0; i < reservation_count; ++i)
            if (reservations[i].status == INHOUSE && reservations[i].departure < day)
                indices[count++] = i;
        qsort(indices, count, sizeof indices[0], departure_sort);
        for (int i = 0; i < count; ++i)
            check_out(indices[i], reservations[indices[i]].departure, true);
        count = 0;
        for (int i = 0; i < reservation_count; ++i)
            if (reservations[i].status == BOOKED && reservations[i].arrival < day)
                indices[count++] = i;
        qsort(indices, count, sizeof indices[0], arrival_sort);
        for (int i = 0; i < count; ++i) {
            Reservation *reservation = &reservations[indices[i]];
            release_nights(reservation, -1);
            reservation->fee = reservation->nights[0].rate;
            reservation->paid = reservation->fee;
            reservation->status = NOSHOW;
            reservation->posting = reservation->arrival;
            printf("  NOSHOW %s %s fee %s %s\n", reservation->id, reservation->guest,
                   money(reservation->fee), deposit_text(reservation, reservation->fee));
        }
        today = day;
    } else if (strcmp(cmd, "BOOK") == 0 ||
               strcmp(cmd, "BOOKROOM") == 0 || strcmp(cmd, "WAITLIST") == 0) {
        if (duplicate_id(a[0])) return;
        bool specific = strcmp(cmd, "BOOKROOM") == 0;
        int requested = -1;
        if (specific) {
            requested = require_room(a[2]);
            if (requested < 0) return;
        } else if (!require_type(a[2])) return;
        int arrival, departure;
        if (!stay_checked(a[3], a[4], &arrival, &departure)) return;
        if (specific) {
            int unavailable = first_unavailable(requested, arrival, departure, -1);
            if (unavailable >= 0) {
                printf("ERROR room unavailable %s %s\n", a[2], date_text(unavailable));
                return;
            }
            create_reservation(a[0], a[1], requested, arrival, departure, false);
        } else {
            int room = free_room(a[2], arrival, departure, -1);
            if (room >= 0) {
                create_reservation(a[0], a[1], room, arrival, departure, false);
            } else if (strcmp(cmd, "BOOK") == 0) {
                printf("ERROR no availability %s %s %s\n", a[2], a[3], a[4]);
            } else {
                Waiting *entry = &waitlist[waiting_count++];
                strcpy(entry->id, a[0]);
                strcpy(entry->guest, a[1]);
                strcpy(entry->type, a[2]);
                entry->arrival = arrival;
                entry->departure = departure;
                use_id(a[0]);
                printf("WAITLIST %s queued position %d\n", a[0], waiting_count);
            }
        }
    } else if (strcmp(cmd, "MODIFY") == 0) {
        int index = require_reservation(a[0], BOOKED);
        if (index < 0) return;
        int arrival, departure;
        if (!stay_checked(a[1], a[2], &arrival, &departure)) return;
        Reservation *reservation = &reservations[index];
        int room = reservation->room;
        const char *choice = "kept";
        if (first_unavailable(room, arrival, departure, index) >= 0) {
            room = free_room(rooms[reservation->room].type, arrival, departure, index);
            if (room < 0) {
                printf("ERROR no availability %s %s %s\n",
                       rooms[reservation->room].type, a[1], a[2]);
                return;
            }
            choice = "reassigned";
        }
        release_nights(reservation, -1);
        reservation->room = room;
        reservation->arrival = arrival;
        reservation->departure = departure;
        price_nights(reservation, room, arrival, departure);
        occupy(reservation, index, -1);
        printf("MODIFY %s room %d %s %s -> %s nights %d total %s\n",
               a[0], rooms[room].number, choice, a[1], a[2],
               departure - arrival, money(lodging(reservation)));
    } else if (strcmp(cmd, "CANCEL") == 0) {
        for (int i = 0; i < waiting_count; ++i) {
            if (strcmp(a[0], waitlist[i].id) == 0) {
                memmove(&waitlist[i], &waitlist[i + 1],
                        (size_t)(waiting_count - i - 1) * sizeof waitlist[0]);
                --waiting_count;
                printf("CANCEL %s waitlist removed\n", a[0]);
                return;
            }
        }
        int index = require_reservation(a[0], BOOKED);
        if (index < 0) return;
        Reservation *reservation = &reservations[index];
        int days = reservation->arrival - today;
        int64_t rate = reservation->nights[0].rate;
        int64_t fee = days >= 7 ? 0 : days >= 1 ? rate / 2 : rate;
        release_nights(reservation, -1);
        reservation->fee = fee;
        reservation->paid = fee;
        reservation->status = CANCELLED;
        reservation->posting = today;
        printf("CANCEL %s days %d fee %s %s\n",
               a[0], days, money(fee), deposit_text(reservation, fee));
    } else if (strcmp(cmd, "CHECKIN") == 0) {
        int index = require_reservation(a[0], BOOKED);
        if (index < 0) return;
        Reservation *reservation = &reservations[index];
        int room = reservation->room;
        if (reservation->arrival != today) {
            printf("ERROR not arrival date %s %s\n", a[0], date_text(reservation->arrival));
            return;
        }
        int occupant = inhouse(room);
        if (occupant >= 0) {
            printf("ERROR room occupied %d %s\n", rooms[room].number, reservations[occupant].id);
            return;
        }
        if (!rooms[room].clean) {
            printf("ERROR room dirty %d\n", rooms[room].number);
            return;
        }
        reservation->status = INHOUSE;
        printf("CHECKIN %s %s room %d until %s\n",
               reservation->id, reservation->guest, rooms[room].number,
               date_text(reservation->departure));
    } else if (strcmp(cmd, "MOVE") == 0) {
        int index = require_reservation(a[0], INHOUSE);
        if (index < 0) return;
        int room = require_room(a[1]);
        if (room < 0) return;
        Reservation *reservation = &reservations[index];
        int previous = reservation->room;
        if (room == previous) {
            printf("ERROR same room %s\n", a[1]);
            return;
        }
        int remaining = 0, first = -1;
        for (int i = 0; i < reservation->night_count; ++i) {
            if (reservation->nights[i].day >= today) {
                if (first < 0) first = reservation->nights[i].day;
                ++remaining;
            }
        }
        if (remaining == 0) {
            printf("ERROR no remaining nights %s\n", a[0]);
            return;
        }
        int unavailable = first_unavailable(room, first, reservation->departure, index);
        if (unavailable >= 0) {
            printf("ERROR room unavailable %s %s\n", a[1], date_text(unavailable));
            return;
        }
        int occupant = inhouse(room);
        if (occupant >= 0) {
            printf("ERROR room occupied %s %s\n", a[1], reservations[occupant].id);
            return;
        }
        if (!rooms[room].clean) {
            printf("ERROR room dirty %s\n", a[1]);
            return;
        }
        release_nights(reservation, today);
        for (int i = 0; i < reservation->night_count; ++i) {
            if (reservation->nights[i].day >= today)
                reservation->nights[i].room = room;
        }
        occupy(reservation, index, today);
        rooms[previous].clean = false;
        reservation->room = room;
        printf("MOVE %s %d -> %s nights %d\n", a[0], rooms[previous].number, a[1], remaining);
    } else if (strcmp(cmd, "EXTEND") == 0) {
        int index = require_reservation(a[0], INHOUSE);
        if (index < 0) return;
        Reservation *reservation = &reservations[index];
        int departure;
        if (!date_checked(a[1], &departure)) return;
        if (departure <= reservation->departure) {
            printf("ERROR invalid range %s %s\n", date_text(reservation->departure), a[1]);
            return;
        }
        if (departure - reservation->arrival > 30) {
            printf("ERROR too long %d\n", departure - reservation->arrival);
            return;
        }
        int unavailable = first_unavailable(reservation->room, reservation->departure,
                                             departure, index);
        if (unavailable >= 0) {
            printf("ERROR room unavailable %d %s\n",
                   rooms[reservation->room].number, date_text(unavailable));
            return;
        }
        int prior = reservation->night_count;
        for (int day = reservation->departure; day < departure; ++day) {
            Night *night = &reservation->nights[reservation->night_count++];
            night->day = day;
            night->room = reservation->room;
            night->rate = night_rate(&rooms[reservation->room], day);
        }
        reservation->departure = departure;
        occupy(reservation, index, reservation->nights[prior].day);
        printf("EXTEND %s until %s nights %d total %s\n",
               a[0], a[1], reservation->night_count, money(lodging(reservation)));
    } else if (strcmp(cmd, "CHARGE") == 0) {
        int index = require_reservation(a[0], INHOUSE);
        if (index < 0) return;
        int64_t amount = cents(a[1]);
        if (amount == 0) {
            printf("ERROR invalid amount\n");
            return;
        }
        Reservation *reservation = &reservations[index];
        Extra *extra = &reservation->extras[reservation->extra_count++];
        strcpy(extra->item, a[2]);
        extra->amount = amount;
        int64_t total = 0;
        for (int i = 0; i < reservation->extra_count; ++i)
            total += reservation->extras[i].amount;
        printf("CHARGE %s %s %s extras %s\n", a[0], a[2], a[1], money(total));
    } else if (strcmp(cmd, "PAY") == 0) {
        int index = require_reservation(a[0], -1);
        if (index < 0) return;
        Reservation *reservation = &reservations[index];
        if (reservation->status != BOOKED && reservation->status != INHOUSE) {
            printf("ERROR invalid status %s %s\n", a[0], status_names[reservation->status]);
            return;
        }
        int64_t amount = cents(a[1]);
        if (amount == 0) {
            printf("ERROR invalid amount\n");
            return;
        }
        reservation->deposit += amount;
        printf("PAY %s %s deposit %s\n", a[0], a[1], money(reservation->deposit));
    } else if (strcmp(cmd, "CHECKOUT") == 0) {
        int index = require_reservation(a[0], INHOUSE);
        if (index >= 0) check_out(index, today, false);
    } else if (strcmp(cmd, "INVOICE") == 0) {
        int index = require_reservation(a[0], -1);
        if (index < 0) return;
        Reservation *reservation = &reservations[index];
        Room *room = &rooms[reservation->room];
        printf("INVOICE %s %s room %d %s %s\n",
               reservation->id, reservation->guest, room->number, room->type,
               status_names[reservation->status]);
        if (reservation->status == CANCELLED || reservation->status == NOSHOW) {
            printf("  %s fee %s\n", reservation->status == CANCELLED ?
                   "cancellation" : "noshow", money(reservation->fee));
            printf("  total %s\n", money(reservation->fee));
            printf("  %s\n", deposit_text(reservation, reservation->fee));
        } else {
            for (int i = 0; i < reservation->night_count; ++i) {
                Night *night = &reservation->nights[i];
                printf("  %s room %d %s\n",
                       date_weekday(night->day), rooms[night->room].number, money(night->rate));
            }
            Bill bill = reservation->status == CHECKEDOUT ?
                        reservation->bill : calculate_bill(reservation);
            printf("  lodging %s\n", money(bill.lodging));
            printf("  discount %s\n", money(bill.discount));
            if (reservation->has_penalty)
                printf("  penalty %s %s\n",
                       date_weekday(reservation->penalty_day), money(bill.penalty));
            for (int i = 0; i < reservation->extra_count; ++i)
                printf("  extra %s %s\n", reservation->extras[i].item,
                       money(reservation->extras[i].amount));
            printf("  tax %s\n", money(bill.tax));
            printf("  total %s\n", money(bill.total));
            printf("  %s\n", deposit_text(reservation, bill.total));
        }
    } else if (strcmp(cmd, "AVAIL") == 0) {
        if (!require_type(a[0])) return;
        int start, end;
        if (!period_checked(a[1], a[2], false, true, &start, &end)) return;
        printf("AVAIL %s %s -> %s\n", a[0], a[1], a[2]);
        int indices[MAX_ROOMS];
        room_order(indices);
        for (int day = start; day <= end; ++day) {
            int free_count = 0;
            int free_rooms[MAX_ROOMS];
            for (int i = 0; i < room_count; ++i) {
                int room = indices[i];
                if (strcmp(rooms[room].type, a[0]) == 0 &&
                    !blocked[room][day] && !occupied[room][day])
                    free_rooms[free_count++] = rooms[room].number;
            }
            printf("  %s free %d", date_weekday(day), free_count);
            for (int i = 0; i < free_count; ++i) printf(" %d", free_rooms[i]);
            putchar('\n');
        }
    } else if (strcmp(cmd, "OCCUPANCY") == 0) {
        int day;
        if (!date_checked(a[0], &day)) return;
        int indices[MAX_ROOMS], count = 0;
        for (int i = 0; i < room_count; ++i) indices[count++] = i;
        printf("OCCUPANCY %s ", date_weekday(day));
        occupancy_parts(indices, count, day);
        putchar('\n');
        for (int kind = 0; kind < 3; ++kind) {
            count = 0;
            for (int i = 0; i < room_count; ++i)
                if (strcmp(types[kind], rooms[i].type) == 0) indices[count++] = i;
            if (count == 0) continue;
            printf("  %s ", types[kind]);
            occupancy_parts(indices, count, day);
            putchar('\n');
        }
    } else if (strcmp(cmd, "STATS") == 0) {
        int start, end;
        if (!period_checked(a[0], a[1], false, true, &start, &end)) return;
        Metrics totals = {0};
        printf("STATS %s -> %s\n", a[0], a[1]);
        for (int day = start; day <= end; ++day) {
            Metrics m = daily_values(day);
            totals.available += m.available;
            totals.occupied += m.occupied;
            totals.revenue += m.revenue;
            printf("  %s ", date_weekday(day));
            metrics_parts(m);
            putchar('\n');
        }
        printf("  total ");
        metrics_parts(totals);
        putchar('\n');
    } else if (strcmp(cmd, "ROOMS") == 0) {
        printf("ROOMS %s rooms %d\n", date_weekday(today), room_count);
        int indices[MAX_ROOMS];
        room_order(indices);
        for (int i = 0; i < room_count; ++i) {
            int room = indices[i];
            printf("  %d %s base %s tonight %s %s ",
                   rooms[room].number, rooms[room].type, money(rooms[room].rate),
                   money(night_rate(&rooms[room], today)),
                   rooms[room].clean ? "clean" : "dirty");
            int guest = inhouse(room);
            if (guest >= 0)
                printf("occupied %s", reservations[guest].id);
            else if (blocked[room][today]) printf("blocked");
            else printf("vacant");
            int next = -1;
            for (int j = 0; j < reservation_count; ++j) {
                Reservation *reservation = &reservations[j];
                if (reservation->room == room && reservation->status == BOOKED &&
                    (next < 0 || reservation->arrival < reservations[next].arrival ||
                     (reservation->arrival == reservations[next].arrival &&
                      strcmp(reservation->id, reservations[next].id) < 0)))
                    next = j;
            }
            if (next >= 0)
                printf(" next %s %s", reservations[next].id, date_text(reservations[next].arrival));
            putchar('\n');
        }
    } else if (strcmp(cmd, "LIST") == 0) {
        int indices[MAX_RESERVATIONS], count = 0;
        for (int i = 0; i < reservation_count; ++i)
            if (strcmp(status_names[reservations[i].status], a[0]) == 0) indices[count++] = i;
        qsort(indices, count, sizeof indices[0], arrival_sort);
        printf("LIST %s %d\n", a[0], count);
        for (int i = 0; i < count; ++i) {
            Reservation *reservation = &reservations[indices[i]];
            printf("  %s %s room %d %s -> %s\n",
                   reservation->id, reservation->guest, rooms[reservation->room].number,
                   date_text(reservation->arrival), date_text(reservation->departure));
        }
    } else if (strcmp(cmd, "QUEUE") == 0) {
        printf("QUEUE %d\n", waiting_count);
        for (int i = 0; i < waiting_count; ++i) {
            Waiting *entry = &waitlist[i];
            printf("  %d %s %s %s %s -> %s\n",
                   i + 1, entry->id, entry->guest, entry->type,
                   date_text(entry->arrival), date_text(entry->departure));
        }
    } else if (strcmp(cmd, "SCHEDULE") == 0) {
        int day;
        if (!date_checked(a[0], &day)) return;
        int arrivals[MAX_RESERVATIONS], departures[MAX_RESERVATIONS];
        int a_count = 0, d_count = 0;
        for (int i = 0; i < reservation_count; ++i) {
            Reservation *reservation = &reservations[i];
            if (reservation->arrival == day && reservation->status != CANCELLED)
                arrivals[a_count++] = i;
            if (reservation->departure == day &&
                (reservation->status == BOOKED || reservation->status == INHOUSE ||
                 reservation->status == CHECKEDOUT))
                departures[d_count++] = i;
        }
        qsort(arrivals, a_count, sizeof arrivals[0], id_sort);
        qsort(departures, d_count, sizeof departures[0], id_sort);
        printf("SCHEDULE %s arrivals %d departures %d\n",
               date_weekday(day), a_count, d_count);
        for (int i = 0; i < a_count; ++i) {
            Reservation *reservation = &reservations[arrivals[i]];
            printf("  arrival %s %s room %d %s\n", reservation->id, reservation->guest,
                   rooms[reservation->room].number, status_names[reservation->status]);
        }
        for (int i = 0; i < d_count; ++i) {
            Reservation *reservation = &reservations[departures[i]];
            printf("  departure %s %s room %d %s\n", reservation->id, reservation->guest,
                   rooms[reservation->room].number, status_names[reservation->status]);
        }
    } else if (strcmp(cmd, "GUEST") == 0) {
        bool found = false;
        for (int i = 0; i < reservation_count; ++i)
            if (strcmp(reservations[i].guest, a[0]) == 0) found = true;
        if (!found) {
            printf("ERROR unknown guest %s\n", a[0]);
            return;
        }
        printf("GUEST %s\n", a[0]);
        for (int i = 0; i < reservation_count; ++i) {
            Reservation *reservation = &reservations[i];
            if (strcmp(reservation->guest, a[0]) != 0) continue;
            bool active = reservation->status == BOOKED || reservation->status == INHOUSE;
            printf("  %s room %d %s %s -> %s %s %s %s\n",
                   reservation->id, rooms[reservation->room].number,
                   rooms[reservation->room].type, date_text(reservation->arrival),
                   date_text(reservation->departure), status_names[reservation->status],
                   active ? "deposit" : "paid",
                   money(active ? reservation->deposit : reservation->paid));
        }
        int64_t total = guest_total(a[0]);
        printf("  total paid %s points %lld tier %s\n",
               money(total), (long long)(total / 100), tier(a[0]));
    } else if (strcmp(cmd, "REVENUE") == 0) {
        int start, end;
        if (!period_checked(a[0], a[1], false, false, &start, &end)) return;
        int64_t values[7] = {0};
        int checkouts = 0, cancellations = 0, noshows = 0;
        for (int i = 0; i < reservation_count; ++i) {
            Reservation *reservation = &reservations[i];
            if (reservation->status == BOOKED || reservation->status == INHOUSE ||
                reservation->posting < start || reservation->posting > end) continue;
            if (reservation->status == CHECKEDOUT) {
                ++checkouts;
                values[0] += reservation->bill.lodging;
                values[1] += reservation->bill.discount;
                values[2] += reservation->bill.penalty;
                values[3] += reservation->bill.extras;
                values[4] += reservation->bill.tax;
            } else if (reservation->status == CANCELLED) {
                ++cancellations;
                values[5] += reservation->fee;
            } else if (reservation->status == NOSHOW) {
                ++noshows;
                values[6] += reservation->fee;
            }
        }
        const char *labels[] = {
            "lodging", "discount", "penalty", "extras", "tax", "cancellation", "noshow"
        };
        printf("REVENUE %s -> %s\n", a[0], a[1]);
        for (int i = 0; i < 7; ++i)
            printf("  %s %s\n", labels[i], money(values[i]));
        int64_t total = values[0] - values[1] + values[2] + values[3] +
                        values[4] + values[5] + values[6];
        printf("  total %s\n", money(total));
        printf("  checkouts %d cancellations %d noshows %d\n",
               checkouts, cancellations, noshows);
    }
}

int main(void) {
    char line[1024];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int commands = atoi(line);
    today = day_number("2026-01-01");
    for (int i = 0; i < commands; ++i) {
        if (!fgets(line, sizeof line, stdin)) break;
        char *cmd = strtok(line, " \t\r\n");
        char *args[48] = {0};
        int count = 0;
        while (count < 48 && (args[count] = strtok(NULL, " \t\r\n"))) ++count;
        command(cmd, args);
        process_waitlist();
    }
    return 0;
}
