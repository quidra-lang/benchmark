# Operations report: service log, sales ledger and staff list.
# Run with the options and files listed in args.txt.

function trim(s) {
    while (substr(s, 1, 1) == " ")
        s = substr(s, 2)
    while (length(s) > 0 && substr(s, length(s)) == " ")
        s = substr(s, 1, length(s) - 1)
    return s
}

function is_int(s,    i, c) {
    if (s == "")
        return 0
    i = substr(s, 1, 1) == "-" ? 2 : 1
    if (i > length(s))
        return 0
    for (; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (index("0123456789", c) == 0)
            return 0
    }
    return 1
}

function commas(n) {
    return n < 1000 ? n : commas(int(n / 1000)) "," sprintf("%03d", n % 1000)
}

function money(cents,    sign) {
    sign = cents < 0 ? "-" : ""
    if (cents < 0)
        cents = -cents
    return sign currency " " commas(int(cents / 100)) "." sprintf("%02d", cents % 100)
}

function bar(n, unit,    s, i) {
    s = ""
    for (i = 0; i < n / unit; i++)
        s = s sprintf("%c", 35)
    return s
}

function qsort(keys, vals, lo, hi,    i, last, t) {
    if (lo >= hi)
        return
    last = lo
    for (i = lo + 1; i <= hi; i++)
        if (vals[keys[i]] > vals[keys[lo]] || (vals[keys[i]] == vals[keys[lo]] && keys[i] < keys[lo])) {
            t = keys[++last]; keys[last] = keys[i]; keys[i] = t
        }
    t = keys[lo]; keys[lo] = keys[last]; keys[last] = t
    qsort(keys, vals, lo, last - 1)
    qsort(keys, vals, last + 1, hi)
}

function sorted_keys(arr, out,    n, k) {
    delete out
    n = 0
    for (k in arr)
        out[++n] = k
    qsort(out, arr, 1, n)
    return n
}

function bump(x) {
    x += 100
    return x
}

function nothing(x) {
    if (x)
        return
}

BEGIN {
    while ((status = getline line < "catalog.txt") > 0) {
        if (substr(line, 1, 1) == "#" || line == "")
            continue
        split(line, f, " ")
        category[f[1]] = f[2]
        cost[f[1]] = f[3]
        products++
    }
    close("catalog.txt")
    saved_fs = FS
    FS = " "
    while ((getline < "catalog.txt") > 0)
        if (NF == 3 && $3 > maxcost) {
            maxcost = $3
            priciest = $1
        }
    FS = saved_fs
    if ((getline junk < "missing.txt") < 0)
        missing = "missing.txt not found"
}

BEGIN {
    printf("%s\n", toupper(title))
    printf("%-10s|%5s|%-8.3s|%05d|%.4d|%%\n", "catalog", products, priciest, maxcost, NR)
    print "currency", currency, "top", top, "status", status
}

{
    bytes += length + 1
}

FILENAME == "events.log" && FNR == 1 {
    FS = " "
    $0 = $0
}

FILENAME == "events.log" && substr($0, 1, 1) == "#" {
    comments++
    next
}

FILENAME == "events.log" && NF == 0 {
    blank++
    next
}

FILENAME == "events.log" && $NF == "+" {
    NF--
    text = $0
    while ((getline more) > 0) {
        joined++
        more = trim(more)
        if (substr(more, length(more)) != "+") {
            text = text " " more
            break
        }
        text = text " " substr(more, 1, length(more) - 2)
    }
    $0 = text
}

FILENAME == "events.log" {
    level[$3]++
    comp[$4]++
    events++
    if (length > longest) {
        longest = length
        longest_at = FNR
    } else if (length == longest)
        ties++
    else
        shorter++
}

FILENAME == "events.log" && $3 == "ERROR" {
    msg = $5
    for (i = 6; i <= NF; i++)
        msg = msg " " $i
    errors[++nerr] = substr($2, 1, 5) " " $4 ": " msg
}

