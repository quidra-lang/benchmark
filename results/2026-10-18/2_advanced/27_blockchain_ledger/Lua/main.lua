local hashing, wallets, transactions, blocks, chain = require("hashing"), require("wallets"), require("transactions"), require("blocks"), require("chain")
local short = hashing.short
local function copy(values)
    local result = {}
    for key, value in pairs(values) do
        result[key] = value
    end
    return result
end
local function keys(values)
    local result = {}
    for key in pairs(values) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end
local function remove(values, target)
    for i, value in ipairs(values) do
        if value == target then
            table.remove(values, i)
            return
        end
    end
end
local function words(line)
    local result = {}
    for word in line:gmatch("%S+") do
        result[#result + 1] = word
    end
    return result
end
local function read_lines(path)
    local result = {}
    for line in io.lines(path) do
        result[#result + 1] = line
    end
    return result
end
local function output_total(outputs, address)
    local total = 0
    for _, output in ipairs(outputs) do
        if not address or output.address == address then
            total = total + output.amount
        end
    end
    return total
end
local function read_params()
    local result = {}
    for line in io.lines("input/params.txt") do
        local fields = words(line)
        local values = {}
        for i = 2, #fields do
            values[#values + 1] = tonumber(fields[i]) or fields[i]
        end
        result[fields[1]] = values
    end
    return result
end
local Node = {}
Node.__index = Node
function Node.new(params, managed)
    local self = setmetatable({params = params, wallets = managed, owners = {}, named = {}, now = 0, records = {}, mempool = {}, orphans = {}, rejected = {}, drop_record = {}, peers = {}, rejections = {}, reorganizations = {}, log_lines = {}}, Node)
    for _, wallet in ipairs(managed) do
        self.owners[wallet.address], self.named[wallet.name] = wallet, wallet
    end
    local outputs = {}
    for i = 1, #params.GENESIS, 2 do
        outputs[#outputs + 1] = {address = self.named[params.GENESIS[i]].address, amount = params.GENESIS[i + 1]}
    end
    local coinbase = transactions.create_coinbase(0, outputs)
    local block = blocks.new(0, string.rep("0", 32), coinbase.txid, 0, 0, 0, {coinbase})
    local utxo = {}
    transactions.apply_transaction(utxo, coinbase, 0)
    self.tip = chain.new(block, nil, utxo, {}, "genesis")
    self.records[block.hash] = self.tip
    self:refresh()
    return self
end
function Node:refresh()
    self.main_chain, self.confirmed = chain.chain_to(self.tip), {}
    for _, record in ipairs(self.main_chain) do
        for _, tx in ipairs(record.block.transactions) do
            self.confirmed[tx.txid] = record.height
        end
    end
end
function Node:log(...)
    local parts = {self.now, ...}
    for i, value in ipairs(parts) do
        parts[i] = tostring(value)
    end
    self.log_lines[#self.log_lines + 1] = table.concat(parts, " ")
end
function Node:tally(kind, reason)
    local key = kind .. " " .. reason
    self.rejections[key] = (self.rejections[key] or 0) + 1
end
function Node:peer(name)
    if not self.peers[name] then
        self.peers[name] = {name = name, accepted_blocks = 0, rejected_blocks = 0, orphaned_blocks = 0, accepted_txs = 0, rejected_txs = 0, ignored = 0, score = 0}
    end
    return self.peers[name]
end
function Node:next_height()
    return self.tip.height + 1
end
function Node:reward(height)
    return chain.reward(height, self.params.REWARD[1], self.params.REWARD[2])
end
function Node:difficulty(parent)
    return chain.required_difficulty(parent, self.params.DIFFICULTY[1], self.params.RETARGET[1], self.params.RETARGET[2])
end
function Node:mature(coin)
    return transactions.is_mature(coin, self:next_height(), self.params.MATURITY[1])
end
function Node:locked()
    local locked = {}
    for _, entry in ipairs(self.mempool) do
        for _, reference in ipairs(entry.transaction.inputs) do
            locked[reference] = true
        end
    end
    return locked
end
function Node:priority()
    local order = {table.unpack(self.mempool)}
    table.sort(order, function(a, b)
        local left, right = a.fee * b.transaction.size, b.fee * a.transaction.size
        return left > right or left == right and a.transaction.txid < b.transaction.txid
    end)
    return order
end
function Node:find(txid)
    for _, entry in ipairs(self.mempool) do
        if entry.transaction.txid == txid then
            return entry
        end
    end
end
function Node:acceptance(tx)
    if tx:is_coinbase() then
        return "coinbase"
    end
    if self.confirmed[tx.txid] or self:find(tx.txid) then
        return "duplicate"
    end
    local reason, fee = transactions.check_transaction(tx, self.tip.utxo, {}, self:next_height(), self.owners, self.params.MATURITY[1])
    if reason then
        return reason
    end
    if fee * 1000 < self.params.MINFEERATE[1] * tx.size then
        return "low-fee"
    end
    local inputs, conflicts, total = {}, {}, 0
    for _, reference in ipairs(tx.inputs) do
        inputs[reference] = true
    end
    for _, entry in ipairs(self.mempool) do
        for _, reference in ipairs(entry.transaction.inputs) do
            if inputs[reference] then
                conflicts[#conflicts + 1], total = entry, total + entry.fee
                break
            end
        end
    end
    if #conflicts > 0 then
        if fee <= total then
            return "conflict"
        end
        for _, entry in ipairs(conflicts) do
            if fee * entry.transaction.size <= entry.fee * tx.size then
                return "conflict"
            end
        end
    end
    return nil, fee, conflicts
end
function Node:record_drop(txid, reason)
    self.drop_record[txid] = reason
    self:log("DROP", short(txid), reason)
end
function Node:drop(entry, reason)
    remove(self.mempool, entry)
    self:record_drop(entry.transaction.txid, reason)
end
function Node:register(tx, fee, conflicts, arrival)
    for _, entry in ipairs(conflicts) do
        self:drop(entry, "replaced")
    end
    self.mempool[#self.mempool + 1] = {transaction = tx, fee = fee, arrival = arrival}
    if #self.mempool > self.params.MEMPOOL[1] then
        local order = self:priority()
        self:drop(order[#order], "mempool-full")
    end
end
function Node:rebuild(returned)
    local previous = self.mempool
    self.mempool = {}
    local candidates = {}
    for _, tx in ipairs(returned) do
        candidates[#candidates + 1] = {transaction = tx, arrival = self.now, returned = true}
    end
    for _, entry in ipairs(previous) do
        candidates[#candidates + 1] = entry
    end
    for _, entry in ipairs(candidates) do
        local tx = entry.transaction
        if not self.confirmed[tx.txid] then
            local reason, fee, conflicts = self:acceptance(tx)
            if reason then
                self:record_drop(tx.txid, reason)
            else
                if entry.returned then
                    self:log("RETURN", short(tx.txid))
                end
                self:register(tx, fee, conflicts, entry.arrival)
            end
        end
    end
end
function Node:switch_tip(target)
    local old, fork = self.tip, chain.fork_point(self.tip, target)
    local disconnected, connected = old.height - fork.height, target.height - fork.height
    if disconnected > self.params.MAXREORG[1] then
        self:log("REFUSE", target.height, short(target.hash), "work", target.cumulative_work, "fork", fork.height, "depth", disconnected)
        return
    end
    local returned = {}
    for i = fork.height + 2, #self.main_chain do
        for j = 2, #self.main_chain[i].block.transactions do
            returned[#returned + 1] = self.main_chain[i].block.transactions[j]
        end
    end
    self.tip = target
    self:refresh()
    if disconnected == 0 then
        self:log("TIP", target.height, short(target.hash), "work", target.cumulative_work)
    else
        self:log("REORG", target.height, short(target.hash), "work", target.cumulative_work, "fork", fork.height, "disconnected", disconnected, "connected", connected)
        self.reorganizations[#self.reorganizations + 1] = {time = self.now, fork = fork.height, disconnected = disconnected, connected = connected, old = old.hash, new = target.hash}
    end
    self:rebuild(returned)
end
function Node:penalize(peer, points)
    local before = peer.score
    peer.score = peer.score + points
    if before < self.params.BAN[1] and peer.score >= self.params.BAN[1] then
        self:log("BAN", peer.name, "score", peer.score)
    end
end
function Node:pay(fields)
    local sender, fee = self.named[fields[3]], tonumber(fields[4])
    local outputs, total = {}, 0
    for i = 5, #fields, 2 do
        local amount = tonumber(fields[i + 1])
        outputs[#outputs + 1], total = {address = self.named[fields[i]].address, amount = amount}, total + amount
    end
    local locked, coins = self:locked(), {}
    for reference, coin in pairs(self.tip.utxo) do
        if coin.address == sender.address and not locked[reference] and self:mature(coin) then
            coins[#coins + 1] = {reference = reference, coin = coin}
        end
    end
    table.sort(coins, function(a, b)
        if a.coin.amount ~= b.coin.amount then
            return a.coin.amount > b.coin.amount
        end
        local aid, ai = a.reference:match("^(%w+):(%d+)$")
        local bid, bi = b.reference:match("^(%w+):(%d+)$")
        return aid < bid or aid == bid and tonumber(ai) < tonumber(bi)
    end)
    local gathered, inputs = 0, {}
    for _, item in ipairs(coins) do
        if gathered >= total + fee then
            break
        end
        inputs[#inputs + 1], gathered = item.reference, gathered + item.coin.amount
    end
    if gathered < total + fee then
        self:log("PAY", sender.name, "fee", fee, "total", total, "rejected", "insufficient-funds")
        self:tally("pay", "insufficient-funds")
        return
    end
    if gathered > total + fee then
        outputs[#outputs + 1] = {address = sender.address, amount = gathered - total - fee}
    end
    local tx = transactions.create_transaction(inputs, outputs, sender.secret)
    local reason, accepted_fee, conflicts = self:acceptance(tx)
    if reason then
        self:log("PAY", sender.name, "fee", fee, "total", total, "tx", short(tx.txid), "rejected", reason)
        self:tally("pay", reason)
        return
    end
    self:log("PAY", sender.name, "fee", fee, "total", total, "tx", short(tx.txid), "accepted", "inputs", #inputs, "outputs", #outputs, "size", tx.size)
    self:register(tx, accepted_fee, conflicts, self.now)
end
function Node:bump(txid, fee)
    local entry = self:find(txid)
    local prefix = "BUMP " .. short(txid) .. " fee " .. fee
    if not entry then
        self:log(prefix, "rejected", "unknown")
        self:tally("bump", "unknown")
        return
    end
    local original, outputs = entry.transaction, {}
    for i, output in ipairs(original.outputs) do
        outputs[i] = {address = output.address, amount = output.amount}
    end
    local last = outputs[#outputs]
    last.amount = last.amount - (fee - entry.fee)
    local valid = last.amount >= 1
    for _, reference in ipairs(original.inputs) do
        if self.tip.utxo[reference].address ~= last.address then
            valid = false
        end
    end
    if not valid then
        self:log(prefix, "rejected", "no-change")
        self:tally("bump", "no-change")
        return
    end
    local tx = transactions.create_transaction(original.inputs, outputs, self.owners[last.address].secret)
    local reason, accepted_fee, conflicts = self:acceptance(tx)
    if reason then
        self:log(prefix, "tx", short(tx.txid), "rejected", reason)
        self:tally("bump", reason)
        return
    end
    self:log(prefix, "tx", short(tx.txid), "accepted", "size", tx.size)
    self:register(tx, accepted_fee, conflicts, self.now)
end
function Node:receive_transaction(peer, tx)
    local reason, fee, conflicts = self:acceptance(tx)
    if reason then
        peer.rejected_txs = peer.rejected_txs + 1
        self:tally("tx", reason)
        self:log("TX", peer.name, short(tx.txid), "rejected", reason)
        if ({coinbase = true, ["bad-output"] = true, ["bad-sig"] = true, overspend = true})[reason] then
            self:penalize(peer, self.params.BAN[3])
        end
    else
        peer.accepted_txs = peer.accepted_txs + 1
        self:log("TX", peer.name, short(tx.txid), "accepted", "fee", fee, "size", tx.size)
        self:register(tx, fee, conflicts, self.now)
    end
end
function Node:mine(wallet)
    local txs, fees, size, total, height = {}, {}, 0, 0, self:next_height()
    for _, entry in ipairs(self:priority()) do
        if size + entry.transaction.size <= self.params.MAXBLOCK[1] then
            txs[#txs + 1], fees[#fees + 1] = entry.transaction, entry.fee
            size, total = size + entry.transaction.size, total + entry.fee
        end
    end
    table.insert(txs, 1, transactions.create_coinbase(height, {{address = wallet.address, amount = self:reward(height) + total}}))
    local block = blocks.mine_block(height, self.tip.hash, txs, math.max(self.now, chain.median_time(self.tip) + 1), self:difficulty(self.tip))
    local utxo = copy(self.tip.utxo)
    for _, tx in ipairs(txs) do
        transactions.apply_transaction(utxo, tx, height)
    end
    local record = chain.new(block, self.tip, utxo, fees, "local")
    self.records[record.hash] = record
    self:log("MINE", wallet.name, height, short(block.hash), "bits", block.difficulty, "nonce", block.nonce, "txs", #txs, "size", size, "fees", total, "work", record.cumulative_work)
    self:switch_tip(record)
end
function Node:reject_block(kind, block, peer, reason)
    self.rejected[block.hash], peer.rejected_blocks = true, peer.rejected_blocks + 1
    self:tally("block", reason:match("^%S+"))
    self:log(kind, peer.name, block.height, short(block.hash), "rejected", reason)
    if reason ~= "time-too-new" then
        self:penalize(peer, self.params.BAN[2])
    end
end
function Node:validate(block, parent)
    if block.height ~= parent.height + 1 then
        return "bad-height"
    end
    if block.difficulty ~= self:difficulty(parent) then
        return "bad-difficulty"
    end
    if block.timestamp <= chain.median_time(parent) then
        return "time-too-old"
    end
    if block.timestamp > self.now + self.params.DRIFT[1] then
        return "time-too-new"
    end
    local utxo, spent, fees, total = copy(parent.utxo), {}, {}, 0
    for i = 2, #block.transactions do
        local tx = block.transactions[i]
        local reason, fee = transactions.check_transaction(tx, utxo, spent, block.height, self.owners, self.params.MATURITY[1])
        if reason then
            return reason .. " tx " .. i
        end
        for _, reference in ipairs(tx.inputs) do
            spent[reference] = true
        end
        transactions.apply_transaction(utxo, tx, block.height)
        fees[#fees + 1], total = fee, total + fee
    end
    local coinbase = block.transactions[1]
    for _, output in ipairs(coinbase.outputs) do
        if not self.owners[output.address] or output.amount == 0 then
            return "bad-output tx 1"
        end
    end
    if coinbase:output_total() > self:reward(block.height) + total then
        return "bad-coinbase"
    end
    transactions.apply_transaction(utxo, coinbase, block.height)
    return nil, utxo, fees
end
function Node:connect(kind, block, peer)
    local parent = self.records[block.previous]
    local reason, utxo, fees = self:validate(block, parent)
    if reason then
        self:reject_block(kind, block, peer, reason)
        return
    end
    local record = chain.new(block, parent, utxo, fees, peer.name)
    self.records[record.hash], peer.accepted_blocks = record, peer.accepted_blocks + 1
    self:log(kind, peer.name, block.height, short(block.hash), "accepted", "work", record.cumulative_work)
    if record.cumulative_work > self.tip.cumulative_work then
        self:switch_tip(record)
    end
end
function Node:resolve(start)
    local queue, head = {start}, 1
    while head <= #queue do
        local parent_hash = queue[head]
        head = head + 1
        local children = {}
        for _, orphan in ipairs(self.orphans) do
            if orphan.block.previous == parent_hash then
                children[#children + 1] = orphan
            end
        end
        for _, orphan in ipairs(children) do
            remove(self.orphans, orphan)
            if self.rejected[parent_hash] then
                self:reject_block("UNORPHAN", orphan.block, orphan.peer, "bad-parent")
            else
                self:connect("UNORPHAN", orphan.block, orphan.peer)
            end
            queue[#queue + 1] = orphan.block.hash
        end
    end
end
function Node:receive_block(peer, block)
    local duplicate = self.records[block.hash] or self.rejected[block.hash]
    for _, orphan in ipairs(self.orphans) do
        if orphan.block.hash == block.hash then
            duplicate = true
        end
    end
    if duplicate then
        self:log("BLOCK", peer.name, block.height, short(block.hash), "rejected", "duplicate")
        peer.rejected_blocks = peer.rejected_blocks + 1
        self:tally("block", "duplicate")
        return
    end
    local reason = blocks.context_free_error(block, self.params.MAXBLOCK[1])
    if not reason and self.rejected[block.previous] then
        reason = "bad-parent"
    end
    if reason then
        self:reject_block("BLOCK", block, peer, reason)
        self:resolve(block.hash)
        return
    end
    if not self.records[block.previous] then
        self.orphans[#self.orphans + 1], peer.orphaned_blocks = {block = block, peer = peer}, peer.orphaned_blocks + 1
        self:log("BLOCK", peer.name, block.height, short(block.hash), "orphan", "parent", short(block.previous))
        if #self.orphans > self.params.ORPHANS[1] then
            self:log("EVICT", short(table.remove(self.orphans, 1).block.hash), "orphan-limit")
        end
        return
    end
    self:connect("BLOCK", block, peer)
    self:resolve(block.hash)
end
function Node:status(txid)
    local height = self.confirmed[txid]
    if height then
        self:log("STATUS", short(txid), "confirmed", height, "confirmations", self:next_height() - height)
        return
    end
    local ranked = self:priority()
    for rank, entry in ipairs(ranked) do
        if entry.transaction.txid == txid then
            self:log("STATUS", short(txid), "mempool", "rank", rank, "of", #ranked)
            return
        end
    end
    if self.drop_record[txid] then
        self:log("STATUS", short(txid), "dropped", self.drop_record[txid])
        return
    end
    for _, record in pairs(self.records) do
        for _, tx in ipairs(record.block.transactions) do
            if tx.txid == txid then
                self:log("STATUS", short(txid), "stale")
                return
            end
        end
    end
    self:log("STATUS", short(txid), "unknown")
end
function Node:print_state()
    local ranked, size = self:priority(), 0
    for _, entry in ipairs(ranked) do
        size = size + entry.transaction.size
    end
    self:log("PRINT", "height", self.tip.height, "tip", short(self.tip.hash), "work", self.tip.cumulative_work, "bits", self:difficulty(self.tip), "reward", self:reward(self:next_height()), "mempool", #ranked, "size", size, "orphans", #self.orphans)
    for rank, entry in ipairs(ranked) do
        self:log("MEMPOOL", rank, short(entry.transaction.txid), "fee", entry.fee, "size", entry.transaction.size)
    end
    for _, wallet in ipairs(self.wallets) do
        local total = 0
        for _, coin in pairs(self.tip.utxo) do
            if coin.address == wallet.address then
                total = total + coin.amount
            end
        end
        self:log("BALANCE", wallet.name, total)
    end
end
function Node:process(fields, texts)
    self.now = tonumber(fields[1])
    local previous = {table.unpack(self.mempool)}
    for _, entry in ipairs(previous) do
        if self.now - entry.arrival >= self.params.EXPIRY[1] then
            self:drop(entry, "expired")
        end
    end
    local kind = fields[2]
    if kind == "PAY" then
        self:pay(fields)
    elseif kind == "BUMP" then
        self:bump(fields[3], tonumber(fields[4]))
    elseif kind == "MINE" then
        self:mine(self.named[fields[3]])
    elseif kind == "STATUS" then
        self:status(fields[3])
    elseif kind == "PRINT" then
        self:print_state()
    else
        local peer = self:peer(fields[3])
        if peer.score >= self.params.BAN[1] then
            peer.ignored = peer.ignored + 1
            self:log("IGNORE", peer.name, kind)
        elseif kind == "TX" then
            self:receive_transaction(peer, transactions.parse_transaction(fields[4]))
        else
            self:receive_block(peer, blocks.parse_block_event(fields, texts))
        end
    end
end
local function miner(record)
    return record.block.transactions[1].outputs[1].address
end
local function chain_lines(node)
    local tip, lines, main = node.tip, {}, {}
    lines[#lines + 1] = string.format("TIP %d %s work %d stored %d orphans %d", tip.height, tip.hash, tip.cumulative_work, #keys(node.records), #node.orphans)
    local rewards, fees, minted = 0, 0, 0
    for _, record in ipairs(node.main_chain) do
        local block = record.block
        main[record.hash] = true
        local name = record.height == 0 and "-" or node.owners[miner(record)].name
        lines[#lines + 1] = string.format("BLOCK %d %s prev %s time %d bits %d nonce %d txs %d size %d fees %d miner %s source %s work %d", block.height, block.hash, short(block.previous), block.timestamp, block.difficulty, block.nonce, #block.transactions, block:size(), record.fees, name, record.source, record.cumulative_work)
        for i, tx in ipairs(block.transactions) do
            if tx:is_coinbase() then
                lines[#lines + 1] = string.format("TX %d %s %s out %d amount %d", i, tx.txid, block.height == 0 and "genesis" or "coinbase", #tx.outputs, tx:output_total())
            else
                lines[#lines + 1] = string.format("TX %d %s payment in %d out %d size %d fee %d", i, tx.txid, #tx.inputs, #tx.outputs, tx.size, record.transaction_fees[i - 1])
            end
        end
        if record.height > 0 then
            rewards, fees, minted = rewards + node:reward(record.height), fees + record.fees, minted + block.transactions[1]:output_total()
        end
    end
    local stale = {}
    for _, record in pairs(node.records) do
        if not main[record.hash] then
            stale[#stale + 1] = record
        end
    end
    table.sort(stale, function(a, b)
        return a.height < b.height or a.height == b.height and a.hash < b.hash
    end)
    for _, record in ipairs(stale) do
        lines[#lines + 1] = string.format("STALE %d %s prev %s source %s work %d", record.height, record.hash, short(record.block.previous), record.source, record.cumulative_work)
    end
    for _, orphan in ipairs(node.orphans) do
        lines[#lines + 1] = string.format("ORPHAN %d %s prev %s source %s", orphan.block.height, orphan.block.hash, short(orphan.block.previous), orphan.peer.name)
    end
    for _, entry in ipairs(node.reorganizations) do
        lines[#lines + 1] = string.format("REORG %d fork %d disconnected %d connected %d old %s new %s", entry.time, entry.fork, entry.disconnected, entry.connected, short(entry.old), short(entry.new))
    end
    for _, wallet in ipairs(node.wallets) do
        local count, coinbase, paid = 0, 0, 0
        for i = 2, #node.main_chain do
            local record = node.main_chain[i]
            if miner(record) == wallet.address then
                count, coinbase, paid = count + 1, coinbase + record.block.transactions[1]:output_total(), paid + record.fees
            end
        end
        if count > 0 then
            lines[#lines + 1] = string.format("MINER %s blocks %d coinbase %d fees %d", wallet.name, count, coinbase, paid)
        end
    end
    local first = 2
    while first <= #node.main_chain do
        local last, difficulty = first, node.main_chain[first].block.difficulty
        while last + 1 <= #node.main_chain and node.main_chain[last + 1].block.difficulty == difficulty do
            last = last + 1
        end
        lines[#lines + 1] = string.format("BITS %d heights %d-%d blocks %d", difficulty, first - 1, last - 1, last - first + 1)
        first = last + 1
    end
    for _, name in ipairs(keys(node.peers)) do
        local p = node.peers[name]
        lines[#lines + 1] = string.format("PEER %s blocks %d rejected %d orphans %d txs %d rejected %d ignored %d score %d %s", name, p.accepted_blocks, p.rejected_blocks, p.orphaned_blocks, p.accepted_txs, p.rejected_txs, p.ignored, p.score, p.score >= node.params.BAN[1] and "banned" or "ok")
    end
    for rank, entry in ipairs(node:priority()) do
        lines[#lines + 1] = string.format("MEMPOOL %d %s fee %d size %d time %d", rank, entry.transaction.txid, entry.fee, entry.transaction.size, entry.arrival)
    end
    for _, key in ipairs(keys(node.rejections)) do
        lines[#lines + 1] = "REJECT " .. key .. " " .. node.rejections[key]
    end
    local total = 0
    for _, coin in pairs(tip.utxo) do
        total = total + coin.amount
    end
    lines[#lines + 1] = string.format("SUPPLY genesis %d rewards %d fees %d burned %d utxo %d", node.main_chain[1].block.transactions[1]:output_total(), rewards, fees, rewards + fees - minted, total)
    return lines
end
local function balance_lines(node)
    local lines, locked = {"wallet,address,balance,immature,locked,incoming,utxos"}, node:locked()
    for _, wallet in ipairs(node.wallets) do
        local balance, immature, held, count, incoming = 0, 0, 0, 0, 0
        for reference, coin in pairs(node.tip.utxo) do
            if coin.address == wallet.address then
                balance, count = balance + coin.amount, count + 1
                if not node:mature(coin) then
                    immature = immature + coin.amount
                end
                if locked[reference] then
                    held = held + coin.amount
                end
            end
        end
        for _, entry in ipairs(node.mempool) do
            incoming = incoming + output_total(entry.transaction.outputs, wallet.address)
        end
        lines[#lines + 1] = string.format("%s,%s,%d,%d,%d,%d,%d", wallet.name, wallet.address, balance, immature, held, incoming, count)
    end
    return lines
end
local function utxo_lines(node)
    local lines, hashes, locked, references, total = {}, {}, node:locked(), keys(node.tip.utxo), 0
    table.sort(references, function(a, b)
        local aid, ai = a:match("^(%w+):(%d+)$")
        local bid, bi = b:match("^(%w+):(%d+)$")
        return aid < bid or aid == bid and tonumber(ai) < tonumber(bi)
    end)
    for _, reference in ipairs(references) do
        local coin = node.tip.utxo[reference]
        local category = coin.height == 0 and "genesis" or coin.coinbase and "coinbase" or "payment"
        local state = not node:mature(coin) and "immature" or locked[reference] and "locked" or "free"
        lines[#lines + 1] = string.format("%s %s %d height %d %s %s", reference, node.owners[coin.address].name, coin.amount, coin.height, category, state)
        hashes[#hashes + 1], total = hashing.digest(lines[#lines]), total + coin.amount
    end
    lines[#lines + 1], lines[#lines + 2] = "TOTAL " .. #references .. " " .. total, "ROOT " .. hashing.merkle_root(hashes)
    return lines
end
local function history_lines(node)
    local lines, confirmed = {}, {}
    for _, record in ipairs(node.main_chain) do
        for _, tx in ipairs(record.block.transactions) do
            confirmed[tx.txid] = tx
        end
    end
    for _, wallet in ipairs(node.wallets) do
        lines[#lines + 1] = "WALLET " .. wallet.name .. " " .. wallet.address
        local count, spent_total, received_total, balance, pending = 0, 0, 0, 0, 0
        for _, record in ipairs(node.main_chain) do
            for _, tx in ipairs(record.block.transactions) do
                local spent, received, involved = 0, 0, false
                for _, reference in ipairs(tx.inputs) do
                    local id, index = reference:match("^(%w+):(%d+)$")
                    local output = confirmed[id].outputs[tonumber(index) + 1]
                    if output.address == wallet.address then
                        spent, involved = spent + output.amount, true
                    end
                end
                for _, output in ipairs(tx.outputs) do
                    if output.address == wallet.address then
                        received, involved = received + output.amount, true
                    end
                end
                if involved then
                    count, spent_total, received_total, balance = count + 1, spent_total + spent, received_total + received, balance + received - spent
                    local category = tx:is_coinbase() and (record.height == 0 and "genesis" or "coinbase") or "payment"
                    lines[#lines + 1] = string.format("%d %s %s spent %d received %d net %+d balance %d", record.height, short(tx.txid), category, spent, received, received - spent, balance)
                end
            end
        end
        for _, entry in ipairs(node:priority()) do
            local spent, received = 0, output_total(entry.transaction.outputs, wallet.address)
            for _, reference in ipairs(entry.transaction.inputs) do
                local coin = node.tip.utxo[reference]
                if coin.address == wallet.address then
                    spent = spent + coin.amount
                end
            end
            if spent ~= 0 or received ~= 0 then
                pending = pending + 1
                lines[#lines + 1] = string.format("pending %s spent %d received %d net %+d", short(entry.transaction.txid), spent, received, received - spent)
            end
        end
        lines[#lines + 1] = string.format("END %s txs %d spent %d received %d balance %d pending %d", wallet.name, count, spent_total, received_total, balance, pending)
    end
    return lines
end
local node = Node.new(read_params(), wallets.read_wallets("input/wallets.txt"))
local events, position = read_lines("input/events.txt"), 1
while position <= #events do
    local fields, texts = words(events[position]), {}
    local count = fields[2] == "BLOCK" and tonumber(fields[10]) or 0
    for i = 1, count do
        texts[i] = events[position + i]
    end
    node:process(fields, texts)
    position = position + count + 1
end
os.execute("mkdir -p output")
local function write_lines(name, lines)
    local handle = assert(io.open("output/" .. name, "wb"))
    if #lines > 0 then
        handle:write(table.concat(lines, "\n"), "\n")
    end
    handle:close()
end
write_lines("log.txt", node.log_lines)
write_lines("chain.txt", chain_lines(node))
write_lines("balances.csv", balance_lines(node))
write_lines("utxo.txt", utxo_lines(node))
write_lines("history.txt", history_lines(node))
