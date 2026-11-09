local Topology = {}
Topology.__index = Topology
local prefixes = {}

function Topology.words(line)
    local fields = {}
    for word in line:gmatch("%S+") do fields[#fields + 1] = word end
    return fields
end

function Topology.read(path)
    local result = {}
    for line in io.lines(path) do result[#result + 1] = Topology.words(line) end
    return result
end

function Topology.address(text)
    local value = 0
    for octet in text:gmatch("%d+") do value = (value << 8) + tonumber(octet) end
    return value
end

function Topology.address_text(value)
    return string.format("%d.%d.%d.%d", (value >> 24) & 255, (value >> 16) & 255,
        (value >> 8) & 255, value & 255)
end

function Topology.prefix(text)
    if not prefixes[text] then
        local address, length = text:match("^([^/]+)/(%d+)$")
        prefixes[text] = {address = Topology.address(address), length = tonumber(length)}
    end
    return prefixes[text]
end

function Topology.contains(prefix, address)
    if type(prefix) == "string" then prefix = Topology.prefix(prefix) end
    local shift = 32 - prefix.length
    return address >> shift == prefix.address >> shift
end

function Topology.less(first, second)
    local a, b = Topology.prefix(first), Topology.prefix(second)
    if a.address ~= b.address then return a.address < b.address end
    return a.length < b.length
end

function Topology.sorted(items)
    local result = {}
    for prefix in pairs(items) do result[#result + 1] = prefix end
    table.sort(result, Topology.less)
    return result
end

local Link = {}
Link.__index = Link

function Link:other(owner)
    return owner == self.first and self.second or self.first
end

function Link:role(owner)
    if self.relationship == "P2P" then return "peer" end
    return owner == self.first and "customer" or "provider"
end

function Link:direction(owner)
    return ({customer = "D", peer = "P", provider = "U"})[self:role(owner)]
end

function Topology.new()
    local self = setmetatable({router_ids = {}, ases = {}, links = {}, by_name = {}, at_as = {},
        between = {}, initial = {}}, Topology)
    for _, f in ipairs(Topology.read("input/topology.txt")) do
        if f[1] == "AS" then
            local owner = tonumber(f[2])
            self.router_ids[owner], self.at_as[owner] = Topology.address(f[3]), {}
            self.ases[#self.ases + 1] = owner
        elseif f[1] == "LINK" then
            local link = setmetatable({number = #self.links, name = f[2], first = tonumber(f[3]),
                second = tonumber(f[4]), relationship = f[5], delay = tonumber(f[6]),
                mrai = tonumber(f[7]), up = true, down_count = 0}, Link)
            self.links[#self.links + 1], self.by_name[link.name] = link, link
            local first, second = self.at_as[link.first], self.at_as[link.second]
            first[#first + 1], second[#second + 1] = link, link
            local low, high = math.min(link.first, link.second), math.max(link.first, link.second)
            local key = low .. ":" .. high
            if not self.between[key] then self.between[key] = link end
        else
            Topology.prefix(f[3])
            self.initial[#self.initial + 1] = f
        end
    end
    table.sort(self.ases)
    return self
end

function Topology:connecting(first, second)
    return self.between[math.min(first, second) .. ":" .. math.max(first, second)]
end

return Topology