FILENAME == "events.log" && $3 == "FATAL"

$4 == "scheduler" && $6 == "start", $4 == "scheduler" && $6 == "end" {
    in_batch++
    if ($6 == "start")
        batches++
}

FILENAME == "sales.csv" && FNR == 1 {
    header = $0
    next
}

FILENAME == "sales.csv" {
    raw = $0
    $2 = trim($2); $3 = trim($3); $4 = trim($4)
    if (NF != 6 || !is_int(trim($5)) || !is_int(trim($6)) || !($4 in category)) {
        bad++
        printf("%s:%d: %s\n", FILENAME, FNR, raw) >> "rejects.txt"
        next
    }
    split($1, d, "-")
    month = d[2] + 0
    amount = $5 * $6
    if ($5 < 0) {
        returns++
        refund -= amount
    }
    revenue[$2] += amount
    region_units[$2] += $5
    by_rep[$3] += amount
    units[$4] += $5
    cat_rev[category[$4]] += amount
    month_rev[month] += amount
    pair[$2, $4] += $5
    margin[$4] += $5 * ($6 - cost[$4])
    if (amount > best) {
        best = amount
        best_line = FNR
    }
    accepted++
    file = "region_" tolower($2) ".txt"
    if (!(file in opened)) {
        opened[file] = 1
        print "date rep product qty amount" > file
    }
    printf("%s %-4s %-9s %3d %14s\n", $1, $3, $4, $5, money(amount)) > file
    if (accepted % 100 == 0) {
        print "checkpoint", accepted, "at line", FNR > "checkpoint.txt"
        close("checkpoint.txt")
    }
}

FILENAME == "staff.txt" && substr($0, 1, 1) == "#" {
    next
}

FILENAME == "staff.txt" && $1 == "@manager" {
    if ((getline) > 0)
        manager = $1
}

FILENAME == "staff.txt" && NF == 4 {
    name[$1] = $2
    home[$1] = $3
    quota[$1] = $4
    staff++
}

FILENAME == "staff.txt" && NF != 4 && $1 != "@manager" {
    print "staff.txt:" FNR ": expected 4 fields, got " NF >> "rejects.txt"
}

