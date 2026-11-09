local address = require('config_io').hex_address
local Bus = {}
Bus.__index = Bus
function Bus.new(latency) return setmetatable({latency = latency, free = 0, wait = 0, transactions = {}}, Bus) end
function Bus:assign(core, kind, block, requested)
    local start = math.max(requested, self.free)
    self.wait, self.free = self.wait + start - requested, start + self.latency
    local transaction = {number = #self.transactions + 1, start = start, core = core, kind = kind, block = block,
        snoops = {}, snoop_hits = 0, invalidations = 0, flush = false}
    self.transactions[#self.transactions + 1] = transaction; return transaction
end
function Bus:line(tx, line_size)
    local line = tx.number .. ' ' .. tx.start .. ' c' .. tx.core .. ' ' .. tx.kind .. ' ' .. address(tx.block * line_size)
    if tx.kind == 'WB' then return line end
    line = line .. ' snoop ' .. (#tx.snoops > 0 and table.concat(tx.snoops, ' ') or 'none')
    if tx.kind == 'BusUpgr' then return line end
    if tx.kind == 'BusRd' or tx.kind == 'BusRdX' then line = line .. ' data ' .. tx.source end
    line = line .. ' l2 ' .. tx.l2
    if tx.eviction then
        local old = tx.eviction
        line = line .. ' evict ' .. address(old.block * line_size) .. ' ' .. (#old.copies > 0 and table.concat(old.copies, ' ') or 'none') .. (old.dirty and ' dirty' or ' clean')
    end
    return line
end
return Bus
