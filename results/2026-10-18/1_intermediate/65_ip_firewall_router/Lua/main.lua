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

local function bad(format, ...)
  error(string.format(format, ...), 0)
end

local function decimal(s)
  return s == "0" or s:match("^[1-9][0-9]*$") ~= nil
end

local function address(a)
  return string.format("%d.%d.%d.%d",(a >> 24) & 255,(a >> 16) & 255,(a >> 8) & 255, a & 255)
end

local function parse_address(s)
  local fields = split(s, ".")
  if #fields ~= 4 then
    return nil
  end
  local a = 0
  for _, p in ipairs(fields) do
    if #p > 3 or not decimal(p) or tonumber(p) > 255 then
      return nil
    end
    a = a * 256 + tonumber(p)
  end
  return a
end

local function network(a, length)
  return a &((0xffffffff <<(32 - length)) & 0xffffffff)
end

local function parse_prefix(s)
  local parts = split(s, "/")
  if #parts ~= 2 or #parts[2] > 2 or not decimal(parts[2]) or tonumber(parts[2]) > 32 then
    return nil
  end
  local a = parse_address(parts[1])
  if not a then
    return nil
  end
  return { address = a, length = tonumber(parts[2]) }
end

local function contains(p, a)
  return network(a, p.length) == network(p.address, p.length)
end

local function prefix_text(p)
  return address(p.address) .. "/" .. p.length
end

local function checked_address(s)
  local a = parse_address(s)
  if not a then
    bad("bad address %s", s)
  end
  return a
end

local function checked_prefix(s)
  local p = parse_prefix(s)
  if not p then
    bad("bad prefix %s", s)
  end
  if p.address ~= network(p.address, p.length) then
    bad("host bits set in %s", s)
  end
  return p
end

local function same_prefix(a, b)
  return a.address == b.address and a.length == b.length
end

