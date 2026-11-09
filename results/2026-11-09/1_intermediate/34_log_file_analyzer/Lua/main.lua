local methods = {
    GET = true, HEAD = true, POST = true, PUT = true,
    DELETE = true, PATCH = true, OPTIONS = true
}
local reasons = {
    "fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency"
}
local classes = {"1xx", "2xx", "3xx", "4xx", "5xx"}
local filter_keys = {"METHOD", "STATUS", "IP", "PATH"}
local month_days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
local forms = {
    SUMMARY = {}, MALFORMED = {}, STATUS = {}, METHODS = {},
    TOP = {"kind", "limit"}, HOURLY = {}, TIMELINE = {"minutes"},
    BANDWIDTH = {}, VISITORS = {}, LATENCY = {"path"},
    HISTOGRAM = {"width"}, APDEX = {"threshold"}, ERRORS = {},
    SLOWEST = {"limit"}, SESSIONS = {"ip", "minutes"},
    BURST = {"length", "times"}, PEAK = {"length"}, GAPS = {"length"},
    IP = {"ip"}, RANGE = {"date", "time", "date", "time"},
    FILTER = {"key", "value"}, UNFILTER = {"subject"}, RESET = {}, STATE = {}
}
local require_records = {
    STATUS = true, METHODS = true, TOP = true, HOURLY = true,
    TIMELINE = true, BANDWIDTH = true, VISITORS = true,
    HISTOGRAM = true, APDEX = true, ERRORS = true, SLOWEST = true,
    BURST = true, PEAK = true, GAPS = true
}
local ranges = {
    limit = {1, 100}, minutes = {1, 1440}, width = {1, 100000},
    threshold = {1, 100000}, length = {1, 86400}, times = {1, 1000}
}
local errors = {
    limit = "invalid number", minutes = "invalid number",
    width = "invalid number", threshold = "invalid number",
    length = "invalid number", times = "invalid number",
    kind = "invalid kind", path = "invalid path", ip = "invalid ip",
    date = "invalid timestamp", time = "invalid timestamp",
    key = "invalid key", subject = "invalid key", value = "invalid value"
}

local function check(condition, message)
    if not condition then error(message, 0) end
end

