#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef long long Integer;
typedef struct { int precision; Integer width, height; } Grid;
typedef struct { int precision; Integer x, y; } Cell;
typedef struct { char data[4096]; size_t length; } Text;
typedef struct Allocation {
    struct Allocation *next;
    char data[];
} Allocation;
static Allocation *allocations;
static jmp_buf invalid;
static Grid grids[6][9];
static const int grid_counts[] = {9,4,6,3,5,6};
static const char *systems[] = {"GEOHASH","MAIDENHEAD","PLUSCODE","GARS","GEOREF","MESH"};
static const char *hash_alphabet = "0123456789bcdefghjkmnpqrstuvwxyz";
static const char *plus_alphabet = "23456789CFGHJMPQRVWX";
static const char *letters24 = "ABCDEFGHJKLMNPQRSTUVWXYZ";
static const char *os_letters = "ABCDEFGHJKLMNOPQRSTUVWXYZ";
static const char *bands = "CDEFGHJKLMNPQRSTUVWX";
static const char *mgrs_rows = "ABCDEFGHJKLMNPQRSTUV";
static const Integer mesh_scale[] = {1,8,80,160,320,640};
static const char *maiden_alphabets[] = {"ABCDEFGHIJKLMNOPQR","0123456789","abcdefghijklmnopqrstuvwx","0123456789"};

