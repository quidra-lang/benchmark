local config_io = {}
function config_io.decimal_integer(value, maximum)
    return #value > 0 and (not maximum or #value <= maximum) and (value == '0' or value:sub(1, 1) ~= '0') and value:match('^%d+$') ~= nil
end
function config_io.valid_hex_address(value) return #value == 8 and value:find('[^0-9a-f]') == nil end
function config_io.hex_address(value) return string.format('%08x', value) end
function config_io.read_config()
    local config = {scenarios = {}, regions = {}, watch = {}}
    for line in io.lines('input/config.txt') do
        local f = {}; for field in line:gmatch('%S+') do f[#f + 1] = field end
        local kind = f[1]
        if kind == 'CORES' then config.cores = tonumber(f[2])
        elseif kind == 'LINE' then config.line = tonumber(f[2])
        elseif kind == 'L1' then config.l1_size, config.l1_ways = tonumber(f[2]), tonumber(f[3])
        elseif kind == 'L2' then config.l2_size, config.l2_ways = tonumber(f[2]), tonumber(f[3])
        elseif kind == 'LATENCY' then config.t1, config.t2, config.tm, config.tb = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
        elseif kind == 'SCENARIO' then config.scenarios[#config.scenarios + 1] = {name = f[2], protocol = f[3], l1 = f[4], l2 = f[5], order = #config.scenarios}
        elseif kind == 'PRIMARY' then config.primary = f[2]
        elseif kind == 'INTERVAL' then config.interval = tonumber(f[2])
        elseif kind == 'TOP' then config.top = tonumber(f[2])
        elseif kind == 'REGION' then config.regions[#config.regions + 1] = {name = f[2], first = tonumber(f[3], 16), last = tonumber(f[4], 16)}
        elseif kind == 'WATCH' then config.watch[#config.watch + 1] = tonumber(f[2], 16) // config.line end
    end
    config.l1_sets = config.l1_size // (config.line * config.l1_ways)
    config.l2_sets = config.l2_size // (config.line * config.l2_ways)
    config.capacity = config.l1_sets * config.l1_ways
    return config
end
function config_io.read_trace()
    local lines = {}; for line in io.lines('input/trace.txt') do lines[#lines + 1] = line end; return lines
end
function config_io.write_lines(filename, lines)
    os.execute('mkdir -p output')
    local file = assert(io.open('output/' .. filename, 'w'))
    file:write(table.concat(lines, '\n'), #lines > 0 and '\n' or ''); file:close()
end
return config_io