local function split_words(line)
    local out = {}
    for word in line:gmatch("%S+") do out[#out + 1] = word end
    return out
end

local function digits(value)
    return value:match("^%d+$") ~= nil
end

local function canonical(value, length)
    return #value >= 1 and #value <= length and digits(value)
        and (#value == 1 or value:sub(1, 1) ~= "0")
end

local function leap(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function year_days(year)
    return leap(year) and 366 or 365
end

local function days_in_month(year, month)
    if month == 2 and leap(year) then return 29 end
    return month_days[month]
end

local function valid_date(value)
    if not value:match("^%d%d%d%d%-%d%d%-%d%d$") then return false end
    local year = tonumber(value:sub(1, 4))
    local month = tonumber(value:sub(6, 7))
    local day = tonumber(value:sub(9, 10))
    return year >= 2000 and year <= 2059 and month >= 1 and month <= 12
        and day >= 1 and day <= days_in_month(year, month)
end

local function valid_time(value)
    if not value:match("^%d%d:%d%d:%d%d$") then return false end
    local hour = tonumber(value:sub(1, 2))
    local minute = tonumber(value:sub(4, 5))
    local second = tonumber(value:sub(7, 8))
    return hour < 24 and minute < 60 and second < 60
end

local function parts_of_ip(ip)
    local result = {}
    for item in (ip .. "."):gmatch("(.-)%.") do
        result[#result + 1] = item
    end
    return result
end

local function valid_ip(ip)
    local parts = parts_of_ip(ip)
    if #parts ~= 4 then return false end
    for _, part in ipairs(parts) do
        if not canonical(part, 3) or tonumber(part) > 255 then return false end
    end
    return true
end

local function valid_status(value)
    return value:match("^%d%d%d$") ~= nil
        and tonumber(value) >= 100 and tonumber(value) <= 599
end

local function valid_filter_value(key, value)
    if key == "METHOD" then return methods[value] ~= nil end
    if key == "STATUS" then
        for _, class in ipairs(classes) do
            if value == class then return true end
        end
        return valid_status(value)
    end
    if key == "IP" then return valid_ip(value) end
    return value:sub(1, 1) == "/"
end

local function contains(values, value)
    for _, item in ipairs(values) do
        if item == value then return true end
    end
    return false
end

local function valid_argument(kind, value, args)
    local range = ranges[kind]
    if range then
        return canonical(value, 6) and tonumber(value) >= range[1]
            and tonumber(value) <= range[2]
    end
    if kind == "kind" then return value == "PATHS" or value == "IPS" end
    if kind == "path" then return value:sub(1, 1) == "/" end
    if kind == "ip" then return valid_ip(value) end
    if kind == "date" then return valid_date(value) end
    if kind == "time" then return valid_time(value) end
    if kind == "key" then return contains(filter_keys, value) end
    if kind == "subject" then
        return value == "RANGE" or contains(filter_keys, value)
    end
    return valid_filter_value(args[1], value)
end

local function malformed_reason(fields)
    if #fields ~= 8 then return "fields" end
    if not valid_date(fields[1]) then return "date" end
    if not valid_time(fields[2]) then return "time" end
    if not valid_ip(fields[3]) then return "ip" end
    if not methods[fields[4]] then return "method" end
    if fields[5]:sub(1, 1) ~= "/" then return "path" end
    if not valid_status(fields[6]) then return "status" end
    if not canonical(fields[7], 8) then return "bytes" end
    if not canonical(fields[8], 6) then return "latency" end
    return nil
end

local function seconds_of(date, clock)
    local year = tonumber(date:sub(1, 4))
    local month = tonumber(date:sub(6, 7))
    local days = tonumber(date:sub(9, 10)) - 1
    for y = 2000, year - 1 do days = days + year_days(y) end
    for m = 1, month - 1 do days = days + days_in_month(year, m) end
    return days * 86400 + tonumber(clock:sub(1, 2)) * 3600
        + tonumber(clock:sub(4, 5)) * 60 + tonumber(clock:sub(7, 8))
end

local function interval_label(seconds)
    local days, minutes = seconds // 86400, (seconds % 86400) // 60
    local year = 2000
    while days >= year_days(year) do
        days = days - year_days(year)
        year = year + 1
    end
    local month = 1
    while days >= days_in_month(year, month) do
        days = days - days_in_month(year, month)
        month = month + 1
    end
    return string.format("%04d-%02d-%02d %02d:%02d",
        year, month, days + 1, minutes // 60, minutes % 60)
end

local function normalize_path(raw)
    local path = raw:match("^[^?]*")
    local parts = {}
    for part in (path .. "/"):gmatch("(.-)/") do
        if part == ".." then
            if #parts > 0 then table.remove(parts) end
        elseif part ~= "" and part ~= "." then
            parts[#parts + 1] = part
        end
    end
    for i, part in ipairs(parts) do
        if digits(part) then
            parts[i] = "{id}"
        elseif #part >= 8 and part:match("^[0-9a-f]+$")
            and part:find("%d") then
            parts[i] = "{hex}"
        end
    end
    return "/" .. table.concat(parts, "/")
end

local function compare_ip(a, b)
    local x, y = parts_of_ip(a), parts_of_ip(b)
    for i = 1, 4 do
        if tonumber(x[i]) ~= tonumber(y[i]) then
            return tonumber(x[i]) < tonumber(y[i])
        end
    end
    return false
end

local function status_matches(filter, status)
    for _, label in ipairs(classes) do
        if filter == label then return status // 100 == tonumber(filter:sub(1, 1)) end
    end
    return status == tonumber(filter)
end

local function decimal(numerator, denominator, places)
    local scale = ({10, 100, 1000})[places]
    local value = (numerator * scale) // denominator
    return string.format("%d.%0" .. places .. "d", value // scale, value % scale)
end

local function percent(numerator, denominator)
    return decimal(numerator * 100, denominator, 2) .. "%"
end

local function bar(n, maximum)
    return string.rep("#", (n * 30 + maximum - 1) // maximum)
end

local function bytes_text(n)
    if n >= 1073741824 then return decimal(n, 1073741824, 1) .. "GB" end
    if n >= 1048576 then return decimal(n, 1048576, 1) .. "MB" end
    if n >= 1024 then return decimal(n, 1024, 1) .. "KB" end
    return tostring(n) .. "B"
end

local function sum(rows, key)
    local result = 0
    for _, row in ipairs(rows) do result = result + row[key] end
    return result
end

local function group_by(rows, get_key)
    local groups = {}
    for _, row in ipairs(rows) do
        local key = get_key(row)
        if not groups[key] then groups[key] = {} end
        table.insert(groups[key], row)
    end
    return groups
end

local function count_by(rows, get_key)
    local counts = {}
    for _, row in ipairs(rows) do
        local key = get_key(row)
        counts[key] = (counts[key] or 0) + 1
    end
    return counts
end

local function keys_of(table_value)
    local keys = {}
    for key in pairs(table_value) do keys[#keys + 1] = key end
    return keys
end

local function sorted_count_keys(counts, compare)
    local keys = keys_of(counts)
    compare = compare or function(a, b) return a < b end
    table.sort(keys, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end
        return compare(a, b)
    end)
    return keys
end

local function class_counts(rows)
    local counts = {0, 0, 0, 0, 0}
    for _, row in ipairs(rows) do
        local i = row.status // 100
        counts[i] = counts[i] + 1
    end
    return counts
end

local function bucket_counts(numbers)
    local first, last = numbers[1], numbers[1]
    for i = 2, #numbers do
        if numbers[i] < first then first = numbers[i] end
        if numbers[i] > last then last = numbers[i] end
    end
    check(last - first + 1 <= 60, "too many buckets")
    local counts = {}
    for _ = first, last do counts[#counts + 1] = 0 end
    for _, n in ipairs(numbers) do
        local i = n - first + 1
        counts[i] = counts[i] + 1
    end
    return first, counts
end

local function percentile(sorted, rank)
    return sorted[(rank * #sorted + 99) // 100]
end

local function window_peak(rows, length)
    local first, count, best_start, best_end = 1, 0, 1, 1
    for last, row in ipairs(rows) do
        while row.seconds - rows[first].seconds >= length do
            first = first + 1
        end
        if last - first + 1 > count then
            count, best_start, best_end = last - first + 1, first, last
        end
    end
    return {count = count, first = rows[best_start], last = rows[best_end]}
end

local function apdex(rows, threshold)
    local satisfied, tolerating = 0, 0
    for _, row in ipairs(rows) do
        if row.status < 500 then
            if row.latency <= threshold then
                satisfied = satisfied + 1
            elseif row.latency <= 4 * threshold then
                tolerating = tolerating + 1
            end
        end
    end
    local points, total = 2 * satisfied + tolerating, 2 * #rows
    local rating = "unacceptable"
    if 100 * points >= 94 * total then rating = "excellent"
    elseif 100 * points >= 85 * total then rating = "good"
    elseif 100 * points >= 70 * total then rating = "fair"
    elseif 100 * points >= 50 * total then rating = "poor" end
    return {
        count = #rows, satisfied = satisfied, tolerating = tolerating,
        frustrated = #rows - satisfied - tolerating,
        points = points, total = total, rating = rating,
        text = decimal(points, total, 3)
    }
end

local function new_analyzer(lines)
    local analyzer = {
        records = {}, malformed = {}, line_count = #lines, output = {},
        filters = {}, range = nil
    }
    for i, line in ipairs(lines) do
        local fields = split_words(line)
        local reason = malformed_reason(fields)
        if reason then
            table.insert(analyzer.malformed, {line = i, reason = reason})
        else
            table.insert(analyzer.records, {
                line = i, date = fields[1], timestamp = fields[1] .. " " .. fields[2],
                hour = tonumber(fields[2]:sub(1, 2)),
                seconds = seconds_of(fields[1], fields[2]),
                ip = fields[3], method = fields[4], path = normalize_path(fields[5]),
                status = tonumber(fields[6]), bytes = tonumber(fields[7]),
                latency = tonumber(fields[8])
            })
        end
    end
    table.sort(analyzer.records, function(a, b)
        return a.seconds < b.seconds or
            (a.seconds == b.seconds and a.line < b.line)
    end)
    return analyzer
end

local function emit(analyzer, ...)
    local parts = {...}
    for i, value in ipairs(parts) do parts[i] = tostring(value) end
    table.insert(analyzer.output, table.concat(parts, " "))
end

local function selected(analyzer)
    local result = {}
    for _, row in ipairs(analyzer.records) do
        local r = analyzer.range
        if (not r or (row.seconds >= r.start and row.seconds <= r.last))
            and (not analyzer.filters.METHOD or row.method == analyzer.filters.METHOD)
            and (not analyzer.filters.STATUS or status_matches(analyzer.filters.STATUS, row.status))
            and (not analyzer.filters.IP or row.ip == analyzer.filters.IP)
            and (not analyzer.filters.PATH or row.path == analyzer.filters.PATH) then
            result[#result + 1] = row
        end
    end
    return result
end

local function bar_line(analyzer, label, count, maximum)
    if count == 0 then emit(analyzer, label, count)
    else emit(analyzer, label, count, bar(count, maximum)) end
end

local function execute_query(analyzer, name, a, rows)
    if name == "SUMMARY" then
        emit(analyzer, "SUMMARY", "lines", analyzer.line_count,
            "valid", #analyzer.records, "malformed", #analyzer.malformed)
        local ips = count_by(rows, function(r) return r.ip end)
        local paths = count_by(rows, function(r) return r.path end)
        emit(analyzer, "requests", #rows, "bytes", sum(rows, "bytes"),
            "ips", #keys_of(ips), "paths", #keys_of(paths))
        if #rows == 0 then emit(analyzer, "span", "none")
        else
            emit(analyzer, "span", rows[1].timestamp, rows[#rows].timestamp,
                rows[#rows].seconds - rows[1].seconds)
        end

    elseif name == "MALFORMED" then
        emit(analyzer, "MALFORMED", #analyzer.malformed)
        for _, reason in ipairs(reasons) do
            local lines = {}
            for _, row in ipairs(analyzer.malformed) do
                if row.reason == reason then lines[#lines + 1] = row.line end
            end
            if #lines > 0 then
                emit(analyzer, reason, #lines, table.unpack(lines))
            end
        end

    elseif name == "STATUS" then
        emit(analyzer, "STATUS", #rows)
        local classes_count = class_counts(rows)
        for i, class in ipairs(classes) do
            emit(analyzer, class, classes_count[i], percent(classes_count[i], #rows))
        end
        local counts = count_by(rows, function(r) return r.status end)
        local status = keys_of(counts)
        table.sort(status)
        for _, code in ipairs(status) do
            emit(analyzer, code, counts[code], percent(counts[code], #rows))
        end

    elseif name == "METHODS" then
        local counts = count_by(rows, function(r) return r.method end)
        emit(analyzer, "METHODS", #rows)
        for _, method in ipairs(sorted_count_keys(counts)) do
            emit(analyzer, method, counts[method], percent(counts[method], #rows))
        end

    elseif name == "TOP" then
        local kind = a[1]
        local counts = count_by(rows, function(r)
            return kind == "PATHS" and r.path or r.ip
        end)
        local ranked = sorted_count_keys(counts,
            kind == "IPS" and compare_ip or nil)
        local shown = math.min(tonumber(a[2]), #ranked)
        emit(analyzer, "TOP", kind, shown, "of", #ranked)
        local rank = 0
        for i = 1, shown do
            if i == 1 or counts[ranked[i]] ~= counts[ranked[i - 1]] then rank = i end
            local key = ranked[i]
            emit(analyzer, rank, key, counts[key], percent(counts[key], #rows))
        end

    elseif name == "HOURLY" then
        local counts = {}
        for i = 1, 24 do counts[i] = 0 end
        for _, row in ipairs(rows) do counts[row.hour + 1] = counts[row.hour + 1] + 1 end
        local maximum = math.max(table.unpack(counts))
        local first = 1
        while counts[first] ~= maximum do first = first + 1 end
        emit(analyzer, "HOURLY", #rows, "peak", string.format("%02d", first - 1), maximum)
        for i, count in ipairs(counts) do
            bar_line(analyzer, string.format("%02d", i - 1), count, maximum)
        end

    elseif name == "TIMELINE" then
        local minutes, numbers = tonumber(a[1]), {}
        local width = minutes * 60
        for _, row in ipairs(rows) do
            numbers[#numbers + 1] = row.seconds // width
        end
        local first, counts = bucket_counts(numbers)
        emit(analyzer, "TIMELINE", minutes, #counts)
        local maximum = math.max(table.unpack(counts))
        for i, count in ipairs(counts) do
            bar_line(analyzer, interval_label((first + i - 1) * width), count, maximum)
        end

    elseif name == "BANDWIDTH" then
        local days = group_by(rows, function(r) return r.date end)
        local size = sum(rows, "bytes")
        emit(analyzer, "BANDWIDTH", #keys_of(days), size, bytes_text(size))
        local dates = keys_of(days)
        table.sort(dates)
        for _, date in ipairs(dates) do
            local count = sum(days[date], "bytes")
            emit(analyzer, date, #days[date], count, bytes_text(count))
        end

    elseif name == "VISITORS" then
        local first, days = {}, group_by(rows, function(r) return r.date end)
        for _, row in ipairs(rows) do
            if not first[row.ip] or row.date < first[row.ip] then first[row.ip] = row.date end
        end
        local dates = keys_of(days)
        table.sort(dates)
        emit(analyzer, "VISITORS", #dates, #keys_of(first))
        for _, date in ipairs(dates) do
            local ips = count_by(days[date], function(r) return r.ip end)
            local fresh = 0
            for ip in pairs(ips) do
                if first[ip] == date then fresh = fresh + 1 end
            end
            local n = #keys_of(ips)
            emit(analyzer, date, "unique", n, "new", fresh, "returning", n - fresh)
        end

    elseif name == "LATENCY" then
        local label = #a > 0 and normalize_path(a[1]) or "all"
        local numbers = {}
        for _, row in ipairs(rows) do
            if #a == 0 or row.path == label then
                numbers[#numbers + 1] = row.latency
            end
        end
        if #numbers == 0 then emit(analyzer, "LATENCY", "no records")
        else
            table.sort(numbers)
            local n, trim = #numbers, #numbers // 10
            local sum_all, sum_trimmed = 0, 0
            for i, value in ipairs(numbers) do
                sum_all = sum_all + value
                if i > trim and i <= n - trim then
                    sum_trimmed = sum_trimmed + value
                end
            end
            emit(analyzer, "LATENCY", label, "count", n, "min", numbers[1],
                "p50", percentile(numbers, 50), "p90", percentile(numbers, 90),
                "p99", percentile(numbers, 99), "max", numbers[n],
                "mean", decimal(sum_all, n, 2),
                "trimmed", decimal(sum_trimmed, n - 2 * trim, 2))
        end

    elseif name == "HISTOGRAM" then
        local width, numbers = tonumber(a[1]), {}
        for _, row in ipairs(rows) do
            numbers[#numbers + 1] = row.latency // width
        end
        local first, counts = bucket_counts(numbers)
        emit(analyzer, "HISTOGRAM", width, #counts)
        local maximum = math.max(table.unpack(counts))
        for i, count in ipairs(counts) do
            local lo = (first + i - 1) * width
            bar_line(analyzer, lo .. "-" .. (lo + width - 1), count, maximum)
        end

    elseif name == "APDEX" then
        local threshold = tonumber(a[1])
        local score = apdex(rows, threshold)
        emit(analyzer, "APDEX", threshold, score.text, score.rating,
            "satisfied", score.satisfied, "tolerating", score.tolerating,
            "frustrated", score.frustrated)
        local paths = {}
        for path, records in pairs(group_by(rows, function(r) return r.path end)) do
            paths[#paths + 1] = {path = path, score = apdex(records, threshold)}
        end
        table.sort(paths, function(x, y)
            local a_score, b_score = x.score, y.score
            local left = a_score.points * b_score.total
            local right = b_score.points * a_score.total
            if left ~= right then return left < right end
            if a_score.count ~= b_score.count then
                return a_score.count > b_score.count
            end
            return x.path < y.path
        end)
        for _, item in ipairs(paths) do
            emit(analyzer, item.path, item.score.text,
                item.score.rating, item.score.count)
        end

    elseif name == "ERRORS" then
        local failed = 0
        for _, row in ipairs(rows) do
            if row.status >= 400 then failed = failed + 1 end
        end
        emit(analyzer, "ERRORS", failed, "of", #rows, percent(failed, #rows))
        local paths = {}
        for path, group in pairs(group_by(rows, function(r) return r.path end)) do
            local client, server = 0, 0
            for _, row in ipairs(group) do
                if row.status // 100 == 4 then client = client + 1 end
                if row.status // 100 == 5 then server = server + 1 end
            end
            if client + server > 0 then
                paths[#paths + 1] = {
                    path = path, count = #group, client = client, server = server
                }
            end
        end
        table.sort(paths, function(x, y)
            local xf, yf = x.client + x.server, y.client + y.server
            if yf * x.count ~= xf * y.count then
                return yf * x.count < xf * y.count
            end
            if yf ~= xf then return yf > xf end
            return x.path < y.path
        end)
        for _, row in ipairs(paths) do
            emit(analyzer, row.path, row.count, row.client, row.server,
                percent(row.client + row.server, row.count))
        end

    elseif name == "SLOWEST" then
        local groups = group_by(rows, function(r) return r.method .. "\1" .. r.path end)
        local endpoints = {}
        for key, records in pairs(groups) do
            local method, path = key:match("^(.-)\1(.*)$")
            local maximum = 0
            for _, row in ipairs(records) do
                if row.latency > maximum then maximum = row.latency end
            end
            endpoints[#endpoints + 1] = {
                method = method, path = path, count = #records,
                total = sum(records, "latency"), maximum = maximum
            }
        end
        table.sort(endpoints, function(x, y)
            local left = y.total * x.count
            local right = x.total * y.count
            if left ~= right then return left < right end
            if x.maximum ~= y.maximum then return x.maximum > y.maximum end
            if x.path ~= y.path then return x.path < y.path end
            return x.method < y.method
        end)
        local shown = math.min(tonumber(a[1]), #endpoints)
        emit(analyzer, "SLOWEST", shown, "of", #endpoints)
        for i = 1, shown do
            local p = endpoints[i]
            emit(analyzer, i, p.method, p.path, "count", p.count,
                "avg", decimal(p.total, p.count, 2), "max", p.maximum)
        end

    elseif name == "SESSIONS" then
        local ip, minutes = a[1], #a == 2 and tonumber(a[2]) or 30
        local found = {}
        for _, row in ipairs(rows) do
            if row.ip == ip then found[#found + 1] = row end
        end
        if #found == 0 then emit(analyzer, "SESSIONS", "no records")
        else
            local sessions = {{found[1]}}
            for i = 2, #found do
                if found[i].seconds - found[i - 1].seconds <= minutes * 60 then
                    local last = sessions[#sessions]
                    last[#last + 1] = found[i]
                else
                    sessions[#sessions + 1] = {found[i]}
                end
            end
            local duration = 0
            for _, session in ipairs(sessions) do
                duration = duration + session[#session].seconds - session[1].seconds
            end
            emit(analyzer, "SESSIONS", ip, "timeout", minutes,
                "count", #sessions, "requests", #found,
                "avg_duration", decimal(duration, #sessions, 1),
                "avg_requests", decimal(#found, #sessions, 1))
            for i, session in ipairs(sessions) do
                local paths = count_by(session, function(r) return r.path end)
                emit(analyzer, i, session[1].timestamp,
                    session[#session].timestamp,
                    session[#session].seconds - session[1].seconds,
                    #session, #keys_of(paths))
            end
        end

    elseif name == "BURST" then
        local length, threshold = tonumber(a[1]), tonumber(a[2])
        local failed = {}
        for _, row in ipairs(rows) do
            if row.status >= 400 then failed[#failed + 1] = row end
        end
        local ips = group_by(failed, function(r) return r.ip end)
        local peaks = {}
        for ip, records in pairs(ips) do
            local window = window_peak(records, length)
            if window.count >= threshold then
                peaks[#peaks + 1] = {ip = ip, window = window}
            end
        end
        table.sort(peaks, function(x, y)
            if x.window.count ~= y.window.count then
                return x.window.count > y.window.count
            end
            return compare_ip(x.ip, y.ip)
        end)
        emit(analyzer, "BURST", length, threshold, #peaks)
        for _, item in ipairs(peaks) do
            local p = item.window
            emit(analyzer, item.ip, p.count, p.first.timestamp, p.last.timestamp)
        end

    elseif name == "PEAK" then
        local length = tonumber(a[1])
        local p = window_peak(rows, length)
        emit(analyzer, "PEAK", length, p.count, p.first.timestamp, p.last.timestamp)

    elseif name == "GAPS" then
        local length, gaps = tonumber(a[1]), {}
        for i = 2, #rows do
            if rows[i].seconds - rows[i - 1].seconds >= length then
                gaps[#gaps + 1] = {rows[i - 1], rows[i]}
            end
        end
        emit(analyzer, "GAPS", length, #gaps)
        for _, gap in ipairs(gaps) do
            emit(analyzer, gap[1].timestamp, gap[2].timestamp,
                gap[2].seconds - gap[1].seconds)
        end

    elseif name == "IP" then
        local ip, found = a[1], {}
        for _, row in ipairs(rows) do
            if row.ip == ip then found[#found + 1] = row end
        end
        if #found == 0 then emit(analyzer, "IP", "no records")
        else
            local paths = count_by(found, function(r) return r.path end)
            local failures = 0
            for _, row in ipairs(found) do
                if row.status >= 400 then failures = failures + 1 end
            end
            emit(analyzer, "IP", ip, "requests", #found,
                "bytes", sum(found, "bytes"), "errors", failures,
                "paths", #keys_of(paths))
            emit(analyzer, "first", found[1].timestamp,
                "last", found[#found].timestamp)
            local method_counts = count_by(found, function(r) return r.method end)
            local method_parts = {"methods"}
            for _, method in ipairs(sorted_count_keys(method_counts)) do
                method_parts[#method_parts + 1] = method
                method_parts[#method_parts + 1] = method_counts[method]
            end
            emit(analyzer, table.unpack(method_parts))
            local category = class_counts(found)
            local class_parts = {"classes"}
            for i, label in ipairs(classes) do
                class_parts[#class_parts + 1] = label
                class_parts[#class_parts + 1] = category[i]
            end
            emit(analyzer, table.unpack(class_parts))
            local ranked = sorted_count_keys(paths)
            for i = 1, math.min(3, #ranked) do
                emit(analyzer, "path", ranked[i], paths[ranked[i]])
            end
        end

    elseif name == "RANGE" then
        local first = seconds_of(a[1], a[2])
        local last = seconds_of(a[3], a[4])
        check(first <= last, "invalid range")
        local start_text, last_text = a[1] .. " " .. a[2], a[3] .. " " .. a[4]
        analyzer.range = {
            start = first, last = last, start_text = start_text, last_text = last_text
        }
        emit(analyzer, "RANGE", start_text, last_text,
            "active", #selected(analyzer))

    elseif name == "FILTER" then
        local key = a[1]
        local value = key == "PATH" and normalize_path(a[2]) or a[2]
        analyzer.filters[key] = value
        emit(analyzer, "FILTER", key, value, "active", #selected(analyzer))

    elseif name == "UNFILTER" then
        local key = a[1]
        if key == "RANGE" then
            check(analyzer.range ~= nil, "not filtered")
            analyzer.range = nil
        else
            check(analyzer.filters[key] ~= nil, "not filtered")
            analyzer.filters[key] = nil
        end
        emit(analyzer, "UNFILTER", key, "active", #selected(analyzer))

    elseif name == "RESET" then
        analyzer.range = nil
        analyzer.filters = {}
        emit(analyzer, "RESET", "active", #selected(analyzer))

    elseif name == "STATE" then
        local r = analyzer.range
        local parts = {
            "STATE", "active", #rows, "range",
            r and (r.start_text .. " " .. r.last_text) or "-"
        }
        for _, key in ipairs(filter_keys) do
            parts[#parts + 1] = key:lower()
            parts[#parts + 1] = analyzer.filters[key] or "-"
        end
        emit(analyzer, table.unpack(parts))
    end
end

local function execute(analyzer, line)
    local fields = split_words(line)
    local name = fields[1] or ""
    local args = {}
    for i = 2, #fields do args[#args + 1] = fields[i] end
    local ok, message = pcall(function()
        local form = forms[name]
        check(form ~= nil, "unknown query")
        local optional = (name == "LATENCY" or name == "SESSIONS")
            and #args == #form - 1
        check(#args == #form or optional, "wrong arguments")
        for i, value in ipairs(args) do
            check(valid_argument(form[i], value, args), errors[form[i]])
        end
        local records = selected(analyzer)
        if require_records[name] and #records == 0 then
            emit(analyzer, name, "no records")
        else
            execute_query(analyzer, name, args, records)
        end
    end)
    if not ok then emit(analyzer, "ERROR", message) end
end

local lines = {}
for line in io.lines() do lines[#lines + 1] = line end
local divider, finish
for i, line in ipairs(lines) do
    if line == "---" and not divider then divider = i end
    if line == "END" and divider then
        finish = i
        break
    end
end

local logs = {}
for i = 1, divider - 1 do logs[#logs + 1] = lines[i] end
local analyzer = new_analyzer(logs)
for i = divider + 1, finish - 1 do execute(analyzer, lines[i]) end
if #analyzer.output > 0 then
    io.write(table.concat(analyzer.output, "\n"), "\n")
end
