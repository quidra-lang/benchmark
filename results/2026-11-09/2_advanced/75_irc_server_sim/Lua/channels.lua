local matches = require('masks').matches
local Channel = {}
Channel.__index = Channel

local function remove(values, item)
    for index, value in ipairs(values) do
        if value == item then table.remove(values, index); return end
    end
end

function Channel.new(name, time)
    return setmetatable({name = name, created = time, members = {}, topic = '', bans = {},
        flags = {n = true, t = true}, key = '', limit = 0, peak = 0, messages = 0}, Channel)
end

function Channel:member(client)
    for _, member in ipairs(self.members) do
        if member.client == client then return member end
    end
end

function Channel:add(client, is_operator)
    local member = {client = client, is_operator = is_operator, voice = false}
    self.members[#self.members + 1] = member
    client.channels[#client.channels + 1] = self
    self.peak = math.max(self.peak, #self.members)
end

function Channel:remove(client)
    remove(self.members, self:member(client))
    remove(client.channels, self)
end

function Channel.status(member) return member.is_operator and '@' or member.voice and '+' or '' end
function Channel.display(member) return Channel.status(member) .. member.client.nickname end

function Channel:name_list(viewer)
    local inside, names = self:member(viewer) ~= nil, {}
    for _, member in ipairs(self.members) do
        if inside or not member.client.invisible then names[#names + 1] = Channel.display(member) end
    end
    return table.concat(names, ' ')
end

function Channel:banned(client)
    for _, ban in ipairs(self.bans) do
        if matches(ban.mask, client:prefix()) then return true end
    end
    return false
end

function Channel:can_speak(client)
    local member = self:member(client)
    local privileged = member and (member.is_operator or member.voice) or false
    return (member ~= nil or not self.flags.n) and (not self.flags.m or privileged)
        and (privileged or not self:banned(client))
end

function Channel:mode_display(include_key)
    local mode = '+'
    for character in ('iklmnt'):gmatch('.') do
        local present
        if character == 'k' then present = self.key ~= ''
        elseif character == 'l' then present = self.limit ~= 0
        else present = self.flags[character] end
        if present then mode = mode .. character end
    end
    if include_key ~= false and self.key ~= '' then mode = mode .. ' ' .. self.key end
    if self.limit ~= 0 then mode = mode .. ' ' .. self.limit end
    return mode
end

return Channel
