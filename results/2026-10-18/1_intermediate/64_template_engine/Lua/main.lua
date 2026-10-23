local ABSENT = {}

local function list(items)
  return { kind = "list", items = items or {} }
end

local function map(items)
  return { kind = "map", items = items or {} }
end

local function kind(v)
  if v == ABSENT then
    return "absent"
  end
  return type(v) == "table" and v.kind or type(v)
end

local function trim(s)
  return (s:gsub("^ +", ""):gsub(" +$", ""))
end

local function starts(s, p)
  return s:sub(1, #p) == p
end

local function split(s, separator)
  local out, at = {}, 1
  while true do
    local p = s:find(separator, at, true)
    if not p then
      out[#out + 1] = s:sub(at)
      return out
    end
    out[#out + 1] = s:sub(at, p - 1)
    at = p + #separator
  end
end

local function identifier(s)
  return s:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function subscript(s)
  return s == "0" or s:match("^[1-9][0-9]*$") ~= nil
end

local function numeric_text(s)
  local digits = s:gsub("^-", "")
  return #digits >= 1 and #digits <= 9 and digits:match("^[0-9]+$") ~= nil
end

local function valid_name(s)
  if s == "." or s == "@index" or s == "@number" or s == "@first" or s == "@last" then
    return true
  end
  for _, p in ipairs(split(s, ".")) do
    if not identifier(p) and not subscript(p) then
      return false
    end
  end
  return true
end

local function fail(number, reason)
  error({ number = number, reason = reason }, 0)
end

local function bad(reason)
  error(reason, 0)
end

local function keys(m)
  local result = {}
  for k in pairs(m) do
    result[#result + 1] = k
  end
  table.sort(result)
  return result
end

local function key_parts(key)
  local parts, pos = {}, 1
  while pos <= #key do
    local p
    if pos > 1 and key:sub(pos, pos) == "[" then
      local close = key:find("]", pos + 1, true)
      if not close or not subscript(key:sub(pos + 1, close - 1)) then
        bad("bad key '" .. key .. "'")
      end
      p = tonumber(key:sub(pos + 1, close - 1))
      pos = close + 1
    else
      if pos > 1 then
        if key:sub(pos, pos) ~= "." then
          bad("bad key '" .. key .. "'")
        end
        pos = pos + 1
      end
      local name = key:match("^([A-Za-z_][A-Za-z0-9_]*)", pos)
      if not name then
        bad("bad key '" .. key .. "'")
      end
      p, pos = name, pos + #name
    end
    parts[#parts + 1] = { part = p, prefix = key:sub(1, pos - 1) }
  end
  if #parts == 0 then
    bad("bad key '" .. key .. "'")
  end
  return parts
end

local function scalar(s, pos)
  if s:sub(pos, pos) == '"' then
    local chars = {}
    pos = pos + 1
    while pos <= #s do
      local c = s:sub(pos, pos)
      pos = pos + 1
      if c == '"' then
        return table.concat(chars), pos
      end
      if c == "\\" then
        local escapes = { n = "\n", ['"'] = '"', ["\\"] = "\\" }
        c = escapes[s:sub(pos, pos)]
        if not c then
          bad("invalid")
        end
        pos = pos + 1
      end
      chars[#chars + 1] = c
    end
    bad("invalid")
  end
  local stop = pos
  while stop <= #s and s:sub(stop, stop) ~= "," and s:sub(stop, stop) ~= "]" do
    stop = stop + 1
  end
  local word = s:sub(pos, stop - 1)
  if word == "true" then
    return true, stop
  end
  if word == "false" then
    return false, stop
  end
  if word == "0" or word:match("^%-?[1-9][0-9]*$") then
    return tonumber(word), stop
  end
  bad("invalid")
end

local function parse_value(s)
  local ok, value = pcall(function ()
    if s == "[]" then
      return list()
    end
    if s == "{}" then
      return map()
    end
    if starts(s, "[") then
      local items, pos = {}, 2
      while true do
        local v
        v, pos = scalar(s, pos)
        items[#items + 1] = v
        if s:sub(pos) == "]" then
          return list(items)
        end
        if s:sub(pos, pos + 1) ~= ", " then
          bad("invalid")
        end
        pos = pos + 2
      end
    end
    local v, stop = scalar(s, 1)
    if stop ~= #s + 1 then
      bad("invalid")
    end
    return v
  end)
  if not ok then
    bad("bad value '" .. s .. "'")
  end
  return value
end

local function get(v, p)
  if type(p) == "number" and kind(v) == "list" and p < #v.items then
    return v.items[p + 1], true
  end
  if type(p) == "string" and kind(v) == "map" and v.items[p] ~= nil then
    return v.items[p], true
  end
  return ABSENT, false
end

local function change(v, parts, at, new_value, remove, key)
  local p, prefix = parts[at].part, parts[at].prefix
  local child, exists = get(v, p)
  if remove and not exists then
    bad("no value at '" .. key .. "'")
  end
  if not remove and type(p) == "number" and p > #v.items then
    bad("index gap at '" .. prefix .. "'")
  end
  if at < #parts then
    if not remove then
      local required = type(parts[at + 1].part) == "number" and "list" or "map"
      if not exists then
        child = required == "list" and list() or map()
      elseif kind(child) ~= required then
        bad("type conflict at '" .. prefix .. "'")
      end
    end
    new_value = change(child, parts, at + 1, new_value, remove, key)
  end
  local out = {}
  for k, x in pairs(v.items) do
    out[k] = x
  end
  if kind(v) == "list" then
    if at == #parts and remove then
      table.remove(out, p + 1)
    else
      out[p + 1] = new_value
    end
    return list(out)
  end
  if at == #parts and remove then
    out[p] = nil
  else
    out[p] = new_value
  end
  return map(out)
end

local function split_quoted(s, separator)
  local out, start, quoted = {}, 1, false
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "'" then
      quoted = not quoted
    elseif c == separator and not quoted then
      out[#out + 1] = s:sub(start, i - 1)
      start = i + 1
    end
  end
  out[#out + 1] = s:sub(start)
  return out
end
local FILTERS = {}
for name in("upper lower title trim length first last reverse items comma sum min max default eq pad lpad truncate replace join sort pluck add sub mul div mod gt lt"):gmatch("%S+") do
  FILTERS[name] = true
end

local function parse_expression(s, number)
  local pieces = split_quoted(s, "|")
  local expression = { name = trim(pieces[1]), filters = {} }
  if not valid_name(expression.name) then
    fail(number, "invalid name '" .. expression.name .. "'")
  end
  for i = 2, #pieces do
    local fields = split_quoted(trim(pieces[i]), ":")
    local name, args, valid = fields[1], {}, true
    if not FILTERS[name] then
      fail(number, "unknown filter '" .. name .. "'")
    end
    for j = 2, #fields do
      local a = fields[j]
      if #a >= 2 and a:sub(1, 1) == "'" and a:sub(- 1) == "'" and not a:sub(2, - 2):find("'", 1, true) then
        args[#args + 1] = a:sub(2, - 2)
      elseif numeric_text(a) then
        args[#args + 1] = tonumber(a)
      else
        valid = false
      end
    end
    local n = #args
    if name == "default" or name == "eq" then
      valid = valid and n == 1
    elseif name == "pad" or name == "lpad" then
      valid = valid and (n == 1 or n == 2) and type(args[1]) == "number" and args[1] >= 0 and (n == 1 or type(args[2]) == "string" and #args[2] == 1)
    elseif name == "truncate" then
      valid = valid and n == 1 and type(args[1]) == "number" and args[1] >= 0
    elseif name == "replace" then
      valid = valid and n == 2 and type(args[1]) == "string" and args[1] ~= "" and type(args[2]) == "string"
    elseif name == "join" or name == "pluck" then
      valid = valid and n == 1 and type(args[1]) == "string"
    elseif name == "sort" then
      valid = valid and (n == 0 or n == 1 and type(args[1]) == "string")
    elseif name == "div" or name == "mod" then
      valid = valid and n == 1 and type(args[1]) == "number" and args[1] ~= 0
    elseif name == "add" or name == "sub" or name == "mul" or name == "gt" or name == "lt" then
      valid = valid and n == 1 and type(args[1]) == "number"
    else
      valid = valid and n == 0
    end
    if not valid then
      fail(number, "bad arguments for '" .. name .. "'")
    end
    expression.filters[#expression.filters + 1] = { name = name, args = args }
  end
  return expression
end
local STANDALONE = { ["#"] = true, ["^"] = true, ["/"] = true, ["!"] = true, [">"] = true, ["="] = true }

local function parse_source(lines)
  local root, opens = {}, {}
  local targets = { root }
  local opening, closing = "{{", "}}"
  for _, line in ipairs(lines) do
    local tokens, pos, count, spaces, only_tag = {}, 1, 0, true, nil
    while true do
      local start = line.text:find(opening, pos, true)
      local text = line.text:sub(pos, start and start - 1 or #line.text)
      tokens[#tokens + 1] = text
      spaces = spaces and trim(text) == ""
      if not start then
        break
      end
      local after, close = start + #opening, closing
      local triple = line.text:sub(after, after) == "{"
      if triple then
        after = after + 1
        close = "}" .. closing
      end
      local stop = line.text:find(close, after, true)
      if not stop then
        fail(line.number, "unclosed tag")
      end
      pos = stop + #close
      local content = trim(line.text:sub(after, stop - 1))
      local tag = { kind = "v", text = content, number = line.number, children = {}, indent = "" }
      if triple then
        tag.kind = "&"
      elseif #content > 0 and ("#^/!>&="):find(content:sub(1, 1), 1, true) then
        tag.kind = content:sub(1, 1)
        if tag.kind ~= "=" then
          tag.text = trim(content:sub(2))
        end
      end
      if tag.kind == "=" then
        local ds = {}
        if #content >= 2 and content:sub(- 1) == "=" then
          for x in content:sub(2, - 2):gmatch("[^ ]+") do
            ds[#ds + 1] = x
          end
        end
        if #ds ~= 2 or ds[1]:find("=", 1, true) or ds[2]:find("=", 1, true) then
          fail(line.number, "invalid delimiters")
        end
        opening, closing = ds[1], ds[2]
      elseif tag.kind == "v" or tag.kind == "&" or tag.kind == "#" or tag.kind == "^" then
        tag.expression = parse_expression(tag.text, line.number)
        if tag.kind == "#" or tag.kind == "^" then
          opens[#opens + 1] = tag
        end
      elseif tag.kind == "/" then
        if not valid_name(tag.text) then
          fail(line.number, "invalid name '" .. tag.text .. "'")
        end
        if #opens == 0 then
          fail(line.number, "unexpected closing '" .. tag.text .. "'")
        end
        local expected = opens[#opens].expression.name
        if tag.text ~= expected then
          fail(line.number, "mismatched closing '" .. tag.text .. "', expected '" .. expected .. "'")
        end
        opens[#opens] = nil
      elseif tag.kind == ">" and not identifier(tag.text) then
        fail(line.number, "invalid name '" .. tag.text .. "'")
      end
      tokens[#tokens + 1] = tag
      count, only_tag = count + 1, tag
    end
    if count == 1 and spaces and STANDALONE[only_tag.kind] then
      if only_tag.kind == ">" then
        only_tag.indent = tokens[1]
      end
      tokens = { only_tag }
    else
      tokens[#tokens + 1] = "\n"
    end
    for _, token in ipairs(tokens) do
      local target = targets[#targets]
      if type(token) == "string" then
        target[#target + 1] = token
      elseif token.kind == "#" or token.kind == "^" then
        target[#target + 1] = token
        targets[#targets + 1] = token.children
      elseif token.kind == "/" then
        targets[#targets] = nil
      elseif token.kind ~= "!" and token.kind ~= "=" then
        target[#target + 1] = token
      end
    end
  end
  if #opens > 0 then
    local tag = opens[#opens]
    fail(tag.number, "unclosed section '" .. tag.expression.name .. "'")
  end
  return root
end

local function truth(v)
  local k = kind(v)
  if k == "absent" then
    return false
  end
  if k == "boolean" then
    return v
  end
  if k == "number" then
    return v ~= 0
  end
  if k == "string" then
    return v ~= ""
  end
  return next(v.items) ~= nil
end
local stringify
stringify = function (v)
  local k = kind(v)
  if k == "absent" then
    return ""
  end
  if k == "string" then
    return v
  end
  if k == "number" then
    return string.format("%.0f", v)
  end
  if k == "boolean" then
    return v and "true" or "false"
  end
  if k == "map" then
    bad("cannot render map")
  end
  local out = {}
  for i, x in ipairs(v.items) do
    out[i] = stringify(x)
  end
  return table.concat(out, ", ")
end

local function number(v, name)
  if v == ABSENT then
    return 0
  end
  if type(v) == "number" then
    return v
  end
  if type(v) == "string" and numeric_text(v) then
    return tonumber(v)
  end
  bad("not a number for '" .. name .. "'")
end

local function field(v, key)
  if kind(v) == "map" and v.items[key] ~= nil then
    return v.items[key]
  end
  return ABSENT
end
local RANK = { absent = 0, number = 1, string = 2, boolean = 3, list = 4, map = 4 }

local function less(a, b)
  local ka, kb = kind(a), kind(b)
  if RANK[ka] ~= RANK[kb] then
    return RANK[ka] < RANK[kb]
  end
  if ka == "number" or ka == "string" then
    return a < b
  end
  if ka == "boolean" then
    return not a and b
  end
  return false
end

local function apply(f, v)
  local name, args, k = f.name, f.args, kind(v)
  if name == "default" then
    if not truth(v) then
      return args[1]
    end
    return v
  elseif name == "length" then
    if k == "list" then
      return #v.items
    elseif k == "map" then
      return #keys(v.items)
    end
  elseif name == "first" or name == "last" then
    if k ~= "list" then
      return v
    end
    if #v.items == 0 then
      return ABSENT
    end
    return v.items[name == "first" and 1 or #v.items]
  elseif name == "reverse" then
    if k == "string" then
      return v:reverse()
    end
    if k ~= "list" then
      return v
    end
    local out = {}
    for i = #v.items, 1, - 1 do
      out[#out + 1] = v.items[i]
    end
    return list(out)
  elseif name == "items" then
    if k ~= "map" then
      return v
    end
    local out = {}
    for _, key in ipairs(keys(v.items)) do
      out[#out + 1] = map({ key = key, value = v.items[key] })
    end
    return list(out)
  elseif name == "sort" or name == "pluck" then
    if k ~= "list" then
      return v
    end
    local out = {}
    if name == "pluck" then
      for i, x in ipairs(v.items) do
        out[i] = field(x, args[1])
      end
    else
      local entries = {}
      for i, x in ipairs(v.items) do
        local sort_key = x
        if #args > 0 then
          sort_key = field(x, args[1])
        end
        entries[i] = { value = x, key = sort_key, index = i }
      end
      table.sort(entries, function (a, b)
        if less(a.key, b.key) then
          return true
        end
        if less(b.key, a.key) then
          return false
        end
        return a.index < b.index
      end)
      for i, entry in ipairs(entries) do
        out[i] = entry.value
      end
    end
    return list(out)
  elseif name == "sum" or name == "min" or name == "max" then
    if k ~= "list" then
      return number(v, name)
    end
    if #v.items == 0 and name ~= "sum" then
      return ABSENT
    end
    local result = 0
    for i, x in ipairs(v.items) do
      local n = number(x, name)
      if name == "sum" then
        result = result + n
      elseif i == 1 or name == "min" and n < result or name == "max" and n > result then
        result = n
      end
    end
    return result
  elseif name == "comma" or name == "add" or name == "sub" or name == "mul" or name == "div" or name == "mod" or name == "gt" or name == "lt" then
    local n = number(v, name)
    if name == "add" then
      return n + args[1]
    elseif name == "sub" then
      return n - args[1]
    elseif name == "mul" then
      return n * args[1]
    elseif name == "div" then
      return math.floor(n / args[1])
    elseif name == "mod" then
      return n - args[1] * math.floor(n / args[1])
    elseif name == "gt" then
      return n > args[1]
    elseif name == "lt" then
      return n < args[1]
    end
    local text, sign = string.format("%.0f", math.abs(n)), n < 0 and "-" or ""
    text = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. text
  elseif name == "join" and k == "list" then
    local out = {}
    for i, x in ipairs(v.items) do
      out[i] = stringify(x)
    end
    return table.concat(out, args[1])
  end
  local s = stringify(v)
  if name == "upper" then
    return s:upper()
  elseif name == "lower" then
    return s:lower()
  elseif name == "title" then
    local out = {}
    for i = 1, #s do
      local c = s:sub(i, i)
      out[i] =(i == 1 or s:sub(i - 1, i - 1) == " ") and c:upper() or c:lower()
    end
    return table.concat(out)
  elseif name == "trim" then
    return trim(s)
  elseif name == "length" then
    return #s
  elseif name == "eq" then
    return s == stringify(args[1])
  elseif name == "pad" or name == "lpad" then
    local fill =(args[2] or " "):rep(math.max(0, args[1] - #s))
    return name == "pad" and s .. fill or fill .. s
  elseif name == "truncate" then
    return #s > args[1] and s:sub(1, args[1]) .. "..." or s
  elseif name == "replace" then
    local out, at = {}, 1
    while true do
      local p = s:find(args[1], at, true)
      if not p then
        out[#out + 1] = s:sub(at)
        break
      end
      out[#out + 1] = s:sub(at, p - 1)
      out[#out + 1] = args[2]
      at = p + #args[1]
    end
    return table.concat(out)
  elseif name == "join" then
    return s
  end
  return v
end
local ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }

local function render(nodes, root, partials, strict)
  local contexts, loops, out = { root }, {}, {}
  local function resolve(name)
    if name == "." then
      return contexts[#contexts], true
    end
    if starts(name, "@") then
      local loop = loops[#loops]
      if not loop then
        return ABSENT, false
      end
      if name == "@index" then
        return loop.index, true
      elseif name == "@number" then
        return loop.index + 1, true
      elseif name == "@first" then
        return loop.index == 0, true
      else
        return loop.index == loop.count - 1, true
      end
    end
    local parts = split(name, ".")
    for i, p in ipairs(parts) do
      if subscript(p) then
        parts[i] = tonumber(p)
      end
    end
    for i = #contexts, 1, - 1 do
      local _, exists = get(contexts[i], parts[1])
      if exists then
        local v = contexts[i]
        for _, p in ipairs(parts) do
          v, exists = get(v, p)
          if not exists then
            return ABSENT, false
          end
        end
        return v, true
      end
    end
    return ABSENT, false
  end
  local function evaluate(expression, check)
    local v, found = resolve(expression.name)
    if check and not found then
      bad("missing '" .. expression.name .. "'")
    end
    for _, f in ipairs(expression.filters) do
      v = apply(f, v)
    end
    return v
  end
  local visit
  visit = function (content, depth)
    for _, tag in ipairs(content) do
      if type(tag) == "string" then
        out[#out + 1] = tag
      else
        local ok, err = pcall(function ()
          if tag.kind == "v" or tag.kind == "&" then
            local s = stringify(evaluate(tag.expression, strict))
            out[#out + 1] = tag.kind == "v" and s:gsub("[&<>\"']", ESCAPES) or s
          elseif tag.kind == "#" or tag.kind == "^" then
            local v = evaluate(tag.expression, false)
            if tag.kind == "^" then
              if not truth(v) then
                visit(tag.children, depth)
              end
            elseif kind(v) == "list" then
              for i, x in ipairs(v.items) do
                contexts[#contexts + 1] = x
                loops[#loops + 1] = { index = i - 1, count = #v.items }
                visit(tag.children, depth)
                contexts[#contexts], loops[#loops] = nil, nil
              end
            elseif truth(v) then
              contexts[#contexts + 1] = v
              visit(tag.children, depth)
              contexts[#contexts] = nil
            end
          elseif tag.kind == ">" then
            local body = partials[tag.text]
            if not body then
              bad("unknown partial '" .. tag.text .. "'")
            end
            if depth == 8 then
              bad("partial depth exceeded at '" .. tag.text .. "'")
            end
            local source = {}
            for i, line in ipairs(body) do
              source[i] = { number = line.number, text = line.text ~= "" and tag.indent .. line.text or "" }
            end
            visit(parse_source(source), depth + 1)
          end
        end)
        if not ok then
          if type(err) == "table" then
            error(err, 0)
          end
          fail(tag.number, err)
        end
      end
    end
  end
  visit(nodes, 0)
  return table.concat(out)
end

local function notation(v)
  if type(v) == "string" then
    return '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
  end
  if kind(v) == "list" then
    return "[]"
  elseif kind(v) == "map" then
    return "{}"
  end
  return stringify(v)
end

local function collect(v, path, out)
  if kind(v) == "map" and next(v.items) then
    for _, k in ipairs(keys(v.items)) do
      collect(v.items[k], path == "" and k or path .. "." .. k, out)
    end
  elseif kind(v) == "list" and #v.items > 0 then
    for i, x in ipairs(v.items) do
      collect(x, path .. "[" ..(i - 1) .. "]", out)
    end
  elseif path ~= "" then
    out[#out + 1] = path .. " = " .. notation(v)
  end
end
local lines = {}
for line in io.lines() do
  lines[#lines + 1] = line
end
local root, partials, templates, strict = map(), {}, {}, false

local function show_template(name)
  local ok, result = pcall(function ()
    return render(parse_source(templates[name]), root, partials, strict)
  end)
  if not ok then
    print("TEMPLATE " .. name .. " ERROR line " .. result.number .. ": " .. result.reason)
    return
  end
  local _, count = result:gsub("\n", "")
  if result ~= "" and result:sub(- 1) ~= "\n" then
    count = count + 1
  end
  print("TEMPLATE " .. name .. " OK lines=" .. count .. " chars=" .. #result)
  if result ~= "" then
    io.write(result)
    if result:sub(- 1) ~= "\n" then
      io.write("\n")
    end
  end
end
local pos = 1
while lines[pos] ~= "END" do
  local line, number = lines[pos], pos
  pos = pos + 1
  local command, name = line:match("^(%S+) ?(.*)$")
  if command == "DATA" or command == "PARTIAL" or command == "TEMPLATE" then
    local body = {}
    while lines[pos] ~= "END" .. command do
      body[#body + 1] = { number = pos, text = lines[pos] }
      pos = pos + 1
    end
    pos = pos + 1
    if command == "DATA" then
      local set, unset, errors = 0, 0, {}
      for _, row in ipairs(body) do
        if row.text ~= "" and not starts(row.text, "#") then
          local remove = starts(row.text, "UNSET ")
          local ok, err = pcall(function ()
            local key, text
            if remove then
              key = row.text:sub(7)
            else
              local p = row.text:find(" = ", 1, true)
              if not p then
                bad("bad line")
              end
              key, text = row.text:sub(1, p - 1), row.text:sub(p + 3)
            end
            local parts = key_parts(key)
            local value = remove and ABSENT or parse_value(text)
            root = change(root, parts, 1, value, remove, key)
          end)
          if not ok then
            errors[#errors + 1] = "ERROR line " .. row.number .. ": " .. err
          elseif remove then
            unset = unset + 1
          else
            set = set + 1
          end
        end
      end
      print("DATA set=" .. set .. " unset=" .. unset .. " errors=" .. #errors)
      for _, err in ipairs(errors) do
        print(err)
      end
    elseif command == "PARTIAL" then
      local ok, err = pcall(parse_source, body)
      if not ok then
        print("PARTIAL " .. name .. " ERROR line " .. err.number .. ": " .. err.reason)
      else
        local status = partials[name] and "REPLACED" or "DEFINED"
        partials[name] = body
        print("PARTIAL " .. name .. " " .. status .. " lines=" .. #body)
      end
    else
      templates[name] = body
      show_template(name)
    end
  elseif command == "RENDER" then
    if templates[name] then
      show_template(name)
    else
      print("TEMPLATE " .. name .. " ERROR line " .. number .. ": unknown template '" .. name .. "'")
    end
  elseif command == "STRICT" then
    strict = name == "ON"
    print(line)
  elseif command == "RESET" then
    root, partials, templates = map(), {}, {}
    print("RESET")
  elseif command == "DUMP" then
    local out = {}
    collect(root, "", out)
    print("DUMP leaves=" .. #out)
    for _, leaf in ipairs(out) do
      print(leaf)
    end
  end
end
