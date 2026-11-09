local function words(text)
    local result = {}
    for word in text:gmatch("[^ ]+") do
        result[#result + 1] = word
    end
    return result
end

local builtin_names = words("black maroon green olive navy purple teal silver gray red lime yellow blue magenta cyan white orange pink brown gold coral salmon violet indigo")
local builtin_hex = words("000000 800000 008000 808000 000080 800080 008080 C0C0C0 808080 FF0000 00FF00 FFFF00 0000FF FF00FF 00FFFF FFFFFF FFA500 FFC0CB A52A2A FFD700 FF7F50 FA8072 EE82EE 4B0082")
local builtin_colors = {}
for i, text in ipairs(builtin_hex) do
    builtin_colors[i] = {
        tonumber(text:sub(1, 2), 16),
        tonumber(text:sub(3, 4), 16),
        tonumber(text:sub(5, 6), 16)
    }
end

local signatures = {
    ["PARSE"] = "c",
    ["DEFINE"] = "name c",
    ["UNDEFINE"] = "name",
    ["LIST"] = "",
    ["HSL"] = "c",
    ["HSV"] = "c",
    ["HWB"] = "c",
    ["CMYK"] = "c",
    ["YCBCR"] = "c",
    ["YIQ"] = "c",
    ["FROMHSL"] = "0:359 0:100 0:100",
    ["FROMHSV"] = "0:359 0:100 0:100",
    ["FROMHWB"] = "0:359 0:100 0:100",
    ["FROMCMYK"] = "0:100 0:100 0:100 0:100",
    ["FROMYCBCR"] = "0:255 0:255 0:255",
    ["FROMYIQ"] = "0:255 -255:255 -255:255",
    ["RGB565"] = "c",
    ["FROM565"] = "code",
    ["ANSI"] = "c",
    ["FROMANSI"] = "0:255",
    ["WEBSAFE"] = "c",
    ["GRAY"] = "c gray",
    ["INVERT"] = "c",
    ["MIX"] = "c c 0:100",
    ["MIXHSL"] = "c c 0:100",
    ["GRADIENT"] = "c c 2:16",
    ["TINTS"] = "c 1:10",
    ["SHADES"] = "c 1:10",
    ["TONES"] = "c 1:10",
    ["BLEND"] = "blend c c",
    ["ALPHA"] = "c 0:100 c 0:100",
    ["SIMULATE"] = "c simulation",
    ["ROTATE"] = "c -720:720",
    ["COMPLEMENT"] = "c",
    ["TRIADIC"] = "c",
    ["TETRADIC"] = "c",
    ["SPLITCOMP"] = "c",
    ["ANALOGOUS"] = "c 1:6 1:60",
    ["LIGHTEN"] = "c 0:100",
    ["DARKEN"] = "c 0:100",
    ["SATURATE"] = "c 0:100",
    ["DESATURATE"] = "c 0:100",
    ["NEAREST"] = "c",
    ["DISTANCE"] = "c c",
    ["CONTRAST"] = "c c",
    ["ACCESSIBLE"] = "c c",
    ["DESCRIBE"] = "c",
    ["RANDOM"] = "1:999999999 1:16",
}
local keywords = {
    gray = words("LUMA AVERAGE LIGHTNESS HSP"),
    blend = words("MULTIPLY SCREEN OVERLAY HARDLIGHT SOFTLIGHT DARKEN LIGHTEN DIFFERENCE EXCLUSION ADD SUBTRACT COLORDODGE COLORBURN HUE SATURATION COLOR LUMINOSITY"),
    simulation = words("PROTANOPIA DEUTERANOPIA TRITANOPIA ACHROMATOPSIA")
}

local function require_valid(condition)
    if not condition then
        error("INVALID", 0)
    end
end

local function contains(values, value)
    for _, other in ipairs(values) do
        if other == value then
            return true
        end
    end
    return false
end

local function copy_color(color)
    return {color[1], color[2], color[3]}
end

local function round_ratio(n, d)
    return (2 * n + d) // (2 * d)
end

local function away_ratio(n, d)
    if n < 0 then
        return -round_ratio(-n, d)
    end
    return round_ratio(n, d)
end

local function byte_clamp(x)
    return math.min(255, math.max(0, x))
end

local function hex_color(color)
    return string.format("#%02X%02X%02X", color[1], color[2], color[3])
end

local function color_sequence(colors)
    local output = {}
    for i, color in ipairs(colors) do
        output[i] = hex_color(color)
    end
    return table.concat(output, " ")
end

local function color_distance(a, b)
    local total = 0
    for i = 1, 3 do
        local difference = a[i] - b[i]
        total = total + difference * difference
    end
    return total
end

local function integer_arg(text, low, high)
    local digits = text:match("^%-?(%d+)$")
    require_valid(digits ~= nil and #digits <= 9)
    local value = tonumber(text)
    require_valid(value >= low and value <= high)
    return value
end

local function parse_color(text, registry)
    if text:match("^#%x%x%x%x%x%x$") then
        return {tonumber(text:sub(2, 3), 16), tonumber(text:sub(4, 5), 16), tonumber(text:sub(6, 7), 16)}
    elseif text:match("^#%x%x%x$") then
        return {17 * tonumber(text:sub(2, 2), 16), 17 * tonumber(text:sub(3, 3), 16), 17 * tonumber(text:sub(4, 4), 16)}
    end
    local r, g, b = text:match("^rgb%((%d+),(%d+),(%d+)%)$")
    if r then
        require_valid(#r <= 3 and #g <= 3 and #b <= 3)
        local color = {tonumber(r), tonumber(g), tonumber(b)}
        require_valid(color[1] <= 255 and color[2] <= 255 and color[3] <= 255)
        return color
    end
    for i, name in ipairs(builtin_names) do
        if text == name then
            return copy_color(builtin_colors[i])
        end
    end
    require_valid(registry.colors[text] ~= nil)
    return copy_color(registry.colors[text])
end

local function typed_arg(text, kind, registry)
    if kind == "c" then
        return parse_color(text, registry)
    elseif kind == "name" then
        require_valid(text:match("^[a-z]+$") ~= nil and #text <= 12)
        return text
    elseif kind == "code" then
        require_valid(text:match("^0x%x%x%x%x$") ~= nil)
        return tonumber(text:sub(3), 16)
    elseif keywords[kind] then
        require_valid(contains(keywords[kind], text))
        return text
    end
    local low, high = kind:match("^(%-?%d+):(%-?%d+)$")
    return integer_arg(text, tonumber(low), tonumber(high))
end

local function hue(color)
    local r, g, b = table.unpack(color)
    local high = math.max(r, g, b)
    local delta = high - math.min(r, g, b)
    if delta == 0 then
        return 0
    end
    local numerator
    if high == r then
        numerator = 60 * (g - b)
        if numerator < 0 then
            numerator = numerator + 360 * delta
        end
    elseif high == g then
        numerator = 60 * (b - r) + 120 * delta
    else
        numerator = 60 * (r - g) + 240 * delta
    end
    return round_ratio(numerator, delta) % 360
end

local function hsl(color)
    local high = math.max(table.unpack(color))
    local low = math.min(table.unpack(color))
    local delta = high - low
    local saturation = 0
    if delta ~= 0 then
        saturation = round_ratio(100 * delta, 255 - math.abs(high + low - 255))
    end
    return {hue(color), saturation, round_ratio(100 * (high + low), 510)}
end

local function base60(h)
    local sector = h // 60
    local fraction = h % 60
    local x = fraction
    if sector % 2 == 1 then
        x = 60 - fraction
    end
    local triples = {{60, x, 0}, {x, 60, 0}, {0, 60, x}, {0, x, 60}, {x, 0, 60}, {60, 0, x}}
    return triples[sector + 1]
end

local function from_hsl(h, s, l)
    local chroma = (100 - math.abs(2 * l - 100)) * s
    local offset = 6000 * l - 30 * chroma
    local result = {}
    for i, u in ipairs(base60(h)) do
        result[i] = round_ratio(255 * (u * chroma + offset), 600000)
    end
    return result
end

local function model_values(model, color)
    local r, g, b = table.unpack(color)
    local high = math.max(r, g, b)
    local low = math.min(r, g, b)
    if model == "HSL" then
        return hsl(color)
    elseif model == "HSV" then
        local saturation = 0
        if high ~= 0 then
            saturation = round_ratio(100 * (high - low), high)
        end
        return {hue(color), saturation, round_ratio(100 * high, 255)}
    elseif model == "HWB" then
        return {hue(color), round_ratio(100 * low, 255), round_ratio(100 * (255 - high), 255)}
    elseif model == "CMYK" then
        if high == 0 then
            return {0, 0, 0, 100}
        end
        return {
            round_ratio(100 * (high - r), high),
            round_ratio(100 * (high - g), high),
            round_ratio(100 * (high - b), high),
            round_ratio(100 * (255 - high), 255)
        }
    elseif model == "YCBCR" then
        return {
            byte_clamp(round_ratio(299 * r + 587 * g + 114 * b, 1000)),
            byte_clamp(round_ratio(128000 - 169 * r - 331 * g + 500 * b, 1000)),
            byte_clamp(round_ratio(128000 + 500 * r - 419 * g - 81 * b, 1000))
        }
    end
    return {
        round_ratio(299 * r + 587 * g + 114 * b, 1000),
        round_ratio(596 * r - 274 * g - 322 * b, 1000),
        round_ratio(211 * r - 523 * g + 312 * b, 1000)
    }
end

local function model_text(model, color)
    local values = model_values(model, color)
    if model == "HSL" or model == "HSV" or model == "HWB" then
        return string.format("%s(%d,%d%%,%d%%)", model:lower(), table.unpack(values))
    elseif model == "CMYK" then
        return string.format("cmyk(%d%%,%d%%,%d%%,%d%%)", table.unpack(values))
    end
    return string.format("%s(%d,%d,%d)", model:lower(), table.unpack(values))
end

local function ansi_color(number)
    if number < 16 then
        return copy_color(builtin_colors[number + 1])
    elseif number >= 232 then
        local value = 8 + 10 * (number - 232)
        return {value, value, value}
    end
    local value = number - 16
    local levels = {0, 95, 135, 175, 215, 255}
    return {levels[value // 36 + 1], levels[(value // 6) % 6 + 1], levels[value % 6 + 1]}
end

local function root_ratio(n, d)
    local low, high = 0, 1
    while d * high * high <= n do
        high = high * 2
    end
    while high - low > 1 do
        local middle = (low + high) // 2
        if d * middle * middle <= n then
            low = middle
        else
            high = middle
        end
    end
    return low
end

local function nearest_index(color, colors)
    local selected = 1
    for i = 2, #colors do
        if color_distance(color, colors[i]) < color_distance(color, colors[selected]) then
            selected = i
        end
    end
    return selected
end

local function contrast(a, b)
    local function luminance(color)
        return 2126 * color[1] * color[1] + 7152 * color[2] * color[2] + 722 * color[3] * color[3]
    end
    local y1, y2 = luminance(a), luminance(b)
    local high = math.max(y1, y2) + 32512500
    local low = math.min(y1, y2) + 32512500
    local verdict
    if high >= 7 * low then
        verdict = "AAA"
    elseif 2 * high >= 9 * low then
        verdict = "AA"
    else
        verdict = "FAIL"
    end
    return round_ratio(100 * high, low), verdict
end

local function contrast_text(a, b)
    local ratio, verdict = contrast(a, b)
    return string.format("%d.%02d %s", ratio // 100, ratio % 100, verdict)
end

local function gradient(a, b, n)
    local output = {}
    for i = 0, n - 1 do
        local color = {}
        for j = 1, 3 do
            color[j] = a[j] + away_ratio((b[j] - a[j]) * i, n - 1)
        end
        output[#output + 1] = color
    end
    return output
end

local function mean_color(colors)
    local total = {0, 0, 0}
    for _, color in ipairs(colors) do
        for j = 1, 3 do
            total[j] = total[j] + color[j]
        end
    end
    for j = 1, 3 do
        total[j] = round_ratio(total[j], #colors)
    end
    return total
end

local function widths(colors)
    local low = copy_color(colors[1])
    local high = copy_color(colors[1])
    for _, color in ipairs(colors) do
        for j = 1, 3 do
            low[j] = math.min(low[j], color[j])
            high[j] = math.max(high[j], color[j])
        end
    end
    return {high[1] - low[1], high[2] - low[2], high[3] - low[3]}
end

local function palette(colors, k)
    local boxes = {colors}
    while #boxes < k do
        local selected, best_width = 0, -1
        for i, box in ipairs(boxes) do
            if #box >= 2 then
                local width = math.max(table.unpack(widths(box)))
                if width > best_width then
                    selected, best_width = i, width
                end
            end
        end
        local box = boxes[selected]
        local ranges = widths(box)
        local axis = 1
        for j = 2, 3 do
            if ranges[j] > ranges[axis] then
                axis = j
            end
        end
        local indexed = {}
        for i, color in ipairs(box) do
            indexed[i] = {color = color, index = i}
        end
        table.sort(indexed, function(a, b)
            if a.color[axis] ~= b.color[axis] then
                return a.color[axis] < b.color[axis]
            end
            return a.index < b.index
        end)
        local left, right = {}, {}
        for i, entry in ipairs(indexed) do
            if i <= #box // 2 then
                left[#left + 1] = entry.color
            else
                right[#right + 1] = entry.color
            end
        end
        boxes[selected] = left
        table.insert(boxes, selected + 1, right)
    end
    return boxes
end

local function blend_component(mode, x, y)
    local multiply = (x * y) // 255
    local screen = 255 - ((255 - x) * (255 - y)) // 255
    if mode == "MULTIPLY" then
        return multiply
    elseif mode == "SCREEN" then
        return screen
    elseif mode == "OVERLAY" or mode == "HARDLIGHT" then
        local lower = x < 128
        if mode == "HARDLIGHT" then
            lower = y < 128
        end
        if lower then
            return (2 * x * y) // 255
        end
        return 255 - (2 * (255 - x) * (255 - y)) // 255
    elseif mode == "SOFTLIGHT" then
        return ((255 - x) * multiply + x * screen) // 255
    elseif mode == "DARKEN" then
        return math.min(x, y)
    elseif mode == "LIGHTEN" then
        return math.max(x, y)
    elseif mode == "DIFFERENCE" then
        return math.abs(x - y)
    elseif mode == "EXCLUSION" then
        return x + y - (2 * x * y) // 255
    elseif mode == "ADD" then
        return math.min(255, x + y)
    elseif mode == "SUBTRACT" then
        return math.max(0, x - y)
    elseif mode == "COLORDODGE" then
        if y == 255 then
            return 255
        end
        return math.min(255, (255 * x) // (255 - y))
    end
    if y == 0 then
        return 0
    end
    return math.max(0, 255 - (255 * (255 - x)) // y)
end

local function execute(command, raw, registry)
    local args = {}
    if command == "PALETTE" or command == "KMEANS" then
        require_valid(#raw >= 2 and #raw <= 33)
        args[1] = integer_arg(raw[1], 1, #raw - 1)
        args[2] = {}
        for i = 2, #raw do
            args[2][#args[2] + 1] = parse_color(raw[i], registry)
        end
    elseif command == "BEST" or command == "SORT" or command == "DITHER" then
        local minimum, maximum = 1, 32
        if command == "BEST" then
            minimum, maximum = 2, 33
        end
        require_valid(#raw >= minimum and #raw <= maximum)
        args[1] = {}
        for i, token in ipairs(raw) do
            args[1][i] = parse_color(token, registry)
        end
    else
        require_valid(signatures[command] ~= nil)
        local kinds = words(signatures[command])
        require_valid(#raw == #kinds)
        for i, token in ipairs(raw) do
            args[i] = typed_arg(token, kinds[i], registry)
        end
    end
    if command == "DEFINE" then
        local name, color = table.unpack(args)
        require_valid(not contains(builtin_names, name))
        if registry.colors[name] == nil then
            registry.order[#registry.order + 1] = name
        end
        registry.colors[name] = copy_color(color)
        return name .. " " .. hex_color(color)
    elseif command == "UNDEFINE" then
        local name = args[1]
        require_valid(registry.colors[name] ~= nil)
        registry.colors[name] = nil
        for i, other in ipairs(registry.order) do
            if other == name then
                table.remove(registry.order, i)
                break
            end
        end
        return name .. " removed"
    elseif command == "LIST" then
        if #registry.order == 0 then
            return "NONE"
        end
        local names, output = {table.unpack(registry.order)}, {}
        table.sort(names)
        for i, name in ipairs(names) do
            output[i] = name .. "=" .. hex_color(registry.colors[name])
        end
        return table.concat(output, " ")
    elseif command == "PARSE" or command == "NEAREST" then
        local color = args[1]
        local names, colors = {table.unpack(builtin_names)}, {table.unpack(builtin_colors)}
        for _, name in ipairs(registry.order) do
            names[#names + 1] = name
            colors[#colors + 1] = registry.colors[name]
        end
        if command == "NEAREST" then
            local i = nearest_index(color, colors)
            return string.format("%s %s %d", names[i], hex_color(colors[i]), color_distance(color, colors[i]))
        end
        local exact = "-"
        for i, other in ipairs(colors) do
            if color_distance(color, other) == 0 then
                exact = names[i]
                break
            end
        end
        local output = {hex_color(color), string.format("rgb(%d,%d,%d)", table.unpack(color))}
        for _, model in ipairs(words("HSL HSV HWB CMYK YCBCR YIQ")) do
            output[#output + 1] = model_text(model, color)
        end
        output[#output + 1] = exact
        return table.concat(output, " ")
    elseif contains(words("HSL HSV HWB CMYK YCBCR YIQ"), command) then
        return model_text(command, args[1])
    end
    local result
    if command == "FROMHSL" then
        result = from_hsl(table.unpack(args))
    elseif command == "FROMHSV" then
        local h, s, v = table.unpack(args)
        local chroma = v * s
        result = {}
        for i, u in ipairs(base60(h)) do
            result[i] = round_ratio(255 * (u * chroma + 6000 * v - 60 * chroma), 600000)
        end
    elseif command == "FROMHWB" then
        local h, w, k = table.unpack(args)
        result = {}
        if w + k >= 100 then
            local value = round_ratio(255 * w, w + k)
            result = {value, value, value}
        else
            for i, u in ipairs(base60(h)) do
                result[i] = round_ratio(255 * (u * (100 - w - k) + 60 * w), 6000)
            end
        end
    elseif command == "FROMCMYK" then
        result = {}
        for i = 1, 3 do
            result[i] = round_ratio(255 * (100 - args[i]) * (100 - args[4]), 10000)
        end
    elseif command == "FROMYCBCR" then
        local y, cb, cr = table.unpack(args)
        result = {
            byte_clamp(round_ratio(1000 * y + 1402 * (cr - 128), 1000)),
            byte_clamp(round_ratio(1000 * y - 344 * (cb - 128) - 714 * (cr - 128), 1000)),
            byte_clamp(round_ratio(1000 * y + 1772 * (cb - 128), 1000))
        }
    elseif command == "FROMYIQ" then
        local y, i, q = table.unpack(args)
        result = {
            byte_clamp(round_ratio(1000 * y + 956 * i + 619 * q, 1000)),
            byte_clamp(round_ratio(1000 * y - 272 * i - 647 * q, 1000)),
            byte_clamp(round_ratio(1000 * y - 1106 * i + 1703 * q, 1000))
        }
    elseif command == "RGB565" then
        local r, g, b = table.unpack(args[1])
        local value = 2048 * round_ratio(31 * r, 255) + 32 * round_ratio(63 * g, 255) + round_ratio(31 * b, 255)
        return string.format("0x%04X", value)
    elseif command == "FROM565" then
        local value = args[1]
        result = {round_ratio(255 * (value // 2048), 31), round_ratio(255 * ((value // 32) % 64), 63), round_ratio(255 * (value % 32), 31)}
    elseif command == "ANSI" then
        local colors = {}
        for number = 16, 255 do
            colors[#colors + 1] = ansi_color(number)
        end
        local i = nearest_index(args[1], colors)
        return string.format("%d %s %d", i + 15, hex_color(colors[i]), color_distance(args[1], colors[i]))
    elseif command == "FROMANSI" then
        result = ansi_color(args[1])
    elseif command == "WEBSAFE" then
        result = {}
        for i, x in ipairs(args[1]) do
            result[i] = 51 * round_ratio(x, 51)
        end
    elseif command == "GRAY" then
        local color, method = table.unpack(args)
        local r, g, b = table.unpack(color)
        local value
        if method == "LUMA" then
            value = round_ratio(299 * r + 587 * g + 114 * b, 1000)
        elseif method == "AVERAGE" then
            value = round_ratio(r + g + b, 3)
        elseif method == "LIGHTNESS" then
            value = round_ratio(math.max(r, g, b) + math.min(r, g, b), 2)
        else
            value = root_ratio(299 * r * r + 587 * g * g + 114 * b * b, 1000)
        end
        result = {value, value, value}
    elseif command == "INVERT" then
        result = {}
        for i, x in ipairs(args[1]) do
            result[i] = 255 - x
        end
    elseif command == "MIX" then
        local a, b, p = table.unpack(args)
        result = {}
        for i = 1, 3 do
            result[i] = round_ratio(a[i] * (100 - p) + b[i] * p, 100)
        end
    elseif command == "MIXHSL" then
        local a, b, p = table.unpack(args)
        local h1, s1, l1 = table.unpack(hsl(a))
        local h2, s2, l2 = table.unpack(hsl(b))
        local delta = (h2 - h1) % 360
        if delta > 180 then
            delta = delta - 360
        end
        result = from_hsl((h1 + away_ratio(delta * p, 100)) % 360,
            s1 + away_ratio((s2 - s1) * p, 100), l1 + away_ratio((l2 - l1) * p, 100))
    elseif command == "GRADIENT" then
        return color_sequence(gradient(table.unpack(args)))
    elseif command == "TINTS" or command == "SHADES" or command == "TONES" then
        local value = ({TINTS = 255, SHADES = 0, TONES = 128})[command]
        local colors = gradient(args[1], {value, value, value}, args[2] + 2)
        table.remove(colors)
        table.remove(colors, 1)
        return color_sequence(colors)
    elseif command == "BLEND" then
        local mode, a, b = table.unpack(args)
        if contains(words("HUE SATURATION COLOR LUMINOSITY"), mode) then
            local h1, s1, l1 = table.unpack(hsl(a))
            local h2, s2, l2 = table.unpack(hsl(b))
            if mode == "HUE" then
                result = from_hsl(h2, s1, l1)
            elseif mode == "SATURATION" then
                result = from_hsl(h1, s2, l1)
            elseif mode == "COLOR" then
                result = from_hsl(h2, s2, l1)
            else
                result = from_hsl(h1, s1, l2)
            end
        else
            result = {}
            for i = 1, 3 do
                result[i] = blend_component(mode, a[i], b[i])
            end
        end
    elseif command == "ALPHA" then
        local a, p, b, q = table.unpack(args)
        local opacity = 100 * p + q * (100 - p)
        result = {0, 0, 0}
        if opacity > 0 then
            for i = 1, 3 do
                result[i] = round_ratio(100 * p * a[i] + q * (100 - p) * b[i], opacity)
            end
        end
        return string.format("%s %d%%", hex_color(result), round_ratio(opacity, 100))
    elseif command == "SIMULATE" then
        local color, kind = table.unpack(args)
        local matrices = {
            PROTANOPIA = {{567, 433, 0}, {558, 442, 0}, {0, 242, 758}},
            DEUTERANOPIA = {{625, 375, 0}, {700, 300, 0}, {0, 300, 700}},
            TRITANOPIA = {{950, 50, 0}, {0, 433, 567}, {0, 475, 525}},
            ACHROMATOPSIA = {{299, 587, 114}, {299, 587, 114}, {299, 587, 114}}
        }
        result = {}
        for i, row in ipairs(matrices[kind]) do
            result[i] = round_ratio(row[1] * color[1] + row[2] * color[2] + row[3] * color[3], 1000)
        end
    elseif contains(words("ROTATE COMPLEMENT TRIADIC TETRADIC SPLITCOMP ANALOGOUS"), command) then
        local h, s, l = table.unpack(hsl(args[1]))
        local offsets
        if command == "ROTATE" then
            offsets = {args[2]}
        elseif command == "ANALOGOUS" then
            offsets = {}
            for i = -args[2], args[2] do
                if i ~= 0 then
                    offsets[#offsets + 1] = i * args[3]
                end
            end
        else
            offsets = ({COMPLEMENT = {180}, TRIADIC = {120, 240}, TETRADIC = {90, 180, 270}, SPLITCOMP = {150, 210}})[command]
        end
        local output = {}
        for i, d in ipairs(offsets) do
            output[i] = from_hsl((h + d) % 360, s, l)
        end
        return color_sequence(output)
    elseif contains(words("LIGHTEN DARKEN SATURATE DESATURATE"), command) then
        local h, s, l = table.unpack(hsl(args[1]))
        local p = args[2]
        if command == "LIGHTEN" then
            l = math.min(100, l + p)
        elseif command == "DARKEN" then
            l = math.max(0, l - p)
        elseif command == "SATURATE" then
            s = math.min(100, s + p)
        else
            s = math.max(0, s - p)
        end
        result = from_hsl(h, s, l)
    elseif command == "DISTANCE" then
        local a, b = table.unpack(args)
        local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
        local weighted = (1024 + a[1] + b[1]) * dr * dr + 2048 * dg * dg + (1534 - a[1] - b[1]) * db * db
        return string.format("%d %d", color_distance(a, b), root_ratio(weighted, 512))
    elseif command == "CONTRAST" then
        return contrast_text(table.unpack(args))
    elseif command == "ACCESSIBLE" then
        local bg = args[2]
        result = args[1]
        local _, verdict = contrast(result, bg)
        if verdict == "FAIL" then
            local h, s, l = table.unpack(hsl(result))
            local found = false
            for step = 1, 100 do
                for _, lightness in ipairs({l - step, l + step}) do
                    if lightness >= 0 and lightness <= 100 then
                        local candidate = from_hsl(h, s, lightness)
                        local _, candidate_verdict = contrast(candidate, bg)
                        if candidate_verdict ~= "FAIL" then
                            result = candidate
                            found = true
                            break
                        end
                    end
                end
                if found then
                    break
                end
            end
        end
        return hex_color(result) .. " " .. contrast_text(result, bg)
    elseif command == "BEST" then
        local colors = args[1]
        local bg = colors[1]
        local selected = 2
        for i = 3, #colors do
            if contrast(colors[i], bg) > contrast(colors[selected], bg) then
                selected = i
            end
        end
        return hex_color(colors[selected]) .. " " .. contrast_text(colors[selected], bg)
    elseif command == "DESCRIBE" then
        local h, s, l = table.unpack(hsl(args[1]))
        if l <= 5 then
            return "black"
        elseif l >= 95 then
            return "white"
        end
        local lightness
        if l <= 20 then
            lightness = "very dark"
        elseif l <= 40 then
            lightness = "dark"
        elseif l <= 60 then
            lightness = "medium"
        elseif l <= 80 then
            lightness = "light"
        else
            lightness = "very light"
        end
        if s < 10 then
            return lightness .. " gray"
        end
        local saturation
        if s < 40 then
            saturation = "muted"
        elseif s < 80 then
            saturation = "moderate"
        else
            saturation = "vivid"
        end
        local names = words("red orange yellow chartreuse green spring-green cyan azure blue violet magenta rose")
        return lightness .. " " .. saturation .. " " .. names[((h + 15) % 360) // 30 + 1]
    elseif command == "PALETTE" or command == "KMEANS" then
        local k, colors = table.unpack(args)
        local boxes = palette(colors, k)
        local representatives, counts = {}, {}
        for j, box in ipairs(boxes) do
            representatives[j] = mean_color(box)
            counts[j] = #box
        end
        local iterations = 0
        if command == "KMEANS" then
            for iteration = 1, 20 do
                local assigned = {}
                for j = 1, k do
                    assigned[j] = {}
                end
                for _, color in ipairs(colors) do
                    local j = nearest_index(color, representatives)
                    assigned[j][#assigned[j] + 1] = color
                end
                local updated = {}
                local unchanged = true
                for j = 1, k do
                    counts[j] = #assigned[j]
                    if counts[j] == 0 then
                        updated[j] = representatives[j]
                    else
                        updated[j] = mean_color(assigned[j])
                    end
                    if color_distance(updated[j], representatives[j]) ~= 0 then
                        unchanged = false
                    end
                end
                representatives = updated
                iterations = iteration
                if unchanged then
                    break
                end
            end
        end
        local output = {}
        for j = 1, k do
            output[j] = hex_color(representatives[j]) .. ":" .. counts[j]
        end
        if command == "KMEANS" then
            return iterations .. " " .. table.concat(output, " ")
        end
        return table.concat(output, " ")
    elseif command == "SORT" then
        local indexed = {}
        for i, color in ipairs(args[1]) do
            indexed[i] = {color = color, value = hsl(color), index = i}
        end
        table.sort(indexed, function(a, b)
            for j = 1, 3 do
                if a.value[j] ~= b.value[j] then
                    return a.value[j] < b.value[j]
                end
            end
            return a.index < b.index
        end)
        local output = {}
        for i, entry in ipairs(indexed) do
            output[i] = entry.color
        end
        return color_sequence(output)
    elseif command == "DITHER" then
        local error_color = {0, 0, 0}
        local colors, output = {table.unpack(builtin_colors,1,16)}, {}
        for _, color in ipairs(args[1]) do
            local adjusted = {}
            for j = 1, 3 do
                adjusted[j] = byte_clamp(color[j] + error_color[j])
            end
            local selected = nearest_index(adjusted, colors)
            output[#output + 1] = builtin_names[selected]
            for j = 1, 3 do
                error_color[j] = adjusted[j] - colors[selected][j]
            end
        end
        return table.concat(output, " ")
    elseif command == "RANDOM" then
        local state, n = table.unpack(args)
        local output = {}
        for i = 1, n do
            state = (48271 * state) % 2147483647
            local u = state
            state = (48271 * state) % 2147483647
            local v = state
            state = (48271 * state) % 2147483647
            output[i] = from_hsl(u % 360, 40 + v % 61, 25 + state % 51)
        end
        return color_sequence(output)
    end
    return hex_color(result)
end

local count = tonumber(io.read("l"))
local registry = {colors = {}, order = {}}
for i = 1, count do
    local parts = words(io.read("l"))
    local command = table.remove(parts, 1)
    local valid, output = pcall(execute, command, parts, registry)
    if valid then
        io.write(output, "\n")
    else
        io.write("INVALID\n")
    end
end
