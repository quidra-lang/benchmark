const METHODS = Set(["GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"])
const REASONS = [
    "fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency"
]
const CLASSES = ["1xx", "2xx", "3xx", "4xx", "5xx"]
const FILTER_KEYS = ["METHOD", "STATUS", "IP", "PATH"]
const MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const FORMS = Dict(
    "SUMMARY" => String[], "MALFORMED" => String[],
    "STATUS" => String[], "METHODS" => String[],
    "TOP" => ["kind", "limit"], "HOURLY" => String[],
    "TIMELINE" => ["minutes"], "BANDWIDTH" => String[],
    "VISITORS" => String[], "LATENCY" => ["path"],
    "HISTOGRAM" => ["width"], "APDEX" => ["threshold"],
    "ERRORS" => String[], "SLOWEST" => ["limit"],
    "SESSIONS" => ["ip", "minutes"], "BURST" => ["length", "times"],
    "PEAK" => ["length"], "GAPS" => ["length"],
    "IP" => ["ip"], "RANGE" => ["date", "time", "date", "time"],
    "FILTER" => ["key", "value"], "UNFILTER" => ["subject"],
    "RESET" => String[], "STATE" => String[]
)
const REQUIRE_RECORDS = Set([
    "STATUS", "METHODS", "TOP", "HOURLY", "TIMELINE", "BANDWIDTH",
    "VISITORS", "HISTOGRAM", "APDEX", "ERRORS", "SLOWEST", "BURST", "PEAK", "GAPS"
])
const RANGES = Dict(
    "limit" => (1, 100), "minutes" => (1, 1440), "width" => (1, 100000),
    "threshold" => (1, 100000), "length" => (1, 86400), "times" => (1, 1000)
)
const ERRORS = Dict(
    "limit" => "invalid number", "minutes" => "invalid number",
    "width" => "invalid number", "threshold" => "invalid number",
    "length" => "invalid number", "times" => "invalid number",
    "kind" => "invalid kind", "path" => "invalid path", "ip" => "invalid ip",
    "date" => "invalid timestamp", "time" => "invalid timestamp",
    "key" => "invalid key", "subject" => "invalid key", "value" => "invalid value"
)

struct QueryError <: Exception
    message::String
end

function ensure(condition, reason)
    condition || throw(QueryError(reason))
end

function tokens(line)
    value = strip(line)
    isempty(value) && return String[]
    return String.(split(value, r"\s+"))
end

digits(s) = occursin(r"^[0-9]+$", s)
canonical(s, maxlen) = !isempty(s) && length(s) <= maxlen &&
    digits(s) && (length(s) == 1 || s[1] != '0')

leap(year) = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
year_days(year) = leap(year) ? 366 : 365
month_days(year, month) = month == 2 && leap(year) ? 29 : MONTH_DAYS[month]

