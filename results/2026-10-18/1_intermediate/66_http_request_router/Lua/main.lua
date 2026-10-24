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

local function cut(s, separator)
  local p = s:find(separator, 1, true)
  if p then
    return s:sub(1, p - 1), s:sub(p + #separator), true
  end
  return s, "", false
end

local function starts(s, p)
  return s:sub(1, #p) == p
end

local function trim(s)
  return (s:gsub("^ +", ""):gsub(" +$", ""))
end

local function bad(format, ...)
  error(string.format(format, ...), 0)
end

local function keys(m)
  local out = {}
  for k in pairs(m) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

local function valid_name(s)
  return #s <= 20 and s:match("^[a-z][a-z0-9_]*$") ~= nil
end

local function role_name(s)
  return #s >= 1 and #s <= 16 and s:match("^[a-z]+$") ~= nil
end

local function unreserved(c)
  return c:match("^[A-Za-z0-9%-%._~]$") ~= nil
end

local function segment(s)
  return s ~= "" and s ~= "." and s ~= ".." and s:match("^[A-Za-z0-9%-%._~]+$") ~= nil
end

local function canonical(s)
  if s == "/" then
    return true
  end
  if not starts(s, "/") then
    return false
  end
  for _, p in ipairs(split(s:sub(2), "/")) do
    if not segment(p) then
      return false
    end
  end
  return true
end

local function media_part(s)
  return s:match("^[a-z0-9%.%+%-]+$") ~= nil
end

local function media(s)
  local p = split(s, "/")
  return #p == 2 and media_part(p[1]) and media_part(p[2])
end

local function int_value(s)
  return #s >= 1 and #s <= 9 and s:match("^[0-9]+$") ~= nil
end

local function slug(s)
  return s:match("^[a-z0-9%-]+$") ~= nil
end

local function decimal(s)
  return s == "0" or s:match("^[1-9][0-9]*$") ~= nil
end

local function encode(s)
  return (s:gsub(".", function (c)
    return unreserved(c) and c or string.format("%%%02X", c:byte())
  end))
end

local function decode(s)
  return (s:gsub("%%(%x%x)", function (h)
    return string.char(tonumber(h, 16))
  end))
end

local function escape_check(s)
  local at = 1
  while at <= #s do
    if s:sub(at, at) == "%" then
      local h = s:sub(at + 1, at + 2)
      if #h ~= 2 or not h:match("^%x%x$") or tonumber(h, 16) < 32 or tonumber(h, 16) > 126 then
        return false
      end
      at = at + 2
    end
    at = at + 1
  end
  return true
end

local function normalize(path)
  path = path:gsub("%%(%x%x)", function (h)
    local c = string.char(tonumber(h, 16))
    return unreserved(c) and c or "%" .. h:upper()
  end)
  local out = {}
  for _, p in ipairs(split(path:sub(2), "/")) do
    if p == ".." then
      out[#out] = nil
    elseif p ~= "" and p ~= "." then
      out[#out + 1] = p
    end
  end
  return "/" .. table.concat(out, "/")
end

local function rule_path(s)
  if s:sub(- 2) == "/*" then
    local base = s:sub(1, - 3)
    return base, true, base ~= "/" and canonical(base)
  end
  return s, false, canonical(s)
end

local function parse_pattern(pattern)
  if pattern == "/" then
    return {}
  end
  if not starts(pattern, "/") then
    return nil
  end
  local parts, out, names = split(pattern:sub(2), "/"), {}, {}
  for i, p in ipairs(parts) do
    local piece = { kind = "literal", name = p }
    if not segment(p) then
      if #p < 3 or p:sub(1, 1) ~= "{" or p:sub(- 1) ~= "}" then
        return nil
      end
      local inside = p:sub(2, - 2)
      piece.kind, piece.name = "param", inside
      if starts(inside, "*") then
        piece.kind, piece.name = "wild", inside:sub(2)
        if i ~= #parts then
          return nil
        end
      else
        local name, kind, colon = cut(inside, ":")
        if colon then
          if kind ~= "int" and kind ~= "slug" then
            return nil
          end
          piece.kind, piece.name = kind, name
        end
      end
      if not valid_name(piece.name) or names[piece.name] then
        return nil
      end
      names[piece.name] = true
    end
    out[#out + 1] = piece
  end
  return out
end
local routes, priority, by_name, tokens, redirects, origins, clients, statuses = {}, {}, {}, {}, {}, {}, {}, {}
local capacity, period, config_errors, requests, url_ok, url_error = 0, 0, 0, 0, 0, 0
local BASE_METHODS = { GET = true, POST = true, PUT = true, PATCH = true, DELETE = true }
local METHODS = { GET = true, HEAD = true, POST = true, PUT = true, PATCH = true, DELETE = true, OPTIONS = true }

local function config(w)
  local cmd, n = w[1], #w - 1
  if cmd ~= "ROUTE" and cmd ~= "TOKEN" and cmd ~= "REDIRECT" and cmd ~= "ORIGIN" and cmd ~= "LIMIT" and cmd ~= "TYPES" then
    bad("unknown command %s", cmd)
  end
  local count_ok = cmd == "ROUTE" and (n == 3 or n == 5) or (cmd == "TOKEN" or cmd == "LIMIT") and n == 2 or cmd == "REDIRECT" and n == 3 or cmd == "ORIGIN" and n == 1 or cmd == "TYPES" and n >= 2
  if not count_ok then
    bad("wrong number of arguments")
  end
  if cmd == "ROUTE" then
    if not valid_name(w[2]) then
      bad("bad route name %s", w[2])
    end
    if by_name[w[2]] then
      bad("duplicate route %s", w[2])
    end
    local methods = {}
    for _, m in ipairs(split(w[3], ",")) do
      if not BASE_METHODS[m] or methods[m] then
        bad("bad methods %s", w[3])
      end
      methods[m] = true
    end
    local pieces = parse_pattern(w[4])
    if not pieces then
      bad("bad pattern %s", w[4])
    end
    local role
    if n == 5 then
      if w[5] ~= "ROLE" then
        bad("unknown option %s", w[5])
      end
      if not role_name(w[6]) then
        bad("bad role %s", w[6])
      end
      role = w[6]
      if role == "none" then
        role = nil
      end
    end
    local r = { name = w[2], pattern = w[4], methods = methods, pieces = pieces, role = role, number = #routes + 1, literals = 0, typed = 0, wild = false, selections = 0 }
    for _, p in ipairs(pieces) do
      if p.kind == "literal" then
        r.literals = r.literals + 1
      elseif p.kind == "int" or p.kind == "slug" then
        r.typed = r.typed + 1
      elseif p.kind == "wild" then
        r.wild = true
      end
    end
    routes[#routes + 1], by_name[r.name] = r, r
  elseif cmd == "TOKEN" then
    if #w[2] < 1 or #w[2] > 32 or not w[2]:match("^[A-Za-z0-9%._%-]+$") then
      bad("bad token %s", w[2])
    end
    if tokens[w[2]] then
      bad("duplicate token %s", w[2])
    end
    if not role_name(w[3]) then
      bad("bad role %s", w[3])
    end
    tokens[w[2]] = w[3]
  elseif cmd == "REDIRECT" then
    local from, wildcard, ok = rule_path(w[2])
    if not ok then
      bad("bad path %s", w[2])
    end
    local to, to_wildcard, valid = rule_path(w[3])
    if not valid then
      bad("bad path %s", w[3])
    end
    if wildcard ~= to_wildcard then
      bad("wildcard mismatch")
    end
    if w[4] ~= "301" and w[4] ~= "302" and w[4] ~= "307" and w[4] ~= "308" then
      bad("bad redirect code %s", w[4])
    end
    for _, r in ipairs(redirects) do
      if r.from == from and r.wildcard == wildcard then
        bad("duplicate redirect %s", w[2])
      end
    end
    redirects[#redirects + 1] = { from = from, to = to, wildcard = wildcard, code = tonumber(w[4]) }
  elseif cmd == "ORIGIN" then
    local host = w[2]:match("^http://([a-z0-9%.%-%:]+)$") or w[2]:match("^https://([a-z0-9%.%-%:]+)$")
    if not host then
      bad("bad origin %s", w[2])
    end
    if origins[w[2]] then
      bad("duplicate origin %s", w[2])
    end
    origins[w[2]] = true
  elseif cmd == "LIMIT" then
    local n, s = tonumber(w[2]), tonumber(w[3])
    if not decimal(w[2]) or not decimal(w[3]) or n < 1 or n > 100 or s < 1 or s > 3600 then
      bad("bad limit")
    end
    if capacity > 0 then
      bad("duplicate limit")
    end
    capacity, period = n, s
  elseif cmd == "TYPES" then
    local r = by_name[w[2]]
    if not r then
      bad("unknown route %s", w[2])
    end
    if r.types then
      bad("duplicate types %s", w[2])
    end
    local seen, types = {}, {}
    for i = 3, #w do
      local t = w[i]
      if not media(t) then
        bad("bad media type %s", t)
      end
      if seen[t] then
        bad("duplicate media type %s", t)
      end
      seen[t] = true
      types[#types + 1] = t
    end
    r.types = types
  end
end

local function method_list(methods, options)
  local set = {}
  for m in pairs(methods) do
    set[m] = true
  end
  if set.GET then
    set.HEAD = true
  end
  if options then
    set.OPTIONS = true
  end
  return keys(set)
end

local function show_table()
  local limit = capacity > 0 and capacity .. "/" .. period or "none"
  print(string.format("CONFIG routes=%d tokens=%d redirects=%d origins=%d limit=%s errors=%d", #routes, #keys(tokens), #redirects, #keys(origins), limit, config_errors))
  for i, r in ipairs(routes) do
    priority[i] = r
    if not r.types then
      r.types = { "application/json" }
    end
  end
  table.sort(priority, function (a, b)
    if a.literals ~= b.literals then
      return a.literals > b.literals
    end
    if a.typed ~= b.typed then
      return a.typed > b.typed
    end
    if a.wild ~= b.wild then
      return not a.wild
    end
    return a.number < b.number
  end)
  for i, r in ipairs(priority) do
    print(string.format("TABLE %d %s %s %s role=%s types=%s", i, r.name, table.concat(method_list(r.methods, false), ","), r.pattern, r.role or "-", table.concat(r.types, ",")))
  end
end

local function match(r, segments)
  local m = #r.pieces -(r.wild and 1 or 0)
  if not r.wild and #segments ~= m or r.wild and #segments < m then
    return nil
  end
  local params = {}
  for j, p in ipairs(r.pieces) do
    local x = segments[j]
    if p.kind == "literal" then
      if p.name ~= x then
        return nil
      end
    elseif p.kind == "int" then
      if not int_value(x) then
        return nil
      end
      params[#params + 1] = { p.name, tostring(tonumber(x)) }
    elseif p.kind == "slug" then
      if not slug(x) then
        return nil
      end
      params[#params + 1] = { p.name, x }
    elseif p.kind == "param" then
      params[#params + 1] = { p.name, decode(x) }
    else
      local values = {}
      for i = j, #segments do
        values[#values + 1] = decode(segments[i])
      end
      params[#params + 1] = { p.name, table.concat(values, "/") }
    end
  end
  table.sort(params, function (a, b)
    return a[1] < b[1]
  end)
  return params
end

local function q_weight(s)
  local whole, fraction, point = cut(s, ".")
  if whole ~= "0" and whole ~= "1" then
    return nil
  end
  if point and (#fraction > 3 or fraction ~= "" and not fraction:match("^[0-9]+$")) then
    return nil
  end
  if whole == "1" and fraction:find("[1-9]") then
    return nil
  end
  return tonumber(whole ..(fraction .. "000"):sub(1, 3))
end

local function negotiate(types, accept)
  if accept == nil then
    return types[1]
  end
  local elements = {}
  for _, text in ipairs(split(accept, ",")) do
    local fields = split(text, ";")
    local range, specificity = trim(fields[1]):lower(), 3
    if range == "*/*" then
      specificity = 1
    elseif range:sub(- 2) == "/*" and media_part(range:sub(1, - 3)) then
      specificity = 2
    elseif not media(range) then
      specificity = 0
    end
    local weight = 1000
    for i = 2, #fields do
      local name, value, equal = cut(trim(fields[i]), "=")
      if equal and trim(name):lower() == "q" then
        weight = q_weight(trim(value))
        break
      end
    end
    if specificity > 0 and weight ~= nil then
      elements[#elements + 1] = { range = range, specificity = specificity, weight = weight }
    end
  end
  local selected, best = nil, 0
  for _, t in ipairs(types) do
    local specificity, weight = 0, 0
    local main = cut(t, "/")
    for _, e in ipairs(elements) do
      if (e.range == "*/*" or e.range == main .. "/*" or e.range == t) and e.specificity > specificity then
        specificity, weight = e.specificity, e.weight
      end
    end
    if weight > best then
      selected, best = t, weight
    end
  end
  return selected
end

local function quoted(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end
local HTML = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }

local function html(s)
  return (s:gsub('[&<>"]', HTML))
end

local function body_for(route, params, query, headers, selected)
  local queries, cookies, seen = {}, {}, {}
  for _, p in ipairs(split(query, "&")) do
    if p ~= "" then
      local name, value = cut(p, "=")
      queries[#queries + 1] = { decode((name:gsub("%+", " "))), decode((value:gsub("%+", " "))) }
    end
  end
  if headers.cookie then
    for _, p in ipairs(split(headers.cookie, ";")) do
      local name, value, equal = cut(trim(p), "=")
      if equal and name ~= "" and not seen[name] then
        seen[name] = true
        cookies[#cookies + 1] = { name, value }
      end
    end
  end
  table.sort(cookies, function (a, b)
    return a[1] < b[1]
  end)
  if selected == "application/json" then
    local function object(ps)
      local out = {}
      for _, p in ipairs(ps) do
        out[#out + 1] = quoted(p[1]) .. ":" .. quoted(p[2])
      end
      return "{" .. table.concat(out, ",") .. "}"
    end
    local qs = {}
    for _, p in ipairs(queries) do
      qs[#qs + 1] = "[" .. quoted(p[1]) .. "," .. quoted(p[2]) .. "]"
    end
    return '{"route":' .. quoted(route.name) .. ',"params":' .. object(params) .. ',"query":[' .. table.concat(qs, ",") .. '],"cookies":' .. object(cookies) .. "}"
  elseif selected == "text/html" then
    local out = { "<dl><dt>route</dt><dd>" .. html(route.name) .. "</dd>" }
    for i, ps in ipairs({ params, queries, cookies }) do
      local label =({ "param", "query", "cookie" })[i]
      for _, p in ipairs(ps) do
        out[#out + 1] = "<dt>" .. label .. " " .. html(p[1]) .. "</dt><dd>" .. html(p[2]) .. "</dd>"
      end
    end
    out[#out + 1] = "</dl>"
    return table.concat(out)
  end
  local function encoded(ps)
    if #ps == 0 then
      return "-"
    end
    local out = {}
    for _, p in ipairs(ps) do
      out[#out + 1] = encode(p[1]) .. "=" .. encode(p[2])
    end
    return table.concat(out, "&")
  end
  return "route=" .. route.name .. " params=" .. encoded(params) .. " query=" .. encoded(queries) .. " cookies=" .. encoded(cookies)
end

local function etag(body)
  local a, b = 1, 0
  for i = 1, #body do
    a =(a + body:byte(i)) % 65521
    b =(b + a) % 65521
  end
  return string.format('"%04x%04x"', b, a)
end

local function reply(status, body, headers)
  return { status = status, body = body, headers = headers or {} }
end

local function dispatch(method, target, h)
  if not METHODS[method] then
    return reply(501, "not implemented: " .. method)
  end
  if not h.host or h.host == "" then
    return reply(400, "bad request: missing host")
  end
  local effective = method
  if h["x-http-method-override"] ~= nil then
    local override = h["x-http-method-override"]
    if method == "POST" and (override == "PUT" or override == "PATCH" or override == "DELETE") then
      effective = override
    else
      return reply(400, "bad request: method override")
    end
  end
  local c = h["x-client"]
  if c and c ~= "" then
    local t = tonumber(h["x-time"])
    if not clients[c] then
      clients[c] = { level = capacity * period, last = t, allowed = 0, limited = 0 }
    end
    local record = clients[c]
    if capacity > 0 then
      record.level, record.last = math.min(capacity * period, record.level +(t - record.last) * capacity), t
      if record.level < period then
        record.limited = record.limited + 1
        return reply(429, "too many requests: client " .. c, { ["Retry-After"] = tostring(math.ceil((period - record.level) / capacity)) })
      end
      record.level = record.level - period
    end
    record.allowed = record.allowed + 1
  end
  local path, query, has_query = cut(target, "?")
  local suffix = has_query and "?" .. query or ""
  local normalized = normalize(path)
  if normalized ~= path then
    local location = normalized .. suffix
    return reply(308, "redirect to " .. location, { Location = location })
  end
  for _, r in ipairs(redirects) do
    if path == r.from or r.wildcard and starts(path, r.from .. "/") then
      local location = r.to .. path:sub(#r.from + 1) .. suffix
      return reply(r.code, "redirect to " .. location, { Location = location })
    end
  end
  local segments = path == "/" and {} or split(path:sub(2), "/")
  local matches, values, allowed = {}, {}, {}
  for _, r in ipairs(priority) do
    local params = match(r, segments)
    if params then
      matches[#matches + 1] = r
      values[r] = params
      for m in pairs(r.methods) do
        allowed[m] = true
      end
    end
  end
  if #matches == 0 then
    return reply(404, "not found: " .. path)
  end
  local allow = table.concat(method_list(allowed, true), ", ")
  if effective == "OPTIONS" then
    return reply(204, "", { Allow = allow })
  end
  local lookup = effective == "HEAD" and "GET" or effective
  local selected
  for _, r in ipairs(matches) do
    if r.methods[lookup] then
      selected = r
      break
    end
  end
  if not selected then
    return reply(405, "method not allowed: " .. effective, { Allow = allow })
  end
  selected.selections = selected.selections + 1
  if selected.role then
    if h.authorization == nil then
      return reply(401, "unauthorized: missing token", { ["WWW-Authenticate"] = 'Bearer realm="api"' })
    end
    local scheme, token = cut(h.authorization, " ")
    if scheme:lower() ~= "bearer" or not tokens[token] then
      return reply(401, "unauthorized: invalid token", { ["WWW-Authenticate"] = 'Bearer realm="api", error="invalid_token"' })
    end
    if tokens[token] ~= selected.role and tokens[token] ~= "admin" then
      return reply(403, "forbidden: requires role " .. selected.role)
    end
  end
  local selected_type = negotiate(selected.types, h.accept)
  local response
  if not selected_type then
    response = reply(406, "not acceptable: " .. table.concat(selected.types, ", "))
  else
    local body = body_for(selected, values[selected], query, h, selected_type)
    local tag, conditional = etag(body), false
    if h["if-none-match"] ~= nil then
      for _, p in ipairs(split(h["if-none-match"], ",")) do
        p = trim(p)
        if starts(p, "W/") then
          p = p:sub(3)
        end
        if p == "*" or p == tag then
          conditional = true
          break
        end
      end
    end
    if conditional then
      if lookup == "GET" then
        response = reply(304, "", { ETag = tag })
      else
        response = reply(412, "precondition failed: " .. tag)
      end
    else
      response = reply(200, body, { ETag = tag })
      response.content_type = selected_type
    end
  end
  if #selected.types > 1 then
    response.headers.Vary = "Accept"
  end
  return response
end

local function request(line, header_lines)
  local parts = split(line, " ")
  if #parts ~= 3 or #parts[1] < 1 or #parts[1] > 16 or not parts[1]:match("^[A-Z]+$") or not starts(parts[2], "/") or parts[2]:find("#", 1, true) or parts[3] ~= "HTTP/1.1" then
    return reply(400, "bad request: request line")
  end
  local head = parts[1] == "HEAD"
  local function early(body)
    local response = reply(400, body)
    response.head = head
    return response
  end
  if not escape_check(parts[2]) then
    return early("bad request: percent escape")
  end
  local h = {}
  for i, text in ipairs(header_lines) do
    local name, value, colon = cut(text, ":")
    if not colon or not name:match("^[A-Za-z0-9%-]+$") then
      return early("bad request: header line " .. i)
    end
    name = name:lower()
    if h[name] ~= nil then
      return early("bad request: duplicate header " .. name)
    end
    h[name] = trim(value)
  end
  local response = dispatch(parts[1], parts[2], h)
  response.head = head
  if h.origin ~= nil and origins[h.origin] then
    response.headers["Access-Control-Allow-Origin"] = h.origin
    if response.status == 204 and h["access-control-request-method"] ~= nil then
      response.headers["Access-Control-Allow-Methods"] = response.headers.Allow
    end
  end
  return response
end
local PHRASES = { [200] = "OK", [204] = "No Content", [301] = "Moved Permanently", [302] = "Found", [304] = "Not Modified", [307] = "Temporary Redirect", [308] = "Permanent Redirect", [400] = "Bad Request", [401] = "Unauthorized", [403] = "Forbidden", [404] = "Not Found", [405] = "Method Not Allowed", [406] = "Not Acceptable", [412] = "Precondition Failed", [429] = "Too Many Requests", [501] = "Not Implemented" }
local HEADER_ORDER = { "Location", "Allow", "Retry-After", "WWW-Authenticate", "Access-Control-Allow-Origin", "Access-Control-Allow-Methods", "Vary", "ETag", "Content-Type", "Content-Length" }

local function print_response(response)
  requests = requests + 1
  statuses[response.status] =(statuses[response.status] or 0) + 1
  if response.status ~= 204 and response.status ~= 304 then
    response.headers["Content-Type"] = response.status == 200 and response.content_type or "text/plain"
    response.headers["Content-Length"] = tostring(#response.body)
  end
  print("REQUEST " .. requests)
  print("HTTP/1.1 " .. response.status .. " " .. PHRASES[response.status])
  for _, name in ipairs(HEADER_ORDER) do
    if response.headers[name] ~= nil then
      print(name .. ": " .. response.headers[name])
    end
  end
  if response.status ~= 204 and response.status ~= 304 and not response.head then
    print(response.body)
  end
end

local function urlfor(w)
  local name, r = w[2], by_name[w[2]]
  if not r then
    bad("unknown route %s", name)
  end
  local parameters, values, query = {}, {}, {}
  for _, p in ipairs(r.pieces) do
    if p.kind ~= "literal" then
      parameters[p.name] = true
    end
  end
  for i = 3, #w do
    local key, value, equal = cut(w[i], "=")
    if not equal or key == "" then
      bad("bad argument %s", w[i])
    end
    if parameters[key] then
      if values[key] ~= nil then
        bad("duplicate parameter %s", key)
      end
      values[key] = value
    else
      query[#query + 1] = { key, value }
    end
  end
  local path = {}
  for _, p in ipairs(r.pieces) do
    if p.kind == "literal" then
      path[#path + 1] = p.name
    else
      local value = values[p.name]
      if p.kind ~= "wild" and value == nil then
        bad("missing parameter %s", p.name)
      end
      value = value or ""
      local valid = true
      if p.kind == "param" then
        valid = value ~= "" and value ~= "." and value ~= ".."
      elseif p.kind == "int" then
        valid = int_value(value)
      elseif p.kind == "slug" then
        valid = slug(value)
      elseif value ~= "" then
        for _, part in ipairs(split(value, "/")) do
          if part == "" or part == "." or part == ".." then
            valid = false
            break
          end
        end
      end
      if not valid then
        bad("bad value for %s", p.name)
      end
      if p.kind == "wild" then
        if value ~= "" then
          for _, part in ipairs(split(value, "/")) do
            path[#path + 1] = encode(part)
          end
        end
      else
        path[#path + 1] = encode(value)
      end
    end
  end
  local url = "/" .. table.concat(path, "/")
  if #query > 0 then
    local parts = {}
    for _, p in ipairs(query) do
      parts[#parts + 1] = encode(p[1]) .. "=" .. encode(p[2])
    end
    url = url .. "?" .. table.concat(parts, "&")
  end
  return "URLFOR " .. name .. " " .. url
end
local lines = {}
for line in io.lines() do
  lines[#lines + 1] = line
end
local pos = 1
while lines[pos] ~= "REQUESTS" do
  local ok, err = pcall(config, split(lines[pos], " "))
  if not ok then
    config_errors = config_errors + 1
    print("CONFIG ERROR " .. pos .. ": " .. err)
  end
  pos = pos + 1
end
pos = pos + 1
show_table()
while lines[pos] ~= "END" do
  local line = lines[pos]
  pos = pos + 1
  if starts(line, "URLFOR ") then
    local ok, result = pcall(urlfor, split(line, " "))
    if ok then
      url_ok = url_ok + 1
      print(result)
    else
      url_error = url_error + 1
      print("URLFOR ERROR " .. result)
    end
  else
    local headers = {}
    while lines[pos] ~= "" do
      headers[#headers + 1] = lines[pos]
      pos = pos + 1
    end
    pos = pos + 1
    print_response(request(line, headers))
  end
end
print(string.format("SUMMARY requests=%d urlfor_ok=%d urlfor_error=%d", requests, url_ok, url_error))
for _, status in ipairs(keys(statuses)) do
  print("STATUS " .. status .. " " .. statuses[status])
end
for _, r in ipairs(routes) do
  print("ROUTE " .. r.name .. " " .. r.selections)
end
for _, c in ipairs(keys(clients)) do
  local r = clients[c]
  print(string.format("CLIENT %s allowed=%d limited=%d", c, r.allowed, r.limited))
end
