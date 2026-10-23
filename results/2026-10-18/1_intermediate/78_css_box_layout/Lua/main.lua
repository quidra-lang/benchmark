local function split(s, separator)
    local list, start = {}, 1
    while true do
        local at = s:find(separator, start, true)
        if not at then list[#list + 1] = s:sub(start); break end
        list[#list + 1], start = s:sub(start, at - 1), at + #separator
    end
    return list
end
local function copy(t) local result = {}; for k, v in pairs(t) do result[k] = v end; return result end
local function contains(s, ...) for _, v in ipairs({...}) do if s == v then return true end end; return false end
local function unsigned(s) return #s >= 1 and #s <= 3 and s:match("^[0-9]+$") ~= nil end
local function positive(s) return unsigned(s) and tonumber(s) > 0 end
local function signed(s) return unsigned(s) or s:sub(1, 1) == "-" and unsigned(s:sub(2)) end
local function percentage(s) return s:sub(-1) == "%" and unsigned(s:sub(1, -2)) end
local function sum(list, first, last)
    local value = 0
    for i = first or 1, last or #list do value = value + list[i] end
    return value
end
local initial = {
    display="block", position="static", ["box-sizing"]="content-box", width="auto", height="auto",
    ["min-width"]="0", ["min-height"]="0", ["max-width"]="none", ["max-height"]="none",
    top="auto", right="auto", bottom="auto", left="auto", ["flex-direction"]="row", ["flex-wrap"]="nowrap",
    ["justify-content"]="start", ["align-items"]="stretch", ["align-self"]="auto", ["row-gap"]="0", ["column-gap"]="0",
    order="0", ["flex-grow"]="0", ["flex-shrink"]="1", ["flex-basis"]="auto",
    ["grid-template-columns"]="none", ["grid-template-rows"]="none", ["grid-column"]="auto", ["grid-row"]="auto",
}
for _, prefix in ipairs({"margin", "padding", "border"}) do for _, side in ipairs({"top", "right", "bottom", "left"}) do initial[prefix .. "-" .. side] = "0" end end
local function gridValue(value)
    local p = split(value, " ")
    if #p == 1 then return p[1] == "auto" or positive(p[1]) end
    if #p == 2 then return p[1] == "span" and positive(p[2]) end
    if #p == 3 then return positive(p[1]) and p[2] == "/" and positive(p[3]) and tonumber(p[1]) < tonumber(p[3]) end
    return #p == 4 and positive(p[1]) and p[2] == "/" and p[3] == "span" and positive(p[4])
end
local function valid(property, value)
    local parts = split(value, " ")
    if contains(property, "margin", "padding", "border", "gap") then
        if #parts < 1 or #parts > (property == "gap" and 2 or 4) then return nil end
        for _, part in ipairs(parts) do if not unsigned(part) or property == "border" and not contains(part, "0", "1") then return nil end end
        if property == "gap" then return {{"row-gap", parts[1]}, {"column-gap", parts[2] or parts[1]}} end
        local values = {parts[1], parts[2] or parts[1], parts[3] or parts[1], parts[4] or parts[2] or parts[1]}
        local result = {}
        for i, side in ipairs({"top", "right", "bottom", "left"}) do result[#result + 1] = {property .. "-" .. side, values[i]} end
        return result
    end
    if not initial[property] then return nil end
    local good = false
    if property:sub(1, 14) == "grid-template-" then
        good = value == "none"
        if not good then
            good = true
            for _, part in ipairs(parts) do if not unsigned(part) and part ~= "auto" and not (part:sub(-2) == "fr" and positive(part:sub(1, -3))) then good = false; break end end
        end
    elseif property == "grid-column" or property == "grid-row" then good = gridValue(value)
    elseif #parts == 1 then
        if property == "display" then good = contains(value, "block", "flex", "grid", "none")
        elseif property == "position" then good = contains(value, "static", "relative", "absolute")
        elseif property == "box-sizing" then good = contains(value, "content-box", "border-box")
        elseif contains(property, "width", "height", "flex-basis") then good = value == "auto" or unsigned(value) or percentage(value)
        elseif contains(property, "min-width", "min-height") then good = unsigned(value) or percentage(value)
        elseif contains(property, "max-width", "max-height") then good = value == "none" or unsigned(value) or percentage(value)
        elseif contains(property, "top", "right", "bottom", "left") then good = value == "auto" or signed(value)
        elseif property == "flex-direction" then good = contains(value, "row", "row-reverse", "column", "column-reverse")
        elseif property == "flex-wrap" then good = contains(value, "nowrap", "wrap")
        elseif property == "justify-content" then good = contains(value, "start", "end", "center", "space-between", "space-around", "space-evenly")
        elseif property == "align-items" then good = contains(value, "stretch", "start", "end", "center")
        elseif property == "align-self" then good = contains(value, "auto", "stretch", "start", "end", "center")
        elseif property == "order" then good = signed(value)
        elseif property:sub(1, 7) == "border-" then good = contains(value, "0", "1")
        else good = unsigned(value) end
    end
    return good and {{property, value}} or nil
end
local Element = {}
Element.__index = Element
function Element:n(property) return tonumber(self.style[property]) end
function Element:frame(horizontal)
    if horizontal then return self:n("padding-left") + self:n("padding-right") + self:n("border-left") + self:n("border-right") end
    return self:n("padding-top") + self:n("padding-bottom") + self:n("border-top") + self:n("border-bottom")
end
function Element:margin(horizontal)
    if horizontal then return self:n("margin-left") + self:n("margin-right") end
    return self:n("margin-top") + self:n("margin-bottom")
end
function Element:resolve(property, reference, horizontal)
    local value = self.style[property]
    if value == "auto" or value == "none" then return nil end
    local n
    if value:sub(-1) == "%" then if reference == nil then return nil end; n = reference * tonumber(value:sub(1, -2)) // 100
    else n = tonumber(value) end
    if self.style["box-sizing"] == "border-box" then n = math.max(0, n - self:frame(horizontal)) end
    return n
end
function Element:clamp(value, reference, horizontal)
    local axis = horizontal and "width" or "height"
    local lower, upper = self:resolve("min-" .. axis, reference, horizontal), self:resolve("max-" .. axis, reference, horizontal)
    if upper then value = math.min(value, upper) end
    return math.max(value, lower or 0)
end
function Element:flow()
    local result = {}
    for _, child in ipairs(self.children) do if child.displayed and child.style.position ~= "absolute" then result[#result + 1] = child end end
    return result
end
function Element:items()
    local list = self:flow()
    table.sort(list, function(a, b) return a:n("order") < b:n("order") or a:n("order") == b:n("order") and a.index < b.index end)
    return list
end
function Element:align(parent) return self.style["align-self"] == "auto" and parent.style["align-items"] or self.style["align-self"] end
function Element:border() return {self.x, self.y, self.cw + self:frame(true), self.ch + self:frame(false)} end
function Element:content() return {self.x + self:n("border-left") + self:n("padding-left"), self.y + self:n("border-top") + self:n("padding-top"), self.cw, self.ch} end
function Element:marginBox()
    local r = self:border()
    return {r[1] - self:n("margin-left"), r[2] - self:n("margin-top"), r[3] + self:margin(true), r[4] + self:margin(false)}
end
local function distribute(total, weights)
    local result, totalWeight, used = {}, sum(weights), 0
    for i, weight in ipairs(weights) do result[i] = totalWeight > 0 and total * weight // totalWeight or 0; used = used + result[i] end
    for i, weight in ipairs(weights) do if used == total then break end; if weight > 0 then result[i], used = result[i] + 1, used + 1 end end
    return result
end
local function gridSpec(value)
    local p = split(value, " ")
    if value == "auto" then return 0, 1 end
    if p[1] == "span" then return 0, tonumber(p[2]) end
    local start = tonumber(p[1])
    if #p == 1 then return start, 1 end
    return start, #p == 3 and tonumber(p[3]) - start or tonumber(p[4])
end
local function tracks(value, columns)
    if value == "none" then return columns and {{kind="auto", value=0}} or {} end
    local result = {}
    for _, word in ipairs(split(value, " ")) do
        local t = {kind="fixed", value=tonumber(word)}
        if word == "auto" then t.kind = "auto" elseif word:sub(-2) == "fr" then t.kind, t.value = "fr", tonumber(word:sub(1, -3)) end
        result[#result + 1] = t
    end
    return result
end
local D = {rules={}, elements={}, byID={}, output={}}
function D:emit(format, ...) self.output[#self.output + 1] = string.format(format, ...) end
function D:placement(e)
    local columns, rows, items = #tracks(e.style["grid-template-columns"], true), #tracks(e.style["grid-template-rows"], false), {}
    for _, child in ipairs(e:items()) do
        local c, cs = gridSpec(child.style["grid-column"])
        local r, rs = gridSpec(child.style["grid-row"])
        items[#items + 1] = {e=child, row=r, col=c, rows=rs, cols=cs}
        columns = math.max(columns, c > 0 and c + cs - 1 or cs)
    end
    local occupied = {}
    local function overlaps(p, r, c)
        for y = r, r + p.rows - 1 do for x = c, c + p.cols - 1 do if occupied[y .. ":" .. x] then return true end end end
        return false
    end
    local function mark(p) for y = p.row, p.row + p.rows - 1 do for x = p.col, p.col + p.cols - 1 do occupied[y .. ":" .. x] = true end end end
    for _, p in ipairs(items) do if p.row > 0 and p.col > 0 then mark(p) end end
    local cr, cc = 1, 1
    for _, p in ipairs(items) do
        if p.row == 0 or p.col == 0 then
            if p.row > 0 then
                p.col = 1
                for c = 1, columns - p.cols + 1 do if not overlaps(p, p.row, c) then p.col = c; break end end
            elseif p.col > 0 then
                if p.col < cc then cr = cr + 1 end
                local r = cr; while overlaps(p, r, p.col) do r = r + 1 end
                p.row, cr, cc = r, r, p.col + p.cols
            else
                local r, c = cr, cc
                while true do
                    if c + p.cols - 1 > columns then r, c = r + 1, 1 elseif overlaps(p, r, c) then c = c + 1 else break end
                end
                p.row, p.col, cr, cc = r, c, r, c + p.cols
            end
            mark(p)
        end
        rows = math.max(rows, p.row + p.rows - 1)
    end
    return items, columns, rows
end
local function trackSizes(spec, count, available, gap, items, contributions, horizontal)
    local sizes, weights, kinds, hasFR = {}, {}, {}, false
    for i = 1, count do
        local t = spec[i] or {kind="auto", value=0}
        sizes[i], weights[i], kinds[i] = 0, 0, t.kind
        if t.kind == "fixed" then sizes[i] = t.value
        elseif t.kind == "auto" or available == nil then
            for j, p in ipairs(items) do
                local start, span = horizontal and p.col or p.row, horizontal and p.cols or p.rows
                if start == i and span == 1 then sizes[i] = math.max(sizes[i], contributions[j]) end
            end
        end
        if t.kind == "fr" then weights[i], hasFR = t.value, true end
    end
    if available ~= nil and count > 0 then
        local left = available - sum(sizes) - gap * (count - 1)
        if left > 0 then
            if not hasFR then for i, kind in ipairs(kinds) do if kind == "auto" then weights[i] = 1 end end end
            local extra = distribute(left, weights)
            for i = 1, count do sizes[i] = sizes[i] + extra[i] end
        end
    end
    return sizes
end
function D:contribution(e)
    local width = e:resolve("width", nil, true)
    return e:clamp(width or self:maxContent(e), nil, true) + e:frame(true) + e:margin(true)
end
function D:maxContent(e)
    if e.text then return #e.text end
    local children = e:flow()
    if e.style.display == "flex" and e.style["flex-direction"]:sub(1, 3) == "row" then
        local value = 0; for _, child in ipairs(children) do value = value + self:contribution(child) end
        return value + (#children > 0 and e:n("column-gap") * (#children - 1) or 0)
    elseif e.style.display == "grid" then
        local items, nc = self:placement(e)
        local values = {}; for i, p in ipairs(items) do values[i] = self:contribution(p.e) end
        return sum(trackSizes(tracks(e.style["grid-template-columns"], true), nc, nil, e:n("column-gap"), items, values, true)) + e:n("column-gap") * (nc - 1)
    end
    local value = 0; for _, child in ipairs(children) do value = math.max(value, self:contribution(child)) end; return value
end
local function wrap(text, width)
    local lines = {}
    for _, word in ipairs(split(text, " ")) do
        if #lines == 0 or #lines[#lines] + 1 + #word > width then lines[#lines + 1] = word else lines[#lines] = lines[#lines] .. " " .. word end
    end
    return lines
end
function D:layoutElement(e, cw, ch, fw, fh)
    e.cw = fw
    if fw == nil then e.cw = e:clamp(e:resolve("width", cw, true) or math.max(0, cw - e:margin(true) - e:frame(true)), cw, true) end
    if fh == nil then local h = e:resolve("height", ch, false); if h then fh = e:clamp(h, ch, false) end end
    local a = 0; e.lines = {}
    if e.text then e.lines = wrap(e.text, e.cw); a = #e.lines
    elseif e.style.display == "flex" then a = self:flex(e, fh, ch)
    elseif e.style.display == "grid" then a = self:grid(e, fh)
    else a = self:block(e, fh) end
    e.ch = fh or e:clamp(a, ch, false)
    return a
end
local function position(e, child, x, y)
    child.rx, child.ry = x + e:n("border-left") + e:n("padding-left"), y + e:n("border-top") + e:n("padding-top")
end
function D:block(e, k)
    local bottom, previous, count = 0, 0, 0
    for _, child in ipairs(e:flow()) do
        self:layoutElement(child, e.cw, k)
        local y = child:n("margin-top")
        if count > 0 then y = bottom + math.max(previous, y) end
        position(e, child, child:n("margin-left"), y)
        bottom, previous, count = y + child.ch + child:frame(false), child:n("margin-bottom"), count + 1
    end
    return count > 0 and bottom + previous or 0
end
function D:flex(e, k, ch)
    local horizontal = e.style["flex-direction"]:sub(1, 3) == "row"
    local reversed = e.style["flex-direction"]:sub(-7) == "reverse"
    local mainRef = horizontal and e.cw or k
    local gap = e:n(horizontal and "column-gap" or "row-gap")
    local items = {}
    for _, child in ipairs(e:items()) do
        local item = {e=child, outer=child:frame(horizontal) + child:margin(horizontal)}
        if not horizontal then
            local r = math.max(0, e.cw - child:margin(true) - child:frame(true))
            local c = r
            if child.style.width ~= "auto" then c = child:resolve("width", e.cw, true) elseif child:align(e) ~= "stretch" then c = math.min(self:maxContent(child), r) end
            item.cross = child:clamp(c, e.cw, true)
        end
        item.base = child:resolve("flex-basis", mainRef, horizontal) or child:resolve(horizontal and "width" or "height", mainRef, horizontal)
        if item.base == nil then item.base = horizontal and self:maxContent(child) or self:layoutElement(child, e.cw, k, item.cross) end
        item.hypothetical = child:clamp(item.base, mainRef, horizontal)
        items[#items + 1] = item
    end
    local length = horizontal and e.cw or k
    if length == nil then
        length = 0; for _, item in ipairs(items) do length = length + item.hypothetical + item.outer end
        length = e:clamp(length + (#items > 0 and gap * (#items - 1) or 0), ch, false)
    end
    local lines, used = {}, 0
    for _, item in ipairs(items) do
        if #lines == 0 then lines[1] = {}; used = 0 end
        if horizontal and e.style["flex-wrap"] == "wrap" and #lines[#lines] > 0 and used + gap + item.hypothetical + item.outer > length then lines[#lines + 1] = {}; used = 0 end
        if #lines[#lines] > 0 then used = used + gap end
        lines[#lines][#lines[#lines] + 1] = item; used = used + item.hypothetical + item.outer
    end
    local crossStart, totalCross = 0, 0
    for _, line in ipairs(lines) do
        local gaps = gap * (#line - 1)
        local hypothetical = gaps; for _, item in ipairs(line) do hypothetical = hypothetical + item.hypothetical + item.outer end
        local growing = hypothetical < length
        for _, item in ipairs(line) do
            item.weight = growing and item.e:n("flex-grow") or item.e:n("flex-shrink") * item.base
            item.frozen = item.weight == 0 or growing and item.base > item.hypothetical or not growing and item.base < item.hypothetical
            item.size = item.hypothetical
        end
        while true do
            local free, weights, unfrozen = length - gaps, {}, 0
            for i, item in ipairs(line) do
                weights[i] = 0
                if item.frozen then free = free - item.size - item.outer else free = free - item.base - item.outer; weights[i], unfrozen = item.weight, unfrozen + 1 end
            end
            if unfrozen == 0 then break end
            local assignments = distribute(math.max(0, growing and free or -free), weights)
            local violations, totalViolation = {}, 0
            for i, item in ipairs(line) do
                if not item.frozen then
                    local tentative = item.base + (growing and assignments[i] or -assignments[i])
                    item.size = item.e:clamp(tentative, mainRef, horizontal)
                    violations[i] = item.size - tentative; totalViolation = totalViolation + violations[i]
                end
            end
            for i, item in ipairs(line) do if not item.frozen and (totalViolation == 0 or totalViolation > 0 and violations[i] > 0 or totalViolation < 0 and violations[i] < 0) then item.frozen = true end end
        end
        local lc = e.cw
        if horizontal then
            lc = 0
            for _, item in ipairs(line) do self:layoutElement(item.e, e.cw, k, item.size); item.cross = item.e.ch; lc = math.max(lc, item.cross + item.e:frame(false) + item.e:margin(false)) end
            if #lines == 1 then lc = k or e:clamp(lc, ch, false) end
        end
        local remaining, spaces = length - gaps, {}
        for i, item in ipairs(line) do remaining = remaining - item.size - item.outer; spaces[i] = 0 end
        local justify = e.style["justify-content"]
        if remaining > 0 then
            if justify == "end" then spaces[1] = remaining elseif justify == "center" then spaces[1] = remaining // 2
            elseif contains(justify, "space-between", "space-around", "space-evenly") then
                local weights = {}
                for i = 1, #line + 1 do
                    if justify == "space-between" then weights[i] = (i == 1 or i == #line + 1) and 0 or 1
                    elseif justify == "space-around" then weights[i] = (i == 1 or i == #line + 1) and 1 or 2 else weights[i] = 1 end
                end
                local values = distribute(remaining, weights); for i = 1, #line do spaces[i] = values[i] end
            end
        end
        local cursor = 0
        for i, item in ipairs(line) do
            local child, c = item.e, item.cross
            local align = child:align(e)
            if horizontal then
                if align == "stretch" and child.style.height == "auto" then c = child:clamp(math.max(0, lc - child:frame(false) - child:margin(false)), k, false); self:layoutElement(child, e.cw, k, item.size, c)
                else self:layoutElement(child, e.cw, k, item.size); c = child.ch end
            else self:layoutElement(child, e.cw, k, c, item.size) end
            local q = lc - c - child:frame(not horizontal) - child:margin(not horizontal)
            local offset = q > 0 and (align == "end" and q or align == "center" and q // 2 or 0) or 0
            cursor = cursor + spaces[i]
            local side = horizontal and (reversed and "right" or "left") or (reversed and "bottom" or "top")
            local main = reversed and length - cursor - child:n("margin-" .. side) - item.size - child:frame(horizontal) or cursor + child:n("margin-" .. side)
            local cross = offset + child:n(horizontal and "margin-top" or "margin-left") + (horizontal and crossStart or 0)
            if horizontal then position(e, child, main, cross) else position(e, child, cross, main) end
            cursor = cursor + item.size + item.outer + gap
        end
        crossStart, totalCross = crossStart + lc + e:n("row-gap"), totalCross + lc
    end
    if not horizontal then return length end
    return totalCross + (#lines > 0 and e:n("row-gap") * (#lines - 1) or 0)
end
local function area(sizes, start, span, gap) return sum(sizes, start, start + span - 1) + gap * (span - 1), sum(sizes, 1, start - 1) + gap * (start - 1) end
function D:grid(e, k)
    local items, nc, nr = self:placement(e)
    local contributions, widths, positions, actual = {}, {}, {}, {}
    for i, p in ipairs(items) do contributions[i] = self:contribution(p.e) end
    local columns = trackSizes(tracks(e.style["grid-template-columns"], true), nc, e.cw, e:n("column-gap"), items, contributions, true)
    for i, p in ipairs(items) do
        local aw, ax = area(columns, p.col, p.cols, e:n("column-gap"))
        local gw = p.e:clamp(p.e:resolve("width", aw, true) or math.max(0, aw - p.e:margin(true) - p.e:frame(true)), aw, true)
        widths[i], positions[i], actual[i] = aw, ax, gw
        self:layoutElement(p.e, aw, nil, gw)
        contributions[i] = p.e.ch + p.e:frame(false) + p.e:margin(false)
    end
    local rows = trackSizes(tracks(e.style["grid-template-rows"], false), nr, k, e:n("row-gap"), items, contributions, false)
    for i, p in ipairs(items) do
        local ah, ay = area(rows, p.row, p.rows, e:n("row-gap"))
        local child, fh = p.e, nil
        if child:align(e) == "stretch" and child.style.height == "auto" then fh = child:clamp(math.max(0, ah - child:frame(false) - child:margin(false)), ah, false) end
        self:layoutElement(child, widths[i], ah, actual[i], fh)
        local q, align = ah - child.ch - child:frame(false) - child:margin(false), child:align(e)
        local offset = q > 0 and (align == "end" and q or align == "center" and q // 2 or 0) or 0
        position(e, child, positions[i] + child:n("margin-left"), ay + offset + child:n("margin-top"))
    end
    return nr == 0 and 0 or sum(rows) + e:n("row-gap") * (nr - 1)
end
function D:layout()
    for _, e in ipairs(self.elements) do
        e.style = copy(initial)
        local specificities = {}
        for _, rule in ipairs(self.rules) do
            local specificity = -1
            for _, selector in ipairs(rule.selectors) do
                if selector:sub(1, 1) == "#" then if e.id == selector:sub(2) then specificity = math.max(specificity, 2) end
                elseif selector:sub(1, 1) == "." then if e.classes[selector:sub(2)] then specificity = math.max(specificity, 1) end
                elseif e.kind == selector then specificity = math.max(specificity, 0) end
            end
            if specificity >= 0 then for _, decl in ipairs(rule.declarations) do if specificities[decl[1]] == nil or specificity >= specificities[decl[1]] then e.style[decl[1]], specificities[decl[1]] = decl[2], specificity end end end
        end
        for p, v in pairs(e.inline) do e.style[p] = v end
        e.displayed, e.containing = e.style.display ~= "none" and (not e.parent or e.parent.displayed), nil
    end
    local root = self.elements[1]
    if root.displayed and root.style.position ~= "absolute" then self:layoutElement(root, self.width, self.height); root.rx, root.ry = root:n("margin-left"), root:n("margin-top") end
    for _, e in ipairs(self.elements) do
        if e.displayed and e.style.position == "absolute" then
            local ancestor = e.parent
            while ancestor and ancestor.style.position == "static" do ancestor = ancestor.parent end
            e.containing = ancestor
            local cbw, cbh = self.width, self.height
            if ancestor then cbw, cbh = ancestor.cw + ancestor:n("padding-left") + ancestor:n("padding-right"), ancestor.ch + ancestor:n("padding-top") + ancestor:n("padding-bottom") end
            local w = e:resolve("width", cbw, true)
            if w == nil then
                local r = math.max(0, cbw - (e.style.left ~= "auto" and e:n("left") or 0) - (e.style.right ~= "auto" and e:n("right") or 0) - e:margin(true) - e:frame(true))
                w = e.style.left ~= "auto" and e.style.right ~= "auto" and r or math.min(self:maxContent(e), r)
            end
            w = e:clamp(w, cbw, true)
            local fh
            if e.style.height == "auto" and e.style.top ~= "auto" and e.style.bottom ~= "auto" then fh = e:clamp(math.max(0, cbh - e:n("top") - e:n("bottom") - e:margin(false) - e:frame(false)), cbh, false) end
            self:layoutElement(e, cbw, cbh, w, fh)
            e.rx = e.style.left ~= "auto" and e:n("left") + e:n("margin-left") or e.style.right ~= "auto" and cbw - e:n("right") - e:n("margin-right") - e.cw - e:frame(true) or e:n("margin-left")
            e.ry = e.style.top ~= "auto" and e:n("top") + e:n("margin-top") or e.style.bottom ~= "auto" and cbh - e:n("bottom") - e:n("margin-bottom") - e.ch - e:frame(false) or e:n("margin-top")
        end
    end
    for _, e in ipairs(self.elements) do if e.displayed then
        local x, y = 0, 0
        if e.style.position == "absolute" then if e.containing then x, y = e.containing.x + e.containing:n("border-left"), e.containing.y + e.containing:n("border-top") end
        elseif e.parent then x, y = e.parent.x, e.parent.y end
        e.x, e.y = x + e.rx, y + e.ry
        if e.style.position == "relative" then
            e.x = e.x + (e.style.left ~= "auto" and e:n("left") or e.style.right ~= "auto" and -e:n("right") or 0)
            e.y = e.y + (e.style.top ~= "auto" and e:n("top") or e.style.bottom ~= "auto" and -e:n("bottom") or 0)
        end
    end end
end
function D:snapshot()
    local result = {}
    for i, e in ipairs(self.elements) do result[i] = e.displayed and table.concat(e:border(), ":") or "none" end
    return result
end
function D:changed(before)
    local after, names = self:snapshot(), {}
    for i, e in ipairs(self.elements) do if before[i] ~= after[i] then names[#names + 1] = e.id end end
    return #names > 0 and table.concat(names, " ") or "no change"
end
function D:render()
    local screen = {}
    for y = 0, self.height - 1 do screen[y] = {}; for x = 0, self.width - 1 do screen[y][x] = "." end end
    local function draw(x, y, c) if x >= 0 and x < self.width and y >= 0 and y < self.height then screen[y][x] = c end end
    for _, e in ipairs(self.elements) do if e.displayed then
        local r = e:border()
        for y = math.max(0, r[2]), math.min(self.height, r[2] + r[4]) - 1 do for x = math.max(0, r[1]), math.min(self.width, r[1] + r[3]) - 1 do
            local horizontal = e:n("border-top") == 1 and y == r[2] or e:n("border-bottom") == 1 and y == r[2] + r[4] - 1
            local vertical = e:n("border-left") == 1 and x == r[1] or e:n("border-right") == 1 and x == r[1] + r[3] - 1
            draw(x, y, horizontal and vertical and "+" or horizontal and "-" or vertical and "|" or " ")
        end end
        local c = e:content()
        for i, line in ipairs(e.lines) do for j = 1, #line do draw(c[1] + j - 1, c[2] + i - 1, line:sub(j, j)) end end
    end end
    self:emit("render %dx%d", self.width, self.height); self:emit("%s", string.rep("#", self.width + 2))
    for y = 0, self.height - 1 do local row = {}; for x = 0, self.width - 1 do row[#row + 1] = screen[y][x] end; self:emit("#%s#", table.concat(row)) end
    self:emit("%s", string.rep("#", self.width + 2))
end
function D:command(line)
    local args = split(line, " "); local command = table.remove(args, 1)
    if command == "LAYOUT" then
        self:emit("layout %dx%d", self.width, self.height)
        for _, e in ipairs(self.elements) do if e.displayed then self:emit("%s%s %d %d %d %d", string.rep(" ", e.depth * 2), e.id, table.unpack(e:border())) else self:emit("%s%s none", string.rep(" ", e.depth * 2), e.id) end end
    elseif command == "BOX" then
        local e = self.byID[args[1]]
        if not e then self:emit("error: unknown element %s", args[1]); return end
        if not e.displayed then self:emit("box %s: none", e.id); return end
        self:emit("box %s", e.id)
        local r = e:border()
        local padding = {r[1] + e:n("border-left"), r[2] + e:n("border-top"), e.cw + e:n("padding-left") + e:n("padding-right"), e.ch + e:n("padding-top") + e:n("padding-bottom")}
        local names = {"margin", "border", "padding", "content"}
        for i, box in ipairs({e:marginBox(), r, padding, e:content()}) do self:emit("%s %d %d %d %d", names[i], table.unpack(box)) end
    elseif command == "RENDER" then self:render()
    elseif command == "HIT" then
        local x, y = tonumber(args[1]), tonumber(args[2])
        if x >= self.width or y >= self.height then self:emit("error: point %d %d outside viewport", x, y); return end
        local found
        for _, e in ipairs(self.elements) do if e.displayed then local r = e:border(); if x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] then found = e end end end
        local path = {}; while found do table.insert(path, 1, found.id); found = found.parent end
        self:emit("hit %d %d: %s", x, y, #path > 0 and table.concat(path, " > ") or "none")
    elseif command == "SET" then
        local e, property = self.byID[args[1]], args[2]
        local value = table.concat(args, " ", 3)
        if not e then self:emit("error: unknown element %s", args[1]); return end
        if not initial[property] and not contains(property, "margin", "padding", "border", "gap") then self:emit("error: unknown property %s", property); return end
        local declarations = valid(property, value)
        if not declarations then self:emit("error: invalid value for %s: %s", property, value); return end
        local before = self:snapshot(); for _, decl in ipairs(declarations) do e.inline[decl[1]] = decl[2] end
        self:layout(); self:emit("set %s %s %s: %s", e.id, property, value, self:changed(before))
    elseif command == "VIEWPORT" then
        local w, h = tonumber(args[1]), tonumber(args[2])
        if w < 1 or w > 80 or h < 1 or h > 40 then self:emit("error: invalid viewport %d %d", w, h); return end
        local before = self:snapshot(); self.width, self.height = w, h; self:layout(); self:emit("viewport %d %d: %s", w, h, self:changed(before))
    elseif command == "OVERFLOW" then
        local names = {}
        for _, e in ipairs(self.elements) do if e.displayed then
            local overflow = false
            if e.text then overflow = #e.lines > e.ch; for _, text in ipairs(e.lines) do overflow = overflow or #text > e.cw end
            else
                local content = e:content()
                for _, child in ipairs(e:flow()) do local r = child:marginBox(); if r[1] < content[1] or r[2] < content[2] or r[1] + r[3] > content[1] + content[3] or r[2] + r[4] > content[2] + content[4] then overflow = true end end
            end
            if overflow then names[#names + 1] = e.id end
        end end
        self:emit("overflow: %s", #names > 0 and table.concat(names, " ") or "none")
    else self:emit("error: unknown command %s", command) end
end
local dimensions = split(io.read("*l"), " ")
D.width, D.height = tonumber(dimensions[1]), tonumber(dimensions[2])
while true do
    local line = io.read("*l"); if line == "---" then break end
    local at = line:find(" { ", 1, true)
    local rule = {selectors=split(line:sub(1, at - 1), ", "), declarations={}}
    for _, part in ipairs(split(line:sub(at + 3, -3), "; ")) do
        local colon = part:find(": ", 1, true)
        local declarations = valid(part:sub(1, colon - 1), part:sub(colon + 2))
        for _, decl in ipairs(declarations or {}) do rule.declarations[#rule.declarations + 1] = decl end
    end
    D.rules[#D.rules + 1] = rule
end
local stack = {}
while true do
    local line = io.read("*l"); if line == "===" then break end
    local indentation = line:match("^ *")
    local depth = #indentation // 2
    local head, text = line:sub(#indentation + 1):match("^([^ ]+) ?(.*)$")
    local kind, rest = head:match("^([^#]+)#(.+)$")
    local parts = split(rest, ".")
    local e = setmetatable({kind=kind, id=parts[1], text=text ~= "" and text:sub(2, -2) or nil, classes={}, inline={}, children={}, depth=depth, index=#D.elements + 1}, Element)
    for i = 2, #parts do e.classes[parts[i]] = true end
    if depth > 0 then e.parent = stack[depth]; e.parent.children[#e.parent.children + 1] = e end
    stack[depth + 1] = e; D.elements[#D.elements + 1] = e; D.byID[e.id] = e
end
D:layout()
while true do local line = io.read("*l"); if line == "END" then break end; D:command(line) end
if #D.output > 0 then io.write(table.concat(D.output, "\n"), "\n") end