function valid_date(s)
    occursin(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", s) || return false
    year = parse(Int, s[1:4])
    month = parse(Int, s[6:7])
    day = parse(Int, s[9:10])
    return 2000 <= year <= 2059 && 1 <= month <= 12 &&
        1 <= day <= month_days(year, month)
end

function valid_time(s)
    occursin(r"^[0-9]{2}:[0-9]{2}:[0-9]{2}$", s) || return false
    return parse(Int, s[1:2]) < 24 && parse(Int, s[4:5]) < 60 &&
        parse(Int, s[7:8]) < 60
end

function valid_ip(s)
    parts = split(s, '.'; keepempty=true)
    length(parts) == 4 || return false
    return all(p -> canonical(p, 3) && parse(Int, p) <= 255, parts)
end

valid_status(s) = occursin(r"^[0-9]{3}$", s) &&
    100 <= parse(Int, s) <= 599

function valid_filter_value(key, value)
    if key == "METHOD"
        return value in METHODS
    elseif key == "STATUS"
        return value in CLASSES || valid_status(value)
    elseif key == "IP"
        return valid_ip(value)
    end
    return startswith(value, "/")
end

function valid_argument(kind, value, args)
    if haskey(RANGES, kind)
        low, high = RANGES[kind]
        return canonical(value, 6) && low <= parse(Int, value) <= high
    end
    kind == "kind" && return value in ["PATHS", "IPS"]
    kind == "path" && return startswith(value, "/")
    kind == "ip" && return valid_ip(value)
    kind == "date" && return valid_date(value)
    kind == "time" && return valid_time(value)
    kind == "key" && return value in FILTER_KEYS
    if kind == "subject"
        return value == "RANGE" || value in FILTER_KEYS
    end
    return valid_filter_value(args[1], value)
end

function malformed_reason(fields)
    length(fields) == 8 || return "fields"
    valid_date(fields[1]) || return "date"
    valid_time(fields[2]) || return "time"
    valid_ip(fields[3]) || return "ip"
    fields[4] in METHODS || return "method"
    startswith(fields[5], "/") || return "path"
    valid_status(fields[6]) || return "status"
    canonical(fields[7], 8) || return "bytes"
    canonical(fields[8], 6) || return "latency"
    return nothing
end

function seconds_of(date, clock)
    year = parse(Int, date[1:4])
    month = parse(Int, date[6:7])
    days = parse(Int, date[9:10]) - 1
    for y in 2000:year-1
        days += year_days(y)
    end
    for m in 1:month-1
        days += month_days(year, m)
    end
    return days * 86400 + parse(Int, clock[1:2]) * 3600 +
        parse(Int, clock[4:5]) * 60 + parse(Int, clock[7:8])
end

padded(n, width=2) = lpad(string(n), width, '0')

function interval_label(seconds)
    days = seconds ÷ 86400
    minutes = seconds % 86400 ÷ 60
    year = 2000
    while days >= year_days(year)
        days -= year_days(year)
        year += 1
    end
    month = 1
    while days >= month_days(year, month)
        days -= month_days(year, month)
        month += 1
    end
    return string(padded(year, 4), "-", padded(month), "-", padded(days + 1),
        " ", padded(minutes ÷ 60), ":", padded(minutes % 60))
end

function normalize_path(raw)
    path = split(raw, '?'; limit=2)[1]
    parts = String[]
    for part in split(path, '/'; keepempty=true)
        if part == ".."
            isempty(parts) || pop!(parts)
        elseif part != "" && part != "."
            push!(parts, String(part))
        end
    end
    for i in eachindex(parts)
        s = parts[i]
        if digits(s)
            parts[i] = "{id}"
        elseif length(s) >= 8 && occursin(r"^[0-9a-f]+$", s) &&
            occursin(r"[0-9]", s)
            parts[i] = "{hex}"
        end
    end
    return "/" * join(parts, "/")
end

function compare_ip(a, b)
    left = parse.(Int, split(a, '.'))
    right = parse.(Int, split(b, '.'))
    for i in 1:4
        left[i] != right[i] && return left[i] < right[i]
    end
    return false
end

function status_matches(filter, status)
    if filter in CLASSES
        return status ÷ 100 == parse(Int, filter[1:1])
    end
    return status == parse(Int, filter)
end

function decimal(numerator, denominator, places)
    scale = 10 ^ places
    result = (numerator * scale) ÷ denominator
    return string(result ÷ scale, ".", padded(result % scale, places))
end

percent(a, b) = decimal(a * 100, b, 2) * "%"
bar(count, maximum) = repeat("#", (count * 30 + maximum - 1) ÷ maximum)

function bytes_text(size)
    size >= 1073741824 && return decimal(size, 1073741824, 1) * "GB"
    size >= 1048576 && return decimal(size, 1048576, 1) * "MB"
    size >= 1024 && return decimal(size, 1024, 1) * "KB"
    return string(size, "B")
end

struct Record
    line::Int
    date::String
    timestamp::String
    hour::Int
    seconds::Int
    ip::String
    method::String
    path::String
    status::Int
    bytes::Int
    latency::Int
end

function record_of(line, f)
    return Record(line, f[1], f[1] * " " * f[2], parse(Int, f[2][1:2]),
        seconds_of(f[1], f[2]), f[3], f[4], normalize_path(f[5]),
        parse(Int, f[6]), parse(Int, f[7]), parse(Int, f[8]))
end

function group_by(records, key)
    groups = Dict{String, Vector{Record}}()
    for row in records
        name = key(row)
        push!(get!(groups, name, Record[]), row)
    end
    return groups
end

function count_by(records, key)
    counts = Dict{String, Int}()
    for row in records
        name = key(row)
        counts[name] = get(counts, name, 0) + 1
    end
    return counts
end

function ranked(counts; tie=(a,b)->a<b)
    return sort!(collect(keys(counts));
        lt=(a,b)->counts[a] != counts[b] ? counts[a] > counts[b] : tie(a,b))
end

function class_counts(records)
    counts = zeros(Int, 5)
    for r in records
        counts[r.status ÷ 100] += 1
    end
    return counts
end

function bucket_counts(values)
    first, last = minimum(values), maximum(values)
    ensure(last - first + 1 <= 60, "too many buckets")
    counts = zeros(Int, last - first + 1)
    for value in values
        counts[value - first + 1] += 1
    end
    return first, counts
end

percentile(values, rank) = values[(rank * length(values) + 99) ÷ 100]

function peak(records, width)
    first = 1
    best = 0
    start = 1
    last = 1
    for i in eachindex(records)
        while records[i].seconds - records[first].seconds >= width
            first += 1
        end
        if i - first + 1 > best
            best = i - first + 1
            start = first
            last = i
        end
    end
    return (size=best, start=records[start], last=records[last])
end

function apdex(records, threshold)
    sat = count(r -> r.status < 500 && r.latency <= threshold, records)
    tol = count(r -> r.status < 500 &&
        threshold < r.latency <= threshold * 4, records)
    n = length(records)
    points, total = 2 * sat + tol, 2 * n
    rating = if points * 100 >= 94 * total
        "excellent"
    elseif points * 100 >= 85 * total
        "good"
    elseif points * 100 >= 70 * total
        "fair"
    elseif points * 100 >= 50 * total
        "poor"
    else
        "unacceptable"
    end
    return (count=n, satisfied=sat, tolerating=tol, frustrated=n-sat-tol,
        points=points, total=total, text=decimal(points, total, 3), rating=rating)
end

mutable struct Analyzer
    records::Vector{Record}
    malformed::Vector{Tuple{Int,String}}
    linecount::Int
    filters::Dict{String,Union{Nothing,String}}
    timerange::Union{Nothing,Tuple{Int,Int,String,String}}
    output::Vector{String}
end

function Analyzer(lines::Vector{String})
    records = Record[]
    malformed = Tuple{Int,String}[]
    for (index, line) in enumerate(lines)
        fields = tokens(line)
        reason = malformed_reason(fields)
        if reason === nothing
            push!(records, record_of(index, fields))
        else
            push!(malformed, (index, reason))
        end
    end
    sort!(records; by=r -> (r.seconds, r.line))
    filters = Dict{String,Union{Nothing,String}}(key => nothing for key in FILTER_KEYS)
    return Analyzer(records, malformed, length(lines), filters, nothing, String[])
end

function emit!(a::Analyzer, args...)
    push!(a.output, join(string.(args), " "))
end

function selected(a::Analyzer)
    result = Record[]
    for r in a.records
        window = a.timerange
        window !== nothing && (r.seconds < window[1] || r.seconds > window[2]) && continue
        a.filters["METHOD"] !== nothing && r.method != a.filters["METHOD"] && continue
        a.filters["STATUS"] !== nothing &&
            !status_matches(a.filters["STATUS"], r.status) && continue
        a.filters["IP"] !== nothing && r.ip != a.filters["IP"] && continue
        a.filters["PATH"] !== nothing && r.path != a.filters["PATH"] && continue
        push!(result, r)
    end
    return result
end

function bar_line!(a, label, number, maximum)
    if number == 0
        emit!(a, label, number)
    else
        emit!(a, label, number, bar(number, maximum))
    end
end

function run!(a::Analyzer, name, args, rows)
    if name == "SUMMARY"
        emit!(a, "SUMMARY", "lines", a.linecount, "valid", length(a.records),
            "malformed", length(a.malformed))
        emit!(a, "requests", length(rows), "bytes", sum((r.bytes for r in rows); init=0),
            "ips", length(Set(r.ip for r in rows)),
            "paths", length(Set(r.path for r in rows)))
        if isempty(rows)
            emit!(a, "span", "none")
        else
            emit!(a, "span", first(rows).timestamp, last(rows).timestamp,
                last(rows).seconds - first(rows).seconds)
        end

    elseif name == "MALFORMED"
        emit!(a, "MALFORMED", length(a.malformed))
        for reason in REASONS
            indices = [index for (index, why) in a.malformed if why == reason]
            isempty(indices) || emit!(a, reason, length(indices), indices...)
        end

    elseif name == "STATUS"
        emit!(a, "STATUS", length(rows))
        grouped = class_counts(rows)
        for i in eachindex(CLASSES)
            emit!(a, CLASSES[i], grouped[i], percent(grouped[i], length(rows)))
        end
        status = Dict{Int,Int}()
        for row in rows
            status[row.status] = get(status, row.status, 0) + 1
        end
        for code in sort!(collect(keys(status)))
            emit!(a, code, status[code], percent(status[code], length(rows)))
        end

    elseif name == "METHODS"
        values = count_by(rows, r -> r.method)
        emit!(a, "METHODS", length(rows))
        for method in ranked(values)
            emit!(a, method, values[method], percent(values[method], length(rows)))
        end

    elseif name == "TOP"
        kind = args[1]
        values = count_by(rows, r -> kind == "PATHS" ? r.path : r.ip)
        names = ranked(values; tie=kind == "IPS" ? compare_ip : ((a,b)->a<b))
        shown = min(parse(Int, args[2]), length(names))
        emit!(a, "TOP", kind, shown, "of", length(names))
        rank = 0
        for i in 1:shown
            (i == 1 || values[names[i]] != values[names[i-1]]) && (rank = i)
            emit!(a, rank, names[i], values[names[i]], percent(values[names[i]], length(rows)))
        end

    elseif name == "HOURLY"
        values = zeros(Int, 24)
        for row in rows
            values[row.hour+1] += 1
        end
        highest = maximum(values)
        firsthour = findfirst(==(highest), values)-1
        emit!(a, "HOURLY", length(rows), "peak", padded(firsthour), highest)
        for i in 1:24
            bar_line!(a, padded(i-1), values[i], highest)
        end

    elseif name == "TIMELINE"
        minutes = parse(Int, args[1])
        width = minutes * 60
        firstbucket, counts = bucket_counts([r.seconds ÷ width for r in rows])
        emit!(a, "TIMELINE", minutes, length(counts))
        largest = maximum(counts)
        for i in eachindex(counts)
            bar_line!(a, interval_label((firstbucket + i - 1) * width), counts[i], largest)
        end

    elseif name == "BANDWIDTH"
        days = group_by(rows, r -> r.date)
        volume = sum(r.bytes for r in rows)
        emit!(a, "BANDWIDTH", length(days), volume, bytes_text(volume))
        for date in sort!(collect(keys(days)))
            daybytes = sum(r.bytes for r in days[date])
            emit!(a, date, length(days[date]), daybytes, bytes_text(daybytes))
        end

    elseif name == "VISITORS"
        firstvisit = Dict{String,String}()
        for row in rows
            if !haskey(firstvisit, row.ip) || row.date < firstvisit[row.ip]
                firstvisit[row.ip] = row.date
            end
        end
        days = group_by(rows, r -> r.date)
        emit!(a, "VISITORS", length(days), length(firstvisit))
        for date in sort!(collect(keys(days)))
            ips = Set(row.ip for row in days[date])
            fresh = count(ip -> firstvisit[ip] == date, ips)
            emit!(a, date, "unique", length(ips), "new", fresh, "returning", length(ips) - fresh)
        end

    elseif name == "LATENCY"
        label = isempty(args) ? "all" : normalize_path(args[1])
        chosen = isempty(args) ? rows : filter(r -> r.path == label, rows)
        if isempty(chosen)
            emit!(a, "LATENCY", "no records")
        else
            values = sort!([r.latency for r in chosen])
            n, trim = length(values), length(values) ÷ 10
            trimmed = values[trim+1:n-trim]
            emit!(a, "LATENCY", label, "count", n, "min", first(values),
                "p50", percentile(values, 50), "p90", percentile(values, 90),
                "p99", percentile(values, 99), "max", last(values),
                "mean", decimal(sum(values), n, 2),
                "trimmed", decimal(sum(trimmed), length(trimmed), 2))
        end

    elseif name == "HISTOGRAM"
        width = parse(Int, args[1])
        firstbucket, counts = bucket_counts([r.latency ÷ width for r in rows])
        emit!(a, "HISTOGRAM", width, length(counts))
        largest = maximum(counts)
        for i in eachindex(counts)
            low = (firstbucket + i - 1) * width
            bar_line!(a, string(low, "-", low + width - 1), counts[i], largest)
        end

    elseif name == "APDEX"
        threshold = parse(Int, args[1])
        overall = apdex(rows, threshold)
        emit!(a, "APDEX", threshold, overall.text, overall.rating,
            "satisfied", overall.satisfied, "tolerating", overall.tolerating,
            "frustrated", overall.frustrated)
        paths = [(path=path, score=apdex(group, threshold))
            for (path, group) in group_by(rows, r -> r.path)]
        sort!(paths; lt=(x,y)->begin
            a_score, b_score = x.score, y.score
            left = a_score.points * b_score.total
            right = b_score.points * a_score.total
            left != right && return left < right
            a_score.count != b_score.count && return a_score.count > b_score.count
            return x.path < y.path
        end)
        for item in paths
            emit!(a, item.path, item.score.text, item.score.rating, item.score.count)
        end

    elseif name == "ERRORS"
        failed = count(r -> r.status >= 400, rows)
        emit!(a, "ERRORS", failed, "of", length(rows), percent(failed, length(rows)))
        paths = NamedTuple[]
        for (path, group) in group_by(rows, r -> r.path)
            client = count(r -> r.status ÷ 100 == 4, group)
            server = count(r -> r.status ÷ 100 == 5, group)
            client + server > 0 && push!(paths,
                (path=path, count=length(group), client=client, server=server))
        end
        sort!(paths; lt=(x,y)->begin
            xf, yf = x.client+x.server, y.client+y.server
            yf * x.count != xf * y.count && return yf * x.count < xf * y.count
            yf != xf && return yf > xf
            return x.path < y.path
        end)
        for row in paths
            emit!(a, row.path, row.count, row.client, row.server,
                percent(row.client + row.server, row.count))
        end

    elseif name == "SLOWEST"
        endpoints = NamedTuple[]
        for (key, group) in group_by(rows, r -> r.method * "\u0001" * r.path)
            pair = split(key, '\u0001'; limit=2)
            push!(endpoints, (method=pair[1], path=pair[2], count=length(group),
                total=sum(r.latency for r in group),
                maximum=maximum(r.latency for r in group)))
        end
        sort!(endpoints; lt=(x,y)->begin
            left, right = y.total * x.count, x.total * y.count
            left != right && return left < right
            x.maximum != y.maximum && return x.maximum > y.maximum
            x.path != y.path && return x.path < y.path
            return x.method < y.method
        end)
        shown = min(parse(Int, args[1]), length(endpoints))
        emit!(a, "SLOWEST", shown, "of", length(endpoints))
        for i in 1:shown
            row = endpoints[i]
            emit!(a, i, row.method, row.path, "count", row.count,
                "avg", decimal(row.total, row.count, 2), "max", row.maximum)
        end

    elseif name == "SESSIONS"
        ip = args[1]
        minutes = length(args) == 2 ? parse(Int, args[2]) : 30
        found = filter(r -> r.ip == ip, rows)
        if isempty(found)
            emit!(a, "SESSIONS", "no records")
        else
            sessions = [Record[found[1]]]
            for i in 2:length(found)
                if found[i].seconds - found[i-1].seconds <= minutes * 60
                    push!(sessions[end], found[i])
                else
                    push!(sessions, Record[found[i]])
                end
            end
            duration = sum(last(group).seconds - first(group).seconds for group in sessions)
            emit!(a, "SESSIONS", ip, "timeout", minutes, "count", length(sessions),
                "requests", length(found),
                "avg_duration", decimal(duration, length(sessions), 1),
                "avg_requests", decimal(length(found), length(sessions), 1))
            for (i, session) in enumerate(sessions)
                emit!(a, i, first(session).timestamp, last(session).timestamp,
                    last(session).seconds-first(session).seconds, length(session),
                    length(Set(r.path for r in session)))
            end
        end

    elseif name == "BURST"
        width, threshold = parse(Int, args[1]), parse(Int, args[2])
        failed = filter(r -> r.status >= 400, rows)
        peaks = [(ip=ip, window=peak(group, width))
            for (ip, group) in group_by(failed, r -> r.ip)]
        filter!(x -> x.window.size >= threshold, peaks)
        sort!(peaks; lt=(x,y)->x.window.size != y.window.size ?
            x.window.size > y.window.size : compare_ip(x.ip, y.ip))
        emit!(a, "BURST", width, threshold, length(peaks))
        for item in peaks
            emit!(a, item.ip, item.window.size,
                item.window.start.timestamp, item.window.last.timestamp)
        end

    elseif name == "PEAK"
        width = parse(Int, args[1])
        value = peak(rows, width)
        emit!(a, "PEAK", width, value.size,
            value.start.timestamp, value.last.timestamp)

    elseif name == "GAPS"
        threshold = parse(Int, args[1])
        gaps = Tuple{Record,Record}[]
        for i in 2:length(rows)
            if rows[i].seconds - rows[i-1].seconds >= threshold
                push!(gaps, (rows[i-1], rows[i]))
            end
        end
        emit!(a, "GAPS", threshold, length(gaps))
        for (before, after) in gaps
            emit!(a, before.timestamp, after.timestamp, after.seconds-before.seconds)
        end

    elseif name == "IP"
        ip = args[1]
        found = filter(r -> r.ip == ip, rows)
        if isempty(found)
            emit!(a, "IP", "no records")
        else
            paths = count_by(found, r -> r.path)
            emit!(a, "IP", ip, "requests", length(found),
                "bytes", sum(r.bytes for r in found),
                "errors", count(r -> r.status >= 400, found),
                "paths", length(paths))
            emit!(a, "first", first(found).timestamp, "last", last(found).timestamp)
            methods = count_by(found, r -> r.method)
            parts = Any["methods"]
            for method in ranked(methods)
                append!(parts, (method, methods[method]))
            end
            emit!(a, parts...)
            classes = class_counts(found)
            parts = Any["classes"]
            for i in eachindex(CLASSES)
                append!(parts, (CLASSES[i], classes[i]))
            end
            emit!(a, parts...)
            for path in Iterators.take(ranked(paths), 3)
                emit!(a, "path", path, paths[path])
            end
        end

    elseif name == "RANGE"
        firsttime = seconds_of(args[1], args[2])
        lasttime = seconds_of(args[3], args[4])
        ensure(firsttime <= lasttime, "invalid range")
        fromlabel, tolabel = args[1] * " " * args[2], args[3] * " " * args[4]
        a.timerange = (firsttime, lasttime, fromlabel, tolabel)
        emit!(a, "RANGE", fromlabel, tolabel, "active", length(selected(a)))

    elseif name == "FILTER"
        key, value = args
        key == "PATH" && (value = normalize_path(value))
        a.filters[key] = value
        emit!(a, "FILTER", key, value, "active", length(selected(a)))

    elseif name == "UNFILTER"
        key = args[1]
        if key == "RANGE"
            ensure(a.timerange !== nothing, "not filtered")
            a.timerange = nothing
        else
            ensure(a.filters[key] !== nothing, "not filtered")
            a.filters[key] = nothing
        end
        emit!(a, "UNFILTER", key, "active", length(selected(a)))

    elseif name == "RESET"
        a.timerange = nothing
        for key in FILTER_KEYS
            a.filters[key] = nothing
        end
        emit!(a, "RESET", "active", length(selected(a)))

    elseif name == "STATE"
        value = a.timerange === nothing ? "-" :
            a.timerange[3] * " " * a.timerange[4]
        parts = Any["STATE", "active", length(rows), "range", value]
        for key in FILTER_KEYS
            append!(parts, (lowercase(key),
                a.filters[key] === nothing ? "-" : a.filters[key]))
        end
        emit!(a, parts...)
    end
end

function execute!(a::Analyzer, line)
    fields = tokens(line)
    name = isempty(fields) ? "" : fields[1]
    args = fields[2:end]
    try
        ensure(haskey(FORMS, name), "unknown query")
        form = FORMS[name]
        optional = name in ["LATENCY", "SESSIONS"] && length(args) == length(form)-1
        ensure(length(args) == length(form) || optional, "wrong arguments")
        for i in eachindex(args)
            ensure(valid_argument(form[i], args[i], args), ERRORS[form[i]])
        end
        rows = selected(a)
        if name in REQUIRE_RECORDS && isempty(rows)
            emit!(a, name, "no records")
        else
            run!(a, name, args, rows)
        end
    catch error
        error isa QueryError || rethrow()
        emit!(a, "ERROR", error.message)
    end
end

function main()
    lines = readlines(stdin)
    separator = findfirst(==("---"), lines)
    ending = findnext(==("END"), lines, separator + 1)
    analyzer = Analyzer(lines[1:separator-1])
    for i in separator+1:ending-1
        execute!(analyzer, lines[i])
    end
    isempty(analyzer.output) || println(join(analyzer.output, "\n"))
end

main()
