local protocol = require('protocol')
local masks = require('masks')
local Client = require('clients')
local Channel = require('channels')
local modes = require('modes')

local function add(counts, key, amount) counts[key] = (counts[key] or 0) + (amount or 1) end
local function count(counts, key) return counts[key] or 0 end
local function contains(values, item)
    for _, value in ipairs(values) do if value == item then return true end end
    return false
end
local function remove(values, item)
    for index, value in ipairs(values) do if value == item then table.remove(values, index); return end end
end
local function split(value)
    local values = {}
    for item in value:gmatch('[^,]+') do values[#values + 1] = item end
    return values
end
local function sorted_keys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end
local function sum(values)
    local result = 0
    for _, value in pairs(values) do result = result + value end
    return result
end

local numeric_contents = {
    [1] = function(s, c) return ':Welcome to the Internet Relay Network ' .. c:prefix() end,
    [2] = function(s) return ':Your host is ' .. s.settings.NAME .. ', running version ' .. s.settings.VERSION end,
    [3] = function(s) return ':This server was created ' .. s.settings.CREATED end,
    [4] = function(s) return s.settings.NAME .. ' ' .. s.settings.VERSION .. ' i biklmnotv' end,
    [5] = function(s)
        local v = s.settings
        return 'CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=' .. v.NICKLEN .. ' CHANNELLEN=' .. v.CHANNELLEN
            .. ' TOPICLEN=' .. v.TOPICLEN .. ' CHANLIMIT=#:' .. v.MAXCHANNELS
            .. ' CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server'
    end,
    [221] = function(s, c) return c:mode() end,
    [301] = function(s, c, v) return v.user.nickname .. ' :' .. v.user.away end,
    [305] = ':You are no longer marked as being away',
    [306] = ':You have been marked as being away',
    [311] = function(s, c, v) local u = v.user; return u.nickname .. ' ' .. u.username .. ' ' .. u.hostname .. ' * :' .. u.realname end,
    [312] = function(s, c, v) return v.user.nickname .. ' ' .. s.settings.NAME .. ' :' .. s.settings.DESCRIPTION end,
    [317] = function(s, c, v) local u = v.user; return u.nickname .. ' ' .. (s.time - u.last_speaking) .. ' ' .. u.registration_time .. ' :seconds idle, signon time' end,
    [318] = function(s, c, v) return v.x .. ' :End of /WHOIS list.' end,
    [319] = function(s, c, v) return v.user.nickname .. ' :' .. s:joined_channels(v.user, ' ') end,
    [324] = function(s, c, v) return v.channel.name .. ' ' .. v.channel:mode_display(v.channel:member(c) ~= nil) end,
    [329] = function(s, c, v) return v.channel.name .. ' ' .. v.channel.created end,
    [331] = function(s, c, v) return v.channel.name .. ' :No topic is set' end,
    [332] = function(s, c, v) return v.channel.name .. ' :' .. v.channel.topic end,
    [333] = function(s, c, v) local ch = v.channel; return ch.name .. ' ' .. ch.topic_setter .. ' ' .. ch.topic_time end,
    [341] = function(s, c, v) return v.user.nickname .. ' ' .. v.channel.name end,
    [353] = function(s, c, v) return '= ' .. v.channel.name .. ' :' .. v.text end,
    [366] = function(s, c, v) return v.x .. ' :End of /NAMES list.' end,
    [367] = function(s, c, v) return v.channel.name .. ' ' .. v.ban.mask .. ' ' .. v.ban.setter .. ' ' .. v.ban.time end,
    [368] = function(s, c, v) return v.channel.name .. ' :End of channel ban list' end,
    [372] = function(s, c, v) return ':- ' .. v.text end,
    [375] = function(s) return ':- ' .. s.settings.NAME .. ' Message of the day -' end,
    [376] = ':End of /MOTD command.',
    [401] = function(s, c, v) return v.x .. ' :No such nick/channel' end,
    [403] = function(s, c, v) return v.x .. ' :No such channel' end,
    [404] = function(s, c, v) return v.channel.name .. ' :Cannot send to channel' end,
    [405] = function(s, c, v) return v.x .. ' :You have joined too many channels' end,
    [409] = ':No origin specified',
    [411] = function(s, c, v) return ':No recipient given (' .. v.command .. ')' end,
    [412] = ':No text to send',
    [421] = function(s, c, v) return v.command .. ' :Unknown command' end,
    [431] = ':No nickname given',
    [432] = function(s, c, v) return v.x .. ' :Erroneous nickname' end,
    [433] = function(s, c, v) return v.x .. ' :Nickname is already in use' end,
    [441] = function(s, c, v) return v.user.nickname .. ' ' .. v.channel.name .. " :They aren't on that channel" end,
    [442] = function(s, c, v) return v.channel.name .. " :You're not on that channel" end,
    [443] = function(s, c, v) return v.user.nickname .. ' ' .. v.channel.name .. ' :is already on channel' end,
    [451] = ':You have not registered',
    [461] = function(s, c, v) return v.command .. ' :Not enough parameters' end,
    [462] = ':You may not reregister',
    [467] = function(s, c, v) return v.channel.name .. ' :Channel key already set' end,
    [471] = function(s, c, v) return v.channel.name .. ' :Cannot join channel (+l)' end,
    [472] = function(s, c, v) return v.character .. ' :is unknown mode char to me for ' .. v.channel.name end,
    [473] = function(s, c, v) return v.channel.name .. ' :Cannot join channel (+i)' end,
    [474] = function(s, c, v) return v.channel.name .. ' :Cannot join channel (+b)' end,
    [475] = function(s, c, v) return v.channel.name .. ' :Cannot join channel (+k)' end,
    [482] = function(s, c, v) return v.channel.name .. " :You're not channel operator" end,
    [501] = ':Unknown MODE flag',
    [502] = ':Cannot change mode for other users',
}

local Server = {}
Server.__index = Server
function Server.new()
    local settings, motd, traffic, line_counts = {}, {}, {}, {}
    local integers = {NICKLEN = true, CHANNELLEN = true, TOPICLEN = true, MAXCHANNELS = true,
        BUCKET = true, REFILL = true, QUEUE = true, PINGFREQ = true, TIMEOUT = true}
    for line in io.lines('input/server.txt') do
        local key, value = line:match('^(%S+) (.*)$')
        if key == 'MOTD' then motd[#motd + 1] = value
        else settings[key] = integers[key] and tonumber(value) or value end
    end
    for line in io.lines('input/traffic.txt') do
        local time, identifier, body = line:match('^(%d+) ([a-z0-9]+) (.*)$')
        local kind, host = 'messages', body:match('^CONNECT ([%w.%-]+)$')
        if host and #host <= 63 then kind = 'connect'
        elseif body == 'DISCONNECT' then kind = 'disconnect' end
        traffic[#traffic + 1] = {time = tonumber(time), identifier = identifier, kind = kind, body = body}
        add(line_counts, kind)
    end
    return setmetatable({settings = settings, motd = motd, traffic = traffic, finish = traffic[#traffic].time,
        time = 0, clients = {}, client_by_id = {}, channels = {}, channel_by_name = {}, sent = {},
        commands = {}, numerics = {}, line_counts = line_counts, statistics = {}, disconnects = {}, gone = {},
        peak_connections = {0, 0}, peak_registered = {0, 0}}, Server)
end

function Server:present()
    local clients = {}
    for _, client in ipairs(self.clients) do if client.active then clients[#clients + 1] = client end end
    return clients
end
function Server:send(client, line)
    self.sent[#self.sent + 1] = self.time .. ' ' .. client.identifier .. ' ' .. line
    client.sent = client.sent + 1
end
function Server:numeric(client, number, values)
    local content = numeric_contents[number]
    if type(content) == 'function' then content = content(self, client, values or {}) end
    add(self.numerics, number)
    self:send(client, ':' .. self.settings.NAME .. ' ' .. string.format('%03d', number) .. ' ' .. client:addressee() .. ' ' .. content)
end
function Server:broadcast(channel, line, exclude)
    for _, member in ipairs(channel.members) do if member.client ~= exclude then self:send(member.client, line) end end
end
function Server:send_peers(client, line)
    local peers = {}
    for _, channel in ipairs(client.channels) do for _, member in ipairs(channel.members) do peers[member.client] = true end end
    for _, other in ipairs(self:present()) do if other ~= client and peers[other] then self:send(other, line) end end
end
function Server:find_user(nickname)
    local folded = protocol.fold(nickname)
    for _, client in ipairs(self:present()) do
        if client.registered and protocol.fold(client.nickname) == folded then return client end
    end
end
function Server:find_channel(name) return self.channel_by_name[protocol.fold(name)] end
function Server:joined_channels(client, separator)
    local names = {}
    for _, channel in ipairs(client.channels) do names[#names + 1] = Channel.status(channel:member(client)) .. channel.name end
    return table.concat(names, separator)
end
function Server:remove_member(client, channel)
    channel:remove(client)
    if #channel.members == 0 then
        remove(self.channels, channel)
        self.channel_by_name[protocol.fold(channel.name)] = nil
        for _, other in ipairs(self:present()) do remove(other.invites, channel) end
    end
end
function Server:disconnect(client, reason, kind)
    if kind ~= 'closed' then
        self:send(client, 'ERROR :Closing Link: ' .. client:addressee() .. '[' .. client.hostname .. '] (' .. reason .. ')')
        add(self.statistics, 'errors')
    end
    if client.registered then self:send_peers(client, ':' .. client:prefix() .. ' QUIT :' .. reason) end
    for _, channel in ipairs({table.unpack(client.channels)}) do self:remove_member(client, channel) end
    add(self.statistics, 'discarded', #client.queue)
    client.queue = {}
    self.client_by_id[client.identifier], client.active = nil, false
    self.gone[#self.gone + 1] = {self.time, client.identifier, client:addressee(), reason}
    add(self.disconnects, kind)
end
function Server:complete_registration(client)
    if client.registered or client.nickname == nil or client.username == nil then return end
    client.registered, client.registration_time, client.last_speaking = true, self.time, self.time
    local registered = 0
    for _, other in ipairs(self:present()) do if other.registered then registered = registered + 1 end end
    if registered > self.peak_registered[1] then self.peak_registered = {registered, self.time} end
    for _, number in ipairs({1, 2, 3, 4, 5, 375}) do self:numeric(client, number) end
    for _, line in ipairs(self.motd) do self:numeric(client, 372, {text = line}) end
    self:numeric(client, 376)
    if client.invisible then self:send(client, ':' .. client.nickname .. ' MODE ' .. client.nickname .. ' :+i') end
end
function Server:use_token(client) client:use_token(self.time, self.settings.BUCKET, self.settings.REFILL) end
function Server:arrival(record)
    if record.kind == 'connect' then
        local client = Client.new(record.identifier, record.body:sub(9), self.time, self.settings.BUCKET)
        self.clients[#self.clients + 1], self.client_by_id[record.identifier] = client, client
        local present = self:present()
        if #present > self.peak_connections[1] then self.peak_connections = {#present, self.time} end
        return
    end
    local client = self.client_by_id[record.identifier]
    if record.kind == 'disconnect' then
        if client then self:disconnect(client, 'Remote host closed the connection', 'closed') end
        return
    end
    if not client then add(self.statistics, 'dropped'); return end
    client.received, client.last_received, client.ping_sent = client.received + 1, self.time, nil
    if #client.queue == 0 and client.tokens >= 1 then
        self:use_token(client); self:process(client, record.body)
    elseif #client.queue >= self.settings.QUEUE then
        add(self.statistics, 'discarded'); self:disconnect(client, 'Excess Flood', 'flood')
    else
        client.queue[#client.queue + 1] = record.body; add(self.statistics, 'queued')
    end
end
function Server:run()
    local position = 1
    for time = 0, self.finish do
        self.time = time
        for _, client in ipairs(self:present()) do
            client:refill(time, self.settings.BUCKET, self.settings.REFILL)
            while client.active and #client.queue > 0 and client.tokens >= 1 do
                self:use_token(client)
                local raw = table.remove(client.queue, 1)
                self:process(client, raw)
            end
        end
        while self.traffic[position] and self.traffic[position].time == time do
            self:arrival(self.traffic[position]); position = position + 1
        end
        for _, client in ipairs(self:present()) do
            if client.ping_sent ~= nil then
                if time - client.ping_sent >= self.settings.TIMEOUT then
                    self:disconnect(client, 'Ping timeout: ' .. (time - client.last_received) .. ' seconds', 'timeout')
                end
            elseif time - client.last_received >= self.settings.PINGFREQ then
                self:send(client, 'PING :' .. self.settings.NAME); add(self.statistics, 'pings'); client.ping_sent = time
            end
        end
    end
end
function Server:require_parameters(client, parameters, required, command)
    if #parameters < required then self:numeric(client, 461, {command = command}); return false end
    return true
end
local unregistered_commands = {NICK = true, USER = true, PING = true, PONG = true, QUIT = true}
function Server:process(client, raw)
    add(self.statistics, 'processed')
    local command, parameters = protocol.parse(raw)
    if command == '' then add(self.statistics, 'empty'); return end
    add(self.commands, command)
    if not client.registered and not unregistered_commands[command] then self:numeric(client, 451); return end
    if command == 'PRIVMSG' or command == 'NOTICE' then self:message(client, parameters, command)
    elseif self.handlers[command] then self.handlers[command](self, client, parameters)
    else self:numeric(client, 421, {command = command}) end
end

function Server:nick(client, p)
    if p[1] == nil or p[1] == '' then self:numeric(client, 431); return end
    local nickname = p[1]:sub(1, self.settings.NICKLEN)
    if not protocol.valid_nickname(nickname) then self:numeric(client, 432, {x = nickname}); return end
    if nickname == client.nickname then return end
    local folded = protocol.fold(nickname)
    for _, other in ipairs(self:present()) do
        if other ~= client and other.nickname and protocol.fold(other.nickname) == folded then self:numeric(client, 433, {x = nickname}); return end
    end
    if client.registered then
        local line = ':' .. client:prefix() .. ' NICK :' .. nickname
        self:send(client, line); self:send_peers(client, line)
    end
    client.nickname = nickname; self:complete_registration(client)
end
function Server:user(client, p)
    if client.username ~= nil then self:numeric(client, 462); return end
    if not self:require_parameters(client, p, 4, 'USER') then return end
    client.username, client.realname = p[1], p[4]
    client.invisible = protocol.digits(p[2]) and #p[2] <= 3 and (tonumber(p[2]) // 8) % 2 == 1
    self:complete_registration(client)
end
function Server:ping(client, p)
    if p[1] == nil or p[1] == '' then self:numeric(client, 409); return end
    local name = self.settings.NAME
    self:send(client, ':' .. name .. ' PONG ' .. name .. ' :' .. p[1])
end
function Server:pong(client, p) end
function Server:quit(client, p)
    self:disconnect(client, p[1] and p[1] ~= '' and 'Quit: ' .. p[1] or 'Client Quit', 'quit')
end
function Server:names_reply(client, channel)
    local names = channel:name_list(client)
    if names ~= '' then self:numeric(client, 353, {channel = channel, text = names}) end
    self:numeric(client, 366, {x = channel.name})
end
function Server:join(client, p)
    if not self:require_parameters(client, p, 1, 'JOIN') then return end
    if p[1] == '0' then
        for _, channel in ipairs({table.unpack(client.channels)}) do
            self:broadcast(channel, ':' .. client:prefix() .. ' PART ' .. channel.name); self:remove_member(client, channel)
        end
        return
    end
    local keys = p[2] and split(p[2]) or {}
    for index, name in ipairs(split(p[1])) do
        if not protocol.valid_channel(name, self.settings.CHANNELLEN) then
            self:numeric(client, 403, {x = name})
        else
            local channel, failure = self:find_channel(name), nil
            if channel and channel:member(client) then goto next_name end
            if #client.channels >= self.settings.MAXCHANNELS then self:numeric(client, 405, {x = name}); goto next_name end
            if channel == nil then
                channel = Channel.new(name, self.time)
                self.channels[#self.channels + 1], self.channel_by_name[protocol.fold(name)] = channel, channel
            else
                local invited = contains(client.invites, channel)
                if channel:banned(client) and not invited then failure = 474
                elseif channel.flags.i and not invited then failure = 473
                elseif channel.key ~= '' and (keys[index] or '') ~= channel.key then failure = 475
                elseif channel.limit ~= 0 and #channel.members >= channel.limit then failure = 471 end
                if failure then self:numeric(client, failure, {channel = channel}); goto next_name end
            end
            remove(client.invites, channel); channel:add(client, #channel.members == 0)
            self:broadcast(channel, ':' .. client:prefix() .. ' JOIN ' .. channel.name)
            if channel.topic ~= '' then self:numeric(client, 332, {channel = channel}); self:numeric(client, 333, {channel = channel}) end
            self:names_reply(client, channel)
        end
        ::next_name::
    end
end
function Server:part(client, p)
    if not self:require_parameters(client, p, 1, 'PART') then return end
    local suffix = p[2] and p[2] ~= '' and ' :' .. p[2] or ''
    for _, name in ipairs(split(p[1])) do
        local channel = self:find_channel(name)
        if not channel then self:numeric(client, 403, {x = name})
        elseif not channel:member(client) then self:numeric(client, 442, {channel = channel})
        else self:broadcast(channel, ':' .. client:prefix() .. ' PART ' .. channel.name .. suffix); self:remove_member(client, channel) end
    end
end
function Server:message(client, p, command)
    local replies = command == 'PRIVMSG'
    if replies then client.last_speaking = self.time end
    if p[1] == nil or p[1] == '' then if replies then self:numeric(client, 411, {command = command}) end; return end
    if p[2] == nil or p[2] == '' then if replies then self:numeric(client, 412) end; return end
    for _, target in ipairs(split(p[1])) do
        if target:sub(1, 1) == '#' then
            local channel = self:find_channel(target)
            if not channel then if replies then self:numeric(client, 401, {x = target}) end
            elseif not channel:can_speak(client) then if replies then self:numeric(client, 404, {channel = channel}) end
            else
                channel.messages = channel.messages + 1
                self:broadcast(channel, ':' .. client:prefix() .. ' ' .. command .. ' ' .. channel.name .. ' :' .. p[2], client)
            end
        else
            local user = self:find_user(target)
            if not user then if replies then self:numeric(client, 401, {x = target}) end
            else
                self:send(user, ':' .. client:prefix() .. ' ' .. command .. ' ' .. user.nickname .. ' :' .. p[2])
                if replies and user.away ~= '' then self:numeric(client, 301, {user = user}) end
            end
        end
    end
end
function Server:topic(client, p)
    if not self:require_parameters(client, p, 1, 'TOPIC') then return end
    local channel = self:find_channel(p[1])
    if not channel then self:numeric(client, 403, {x = p[1]}); return end
    local member = channel:member(client)
    if not member then self:numeric(client, 442, {channel = channel}); return end
    if #p == 1 then
        self:numeric(client, channel.topic ~= '' and 332 or 331, {channel = channel})
        if channel.topic ~= '' then self:numeric(client, 333, {channel = channel}) end
        return
    end
    if channel.flags.t and not member.is_operator then self:numeric(client, 482, {channel = channel}); return end
    channel.topic, channel.topic_setter, channel.topic_time = p[2]:sub(1, self.settings.TOPICLEN), client.nickname, self.time
    self:broadcast(channel, ':' .. client:prefix() .. ' TOPIC ' .. channel.name .. ' :' .. channel.topic)
end
function Server:names(client, p)
    if #p == 0 then self:numeric(client, 366, {x = '*'}); return end
    for _, name in ipairs(split(p[1])) do
        local channel = self:find_channel(name)
        if channel then self:names_reply(client, channel) else self:numeric(client, 366, {x = name}) end
    end
end
function Server:whois(client, p)
    if #p == 0 then self:numeric(client, 431); return end
    local user = self:find_user(p[1])
    if not user then self:numeric(client, 401, {x = p[1]}); self:numeric(client, 318, {x = p[1]}); return end
    self:numeric(client, 311, {user = user})
    if #user.channels > 0 then self:numeric(client, 319, {user = user}) end
    self:numeric(client, 312, {user = user})
    if user.away ~= '' then self:numeric(client, 301, {user = user}) end
    self:numeric(client, 317, {user = user}); self:numeric(client, 318, {x = user.nickname})
end
function Server:away(client, p)
    client.away = p[1] or ''
    self:numeric(client, client.away ~= '' and 306 or 305)
end
function Server:invite(client, p)
    if not self:require_parameters(client, p, 2, 'INVITE') then return end
    local user = self:find_user(p[1])
    if not user then self:numeric(client, 401, {x = p[1]}); return end
    local channel = self:find_channel(p[2])
    if not channel then self:numeric(client, 403, {x = p[2]}); return end
    local member = channel:member(client)
    if not member then self:numeric(client, 442, {channel = channel}); return end
    if channel:member(user) then self:numeric(client, 443, {user = user, channel = channel}); return end
    if channel.flags.i and not member.is_operator then self:numeric(client, 482, {channel = channel}); return end
    if not contains(user.invites, channel) then user.invites[#user.invites + 1] = channel end
    self:numeric(client, 341, {user = user, channel = channel})
    if user.away ~= '' then self:numeric(client, 301, {user = user}) end
    self:send(user, ':' .. client:prefix() .. ' INVITE ' .. user.nickname .. ' :' .. channel.name)
end
function Server:kick(client, p)
    if not self:require_parameters(client, p, 2, 'KICK') then return end
    local channel = self:find_channel(p[1])
    if not channel then self:numeric(client, 403, {x = p[1]}); return end
    local member = channel:member(client)
    if not member then self:numeric(client, 442, {channel = channel}); return end
    if not member.is_operator then self:numeric(client, 482, {channel = channel}); return end
    local user = self:find_user(p[2])
    if not user then self:numeric(client, 401, {x = p[2]}); return end
    if not channel:member(user) then self:numeric(client, 441, {user = user, channel = channel}); return end
    local reason = p[3] and p[3] ~= '' and p[3] or client.nickname
    self:broadcast(channel, ':' .. client:prefix() .. ' KICK ' .. channel.name .. ' ' .. user.nickname .. ' :' .. reason)
    self:remove_member(user, channel)
end
function Server:mode(client, p)
    if not self:require_parameters(client, p, 1, 'MODE') then return end
    if p[1]:sub(1, 1) == '#' then self:channel_mode(client, p) else self:user_mode(client, p) end
end
function Server:user_mode(client, p)
    local user = self:find_user(p[1])
    if not user then self:numeric(client, 401, {x = p[1]}); return end
    if user ~= client then self:numeric(client, 502); return end
    if #p == 1 then self:numeric(client, 221); return end
    local sign, changes, unknown = '+', {}, false
    for character in p[2]:gmatch('.') do
        if character == '+' or character == '-' then sign = character
        elseif character == 'i' then
            local desired = sign == '+'
            if client.invisible ~= desired then client.invisible = desired; changes[#changes + 1] = {sign = sign, character = character} end
        else unknown = true end
    end
    if #changes > 0 then self:send(client, ':' .. client.nickname .. ' MODE ' .. client.nickname .. ' :' .. modes.change_string(changes)) end
    if unknown then self:numeric(client, 501) end
end
function Server:channel_mode(client, p)
    local channel = self:find_channel(p[1])
    if not channel then self:numeric(client, 403, {x = p[1]}); return end
    if #p == 1 then self:numeric(client, 324, {channel = channel}); self:numeric(client, 329, {channel = channel}); return end
    local member = channel:member(client)
    local authorized = member and member.is_operator or false
    local bans_sent, denial_sent, changes = false, false, {}
    for _, item in ipairs(modes.channel_items(p[2], {table.unpack(p, 3)})) do
        local character, argument = item.character, item.argument
        if not ('biklmnotv'):find(character, 1, true) then
            self:numeric(client, 472, {character = character, channel = channel})
        elseif character == 'b' and argument == nil then
            if item.sign == '+' and not bans_sent then
                for _, ban in ipairs(channel.bans) do self:numeric(client, 367, {channel = channel, ban = ban}) end
                self:numeric(client, 368, {channel = channel}); bans_sent = true
            end
        elseif argument == nil and (character == 'o' or character == 'v' or item.sign == '+' and (character == 'k' or character == 'l')) then
        elseif not authorized then
            if not denial_sent then self:numeric(client, 482, {channel = channel}); denial_sent = true end
        else
            local change = self:apply_channel_mode(client, channel, item)
            if change then changes[#changes + 1] = change end
        end
    end
    if #changes > 0 then self:broadcast(channel, ':' .. client:prefix() .. ' MODE ' .. channel.name .. ' ' .. modes.change_string(changes)) end
end
function Server:apply_channel_mode(client, channel, item)
    local character, adding, argument, changed = item.character, item.sign == '+', nil, false
    if character == 'o' or character == 'v' then
        local user = self:find_user(item.argument)
        if not user then self:numeric(client, 401, {x = item.argument}); return end
        local member = channel:member(user)
        if not member then self:numeric(client, 441, {user = user, channel = channel}); return end
        local field = character == 'o' and 'is_operator' or 'voice'
        if member[field] ~= adding then member[field], changed, argument = adding, true, user.nickname end
    elseif character == 'b' then
        local mask, found = masks.normalize(item.argument), nil
        for index, ban in ipairs(channel.bans) do if protocol.fold(ban.mask) == protocol.fold(mask) then found = index; break end end
        if adding and not found then
            channel.bans[#channel.bans + 1] = {mask = mask, setter = client.nickname, time = self.time}
            changed, argument = true, mask
        elseif not adding and found then changed, argument = true, table.remove(channel.bans, found).mask end
    elseif character == 'k' then
        if adding then
            if channel.key ~= '' then self:numeric(client, 467, {channel = channel})
            else channel.key, changed, argument = item.argument, true, item.argument end
        elseif channel.key ~= '' then channel.key, changed, argument = '', true, '*' end
    elseif character == 'l' then
        if adding then
            local limit = tonumber(item.argument)
            if channel.limit ~= limit then channel.limit, changed, argument = limit, true, tostring(limit) end
        elseif channel.limit ~= 0 then channel.limit, changed = 0, true end
    elseif adding and not channel.flags[character] then channel.flags[character], changed = true, true
    elseif not adding and channel.flags[character] then channel.flags[character], changed = nil, true end
    if changed then return {sign = item.sign, character = character, argument = argument} end
end

function Server:channel_report()
    local lines, members, bans = {}, 0, 0
    for _, channel in ipairs(self.channels) do
        lines[#lines + 1] = 'CHANNEL ' .. channel.name .. ' created ' .. channel.created .. ' members ' .. #channel.members
            .. ' peak ' .. channel.peak .. ' messages ' .. channel.messages .. ' modes ' .. channel:mode_display()
        lines[#lines + 1] = channel.topic ~= '' and 'TOPIC ' .. channel.topic_setter .. ' ' .. channel.topic_time .. ' ' .. channel.topic or 'TOPIC none'
        for _, ban in ipairs(channel.bans) do lines[#lines + 1] = 'BAN ' .. ban.mask .. ' ' .. ban.setter .. ' ' .. ban.time end
        local names = {}
        for _, member in ipairs(channel.members) do names[#names + 1] = Channel.display(member) end
        lines[#lines + 1] = 'MEMBERS ' .. table.concat(names, ' ')
        members, bans = members + #channel.members, bans + #channel.bans
    end
    lines[#lines + 1] = 'TOTAL channels ' .. #self.channels .. ' members ' .. members .. ' bans ' .. bans
    return lines
end
function Server:client_report()
    local lines, registered, invisible, away = {}, 0, 0, 0
    local clients = self:present()
    for _, client in ipairs(clients) do
        local joined, invites = self:joined_channels(client, ','), {}
        for _, channel in ipairs(client.invites) do invites[#invites + 1] = channel.name end
        lines[#lines + 1] = 'CLIENT ' .. client.identifier .. ' ' .. client:addressee() .. ' ' .. (client.username or '*') .. ' ' .. client.hostname
            .. ' ' .. client:mode() .. ' connected ' .. client.connection_time .. ' signon ' .. (client.registered and client.registration_time or '-')
            .. ' received ' .. client.received .. ' sent ' .. client.sent .. ' tokens ' .. client.tokens .. ' queue ' .. #client.queue
            .. ' channels ' .. (joined ~= '' and joined or 'none') .. ' invites ' .. (#invites > 0 and table.concat(invites, ',') or 'none')
        if client.away ~= '' then lines[#lines + 1] = 'AWAY ' .. client.identifier .. ' ' .. client.away; away = away + 1 end
        if client.registered then registered = registered + 1 end
        if client.invisible then invisible = invisible + 1 end
    end
    lines[#lines + 1] = 'TOTAL clients ' .. #clients .. ' registered ' .. registered .. ' invisible ' .. invisible .. ' away ' .. away
    return lines
end
function Server:statistics_report()
    local c, pending = self.statistics, 0
    for _, client in ipairs(self:present()) do pending = pending + #client.queue end
    local lines = {'END ' .. self.finish,
        'LINES total ' .. #self.traffic .. ' connect ' .. count(self.line_counts, 'connect') .. ' disconnect ' .. count(self.line_counts, 'disconnect') .. ' messages ' .. count(self.line_counts, 'messages'),
        'MESSAGES dropped ' .. count(c, 'dropped') .. ' queued ' .. count(c, 'queued') .. ' processed ' .. count(c, 'processed') .. ' discarded ' .. count(c, 'discarded') .. ' pending ' .. pending .. ' empty ' .. count(c, 'empty'),
        'SENT lines ' .. #self.sent .. ' numerics ' .. sum(self.numerics) .. ' pings ' .. count(c, 'pings') .. ' errors ' .. count(c, 'errors')}
    for _, command in ipairs(sorted_keys(self.commands)) do lines[#lines + 1] = 'COMMAND ' .. command .. ' ' .. self.commands[command] end
    for _, number in ipairs(sorted_keys(self.numerics)) do lines[#lines + 1] = 'NUMERIC ' .. string.format('%03d', number) .. ' ' .. self.numerics[number] end
    lines[#lines + 1] = 'PEAK connections ' .. self.peak_connections[1] .. ' at ' .. self.peak_connections[2]
    lines[#lines + 1] = 'PEAK registered ' .. self.peak_registered[1] .. ' at ' .. self.peak_registered[2]
    local kinds = {}
    for _, kind in ipairs({'quit', 'closed', 'flood', 'timeout'}) do kinds[#kinds + 1] = kind .. ' ' .. count(self.disconnects, kind) end
    lines[#lines + 1] = 'DISCONNECTS ' .. table.concat(kinds, ' ')
    for _, record in ipairs(self.gone) do lines[#lines + 1] = 'GONE ' .. table.concat(record, ' ') end
    return lines
end
function Server:write_outputs()
    os.execute('mkdir -p output')
    local outputs = {['sent.txt'] = self.sent, ['channels.txt'] = self:channel_report(),
        ['clients.txt'] = self:client_report(), ['stats.txt'] = self:statistics_report()}
    for filename, lines in pairs(outputs) do
        local file = assert(io.open('output/' .. filename, 'w'))
        file:write(table.concat(lines, '\n'), #lines > 0 and '\n' or '')
        file:close()
    end
end

Server.handlers = {NICK = Server.nick, USER = Server.user, PING = Server.ping, PONG = Server.pong, QUIT = Server.quit,
    JOIN = Server.join, PART = Server.part, TOPIC = Server.topic, NAMES = Server.names, WHOIS = Server.whois,
    AWAY = Server.away, INVITE = Server.invite, KICK = Server.kick, MODE = Server.mode}
local server = Server.new()
server:run()
server:write_outputs()