local function ports(s)
  if s == "ANY" then
    return { lo = 0, hi = 65535, any = true }
  end
  local p = split(s, "-")
  local lo, hi = tonumber(p[1]), tonumber(p[#p])
  if lo > 65535 or hi > 65535 or lo > hi then
    bad("bad port range %s", s)
  end
  return { lo = lo, hi = hi, any = false }
end

local function ports_text(p)
  if p.any then
    return "any"
  end
  if p.lo == p.hi then
    return tostring(p.lo)
  end
  return p.lo .. "-" .. p.hi
end

local function sorted(xs, before)
  local out = {}
  for i, x in ipairs(xs) do
    out[i] = x
  end
  table.sort(out, before)
  return out
end
local ifaces, by_name, routes, statics, forwards, conns = {}, {}, {}, {}, {}, {}
local timeouts = { TCP = 300, UDP = 60, ICMP = 30 }
local clock, packet_number, connection_number = 0, 0, 0
local forwarded, local_count, error_count, drops = 0, 0, 0, {}
local REASONS = { "down", "martian", "rpf", "invalid", "acl_in", "ttl", "noroute", "acl_out", "exhausted" }

local function interface(name)
  if not by_name[name] then
    bad("no interface %s", name)
  end
  return by_name[name]
end

local function local_address(a)
  for _, i in ipairs(ifaces) do
    if i.prefix.address == a then
      return i
    end
  end
end

local function select_route(a)
  local best
  for _, r in ipairs(routes) do
    if r.out.up and contains(r.prefix, a) and (not best or r.prefix.length > best.prefix.length or r.prefix.length == best.prefix.length and r.metric < best.metric) then
      best = r
    end
  end
  return best
end

local function route_text(r)
  return r.kind .. " " .. prefix_text(r.prefix) ..(r.hop and " via " .. address(r.hop) or "") .. " dev " .. r.out.name .. " metric " .. r.metric
end

local function same_tuple(a, b)
  return a.proto == b.proto and a.src == b.src and a.sport == b.sport and a.dst == b.dst and a.dport == b.dport
end

local function evaluate_acl(i, direction, t, existing)
  local rules = i.rules[direction]
  if #rules == 0 then
    return nil
  end
  for _, r in ipairs(rules) do
    local match =(r.proto == "ANY" or r.proto == t.proto) and contains(r.src, t.src) and contains(r.dst, t.dst) and (not r.established or existing)
    if r.proto == "TCP" or r.proto == "UDP" then
      match = match and t.sport >= r.sports.lo and t.sport <= r.sports.hi and t.dport >= r.dports.lo and t.dport <= r.dports.hi
    end
    if match then
      r.hits = r.hits + 1
      if r.action == "PERMIT" then
        return nil
      end
      if r.action == "DENY" then
        return string.format("DROP acl %s %s %d", i.name, direction, r.seq)
      end
      return string.format("REJECT acl %s %s %d %s", i.name, direction, r.seq, t.proto == "TCP" and "tcp-reset" or "icmp-prohibited")
    end
  end
  i.defaults[direction] = i.defaults[direction] + 1
  return "DROP acl " .. i.name .. " " .. direction .. " default"
end

local function martian(a)
  return a >> 24 == 0 or a >> 24 == 127 or a >> 29 == 7
end

local function packet(i, t, flags, ttl)
  local function drop(reason)
    return "DROP " .. reason, reason
  end
  if not i.up then
    return drop("down")
  end
  if martian(t.src) or martian(t.dst) or local_address(t.src) then
    return drop("martian")
  end
  if i.rpf ~= "off" then
    local back = select_route(t.src)
    if not back or i.rpf == "strict" and back.out ~= i then
      return drop("rpf")
    end
  end
  local pure = t.proto == "TCP" and flags == "S"
  local conn, way = nil, "new"
  for n, c in ipairs(conns) do
    if same_tuple(t, c.orig) then
      conn, way = c, "orig"
    elseif same_tuple(t, c.reply) then
      conn, way = c, "reply"
    end
    if conn then
      if c.state == "CLOSED" and pure then
        table.remove(conns, n)
        conn, way = nil, "new"
      end
      break
    end
  end
  if t.proto == "TCP" and not conn and not pure then
    return drop("invalid")
  end
  local verdict = evaluate_acl(i, "in", t, conn ~= nil)
  if verdict then
    return verdict, "acl_in"
  end
  local translated = { proto = t.proto, src = t.src, sport = t.sport, dst = t.dst, dport = t.dport }
  local used
  if i.outside then
    local matched = false
    for _, m in ipairs(statics) do
      if m.outside == t.dst then
        translated.dst = m.inside
        matched = true
        break
      end
    end
    if not matched and t.dst == i.prefix.address then
      for _, f in ipairs(forwards) do
        if f.out == i and f.proto == t.proto and f.port == t.dport then
          translated.dst, translated.dport = f.inside, f.inport
          matched = true
          break
        end
      end
      if not matched then
        for _, m in ipairs(i.mappings) do
          if m.proto == t.proto and m.outport == t.dport then
            translated.dst, translated.dport, used = m.inside, m.inport, m
            break
          end
        end
      end
    end
  end
  local local_iface = local_address(translated.dst)
  if local_iface then
    return "LOCAL " .. local_iface.name, "local"
  end
  if ttl == 1 then
    return drop("ttl")
  end
  local route = select_route(translated.dst)
  if not route then
    return drop("noroute")
  end
  local o = route.out
  verdict = evaluate_acl(o, "out", translated, conn ~= nil)
  if verdict then
    return verdict, "acl_out"
  end
  if not i.outside and o.outside then
    local matched = false
    for _, m in ipairs(statics) do
      if m.inside == t.src then
        translated.src = m.outside
        matched = true
        break
      end
    end
    if not matched then
      for _, f in ipairs(forwards) do
        if f.out == o and f.proto == t.proto and f.inside == t.src and f.inport == t.sport then
          translated.src, translated.sport = o.prefix.address, f.port
          matched = true
          break
        end
      end
    end
    if not matched and o.pool then
      for _, m in ipairs(o.mappings) do
        if m.proto == t.proto and m.inside == t.src and m.inport == t.sport then
          used = m
          break
        end
      end
      if not used then
        local chosen
        for port = 20000, 19999 + o.pool do
          local busy = false
          for _, m in ipairs(o.mappings) do
            if m.outport == port then
              busy = true
            end
          end
          for _, f in ipairs(forwards) do
            if f.out == o and f.port == port then
              busy = true
            end
          end
          if not busy then
            chosen = port
            break
          end
        end
        if not chosen then
          return drop("exhausted")
        end
        used = { proto = t.proto, inside = t.src, inport = t.sport, outport = chosen, last = clock }
        o.mappings[#o.mappings + 1] = used
      end
      translated.src, translated.sport = o.prefix.address, used.outport
    end
  end
  if used then
    used.last = clock
  end
  if not conn then
    connection_number = connection_number + 1
    conn = { number = connection_number, orig = t, reply = { proto = t.proto, src = translated.dst, sport = translated.dport, dst = translated.src, dport = translated.sport }, input = i, out = o, state = t.proto == "TCP" and "SYN_SENT" or "UNREPLIED", orig_count = 0, reply_count = 0, fin = {}, last = clock }
    conns[#conns + 1] = conn
    way = "new"
  end
  if way == "reply" then
    conn.reply_count = conn.reply_count + 1
  else
    conn.orig_count = conn.orig_count + 1
  end
  conn.last = clock
  if t.proto ~= "TCP" then
    if way == "reply" then
      conn.state = "REPLIED"
    end
  elseif flags:find("R", 1, true) then
    conn.state = "CLOSED"
  else
    if conn.state == "SYN_SENT" and way == "reply" and flags:find("S", 1, true) and flags:find("A", 1, true) then
      conn.state = "ESTABLISHED"
    end
    if flags:find("F", 1, true) and (conn.state == "ESTABLISHED" or conn.state == "FIN_WAIT") then
      conn.fin[way == "reply" and "reply" or "orig"] = true
      conn.state = conn.fin.orig and conn.fin.reply and "CLOSED" or "FIN_WAIT"
    end
  end
  o.tx, route.hits = o.tx + 1, route.hits + 1
  local v = string.format("FORWARD %s %s ttl=%d", o.name, route.hop and "via " .. address(route.hop) or "direct", ttl - 1)
  if translated.dst ~= t.dst or translated.dport ~= t.dport then
    v = v .. string.format(" dnat=%s:%d", address(translated.dst), translated.dport)
  end
  if translated.src ~= t.src or translated.sport ~= t.sport then
    v = v .. string.format(" snat=%s:%d", address(translated.src), translated.sport)
  end
  return v .. string.format(" conn=%d %s", conn.number, way), "forwarded"
end

local function expire()
  local kept, removed_nat = {}, 0
  for _, c in ipairs(conns) do
    local timeout = timeouts[c.orig.proto]
    if c.orig.proto == "TCP" then
      if c.state == "SYN_SENT" or c.state == "FIN_WAIT" then
        timeout = 60
      elseif c.state == "CLOSED" then
        timeout = 10
      end
    end
    if clock - c.last < timeout then
      kept[#kept + 1] = c
    end
  end
  local removed = #conns - #kept
  conns = kept
  for _, i in ipairs(ifaces) do
    kept = {}
    for _, m in ipairs(i.mappings) do
      if clock - m.last >= timeouts[m.proto] then
        removed_nat = removed_nat + 1
      else
        kept[#kept + 1] = m
      end
    end
    i.mappings = kept
  end
  return removed, removed_nat
end

local function show(what)
  local out = {}
  local function add(format, ...)
    out[#out + 1] = string.format(format, ...)
  end
  local ordered = sorted(ifaces, function (a, b)
    return a.name < b.name
  end)
  if what == "IFACES" then
    add("show ifaces count=%d", #ifaces)
    for _, i in ipairs(ordered) do
      local s = string.format("%s %s %s %s rpf=%s", i.name, prefix_text(i.prefix), i.up and "up" or "down", i.outside and "outside" or "inside", i.rpf)
      if i.pool then
        s = s .. string.format(" pat=%d/%d", #i.mappings, i.pool)
      end
      out[#out + 1] = s
    end
  elseif what == "ROUTES" then
    local positions = {}
    for n, r in ipairs(routes) do
      positions[r] = n
    end
    local rs = sorted(routes, function (a, b)
      if a.prefix.address ~= b.prefix.address then
        return a.prefix.address < b.prefix.address
      end
      if a.prefix.length ~= b.prefix.length then
        return a.prefix.length < b.prefix.length
      end
      if a.metric ~= b.metric then
        return a.metric < b.metric
      end
      return positions[a] < positions[b]
    end)
    add("show routes count=%d", #rs)
    for _, r in ipairs(rs) do
      add("%s hits=%d%s", route_text(r), r.hits, r.out.up and "" or " inactive")
    end
  elseif what == "ACL" then
    local count = 0
    for _, i in ipairs(ifaces) do
      count = count + #i.rules["in"] + #i.rules.out
    end
    add("show acl count=%d", count)
    for _, i in ipairs(ordered) do
      for _, d in ipairs({ "in", "out" }) do
        for _, r in ipairs(i.rules[d]) do
          add("acl %s %s %d %s %s %s %s %s %s%s hits=%d", i.name, d, r.seq, r.action, r.proto, r.src.length == 0 and "any" or prefix_text(r.src), ports_text(r.sports), r.dst.length == 0 and "any" or prefix_text(r.dst), ports_text(r.dports), r.established and " established" or "", r.hits)
        end
        if #i.rules[d] > 0 then
          add("acl %s %s default DENY hits=%d", i.name, d, i.defaults[d])
        end
      end
    end
  elseif what == "NAT" then
    local count = 0
    for _, i in ipairs(ifaces) do
      count = count + #i.mappings
    end
    add("show nat static=%d forward=%d pat=%d", #statics, #forwards, count)
    for _, m in ipairs(sorted(statics, function (a, b)
      return a.inside < b.inside
    end)) do
      add("static %s %s", address(m.inside), address(m.outside))
    end
    local fs = sorted(forwards, function (a, b)
      if a.out.name ~= b.out.name then
        return a.out.name < b.out.name
      end
      if a.port ~= b.port then
        return a.port < b.port
      end
      return a.proto < b.proto
    end)
    for _, f in ipairs(fs) do
      add("forward %s %s %d %s:%d", f.out.name, f.proto, f.port, address(f.inside), f.inport)
    end
    for _, i in ipairs(ordered) do
      for _, m in ipairs(sorted(i.mappings, function (a, b)
        return a.outport < b.outport
      end)) do
        add("pat %s %d %s %s:%d idle=%d", i.name, m.outport, m.proto, address(m.inside), m.inport, clock - m.last)
      end
    end
  elseif what == "CONNS" then
    add("show conns count=%d", #conns)
    for _, c in ipairs(conns) do
      local a, b = c.orig, c.reply
      add("conn %d %s %s:%d > %s:%d reply %s:%d > %s:%d in=%s out=%s state=%s pkts=%d/%d idle=%d", c.number, a.proto, address(a.src), a.sport, address(a.dst), a.dport, address(b.src), b.sport, address(b.dst), b.dport, c.input.name, c.out.name, c.state, c.orig_count, c.reply_count, clock - c.last)
    end
  elseif what == "COUNTERS" then
    local total = 0
    for _, count in pairs(drops) do
      total = total + count
    end
    add("show counters packets=%d forwarded=%d local=%d dropped=%d errors=%d", forwarded + local_count + total, forwarded, local_count, total, error_count)
    local parts = { "drops" }
    for _, reason in ipairs(REASONS) do
      parts[#parts + 1] = reason .. "=" ..(drops[reason] or 0)
    end
    out[#out + 1] = table.concat(parts, " ")
    for _, i in ipairs(ordered) do
      add("iface %s rx=%d tx=%d drop=%d", i.name, i.rx, i.tx, i.drop)
    end
  end
  return table.concat(out, "\n")
end

local function command(w)
  local cmd = w[1]
  if cmd == "IFACE" then
    if by_name[w[2]] then
      bad("duplicate interface %s", w[2])
    end
    local p = parse_prefix(w[3])
    if not p or p.length < 8 or p.length > 30 then
      bad("bad prefix %s", w[3])
    end
    local net = network(p.address, p.length)
    if p.address == net or p.address ==(net |(0xffffffff >> p.length)) then
      bad("bad host address %s", w[3])
    end
    for _, i in ipairs(ifaces) do
      local length = math.min(p.length, i.prefix.length)
      if network(p.address, length) == network(i.prefix.address, length) then
        bad("subnet overlaps %s", i.name)
      end
    end
    local i = { name = w[2], prefix = p, up = true, outside = false, rpf = "off", rx = 0, tx = 0, drop = 0, rules = { ["in"] = {}, out = {} }, defaults = { ["in"] = 0, out = 0 }, mappings = {} }
    ifaces[#ifaces + 1], by_name[i.name] = i, i
    routes[#routes + 1] = { kind = "C", prefix = { address = net, length = p.length }, out = i, metric = 0, hits = 0 }
    return string.format("ok iface %s %s network %s/%d", i.name, w[3], address(net), p.length)
  elseif cmd == "UP" or cmd == "DOWN" then
    local i, status = interface(w[2]), cmd:lower()
    if i.up ==(cmd == "UP") then
      bad("interface %s already %s", i.name, status)
    end
    i.up = cmd == "UP"
    return "ok " .. status .. " " .. i.name
  elseif cmd == "ROUTE" then
    local p, hop, out = checked_prefix(w[2]), nil, nil
    if w[3] == "VIA" then
      hop = checked_address(w[4])
    else
      out = interface(w[4])
    end
    local metric = tonumber(w[5])
    if metric < 1 or metric > 255 then
      bad("bad metric %s", w[5])
    end
    if hop then
      if local_address(hop) then
        bad("nexthop %s is local", w[4])
      end
      for _, i in ipairs(ifaces) do
        if contains(i.prefix, hop) then
          out = i
          break
        end
      end
      if not out then
        bad("nexthop %s unreachable", w[4])
      end
    end
    for _, r in ipairs(routes) do
      if r.kind == "S" and same_prefix(r.prefix, p) and r.out == out and r.hop == hop then
        bad("duplicate route %s", w[2])
      end
    end
    local r = { kind = "S", prefix = p, out = out, hop = hop, metric = metric, hits = 0 }
    routes[#routes + 1] = r
    return "ok route " .. route_text(r)
  elseif cmd == "NOROUTE" then
    local p, kept, count = checked_prefix(w[2]), {}, 0
    for _, r in ipairs(routes) do
      if r.kind == "S" and same_prefix(r.prefix, p) then
        count = count + 1
      else
        kept[#kept + 1] = r
      end
    end
    if count == 0 then
      bad("no static route %s", w[2])
    end
    routes = kept
    return string.format("ok noroute %s removed=%d", w[2], count)
  elseif cmd == "LOOKUP" then
    local r = select_route(checked_address(w[2]))
    return "lookup " .. w[2] .. " " ..(r and route_text(r) or "none")
  elseif cmd == "ACL" then
    local i, seq, d = interface(w[2]), tonumber(w[4]), w[3]:lower()
    if seq < 1 or seq > 9999 then
      bad("bad sequence %s", w[4])
    end
    local function acl_prefix(s)
      if s == "ANY" then
        return { address = 0, length = 0 }
      end
      return checked_prefix(s)
    end
    local src = acl_prefix(w[7])
    local sports = ports(w[8])
    local dst = acl_prefix(w[9])
    local dports = ports(w[10])
    if (w[6] == "ICMP" or w[6] == "ANY") and (not sports.any or not dports.any) then
      bad("ports not allowed for %s", w[6])
    end
    for _, r in ipairs(i.rules[d]) do
      if r.seq == seq then
        bad("duplicate sequence %s", w[4])
      end
    end
    i.rules[d][#i.rules[d] + 1] = { seq = seq, action = w[5], proto = w[6], src = src, sports = sports, dst = dst, dports = dports, established = #w == 11, hits = 0 }
    table.sort(i.rules[d], function (a, b)
      return a.seq < b.seq
    end)
    return "ok acl " .. i.name .. " " .. d .. " " .. w[4]
  elseif cmd == "NOACL" then
    local i, d = interface(w[2]), w[3]:lower()
    for n, r in ipairs(i.rules[d]) do
      if r.seq == tonumber(w[4]) then
        table.remove(i.rules[d], n)
        return string.format("ok noacl %s %s %s hits=%d", i.name, d, w[4], r.hits)
      end
    end
    bad("no rule %s on %s %s", w[4], i.name, d)
  elseif cmd == "NAT" then
    if w[2] == "STATIC" then
      local a = checked_address(w[3])
      local b = checked_address(w[4])
      if local_address(a) then
        bad("address %s is local", w[3])
      end
      if local_address(b) then
        bad("address %s is local", w[4])
      end
      for _, m in ipairs(statics) do
        if m.inside == a then
          bad("duplicate static %s", w[3])
        end
      end
      for _, m in ipairs(statics) do
        if m.outside == b then
          bad("duplicate static %s", w[4])
        end
      end
      statics[#statics + 1] = { inside = a, outside = b }
      return "ok nat static " .. w[3] .. " " .. w[4]
    end
    local i = interface(w[3])
    if w[2] == "OUTSIDE" then
      if i.outside then
        bad("interface %s already outside", i.name)
      end
      i.outside = true
      return "ok nat outside " .. i.name
    elseif w[2] == "PAT" then
      local n = tonumber(w[4])
      if n < 1 or n > 1000 then
        bad("bad pool size %s", w[4])
      end
      if i.pool then
        bad("pat already on %s", i.name)
      end
      i.pool, i.outside = n, true
      return string.format("ok nat pat %s %s 20000-%d", i.name, address(i.prefix.address), 19999 + n)
    else
      local port = tonumber(w[5])
      if port < 1 or port > 65535 then
        bad("bad port %s", w[5])
      end
      local a = checked_address(w[6])
      local inport = tonumber(w[7])
      if inport < 1 or inport > 65535 then
        bad("bad port %s", w[7])
      end
      if not i.outside then
        bad("interface %s not outside", i.name)
      end
      if local_address(a) then
        bad("address %s is local", w[6])
      end
      for _, f in ipairs(forwards) do
        if f.out == i and f.proto == w[4] and f.port == port then
          bad("duplicate forward %s %s %s", i.name, w[4], w[5])
        end
      end
      forwards[#forwards + 1] = { out = i, proto = w[4], port = port, inside = a, inport = inport }
      return string.format("ok nat forward %s %s %s %s:%s", i.name, w[4], w[5], w[6], w[7])
    end
  elseif cmd == "RPF" then
    local i = interface(w[2])
    i.rpf = w[3]:lower()
    return "ok rpf " .. i.name .. " " .. i.rpf
  elseif cmd == "TIMEOUT" then
    local n = tonumber(w[3])
    if n < 1 or n > 86400 then
      bad("bad timeout %s", w[3])
    end
    timeouts[w[2]] = n
    return "ok timeout " .. w[2] .. " " .. w[3]
  elseif cmd == "TICK" then
    local n = tonumber(w[2])
    if n < 1 or n > 86400 then
      bad("bad tick %s", w[2])
    end
    clock = clock + n
    local c, m = expire()
    return string.format("ok tick time=%d expired conns=%d nat=%d", clock, c, m)
  elseif cmd == "PACKET" then
    local i, proto, flags = interface(w[2]), w[3], w[4]
    if proto ~= "TCP" and flags ~= "-" then
      bad("flags not allowed for %s", proto)
    end
    if proto == "TCP" and flags ~= "-" then
      local seen = {}
      for c in flags:gmatch(".") do
        if not ("SAFR"):find(c, 1, true) or seen[c] then
          bad("bad flags %s", flags)
        end
        seen[c] = true
      end
    end
    local src = checked_address(w[5])
    local sp = tonumber(w[6])
    if sp > 65535 then
      bad("bad port %s", w[6])
    end
    local dst = checked_address(w[7])
    local dp = tonumber(w[8])
    if dp > 65535 then
      bad("bad port %s", w[8])
    end
    local ttl = tonumber(w[9])
    if ttl < 1 or ttl > 255 then
      bad("bad ttl %s", w[9])
    end
    packet_number, i.rx = packet_number + 1, i.rx + 1
    local verdict, reason = packet(i, { proto = proto, src = src, sport = sp, dst = dst, dport = dp }, flags, ttl)
    if reason == "forwarded" then
      forwarded = forwarded + 1
    elseif reason == "local" then
      local_count = local_count + 1
    else
      drops[reason] =(drops[reason] or 0) + 1
      i.drop = i.drop + 1
    end
    return string.format("#%d %s %s %s:%s > %s:%s %s", packet_number, proto, flags, w[5], w[6], w[7], w[8], verdict)
  elseif cmd == "SHOW" then
    return show(w[2])
  elseif cmd == "CLEAR" then
    if w[2] == "CONNS" then
      local count, mappings = #conns, 0
      conns = {}
      for _, i in ipairs(ifaces) do
        mappings = mappings + #i.mappings
        i.mappings = {}
      end
      return string.format("ok clear conns=%d nat=%d", count, mappings)
    end
    forwarded, local_count, error_count, drops = 0, 0, 0, {}
    for _, i in ipairs(ifaces) do
      i.rx, i.tx, i.drop = 0, 0, 0
      i.defaults = { ["in"] = 0, out = 0 }
      for _, rs in pairs(i.rules) do
        for _, r in ipairs(rs) do
          r.hits = 0
        end
      end
    end
    for _, r in ipairs(routes) do
      r.hits = 0
    end
    return "ok clear counters"
  end
end
local n = tonumber(io.read("*l"))
for _ = 1, n do
  local words = split(io.read("*l"), " ")
  local ok, result = pcall(command, words)
  if ok then
    print(result)
  else
    error_count = error_count + 1
    print("error: " .. result)
  end
end