static void require(bool condition) {
    if (!condition) longjmp(invalid, 1);
}
static char *allocate(size_t length) {
    Allocation *node = malloc(sizeof(*node) + length);
    if (!node) exit(EXIT_FAILURE);
    node->next = allocations;
    allocations = node;
    return node->data;
}
static void release(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations);
        allocations = next;
    }
}
static char *slice(const char *s, size_t start, size_t count) {
    char *result = allocate(count + 1);
    memcpy(result, s + start, count);
    result[count] = '\0';
    return result;
}
static char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    va_list measure;
    va_copy(measure, args);
    int length = vsnprintf(NULL, 0, pattern, measure);
    va_end(measure);
    if (length < 0) exit(EXIT_FAILURE);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, args);
    va_end(args);
    return result;
}
static void append(Text *text, const char *s) {
    size_t length = strlen(s);
    if (text->length + length >= sizeof(text->data)) exit(EXIT_FAILURE);
    memcpy(text->data + text->length, s, length + 1);
    text->length += length;
}
static void character(Text *text, char c) {
    char s[] = {c, '\0'};
    append(text, s);
}
static void item(Text *text, const char *s) {
    if (text->length) append(text, " ");
    append(text, s);
}
static char *copy_text(const Text *text) { return slice(text->data, 0, text->length); }
static Integer floor_ratio(Integer a, Integer b) {
    Integer q = a / b;
    if (a % b < 0) --q;
    return q;
}
static Integer modulo(Integer a, Integer b) { return a - floor_ratio(a,b) * b; }
static Integer absolute(Integer a) { return a < 0 ? -a : a; }
static Integer minimum(Integer a, Integer b) { return a < b ? a : b; }
static Integer maximum(Integer a, Integer b) { return a > b ? a : b; }
static char *padded(Integer value, int width) { return format("%0*lld", width, value); }
static char *coordinate(Integer value) {
    Integer magnitude = absolute(value);
    return format("%s%lld.%06lld", value < 0 ? "-" : "", magnitude / 1000000, magnitude % 1000000);
}
static bool digits(const char *s, int low, int high) {
    size_t length = strlen(s);
    if (length < (size_t)low || length > (size_t)high) return false;
    for (size_t i = 0; i < length; ++i) {
        if (s[i] < '0' || s[i] > '9') return false;
    }
    return true;
}
static Integer integer(const char *s, Integer low, Integer high) {
    bool negative = s[0] == '-';
    const char *body = s + (negative ? 1 : 0);
    require(digits(body,1,9));
    Integer value = 0;
    for (const char *p = body; *p; ++p) value = value * 10 + *p - '0';
    if (negative) value = -value;
    require(value >= low && value <= high);
    return value;
}
static Integer location(const char *s, bool latitude) {
    bool negative = s[0] == '-';
    const char *body = s + (negative ? 1 : 0);
    const char *dot = strchr(body, '.');
    size_t head_length = dot ? (size_t)(dot - body) : strlen(body);
    const char *head = slice(body, 0, head_length);
    require(digits(head,1,3));
    Integer value = integer(head,0,999) * 1000000;
    if (dot) {
        const char *fraction = dot + 1;
        require(digits(fraction,1,6));
        Integer tail = integer(fraction,0,999999);
        for (size_t i = strlen(fraction); i < 6; ++i) tail *= 10;
        value += tail;
    }
    if (negative) value = -value;
    require(latitude ? value >= -90000000 && value <= 90000000 : value >= -180000000 && value < 180000000);
    return value;
}
static int system_id(const char *s) {
    for (int i = 0; i < 6; ++i) if (strcmp(s,systems[i]) == 0) return i;
    longjmp(invalid,1);
}
static void initialize(void) {
    for (int p = 1; p <= 9; ++p) grids[0][p - 1] = (Grid){p, 1LL << ((5*p+1)/2), 1LL << (5*p/2)};
    const Grid definitions[5][6] = {
        {{2,18,18}, {4,180,180}, {6,4320,4320}, {8,43200,43200}},
        {{2,18,9}, {4,360,180}, {6,7200,3600}, {8,144000,72000}, {10,2880000,1440000}, {11,11520000,7200000}},
        {{5,720,360}, {6,1440,720}, {7,4320,2160}},
        {{2,24,12}, {4,360,180}, {8,21600,10800}, {10,216000,108000}, {12,2160000,1080000}},
        {{4,360,270}, {6,2880,2160}, {8,28800,21600}, {9,57600,43200}, {10,115200,86400}, {11,230400,172800}}
    };
    for (int s = 1; s < 6; ++s) {
        for (int p = 0; p < grid_counts[s]; ++p) grids[s][p] = definitions[s-1][p];
    }
}
static int precision_id(int system, Integer p) {
    for (int i = 0; i < grid_counts[system]; ++i) if (grids[system][i].precision == p) return i;
    longjmp(invalid,1);
}
static int precision_argument(int system, const char *s) { return precision_id(system, integer(s,0,999999999)); }
static int digit(const char *alphabet, char c) {
    const char *found = strchr(alphabet,c);
    require(found && c != '\0');
    return (int)(found - alphabet);
}
static Cell point(int system, int precision, Integer latitude, Integer longitude) {
    Grid g = grids[system][precision];
    return (Cell){precision, (longitude+180000000)*g.width/360000000, minimum((latitude+90000000)*g.height/180000000,g.height-1)};
}
static Cell ancestor(int system, Cell c, int precision) {
    Grid g = grids[system][c.precision], parent = grids[system][precision];
    return (Cell){precision,c.x*parent.width/g.width,c.y*parent.height/g.height};
}
static bool equal(Cell a, Cell b) { return a.precision == b.precision && a.x == b.x && a.y == b.y; }
static char *encode(int system, Cell c) {
    int p = grids[system][c.precision].precision;
    Integer x = c.x, y = c.y;
    Text result = {{0},0};
    if (system == 0) {
        int a = (5*p+1)/2, b = 5*p/2, value = 0;
        for (int i = 0; i < 5*p; ++i) {
            int bit = i % 2 == 0 ? (int)(x >> (a-1-i/2) & 1) : (int)(y >> (b-1-i/2) & 1);
            value = value * 2 + bit;
            if (i % 5 == 4) {
                character(&result,hash_alphabet[value]);
                value = 0;
            }
        }
    } else if (system == 1 || system == 2) {
        int count = system == 1 ? p/2 : (int)minimum(p,10)/2;
        int tail = -1;
        if (system == 2 && p == 11) {
            tail = (int)(4*(y%5)+x%4);
            x /= 4;
            y /= 5;
        }
        int xd[5], yd[5];
        for (int i = count - 1; i >= 0; --i) {
            int rx = system == 1 ? (int)strlen(maiden_alphabets[i]) : i == 0 ? 18 : 20;
            int ry = system == 1 ? rx : i == 0 ? 9 : 20;
            xd[i] = (int)(x % rx);
            yd[i] = (int)(y % ry);
            x /= rx;
            y /= ry;
        }
        for (int i = 0; i < count; ++i) {
            if (system == 1) {
                character(&result,maiden_alphabets[i][xd[i]]);
                character(&result,maiden_alphabets[i][yd[i]]);
            } else {
                character(&result,plus_alphabet[yd[i]]);
                character(&result,plus_alphabet[xd[i]]);
            }
        }
        if (tail >= 0) character(&result,plus_alphabet[tail]);
        if (system == 2) {
            while (result.length < 8) character(&result,'0');
            memmove(result.data+9,result.data+8,result.length-8+1);
            result.data[8] = '+';
            ++result.length;
        }
    } else if (system == 3) {
        Integer scale = p == 5 ? 1 : p == 6 ? 2 : 6;
        Integer base_y = y/scale;
        append(&result,padded(x/scale+1,3));
        character(&result,letters24[base_y/24]);
        character(&result,letters24[base_y%24]);
        if (p >= 6) {
            Integer xx = p == 7 ? x/3 : x, yy = p == 7 ? y/3 : y;
            character(&result,(char)('1'+xx%2+2*(1-yy%2)));
        }
        if (p == 7) character(&result,(char)('1'+x%3+3*(2-y%3)));
    } else if (system == 4) {
        if (p == 2) return format("%c%c",letters24[x],letters24[y]);
        int m = (p-4)/2;
        Integer scale = p < 8 ? 1 : m == 2 ? 60 : m == 3 ? 600 : 6000;
        Integer xx = x/scale, yy = y/scale;
        append(&result,format("%c%c%c%c",letters24[xx/15],letters24[yy/15],letters24[xx%15],letters24[yy%15]));
        if (p >= 8) {
            append(&result,padded(x%scale,m));
            append(&result,padded(y%scale,m));
        }
    } else {
        Integer scale = mesh_scale[c.precision];
        x -= 280*scale;
        y -= 135*scale;
        if (x < 0 || x >= 80*scale || y < 0 || y >= 100*scale) return copy_text(&result);
        int count = c.precision+1;
        const int radices[] = {0,8,10,2,2,2};
        int xd[6], yd[6];
        for (int i = count-1; i >= 1; --i) {
            xd[i] = (int)(x%radices[i]);
            yd[i] = (int)(y%radices[i]);
            x /= radices[i];
            y /= radices[i];
        }
        append(&result,padded(y,2));
        append(&result,padded(x,2));
        for (int i = 1; i < count; ++i) {
            if (i <= 2) {
                character(&result,(char)('0'+yd[i]));
                character(&result,(char)('0'+xd[i]));
            } else character(&result,(char)('1'+xd[i]+2*yd[i]));
        }
    }
    return copy_text(&result);
}
static Cell decode(int system, const char *code) {
    int p = (int)strlen(code);
    Integer x = 0, y = 0;
    if (system == 0) {
        require(p >= 1 && p <= 9);
        int position = 0;
        for (int i = 0; i < p; ++i) {
            int value = digit(hash_alphabet,code[i]);
            for (int bit = 4; bit >= 0; --bit) {
                if (position++ % 2 == 0) x = 2*x+(value>>bit&1);
                else y = 2*y+(value>>bit&1);
            }
        }
    } else if (system == 1) {
        precision_id(system,p);
        for (int i = 0; i < p/2; ++i) {
            x = x*(Integer)strlen(maiden_alphabets[i])+digit(maiden_alphabets[i],code[2*i]);
            y = y*(Integer)strlen(maiden_alphabets[i])+digit(maiden_alphabets[i],code[2*i+1]);
        }
    } else if (system == 2) {
        int plus_count = 0;
        for (int i = 0; i < p; ++i) plus_count += code[i] == '+';
        require(p >= 9 && code[8] == '+' && plus_count == 1);
        int prefix = 0;
        while (prefix < 8 && code[prefix] != '0') {
            digit(plus_alphabet,code[prefix]);
            ++prefix;
        }
        require(prefix == 2 || prefix == 4 || prefix == 6 || prefix == 8);
        for (int i = prefix; i < 8; ++i) require(code[i] == '0');
        int suffix = p-9;
        require(prefix == 8 ? suffix == 0 || suffix == 2 || suffix == 3 : suffix == 0);
        require(digit(plus_alphabet,code[0]) <= 8 && digit(plus_alphabet,code[1]) <= 17);
        char *sequence = format("%s%s",slice(code,0,(size_t)prefix),code+9);
        p = (int)strlen(sequence);
        for (int i = 0; i < (int)minimum(p,10)/2; ++i) {
            y = y*(i == 0 ? 9 : 20)+digit(plus_alphabet,sequence[2*i]);
            x = x*(i == 0 ? 18 : 20)+digit(plus_alphabet,sequence[2*i+1]);
        }
        if (p == 11) {
            int tail = digit(plus_alphabet,sequence[10]);
            x = x*4+tail%4;
            y = y*5+tail/4;
        }
    } else if (system == 3) {
        require(p >= 5 && p <= 7);
        require(digits(slice(code,0,3),3,3));
        x = integer(slice(code,0,3),1,720)-1;
        int a = digit(letters24,code[3]), b = digit(letters24,code[4]);
        require(a < 15);
        y = 24*a+b;
        if (p >= 6) {
            require(code[5] >= '1' && code[5] <= '4');
            int q = code[5]-'1';
            x = 2*x+q%2;
            y = 2*y+1-q/2;
        }
        if (p == 7) {
            require(code[6] >= '1' && code[6] <= '9');
            int q = code[6]-'1';
            x = 3*x+q%3;
            y = 3*y+2-q/3;
        }
    } else if (system == 4) {
        precision_id(system,p);
        x = digit(letters24,code[0]);
        y = digit(letters24,code[1]);
        require(y < 12);
        if (p >= 4) {
            int a = digit(letters24,code[2]), b = digit(letters24,code[3]);
            require(a < 15 && b < 15);
            x = 15*x+a;
            y = 15*y+b;
        }
        if (p >= 8) {
            int m = (p-4)/2;
            Integer scale = m == 2 ? 60 : m == 3 ? 600 : 6000;
            const char *e = slice(code,4,(size_t)m), *n = slice(code,4+(size_t)m,(size_t)m);
            require(digits(e,m,m) && digits(n,m,m));
            x = x*scale+integer(e,0,scale-1);
            y = y*scale+integer(n,0,scale-1);
        }
    } else {
        int precision = precision_id(system,p);
        require(digits(code,p,p));
        y = integer(slice(code,0,2),0,99);
        x = integer(slice(code,2,2),0,79);
        if (p >= 6) {
            require(code[4] <= '7' && code[5] <= '7');
            y = y*8+code[4]-'0';
            x = x*8+code[5]-'0';
        }
        if (p >= 8) {
            y = y*10+code[6]-'0';
            x = x*10+code[7]-'0';
        }
        for (int i = 8; i < p; ++i) {
            require(code[i] >= '1' && code[i] <= '4');
            int q = code[i]-'1';
            x = x*2+q%2;
            y = y*2+q/2;
        }
        x += 280*mesh_scale[precision];
        y += 135*mesh_scale[precision];
    }
    return (Cell){precision_id(system,p),x,y};
}
static const char *display(int system, Cell c) {
    const char *code = encode(system,c);
    return *code ? code : "-";
}
static Integer center_numerator(Integer position, Integer divisions, Integer span) { return span*(2*position+1-divisions); }
static int compare(Integer a, Integer b, Integer c, Integer d) {
    Integer left = a*d, right = c*b;
    return left < right ? -1 : left > right ? 1 : 0;
}
static const char *relation(int sa, Cell a, int sb, Cell b) {
    Grid ga = grids[sa][a.precision], gb = grids[sb][b.precision];
    int west = compare(a.x,ga.width,b.x,gb.width), east = compare(a.x+1,ga.width,b.x+1,gb.width);
    int south = compare(a.y,ga.height,b.y,gb.height), north = compare(a.y+1,ga.height,b.y+1,gb.height);
    if (!west && !east && !south && !north) return "EQUAL";
    if (west >= 0 && east <= 0 && south >= 0 && north <= 0) return "INSIDE";
    if (west <= 0 && east >= 0 && south <= 0 && north >= 0) return "CONTAINS";
    int x1 = compare(a.x,ga.width,b.x+1,gb.width), x2 = compare(b.x,gb.width,a.x+1,ga.width);
    int y1 = compare(a.y,ga.height,b.y+1,gb.height), y2 = compare(b.y,gb.height,a.y+1,ga.height);
    if (x1 < 0 && x2 < 0 && y1 < 0 && y2 < 0) return "OVERLAP";
    bool wrap = (a.x == 0 && b.x+1 == gb.width) || (b.x == 0 && a.x+1 == ga.width);
    if (y1 <= 0 && y2 <= 0 && ((x1 <= 0 && x2 <= 0) || wrap)) return "TOUCH";
    return "DISJOINT";
}
static int prune(int system, Cell *cells, int count) {
    bool removed[100] = {false};
    for (int i = 0; i < count; ++i) {
        for (int j = 0; j < count; ++j) {
            if (cells[j].precision < cells[i].precision && equal(ancestor(system,cells[i],cells[j].precision),cells[j])) {
                removed[i] = true;
                break;
            }
        }
    }
    int length = 0;
    for (int i = 0; i < count; ++i) if (!removed[i]) cells[length++] = cells[i];
    return length;
}
static int cell_order(const void *left, const void *right) {
    const Cell *a = left, *b = right;
    if (a->precision != b->precision) return a->precision < b->precision ? -1 : 1;
    if (a->y != b->y) return a->y > b->y ? -1 : 1;
    return a->x < b->x ? -1 : a->x > b->x ? 1 : 0;
}
static char *compact(int system, char **codes, int code_count) {
    Cell cells[100];
    int count = 0;
    for (int i = 0; i < code_count; ++i) {
        Cell c = decode(system,codes[i]);
        bool duplicate = false;
        for (int j = 0; j < count; ++j) duplicate |= equal(c,cells[j]);
        if (!duplicate) cells[count++] = c;
    }
    count = prune(system,cells,count);
    for (;;) {
        bool changed = false;
        for (int i = 0; i < count; ++i) {
            Cell c = cells[i];
            if (!c.precision) continue;
            Cell parent = ancestor(system,c,c.precision-1);
            Grid g = grids[system][c.precision], pg = grids[system][parent.precision];
            Integer needed = (g.width/pg.width)*(g.height/pg.height);
            if (needed > count) continue;
            bool children[100] = {false};
            int matches = 0;
            for (int j = 0; j < count; ++j) {
                children[j] = cells[j].precision == c.precision && equal(ancestor(system,cells[j],parent.precision),parent);
                matches += children[j];
            }
            if (matches != needed) continue;
            int length = 0;
            for (int j = 0; j < count; ++j) if (!children[j]) cells[length++] = cells[j];
            cells[length++] = parent;
            count = prune(system,cells,length);
            changed = true;
            break;
        }
        if (!changed) break;
    }
    qsort(cells,(size_t)count,sizeof(*cells),cell_order);
    Text result = {{0},0};
    for (int i = 0; i < count; ++i) item(&result,encode(system,cells[i]));
    return copy_text(&result);
}
static const char *mgrs_columns(Integer zone) { return zone%3 == 1 ? "ABCDEFGH" : zone%3 == 2 ? "JKLMNPQR" : "STUVWXYZ"; }
static Integer square_digits(char **a, int count, int start, Integer *e, Integer *n) {
    if (count == start) return 100000;
    require(digits(a[start],1,5) && digits(a[start+1],1,5) && strlen(a[start]) == strlen(a[start+1]));
    Integer scale = 1;
    for (size_t i = strlen(a[start]); i < 5; ++i) scale *= 10;
    *e += integer(a[start],0,99999)*scale;
    *n += integer(a[start+1],0,99999)*scale;
    return scale;
}
static const char *execute(char **a, int count) {
    const char *names[] = {
        "ENCODE", "DECODE", "NEIGHBORS", "PARENT", "CHILDREN", "COMMON",
        "COMPACT", "CONTAINS", "COVER", "CONVERT", "STEPS", "PATH", "RELATE",
        "SIZE", "SHORTEN", "RECOVER", "UTMZONE", "OSGB", "UNOSGB", "MGRS",
        "UNMGRS", "QUADKEY", "UNQUADKEY"
    };
    const int lengths[] = {5,3,3,3,3,4,0,5,7,6,4,4,5,3,4,4,3,4,0,6,0,4,2};
    int command = -1;
    for (int i = 0; i < 23; ++i) if (!strcmp(a[0],names[i])) command = i;
    require(command >= 0);
    if (command == 6) require(count >= 3 && count <= 102);
    else if (command == 18) require(count == 2 || count == 4);
    else if (command == 20) require(count == 3 || count == 5);
    else require(count == lengths[command]);
    if (command <= 13) {
        int system = system_id(a[1]);
        if (command == 0) {
            Integer lat = location(a[2],true), lon = location(a[3],false);
            int precision = precision_argument(system,a[4]);
            const char *code = encode(system,point(system,precision,lat,lon));
            return *code ? code : "OUT OF AREA";
        }
        if (command == 8) {
            int precision = precision_argument(system,a[2]);
            Integer lat1 = location(a[3],true), lon1 = location(a[4],false), lat2 = location(a[5],true), lon2 = location(a[6],false);
            require(lat1 <= lat2);
            Cell first = point(system,precision,lat1,lon1), last = point(system,precision,lat2,lon2);
            Grid g = grids[system][precision];
            Integer columns = lon1 <= lon2 ? last.x-first.x+1 : minimum(g.width,last.x-first.x+1+g.width);
            if ((last.y-first.y+1)*columns > 100) return "TOO MANY";
            Text result = {{0},0};
            for (Integer y = last.y; y >= first.y; --y) {
                for (Integer i = 0; i < columns; ++i) item(&result,display(system,(Cell){precision,(first.x+i)%g.width,y}));
            }
            return copy_text(&result);
        }
        if (command == 13) {
            int precision = precision_argument(system,a[2]);
            Grid g = grids[system][precision];
            Integer total = system == 5 ? 8000*mesh_scale[precision]*mesh_scale[precision] : g.width*g.height;
            return format("w=%s h=%s cells=%lld",coordinate(360000000/g.width),coordinate(180000000/g.height),total);
        }
        if (command == 6) return compact(system,a+2,count-2);
        Cell c = decode(system,a[2]);
        Grid g = grids[system][c.precision];
        if (command == 1) {
            Integer south = -90000000+180000000*c.y/g.height, west = -180000000+360000000*c.x/g.width;
            Integer north = -90000000+180000000*(c.y+1)/g.height, east = -180000000+360000000*(c.x+1)/g.width;
            Integer cy = floor_ratio(center_numerator(c.y,g.height,180000000),2*g.height), cx = floor_ratio(center_numerator(c.x,g.width,360000000),2*g.width);
            return format("sw=%s,%s ne=%s,%s c=%s,%s",coordinate(south),coordinate(west),coordinate(north),coordinate(east),coordinate(cy),coordinate(cx));
        }
        if (command == 2) {
            const int dx[] = {0,1,1,1,0,-1,-1,-1}, dy[] = {1,1,0,-1,-1,-1,0,1};
            Text result = {{0},0};
            for (int i = 0; i < 8; ++i) {
                const char *code = c.y+dy[i] < 0 || c.y+dy[i] >= g.height ? "-" : display(system,(Cell){c.precision,modulo(c.x+dx[i],g.width),c.y+dy[i]});
                item(&result,code);
            }
            return copy_text(&result);
        }
        if (command == 3) return c.precision == 0 ? "NONE" : encode(system,ancestor(system,c,c.precision-1));
        if (command == 4) {
            if (c.precision+1 == grid_counts[system]) return "NONE";
            Grid next = grids[system][c.precision+1];
            Integer rx = next.width/g.width, ry = next.height/g.height;
            if (rx*ry > 100) return "TOO MANY";
            Text result = {{0},0};
            for (Integer j = ry-1; j >= 0; --j) {
                for (Integer i = 0; i < rx; ++i) item(&result,display(system,(Cell){c.precision+1,rx*c.x+i,ry*c.y+j}));
            }
            return copy_text(&result);
        }
        if (command == 7) {
            Integer lat = location(a[3],true), lon = location(a[4],false);
            return equal(point(system,c.precision,lat,lon),c) ? "YES" : "NO";
        }
        if (command == 9) {
            require(!strcmp(a[3],"TO"));
            int destination = system_id(a[4]), precision = precision_argument(destination,a[5]);
            Grid next = grids[destination][precision];
            const char *code = encode(destination,(Cell){precision,(2*c.x+1)*next.width/(2*g.width),(2*c.y+1)*next.height/(2*g.height)});
            return *code ? code : "OUT OF AREA";
        }
        if (command == 12) {
            int other_system = system_id(a[3]);
            return relation(system,c,other_system,decode(other_system,a[4]));
        }
        Cell other = decode(system,a[3]);
        if (command == 5) {
            for (int precision = (int)minimum(c.precision,other.precision); precision >= 0; --precision) {
                Cell parent = ancestor(system,c,precision);
                if (equal(parent,ancestor(system,other,precision))) return encode(system,parent);
            }
            return "NONE";
        }
        if (c.precision != other.precision) return "MISMATCH";
        Integer dx = modulo(other.x-c.x,g.width), dy = other.y-c.y;
        if (dx > g.width/2) dx -= g.width;
        if (command == 10) return format("dx=%lld dy=%lld",dx,dy);
        Integer n = maximum(absolute(dx),absolute(dy));
        if (n+1 > 100) return "TOO MANY";
        Text result = {{0},0};
        for (Integer i = 0; i <= n; ++i) {
            Integer x = c.x+(n ? floor_ratio(2*i*dx+n,2*n) : 0), y = c.y+(n ? floor_ratio(2*i*dy+n,2*n) : 0);
            item(&result,display(system,(Cell){c.precision,modulo(x,g.width),y}));
        }
        return copy_text(&result);
    }
    if (command == 14 || command == 15) {
        Integer lat = location(a[2],true), lon = location(a[3],false);
        const char *full = a[1];
        int removed = 0;
        if (command == 15) {
            const char *plus = strchr(full,'+');
            require(plus != NULL);
            int position = (int)(plus-full);
            require((position == 2 || position == 4) && !strchr(plus+1,'+'));
            int suffix = (int)strlen(plus+1);
            require(suffix == 0 || suffix == 2 || suffix == 3);
            for (const char *p = full; *p; ++p) if (*p != '+') digit(plus_alphabet,*p);
            removed = 8-position;
            const char *prefix = encode(2,point(2,precision_id(2,10),lat,lon));
            full = format("%s%s",slice(prefix,0,(size_t)removed),full);
        }
        Cell c = decode(2,full);
        Grid g = grids[2][c.precision];
        require(g.precision >= 8);
        Integer cy = center_numerator(c.y,g.height,180000000), cx = center_numerator(c.x,g.width,360000000);
        Integer yd = 2*g.height, xd = 2*g.width;
        if (command == 14) {
            if (absolute(cy-lat*yd) < 15000*yd && absolute(cx-lon*xd) < 15000*xd) return full+6;
            if (absolute(cy-lat*yd) < 300000*yd && absolute(cx-lon*xd) < 300000*xd) return full+4;
            return full;
        }
        Integer distance = removed == 4 ? 1000000 : 50000;
        Integer my = distance*g.height/180000000, mx = distance*g.width/360000000;
        if ((lat+distance/2)*yd < cy && cy-distance*yd >= -90000000*yd) c.y -= my;
        else if ((lat-distance/2)*yd > cy && cy+distance*yd <= 90000000*yd) c.y += my;
        if ((lon+distance/2)*xd < cx) c.x = modulo(c.x-mx,g.width);
        else if ((lon-distance/2)*xd > cx) c.x = modulo(c.x+mx,g.width);
        return encode(2,c);
    }
    if (command == 16) {
        Integer lat = location(a[1],true), lon = location(a[2],false);
        if (lat < -80000000 || lat >= 84000000) return "NONE";
        char band = bands[minimum((lat+80000000)/8000000,19)];
        Integer zone = (lon+180000000)/6000000+1;
        if (band == 'V' && lon >= 3000000 && lon < 12000000) zone = 32;
        if (band == 'X' && lon >= 0 && lon < 42000000) zone = lon < 9000000 ? 31 : lon < 21000000 ? 33 : lon < 33000000 ? 35 : 37;
        return format("%lld%c",zone,band);
    }
    if (command == 17 || command == 19) {
        Integer e, n;
        int d;
        const char *prefix;
        if (command == 17) {
            e = integer(a[1],0,699999);
            n = integer(a[2],0,1299999);
            d = (int)integer(a[3],0,5);
            prefix = format("%c%c",os_letters[5*(3-n/500000)+2+e/500000],os_letters[5*(4-n/100000%5)+e/100000%5]);
        } else {
            Integer zone = integer(a[1],1,60);
            require(strlen(a[2]) == 1);
            digit(bands,a[2][0]);
            e = integer(a[3],100000,899999);
            n = integer(a[4],0,9999999);
            d = (int)integer(a[5],0,5);
            prefix = format("%lld%s %c%c",zone,a[2],mgrs_columns(zone)[e/100000-1],mgrs_rows[(n/100000+(zone%2 == 0 ? 5 : 0))%20]);
        }
        if (d) return format("%s %s %s",prefix,slice(padded(e%100000,5),0,(size_t)d),slice(padded(n%100000,5),0,(size_t)d));
        return prefix;
    }
    if (command == 18 || command == 20) {
        Integer e, n, scale;
        const char *prefix = "";
        if (command == 18) {
            require(strlen(a[1]) == 2);
            int first = digit(os_letters,a[1][0]), second = digit(os_letters,a[1][1]);
            e = 500000LL*(first%5-2)+100000LL*(second%5);
            n = 500000LL*(3-first/5)+100000LL*(4-second/5);
            require(e >= 0 && e < 700000 && n >= 0 && n < 1300000);
            scale = square_digits(a,count,2,&e,&n);
        } else {
            size_t length = strlen(a[1]);
            require(length == 2 || length == 3);
            const char *zone_text = slice(a[1],0,length-1);
            require(digits(zone_text,1,2) && zone_text[0] != '0');
            Integer zone = integer(zone_text,1,60);
            digit(bands,a[1][length-1]);
            require(strlen(a[2]) == 2);
            e = 100000LL*(digit(mgrs_columns(zone),a[2][0])+1);
            n = 100000LL*modulo(digit(mgrs_rows,a[2][1])-(zone%2 == 0 ? 5 : 0),20);
            scale = square_digits(a,count,3,&e,&n);
            prefix = format("%s ",a[1]);
        }
        return format("%ssw=%lld,%lld size=%lld",prefix,e,n,scale);
    }
    if (command == 21) {
        int z = (int)integer(a[3],1,23);
        Integer x = integer(a[1],0,(1LL<<z)-1), y = integer(a[2],0,(1LL<<z)-1);
        Text key = {{0},0};
        for (int i = z-1; i >= 0; --i) character(&key,(char)('0'+(x>>i&1)+2*(y>>i&1)));
        return copy_text(&key);
    }
    size_t length = strlen(a[1]);
    require(length >= 1 && length <= 23);
    Integer x = 0, y = 0;
    for (size_t i = 0; i < length; ++i) {
        require(a[1][i] >= '0' && a[1][i] <= '3');
        int q = a[1][i]-'0';
        x = 2*x+q%2;
        y = 2*y+q/2;
    }
    return format("x=%lld y=%lld z=%d",x,y,(int)length);
}
int main(void) {
    initialize();
    char line[2004];
    if (!fgets(line,sizeof(line),stdin)) return 0;
    int commands = atoi(line);
    for (int i = 0; i < commands; ++i) {
        if (!fgets(line,sizeof(line),stdin)) break;
        line[strcspn(line,"\n")] = '\0';
        char *arguments[1002];
        int count = 0;
        for (char *word = strtok(line," "); word; word = strtok(NULL," ")) arguments[count++] = word;
        if (setjmp(invalid) == 0) puts(execute(arguments,count));
        else puts("INVALID");
        release();
    }
    return 0;
}