END {
    print ""
    print "== events (" FILENAME " last, NR=" NR ", mode=" mode ") =="
    printf("events %d, comments %d, blank %d, joined %d, batches %d, in batch %d\n",
        events, comments, blank, joined, batches, in_batch)
    printf("longest line %d at %d (ties %d, shorter %d), %d bytes read\n",
        longest, longest_at, ties, shorter, bytes)
    for (lv in level)
        printf "%-6s %3d |%s\n", lv, level[lv], bar(level[lv], 4)
    for (i = 1; i <= nerr; i++)
        print "  " errors[i]
    for (c in comp)
        comps = comps (comps == "" ? "" : ", ") c "=" comp[c]
    print "components:", comps

    print ""
    print "== sales =="
    printf("accepted %d, rejected %d, returns %d (%s)\n", accepted, bad, returns, money(refund))
    total = 0
    for (r in revenue)
        total += revenue[r]
    n = sorted_keys(revenue, order)
    for (i = 1; i <= n; i++) {
        r = order[i]
        printf("%-6s %16s %3d%% %5d units\n", r, money(revenue[r]), revenue[r] * 100 / total, region_units[r])
    }
    printf("%-6s %16s\n", "total", money(total))
    printf("best line %d: %s\n", best_line, money(best))

    print ""
    print "== top " top " reps =="
    n = sorted_keys(by_rep, order)
    for (i = 1; i <= n && i <= top; i++) {
        rep = order[i]
        who = (rep in name) ? name[rep] : "?"
        pct = rep in quota ? by_rep[rep] / quota[rep] : -1
        printf("%d. %-4s %-8s %16s %4d%%", i, rep, who, money(by_rep[rep]), pct)
        if (rep == manager)
            printf(" (manager)")
        printf("\n")
    }
    for (rep in quota)
        if (quota[rep] > 25000)
            high = high " " rep "[" quota[rep] "]"
    print "high quota:" high

    print ""
    print "== months =="
    for (m in month_rev)
        printf("%02d %-30s|%10s\n", m, bar(month_rev[m], 100000), commas(int(month_rev[m] / 100)))

    print ""
    print "== categories =="
    n = sorted_keys(cat_rev, order)
    for (i = 1; i <= n; i++)
        printf("%-9s %16s\n", order[i], money(cat_rev[order[i]]))
    n = sorted_keys(margin, order)
    printf("best margin %s (%s), worst %s (%s)\n", order[1], money(margin[order[1]]),
        order[n], money(margin[order[n]]))

    OFS = ","
    print("region", "product", "units") > "summary.csv"
    for (k in pair) {
        split(k, kp, SUBSEP)
        if (pair[k] >= 150)
            print kp[1], kp[2], pair[k] > "summary.csv"
    }
    close("summary.csv")
    print "pairs", length(pair), ("North", "widget") in pair
    delete pair["North", "widget"]
    print "after delete", length(pair), ("North", "widget") in pair
    delete pair
    print "after clear", length(pair)

    OFS = " "
    print ""
    print "== checks =="
    v = 5
    w = bump(v)
    print v, w, -7 / 2, -7 % 2, 7 % -3, 2 ^ 10, -2 ^ 2, 2 ^ 3 ^ 2
    x = 7; x *= 3; x /= 2; x %= 4; x ^= 3; x -= 1
    y = 1 + \
        2
    print x, --x, x--, x, y, "[" nothing(1) "]", nothing(0) + 1
    print "quote \" backslash \\ slash \/ end"
    print length(probe), (probe["a"] == 0), length(probe), ("b" in probe), length(probe)
    ord[10]; ord[9]; ord[-3]; ord["007"]; ord["b"]; ord["A"]; ord[""]; ord["-0"]
    for (k in ord)
        keys = keys "<" k ">"
    print keys
    ORS = "|"
    print "a"
    print "b"
    ORS = "\n"
    print ""
    print "[" unset "]", unset + 0, length(unset), (unset == 0), (unset == "")
    print ("10" < "9"), (10 < 9), ("abc" < "abd"), int("42abc"), int(" -7x"), +"3" + 4
    print 1 " " 2, 1 - 1, "x" (1 < 2), length("hello"), length()
    print substr("hello", 0, 3), substr("hello", 4), substr("hello", 2, 100), substr("hello", 9) "|"
    print index("banana", "nan"), index("banana", ""), toupper("mixed Case 9"), tolower("ABC-def")
    print split("a::b::c", parts, "::"), parts[3], split("  lead  trail  ", parts), parts[1] parts[2]
    print split("xyz", parts, ""), parts[1] parts[3], split("", parts), length(parts)
    printf("%c%c%c|%-3c|%3c|%.1s\n", 72, "ip", 33, "L", "R", "yes")
    printf("%5.3d|%-6x|%o|%i|%x|%-5s|%05s\n", 7, 255, 64, -12, -255, "ab", "cd")
    $0 = "alpha beta gamma"
    OFS = "-"
    $5 = "epsilon"
    print $0, NF
    NF = 2
    print $0, NF
    $1 = $1
    print $0, $NF, $(NF - 1)
    OFS = " "
    print close("catalog.txt"), close("checkpoint.txt"), missing
    do {
        spins++
    } while (spins < 3)
    for (;;)
        if (++loops >= 4)
            break
    for (i = 0; i < 10; i++) {
        if (i % 3)
            continue
        kept = kept i
    }
    for (empty = 0; empty < 5; empty++)
        ;
    $0 = "3 5 7"
    $2++
    print spins, loops, kept, empty, $0
    code = bad > 9 ? 9 : bad
    exit code
}
