local hashing, transactions = require("hashing"), require("transactions")
local M, Block = {}, {}
Block.__index = Block
function M.header_text(height, previous, merkle, timestamp, difficulty, nonce)
    return table.concat({height, previous, merkle, timestamp, difficulty, nonce}, "|")
end
function M.new(height, previous, merkle, timestamp, difficulty, nonce, txs)
    return setmetatable({height = height, previous = previous, merkle = merkle, timestamp = timestamp, difficulty = difficulty, nonce = nonce, transactions = txs, hash = hashing.digest(M.header_text(height, previous, merkle, timestamp, difficulty, nonce))}, Block)
end
function Block:size()
    local total = 0
    for i = 2, #self.transactions do
        total = total + self.transactions[i].size
    end
    return total
end
function Block:txids()
    local ids = {}
    for i, tx in ipairs(self.transactions) do
        ids[i] = tx.txid
    end
    return ids
end
function M.meets_difficulty(hash, difficulty)
    return hash:sub(1, difficulty) == string.rep("0", difficulty)
end
function M.parse_block_event(fields, texts)
    local txs = {}
    for i, text in ipairs(texts) do
        txs[i] = transactions.parse_transaction(text)
    end
    return M.new(tonumber(fields[4]), fields[5], fields[6], tonumber(fields[7]), tonumber(fields[8]), tonumber(fields[9]), txs)
end
function M.mine_block(height, previous, txs, timestamp, difficulty)
    local ids = {}
    for i, tx in ipairs(txs) do
        ids[i] = tx.txid
    end
    local merkle, nonce = hashing.merkle_root(ids), 0
    while not M.meets_difficulty(hashing.digest(M.header_text(height, previous, merkle, timestamp, difficulty, nonce)), difficulty) do
        nonce = nonce + 1
    end
    return M.new(height, previous, merkle, timestamp, difficulty, nonce, txs)
end
function M.context_free_error(block, maximum)
    if not M.meets_difficulty(block.hash, block.difficulty) then
        return "bad-pow"
    end
    if hashing.merkle_root(block:txids()) ~= block.merkle then
        return "bad-merkle"
    end
    local first = block.transactions[1]
    if not first:is_coinbase() or first.coinbase_height ~= block.height then
        return "bad-structure"
    end
    for i = 2, #block.transactions do
        if block.transactions[i]:is_coinbase() then
            return "bad-structure"
        end
    end
    if block:size() > maximum then
        return "too-large"
    end
end
return M
