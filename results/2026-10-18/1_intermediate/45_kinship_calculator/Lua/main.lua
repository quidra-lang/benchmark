local sex_index = {M = 1, F = 2, X = 3}
local terms = {
    parent = {"father", "mother", "parent"},
    child = {"son", "daughter", "child"},
    sibling = {"brother", "sister", "sibling"},
    pibling = {"uncle", "aunt", "pibling"},
    nibling = {"nephew", "niece", "nibling"},
    spouse = {"husband", "wife", "spouse"},
    late = {"late husband", "late wife", "late spouse"},
    survivor = {"widower", "widow", "surviving spouse"},
    ex = {"ex-husband", "ex-wife", "ex-spouse"},
    stepparent = {"stepfather", "stepmother", "stepparent"},
    stepchild = {"stepson", "stepdaughter", "stepchild"},
    stepsibling = {"stepbrother", "stepsister", "stepsibling"},
    stepgrandparent = {"stepgrandfather", "stepgrandmother", "stepgrandparent"},
    stepgrandchild = {"stepgrandson", "stepgranddaughter", "stepgrandchild"},
    ["parent-in-law"] = {"father-in-law", "mother-in-law", "parent-in-law"},
    ["child-in-law"] = {"son-in-law", "daughter-in-law", "child-in-law"},
    ["sibling-in-law"] = {"brother-in-law", "sister-in-law", "sibling-in-law"},
}
local ordinals = {"first", "second", "third", "fourth", "fifth", "sixth",
                  "seventh", "eighth", "ninth", "tenth"}

local function gendered(kind, sex)
    return terms[kind][sex_index[sex]]
end

local function generation_prefix(g)
    if g == 1 then return "" end
    return string.rep("great-", g - 2) .. "grand"
end

local function ordinal(k)
    if k <= 10 then return ordinals[k] end
    local suffix = "th"
    if k % 100 < 11 or k % 100 > 13 then
        suffix = ({[1] = "st", [2] = "nd", [3] = "rd"})[k % 10] or "th"
    end
    return k .. suffix
end

local function kinship_term(da, db, sex)
    if da == 0 and db == 0 then return "self" end
    if da == 0 then return generation_prefix(db) .. gendered("parent", sex) end
    if db == 0 then return generation_prefix(da) .. gendered("child", sex) end
    if da == 1 and db == 1 then return gendered("sibling", sex) end
    if da == 1 then return generation_prefix(db - 1) .. gendered("pibling", sex) end
    if db == 1 then return generation_prefix(da - 1) .. gendered("nibling", sex) end
    local distance = math.abs(da - db)
    local removal = ""
    if distance == 1 then removal = " once removed"
    elseif distance == 2 then removal = " twice removed"
    elseif distance >= 3 then removal = " " .. distance .. " times removed" end
    return ordinal(math.min(da, db) - 1) .. " cousin" .. removal
end

local function fail(...)
    error({reason = table.concat({...}, " ")}, 0)
end

