local Client = {}
Client.__index = Client

function Client.new(identifier, hostname, time, capacity)
    return setmetatable({identifier = identifier, hostname = hostname, connection_time = time,
        realname = '', invisible = false, registered = false, last_received = time, tokens = capacity,
        queue = {}, channels = {}, invites = {}, away = '', received = 0, sent = 0, active = true}, Client)
end

function Client:addressee() return self.nickname or '*' end
function Client:prefix() return self.nickname .. '!' .. self.username .. '@' .. self.hostname end
function Client:mode() return self.invisible and '+i' or '+' end

function Client:use_token(time, capacity, interval)
    if self.tokens == capacity then self.refill_time = time + interval end
    self.tokens = self.tokens - 1
end

function Client:refill(time, capacity, interval)
    if self.refill_time == time then
        self.tokens = self.tokens + 1
        self.refill_time = self.tokens < capacity and time + interval or nil
    end
end

return Client
