local M = {}
local function days(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = y // 400
    local yy = y - era * 400
    local mm = m + (m > 2 and -3 or 9)
    return era * 146097 + yy * 365 + yy // 4 - yy // 100 + (153 * mm + 2) // 5 + d - 1
end
function M.date(day)
    local era = day // 146097
    local dd = day - era * 146097
    local yy = (dd - dd // 1460 + dd // 36524 - dd // 146096) // 365
    local y = yy + era * 400
    local doy = dd - (365 * yy + yy // 4 - yy // 100)
    local mp = (5 * doy + 2) // 153
    local d = doy - (153 * mp + 2) // 5 + 1
    local m = mp + (mp < 10 and 3 or -9)
    if m <= 2 then y = y + 1 end
    return string.format('%04d-%02d-%02d', y, m, d)
end
local function instant(text)
    local y, m, d, h, n = text:match('(%d+)%-(%d+)%-(%d+) (%d+):(%d+)')
    return days(tonumber(y), tonumber(m), tonumber(d)) * 1440 + tonumber(h) * 60 + tonumber(n)
end
function M.minute(s, t)
    local n = s.epoch + t
    return M.date(n // 1440) .. string.format(' %02d:%02d', n % 1440 // 60, n % 60)
end
function M.hour(s, t) return M.minute(s, t * 60) end
function M.day(s, t) return (s.epoch + t * 60) // 1440 end
local function lines(path)
    local out = {}
    for line in io.lines(path) do out[#out + 1] = line:gsub('\r$', '') end
    return out
end
local function words(text)
    local out = {}
    for word in text:gmatch('%S+') do out[#out + 1] = word end
    return out
end
function M.read()
    local ls = lines('input/params.txt')
    local s = {epoch = instant(ls[1]:sub(7)), stations = {}}
    local i = 2
    while ls[i]:sub(1, 8) == 'station ' do
        local code, name = ls[i]:match('^station (%S+) (.*)$')
        s.stations[#s.stations + 1] = {code = code, name = name}
        i = i + 1
    end
    local raw = {}
    for j = i, #ls do local k, v = ls[j]:match('^(%S+) (.*)$'); raw[k] = v end
    s.reference = raw.reference
    for _, k in ipairs({'flat_run', 'top_residuals', 'grid_minutes', 'correlation_lag'}) do s[k] = tonumber(raw[k]) end
    for _, k in ipairs({'rayleigh', 'snr_min', 'min_range'}) do s[k] = tonumber(raw[k]) + 0.0 end
    local w = words(raw.spike)
    s.spike_window, s.spike_minimum = tonumber(w[1]), tonumber(w[2])
    s.spike_factor, s.spike_floor = tonumber(w[3]) + 0.0, tonumber(w[4]) + 0.0
    w = words(raw.surge)
    s.surge_threshold, s.surge_hours = tonumber(w[1]) + 0.0, tonumber(w[2])
    w = words(raw.predict)
    s.prediction_start = (instant(w[1] .. ' ' .. w[2]) - s.epoch) // 60
    s.prediction_hours = tonumber(w[3])
    w = words(raw.plot)
    s.plot_code, s.plot_hours = w[1], tonumber(w[2])
    s.plot_top, s.plot_bottom, s.plot_step = tonumber(w[3]), tonumber(w[4]), tonumber(w[5])
    local cs = {}
    ls = lines('input/constituents.txt')
    for j = 2, #ls do
        w = words(ls[j]); cs[#cs + 1] = {name = w[1], speed = tonumber(w[2]) + 0.0}
    end
    local obs = {}
    for _, station in ipairs(s.stations) do obs[station.code] = {values = {}, millimetres = {}, rows = 0} end
    ls = lines('input/observations.csv')
    for j = 2, #ls do
        local code, time, value = ls[j]:match('^([^,]+),([^,]+),([^,]+)$')
        local t = (instant(time) - s.epoch) // 60
        local record = obs[code]
        record.rows = record.rows + 1
        if value == 'NA' then record.values[t] = false else
            record.values[t] = tonumber(value) + 0.0
            record.millimetres[t] = tonumber((value:gsub('%.', '')))
        end
    end
    return s, cs, obs
end
return M