local function keys(set)
    local result = {}
    for key in pairs(set) do result[#result + 1] = key end
    return result
end

local function sorted_ids(set)
    local result = keys(set)
    table.sort(result)
    return result
end

local function has(array, value)
    for _, element in ipairs(array) do
        if element == value then return true end
    end
    return false
end

local function copy_array(array)
    local result = {}
    for i, value in ipairs(array) do result[i] = value end
    return result
end

local function add_all(target, source)
    for _, value in ipairs(source) do target[#target + 1] = value end
end

local function one_line(...)
    return {table.concat({...}, " ")}
end

local persons, marriages, history = {}, {}, {}
local children_cache, distance_cache, coefficient_cache, height_cache

local function check_person(x)
    if not persons[x] then fail("UNKNOWN PERSON", x) end
end

local function parents_of(x)
    return persons[x].parents
end

local function children_of(x)
    if not children_cache then
        children_cache = {}
        for id in pairs(persons) do children_cache[id] = {} end
        for child, person in pairs(persons) do
            for _, parent in ipairs(person.parents) do
                local children = children_cache[parent]
                children[#children + 1] = child
            end
        end
    end
    return children_cache[x]
end

local function age_less(a, b)
    if persons[a].birth ~= persons[b].birth then
        return persons[a].birth < persons[b].birth
    end
    return a < b
end

local function age_order(ids)
    local result = copy_array(ids)
    table.sort(result, age_less)
    return result
end

local function person_list(ids)
    if #ids == 0 then return "-" end
    return table.concat(age_order(ids), " ")
end

local function life_years(person)
    return person.birth .. "-" .. (person.death or "")
end

local function common_parents(a, b)
    local count = 0
    for _, parent in ipairs(parents_of(a)) do
        if has(parents_of(b), parent) then count = count + 1 end
    end
    return count
end

local function are_siblings(a, b)
    return a ~= b and common_parents(a, b) > 0
end

local function siblings_of(x)
    local result = {}
    for id in pairs(persons) do
        if are_siblings(x, id) then result[#result + 1] = id end
    end
    return result
end

local function contains(record, x)
    return record.first == x or record.second == x
end

local function other_person(record, x)
    return record.first == x and record.second or record.first
end

local function records_of(x)
    local result = {}
    for _, record in ipairs(marriages) do
        if contains(record, x) then result[#result + 1] = record end
    end
    return result
end

local function current_record(x)
    for _, record in ipairs(marriages) do
        if record.status == "current" and contains(record, x) then return record end
    end
end

local function spouse_of(x)
    local record = current_record(x)
    return record and other_person(record, x) or nil
end

local function last_record(a, b)
    local last
    for _, record in ipairs(marriages) do
        if contains(record, a) and contains(record, b) then last = record end
    end
    return last
end

local function partners_of(x)
    local latest, result = {}, {}
    for _, record in ipairs(records_of(x)) do latest[other_person(record, x)] = record end
    for other, record in pairs(latest) do
        if record.status ~= "divorced" then result[other] = true end
    end
    return result
end

local function step_related(pa, pb)
    for _, p in ipairs(pa) do
        local partners = partners_of(p)
        for _, q in ipairs(pb) do
            if partners[q] then return true end
        end
    end
    return false
end

local function distances(start, upward)
    local key = (upward and "up:" or "down:") .. start
    if distance_cache[key] then return distance_cache[key] end
    local result, queue = {[start] = 0}, {start}
    local position = 1
    while position <= #queue do
        local x = queue[position]
        position = position + 1
        local neighbors = upward and parents_of(x) or children_of(x)
        for _, y in ipairs(neighbors) do
            if result[y] == nil then
                result[y] = result[x] + 1
                queue[#queue + 1] = y
            end
        end
    end
    distance_cache[key] = result
    return result
end

local function is_ancestor(a, b)
    return a ~= b and distances(b, true)[a] ~= nil
end

local function grandparents_of(x)
    local result = {}
    for id, generation in pairs(distances(x, true)) do
        if generation == 2 then result[#result + 1] = id end
    end
    return result
end

local function apex(a, b)
    local da, db = distances(a, true), distances(b, true)
    if db[a] then return {id = a, da = 0, db = db[a], shares = 0} end
    if da[b] then return {id = b, da = da[b], db = 0, shares = 0} end
    local best
    for id, first_distance in pairs(da) do
        if db[id] then
            if not best or first_distance + db[id] < da[best] + db[best]
                or (first_distance + db[id] == da[best] + db[best]
                    and (first_distance < da[best] or (first_distance == da[best] and id < best))) then
                best = id
            end
        end
    end
    if not best then return nil end
    local shares = 0
    for id, first_distance in pairs(da) do
        if first_distance == da[best] and db[id] == db[best] then shares = shares + 1 end
    end
    return {id = best, da = da[best], db = db[best], shares = shares}
end

local function blood_term(top, sex)
    local prefix = top.shares == 1 and "half-" or top.shares >= 4 and "double " or ""
    return prefix .. kinship_term(top.da, top.db, sex)
end

local function relationship(a, b, sex)
    if a == b then return {"self"} end
    sex = sex or persons[a].sex
    local result = {}
    local function add(kind) result[#result + 1] = gendered(kind, sex) end
    local top = apex(a, b)
    if top then result[#result + 1] = blood_term(top, sex) end
    local record = last_record(a, b)
    if not record then
        for _, person in pairs(persons) do
            if has(person.parents, a) and has(person.parents, b) then
                result[#result + 1] = "co-parent"
                break
            end
        end
    elseif record.status == "current" then add("spouse")
    elseif record.status == "widowed" then add(record.died == a and "late" or "survivor")
    else add("ex") end
    local pa, pb = parents_of(a), parents_of(b)
    local partners_a, partners_b = partners_of(a), partners_of(b)
    if not has(pb, a) then
        for _, p in ipairs(pb) do
            if partners_a[p] then add("stepparent"); break end
        end
    end
    if not has(pa, b) then
        for _, p in ipairs(pa) do
            if partners_b[p] then add("stepchild"); break end
        end
    end
    if common_parents(a, b) == 0 and step_related(pa, pb) then add("stepsibling") end
    if not is_ancestor(a, b) then
        for _, p in ipairs(grandparents_of(b)) do
            if partners_a[p] then add("stepgrandparent"); break end
        end
    end
    if not is_ancestor(b, a) then
        for _, p in ipairs(grandparents_of(a)) do
            if partners_b[p] then add("stepgrandchild"); break end
        end
    end
    for p in pairs(partners_b) do
        if has(parents_of(p), a) then add("parent-in-law"); break end
    end
    for p in pairs(partners_a) do
        if has(parents_of(p), b) then add("child-in-law"); break end
    end
    local in_law = false
    for p in pairs(partners_b) do
        if are_siblings(a, p) then in_law = true; break end
    end
    if not in_law then
        for p in pairs(partners_a) do
            if are_siblings(p, b) then in_law = true; break end
        end
    end
    if in_law then add("sibling-in-law") end
    return result
end

local function relationship_text(a, b)
    local result = relationship(a, b)
    return #result > 0 and table.concat(result, ", ") or "no relation"
end

-- Coefficients are exact integer multiples of 2^-37.
local coefficient_scale = 1 << 37
local phi
local function inbreeding(x)
    local parents = parents_of(x)
    if #parents < 2 then return 0 end
    return phi(parents[1], parents[2])
end

phi = function(a, b)
    local key = a < b and a .. ":" .. b or b .. ":" .. a
    if coefficient_cache[key] ~= nil then return coefficient_cache[key] end
    local value
    if a == b then value = (coefficient_scale + inbreeding(a)) // 2
    else
        local x, y = a, b
        if persons[x].birth < persons[y].birth then x, y = y, x end
        value = 0
        for _, parent in ipairs(parents_of(x)) do value = value + phi(parent, y) end
        value = value // 2
    end
    coefficient_cache[key] = value
    return value
end

local function fraction_text(value)
    if value == 0 then return "0/1" end
    local denominator = coefficient_scale
    while denominator > 1 and value % 2 == 0 do
        value, denominator = value // 2, denominator // 2
    end
    return value .. "/" .. denominator
end

local function lineage_length(x)
    if height_cache[x] then return height_cache[x] end
    local height = 0
    for _, parent in ipairs(parents_of(x)) do height = math.max(height, lineage_length(parent)) end
    height_cache[x] = height + 1
    return height + 1
end

local function upward_path(x, top)
    local result = {x}
    while x ~= top do
        local required = distances(x, true)[top] - 1
        local best
        for _, parent in ipairs(parents_of(x)) do
            if distances(parent, true)[top] == required and (not best or parent < best) then best = parent end
        end
        x = best
        result[#result + 1] = x
    end
    return result
end

local function census_status(x, year)
    local last
    for _, record in ipairs(records_of(x)) do
        if record.start <= year then last = record end
    end
    if not last then return "single" end
    if not last.finish or last.finish > year then return "married " .. other_person(last, x) end
    return last.status
end

local function snapshot(line)
    local saved = {line = line, persons = {}, marriages = {}}
    for id, person in pairs(persons) do
        saved.persons[id] = {sex = person.sex, birth = person.birth, name = person.name,
                             death = person.death, parents = copy_array(person.parents)}
    end
    for i, record in ipairs(marriages) do
        local copy = {}
        for key, value in pairs(record) do copy[key] = value end
        saved.marriages[i] = copy
    end
    return saved
end

local modifying = {PERSON = true, DEATH = true, REMOVE = true, PARENT = true,
                   UNPARENT = true, SPOUSE = true, DIVORCE = true}
local two_ids = {PARENT = true, UNPARENT = true, SPOUSE = true, DIVORCE = true,
                 RELATION = true, PATH = true, COMMON = true, KINSHIP = true}
local single_id = {DEATH = true, REMOVE = true, INFO = true, RELATIVES = true, WHO = true,
                   ANCESTORS = true, DESCENDANTS = true, COUSINS = true, SIBLINGS = true,
                   GENERATIONS = true, TREE = true, PEDIGREE = true, TIMELINE = true, FIND = true}
local handlers = {}

function handlers.PERSON(words)
    local x, sex, birth, name = words[2], words[3], tonumber(words[4]), words[5]
    if persons[x] then fail("DUPLICATE PERSON", x) end
    persons[x] = {sex = sex, birth = birth, name = name, parents = {}}
    return one_line("ADDED", x, name, sex, birth)
end

function handlers.DEATH(words)
    local x, year = words[2], tonumber(words[3])
    local person = persons[x]
    if person.death then fail("ALREADY DECEASED", x) end
    if year < person.birth then fail("BAD YEAR", x) end
    for _, record in ipairs(records_of(x)) do
        if year < record.start or (record.finish and year < record.finish) then fail("BAD YEAR", x) end
    end
    local children = copy_array(children_of(x))
    table.sort(children)
    for _, child in ipairs(children) do
        if persons[child].birth > year + 1 then fail("AFTER DEATH", child, x) end
    end
    person.death = year
    local record = current_record(x)
    if not record then return one_line("DIED", x, year) end
    record.finish, record.status, record.died = year, "widowed", x
    return one_line("DIED", x, year, "spouse=" .. other_person(record, x))
end

function handlers.REMOVE(words)
    local x = words[2]
    for _, person in pairs(persons) do
        local parents = {}
        for _, parent in ipairs(person.parents) do
            if parent ~= x then parents[#parents + 1] = parent end
        end
        person.parents = parents
    end
    local remaining = {}
    for _, record in ipairs(marriages) do
        if not contains(record, x) then remaining[#remaining + 1] = record end
    end
    marriages, persons[x] = remaining, nil
    return one_line("REMOVED", x)
end

function handlers.PARENT(words)
    local child, parent = words[2], words[3]
    if child == parent then fail("SAME PERSON", child) end
    if has(parents_of(child), parent) then fail("ALREADY PARENT", child, parent) end
    if #parents_of(child) == 2 then fail("TOO MANY PARENTS", child) end
    if is_ancestor(child, parent) then fail("CYCLE", child, parent) end
    if persons[parent].birth + 12 > persons[child].birth then fail("AGE GAP", child, parent) end
    if persons[parent].death and persons[parent].death + 1 < persons[child].birth then fail("AFTER DEATH", child, parent) end
    local parents = parents_of(child)
    parents[#parents + 1] = parent
    return one_line("LINKED", child, parent, gendered("parent", persons[parent].sex))
end

function handlers.UNPARENT(words)
    local child, parent = words[2], words[3]
    if not has(parents_of(child), parent) then fail("NOT PARENT", child, parent) end
    for i, id in ipairs(parents_of(child)) do
        if id == parent then table.remove(parents_of(child), i); break end
    end
    return one_line("UNLINKED", child, parent)
end

function handlers.SPOUSE(words)
    local a, b, year = words[2], words[3], tonumber(words[4])
    if a == b then fail("SAME PERSON", a) end
    for _, x in ipairs({a, b}) do
        if persons[x].death then fail("DECEASED", x) end
    end
    for _, x in ipairs({a, b}) do
        if spouse_of(x) then fail("ALREADY MARRIED", x) end
    end
    if is_ancestor(a, b) or is_ancestor(b, a) or are_siblings(a, b) then fail("CLOSE KIN", a, b) end
    for _, x in ipairs({a, b}) do
        if year < persons[x].birth + 16 then fail("TOO YOUNG", x) end
    end
    for _, x in ipairs({a, b}) do
        for _, record in ipairs(records_of(x)) do
            if record.finish and record.finish >= year then fail("BAD YEAR", x) end
        end
    end
    marriages[#marriages + 1] = {first = a, second = b, start = year, status = "current"}
    return one_line("MARRIED", a, b, year)
end

function handlers.DIVORCE(words)
    local a, b, year = words[2], words[3], tonumber(words[4])
    if spouse_of(a) ~= b then fail("NOT MARRIED", a, b) end
    local record = current_record(a)
    if year <= record.start then fail("BAD YEAR", a) end
    record.finish, record.status = year, "divorced"
    return one_line("DIVORCED", a, b, year)
end

function handlers.UNDO()
    if #history == 0 then fail("NOTHING TO UNDO") end
    local saved = table.remove(history)
    persons, marriages = saved.persons, saved.marriages
    return {"UNDONE " .. saved.line}
end

function handlers.INFO(words)
    local x = words[2]
    local person = persons[x]
    local lines = {table.concat({"INFO", x, person.name, person.sex, life_years(person)}, " "),
                   "  parents: " .. person_list(parents_of(x))}
    for _, record in ipairs(records_of(x)) do
        lines[#lines + 1] = "  marriage: " .. other_person(record, x) .. " " .. record.start
            .. "-" .. (record.finish or "") .. " " .. record.status
    end
    lines[#lines + 1] = "  children: " .. person_list(children_of(x))
    lines[#lines + 1] = "  siblings: " .. person_list(siblings_of(x))
    lines[#lines + 1] = "  inbreeding: " .. fraction_text(inbreeding(x))
    return lines
end

function handlers.RELATION(words)
    return {"RELATION " .. words[2] .. " " .. words[3] .. ": " .. relationship_text(words[2], words[3])}
end

function handlers.RELATIVES(words)
    local x, lines = words[2], {}
    for _, y in ipairs(sorted_ids(persons)) do
        if y ~= x then
            local relation = relationship(y, x)
            if #relation > 0 then lines[#lines + 1] = "  " .. y .. ": " .. table.concat(relation, ", ") end
        end
    end
    table.insert(lines, 1, "RELATIVES " .. x .. " " .. #lines)
    return lines
end

function handlers.WHO(words)
    local x, lines = words[2], {}
    local query = table.concat(words, " ", 3)
    for _, y in ipairs(sorted_ids(persons)) do
        if y ~= x then
            local relation, neutral = relationship(y, x), relationship(y, x, "X")
            for i, term in ipairs(relation) do
                if term == query or neutral[i] == query then
                    lines[#lines + 1] = "  " .. y .. ": " .. term
                    break
                end
            end
        end
    end
    table.insert(lines, 1, "WHO " .. x .. " " .. query .. " " .. #lines)
    return lines
end

function handlers.PATH(words)
    local a, b = words[2], words[3]
    local top = apex(a, b)
    if not top then return one_line("PATH", a, b, "none") end
    local route, second = upward_path(a, top.id), upward_path(b, top.id)
    for i = #second - 1, 1, -1 do route[#route + 1] = second[i] end
    return {"PATH " .. a .. " " .. b .. " " .. (top.da + top.db) .. ": " .. table.concat(route, " ")}
end

function handlers.COMMON(words)
    local a, b = words[2], words[3]
    local da, db, shared = distances(a, true), distances(b, true), {}
    for id in pairs(da) do
        if db[id] then shared[id] = true end
    end
    local nearest = {}
    for id in pairs(shared) do
        local is_nearest = true
        for _, child in ipairs(children_of(id)) do
            if shared[child] then is_nearest = false; break end
        end
        if is_nearest then nearest[#nearest + 1] = id end
    end
    table.sort(nearest, function(x, y)
        local sx, sy = da[x] + db[x], da[y] + db[y]
        return sx < sy or (sx == sy and x < y)
    end)
    local lines = {"COMMON " .. a .. " " .. b .. " " .. #nearest}
    for _, id in ipairs(nearest) do lines[#lines + 1] = "  " .. id .. " " .. da[id] .. " " .. db[id] end
    return lines
end

local function lineage(words, upward)
    local x = words[2]
    local d, ids = distances(x, upward), {}
    for id in pairs(d) do
        if id ~= x then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return d[a] < d[b] or (d[a] == d[b] and a < b) end)
    local lines = {words[1] .. " " .. x .. " " .. #ids}
    for _, id in ipairs(ids) do
        local term = upward and kinship_term(0, d[id], persons[id].sex) or kinship_term(d[id], 0, persons[id].sex)
        lines[#lines + 1] = "  " .. d[id] .. " " .. id .. " " .. term
    end
    return lines
end
function handlers.ANCESTORS(words) return lineage(words, true) end
function handlers.DESCENDANTS(words) return lineage(words, false) end

function handlers.COUSINS(words)
    local x, degree, matches = words[2], tonumber(words[3]), {}
    for y in pairs(persons) do
        if y ~= x then
            local top = apex(y, x)
            if top and top.da >= 2 and top.db >= 2 and math.min(top.da, top.db) - 1 == degree then
                matches[#matches + 1] = {id = y, removal = math.abs(top.da - top.db), term = blood_term(top, persons[y].sex)}
            end
        end
    end
    table.sort(matches, function(a, b)
        return a.removal < b.removal or (a.removal == b.removal and a.id < b.id)
    end)
    local lines = {"COUSINS " .. x .. " " .. degree .. " " .. #matches}
    for _, match in ipairs(matches) do lines[#lines + 1] = "  " .. match.id .. " " .. match.term end
    return lines
end

function handlers.SIBLINGS(words)
    local x, lines, earlier = words[2], {}, 0
    for _, y in ipairs(age_order(keys(persons))) do
        if y ~= x then
            local common = common_parents(x, y)
            local kind
            if common == 2 then kind = "full"
            elseif common == 1 then kind = "half"
            elseif step_related(parents_of(x), parents_of(y)) then kind = "step" end
            if kind then
                if kind ~= "step" and age_less(y, x) then earlier = earlier + 1 end
                lines[#lines + 1] = "  " .. y .. " " .. kind .. " " .. persons[y].birth
            end
        end
    end
    table.insert(lines, 1, "SIBLINGS " .. x .. " " .. #lines .. " order=" .. (earlier + 1))
    return lines
end

function handlers.GENERATIONS(words)
    local x, groups = words[2], {}
    for id, generation in pairs(distances(x, false)) do
        if id ~= x then
            local group = groups[generation]
            if not group then group = {}; groups[generation] = group end
            group[#group + 1] = id
        end
    end
    local generations = keys(groups)
    table.sort(generations)
    local lines = {"GENERATIONS " .. x .. " " .. #generations}
    for _, generation in ipairs(generations) do
        local members, living, minimum, maximum = groups[generation], 0, math.huge, -math.huge
        for _, id in ipairs(members) do
            local person = persons[id]
            if not person.death then living = living + 1 end
            minimum, maximum = math.min(minimum, person.birth), math.max(maximum, person.birth)
        end
        lines[#lines + 1] = "  " .. generation .. " " .. #members .. " " .. living .. " " .. minimum .. "-" .. maximum
    end
    return lines
end

function handlers.TREE(words)
    local x, lines, visited = words[2], {}, {}
    local function visit(id, depth)
        local indent = string.rep("  ", depth + 1)
        if visited[id] then lines[#lines + 1] = indent .. id .. " (see above)"; return end
        visited[id] = true
        local person = persons[id]
        local line = indent .. id .. " " .. person.name .. " " .. life_years(person)
        local spouse = spouse_of(id)
        if spouse then line = line .. " = " .. spouse end
        lines[#lines + 1] = line
        for _, child in ipairs(age_order(children_of(id))) do visit(child, depth + 1) end
    end
    visit(x, 0)
    table.insert(lines, 1, "TREE " .. x .. " " .. (#keys(distances(x, false)) - 1))
    return lines
end

function handlers.PEDIGREE(words)
    local x, depth, lines, entered = words[2], tonumber(words[3]), {}, {}
    local function enter(id, number, generation)
        local person = persons[id]
        lines[#lines + 1] = string.rep("  ", generation + 1) .. number .. " " .. id .. " " .. person.name .. " " .. life_years(person)
        entered[id] = true
        if generation < depth then
            local parents = copy_array(parents_of(id))
            table.sort(parents, function(a, b)
                local sa, sb = sex_index[persons[a].sex], sex_index[persons[b].sex]
                return sa < sb or (sa == sb and a < b)
            end)
            for i, parent in ipairs(parents) do enter(parent, 2 * number + i - 1, generation + 1) end
        end
    end
    enter(x, 1, 0)
    table.insert(lines, 1, "PEDIGREE " .. x .. " " .. depth .. " entries=" .. #lines .. " distinct=" .. #keys(entered))
    return lines
end

function handlers.TIMELINE(words)
    local x, events = words[2], {}
    local person = persons[x]
    local function event(year, rank, counterpart, text)
        events[#events + 1] = {year = year, rank = rank, counterpart = counterpart, text = text}
    end
    event(person.birth, 0, "", "born")
    for _, record in ipairs(records_of(x)) do
        local other = other_person(record, x)
        event(record.start, 1, other, "married " .. other)
        if record.status == "divorced" then event(record.finish, 3, other, "divorced " .. other)
        elseif record.status == "widowed" and record.died == other then event(record.finish, 4, other, "widowed " .. other) end
    end
    for _, child in ipairs(children_of(x)) do event(persons[child].birth, 2, child, "child " .. child) end
    for _, group in ipairs({{label = "parent", ids = parents_of(x)}, {label = "child", ids = children_of(x)}}) do
        for _, other in ipairs(group.ids) do
            local death = persons[other].death
            if death and death >= person.birth and (not person.death or death <= person.death) then
                event(death, 5, other, "lost " .. group.label .. " " .. other)
            end
        end
    end
    if person.death then event(person.death, 6, "", "died") end
    table.sort(events, function(a, b)
        if a.year ~= b.year then return a.year < b.year end
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.counterpart < b.counterpart
    end)
    local lines = {"TIMELINE " .. x .. " " .. #events}
    for _, e in ipairs(events) do lines[#lines + 1] = "  " .. e.year .. " " .. e.text end
    return lines
end

function handlers.CENSUS(words)
    local year, residents = tonumber(words[2]), {}
    for id, person in pairs(persons) do
        if person.birth <= year and (not person.death or person.death > year) then residents[#residents + 1] = id end
    end
    local lines = {"CENSUS " .. year .. " " .. #residents}
    for _, id in ipairs(age_order(residents)) do
        lines[#lines + 1] = "  " .. id .. " " .. (year - persons[id].birth) .. " " .. census_status(id, year)
    end
    return lines
end

function handlers.KINSHIP(words)
    return one_line("KINSHIP", words[2], words[3], fraction_text(phi(words[2], words[3])))
end

local steps = {
    parent = {"parent"}, father = {"parent", "M"}, mother = {"parent", "F"},
    child = {"child"}, son = {"child", "M"}, daughter = {"child", "F"},
    sibling = {"sibling"}, brother = {"sibling", "M"}, sister = {"sibling", "F"},
    spouse = {"spouse"}, husband = {"spouse", "M"}, wife = {"spouse", "F"},
}
function handlers.FIND(words)
    local x, route = words[2], words[3]
    local current = {[x] = true}
    for step in route:gmatch("[^.]+") do
        local kind, sex = steps[step][1], steps[step][2]
        local collected = {}
        for id in pairs(current) do
            local targets
            if kind == "parent" then targets = parents_of(id)
            elseif kind == "child" then targets = children_of(id)
            elseif kind == "sibling" then targets = siblings_of(id)
            else targets = {spouse_of(id)} end
            for _, target in ipairs(targets) do
                if not sex or persons[target].sex == sex then collected[target] = true end
            end
        end
        current = collected
    end
    current[x] = nil
    local ids = sorted_ids(current)
    local lines = {"FIND " .. x .. " " .. route .. " " .. #ids}
    for _, id in ipairs(ids) do lines[#lines + 1] = "  " .. id .. ": " .. relationship_text(id, x) end
    return lines
end

function handlers.TERM(words)
    return one_line("TERM", words[2], words[3], words[4], kinship_term(tonumber(words[2]), tonumber(words[3]), words[4]))
end

function handlers.STATS()
    local count, living, links, couples, founders, generations = 0, 0, 0, 0, 0, 0
    for id, person in pairs(persons) do
        count = count + 1
        if not person.death then living = living + 1 end
        links = links + #person.parents
        if #person.parents == 0 then founders = founders + 1 end
        generations = math.max(generations, lineage_length(id))
    end
    for _, record in ipairs(marriages) do
        if record.status == "current" then couples = couples + 1 end
    end
    return {"STATS persons=" .. count .. " living=" .. living .. " links=" .. links
        .. " couples=" .. couples .. " founders=" .. founders .. " generations=" .. generations}
end

function handlers.AUDIT()
    local lines = {}
    for _, record in ipairs(marriages) do
        local top = apex(record.first, record.second)
        if top then lines[#lines + 1] = "  marriage " .. record.first .. " " .. record.second .. " " .. blood_term(top, persons[record.first].sex) end
    end
    for _, id in ipairs(sorted_ids(persons)) do
        local value = inbreeding(id)
        if value ~= 0 then lines[#lines + 1] = "  inbred " .. id .. " " .. fraction_text(value) end
    end
    table.insert(lines, 1, "AUDIT " .. #lines)
    return lines
end

local function execute(line)
    children_cache, distance_cache, coefficient_cache, height_cache = nil, {}, {}, {}
    local words = {}
    for word in line:gmatch("%S+") do words[#words + 1] = word end
    local command = words[1]
    if single_id[command] or two_ids[command] then check_person(words[2]) end
    if two_ids[command] then check_person(words[3]) end
    local saved = modifying[command] and snapshot(line) or nil
    local result = handlers[command](words)
    if saved then history[#history + 1] = saved end
    return result
end

local count = tonumber(io.read("l"))
local output = {}
for _ = 1, count do
    local ok, result = pcall(execute, io.read("l"))
    if ok then add_all(output, result)
    else output[#output + 1] = "ERROR " .. result.reason end
end
io.write(table.concat(output, "\n"), "\n")
