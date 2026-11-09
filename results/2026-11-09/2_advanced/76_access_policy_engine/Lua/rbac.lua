local RBAC = {}
RBAC.__index = RBAC
local function names(set)
    local result = {}
    for name in pairs(set) do result[#result + 1] = name end
    table.sort(result); return result
end
local function overlap(first, second)
    local result = {}
    for role in pairs(first) do if second[role] then result[#result + 1] = role end end
    table.sort(result); return result
end
function RBAC:closure(roles)
    local reached, pending = {}, {}
    for role in pairs(roles) do reached[role] = true; pending[#pending + 1] = role end
    while #pending > 0 do
        for junior in pairs(self.inherits[table.remove(pending)]) do
            if not reached[junior] then reached[junior] = true; pending[#pending + 1] = junior end
        end
    end
    return reached
end
function RBAC:path(start, finish)
    local failed = {}
    local function visit(role)
        if role == finish then return {role} end
        if failed[role] then return nil end
        for _, junior in ipairs(names(self.inherits[role])) do
            local suffix = visit(junior)
            if suffix then table.insert(suffix, 1, role); return suffix end
        end
        failed[role] = true
    end
    return visit(start)
end
function RBAC:assigned(user, day)
    local roles = {}
    for _, a in ipairs(self.assignments) do if a.user == user and a.first <= day and day <= a.last then roles[a.role] = true end end
    return roles
end
function RBAC:authorized(user, day) return self:closure(self:assigned(user, day)) end
function RBAC:accept(keyword, f)
    if keyword == 'ROLE' then
        if self.roles[f[2]] then return 'duplicate role ' .. f[2] end
        self.roles[f[2]], self.inherits[f[2]], self.permissions[f[2]] = true, {}, {}
    elseif keyword == 'INHERITS' then
        local senior, junior = f[2], f[3]
        for _, role in ipairs({senior, junior}) do if not self.roles[role] then return 'unknown role ' .. role end end
        if self.inherits[senior][junior] then return 'duplicate inheritance ' .. senior .. ' ' .. junior end
        if self:closure({[junior] = true})[senior] then
            local path = self:path(junior, senior); table.insert(path, 1, senior); return 'cycle ' .. table.concat(path, ' > ')
        end
        self.inherits[senior][junior] = true
    elseif keyword == 'PERMIT' then
        local role, permission = f[2], f[3] .. ' ' .. f[4]
        if not self.roles[role] then return 'unknown role ' .. role end
        if self.permissions[role][permission] then return 'duplicate permission ' .. role .. ' ' .. permission end
        self.permissions[role][permission], self.grants[role .. ' ' .. permission] = true, true
    elseif keyword == 'SSD' or keyword == 'DSD' then
        local collection, name, cardinality = keyword == 'SSD' and self.ssd or self.dsd, f[2], tonumber(f[3])
        for _, item in ipairs(collection) do if item.name == name then return 'duplicate constraint ' .. name end end
        local roles, length = {}, 0
        for role in f[4]:gmatch('[^,]+') do
            if not self.roles[role] then return 'unknown role ' .. role end
            roles[role], length = true, length + 1
        end
        if cardinality < 2 or cardinality > length then return 'bad cardinality ' .. name .. ' ' .. cardinality end
        collection[#collection + 1] = {name = name, cardinality = cardinality, roles = roles}
    else
        local user, role, first, last = f[2], f[3], tonumber(f[4]), tonumber(f[5])
        if not self.roles[role] then return 'unknown role ' .. role end
        if not (1 <= first and first <= last and last <= 365) then return 'bad range ' .. first .. ' ' .. last end
        for _, constraint in ipairs(self.ssd) do
            for day = first, last do
                local roles = self:assigned(user, day); roles[role] = true
                local intersection = overlap(constraint.roles, self:closure(roles))
                if #intersection >= constraint.cardinality then return 'ssd ' .. constraint.name .. ' day ' .. day .. ' roles ' .. table.concat(intersection, ',') end
            end
        end
        self.assignments[#self.assignments + 1] = {user = user, role = role, first = first, last = last}
    end
end
function RBAC.new()
    local self = setmetatable({roles = {}, inherits = {}, permissions = {}, ssd = {}, dsd = {}, assignments = {}, diagnostics = {}, grants = {}}, RBAC)
    local lines = {}
    for line in io.lines('input/rbac.txt') do
        local fields = {}; for field in line:gmatch('%S+') do fields[#fields + 1] = field end
        lines[#lines + 1] = fields
    end
    for _, keyword in ipairs({'ROLE', 'INHERITS', 'PERMIT', 'SSD', 'DSD', 'ASSIGN'}) do
        for number, fields in ipairs(lines) do
            if fields[1] == keyword then
                local reason = self:accept(keyword, fields)
                if reason then self.diagnostics[#self.diagnostics + 1] = {number = number, keyword = keyword, reason = reason} end
            end
        end
    end
    table.sort(self.diagnostics, function(a, b) return a.number < b.number end)
    return self
end
return RBAC
