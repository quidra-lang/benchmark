local hashing, wallets = require("hashing"), require("wallets")
local M = {}
local Transaction = {}
Transaction.__index = Transaction
local function transaction(text, inputs, outputs, signatures, height)
    return setmetatable({text = text, txid = hashing.digest(text), size = #text, inputs = inputs, outputs = outputs, signatures = signatures, coinbase_height = height}, Transaction)
end
function Transaction:is_coinbase()
    return self.coinbase_height ~= nil
end
function Transaction:body()
    return self.text:match("^(.-);sig=")
end
function Transaction:output_total()
    local total = 0
    for _, output in ipairs(self.outputs) do
        total = total + output.amount
    end
    return total
end
local function parse_outputs(text)
    local outputs = {}
    for part in text:gmatch("[^,]+") do
        local address, amount = part:match("^(%w+):(%d+)$")
        outputs[#outputs + 1] = {address = address, amount = tonumber(amount)}
    end
    return outputs
end
local function outputs_text(outputs)
    local parts = {}
    for i, output in ipairs(outputs) do
        parts[i] = output.address .. ":" .. output.amount
    end
    return table.concat(parts, ",")
end
function M.parse_transaction(text)
    local height, outputs = text:match("^cb=(%d+);out=(.+)$")
    if height then
        return transaction(text, {}, parse_outputs(outputs), {}, tonumber(height))
    end
    local inputs, out, sig = text:match("^in=(.-);out=(.-);sig=(.+)$")
    local references, signatures = {}, {}
    for reference in inputs:gmatch("[^,]+") do
        references[#references + 1] = reference
    end
    for signature in sig:gmatch("[^,]+") do
        signatures[#signatures + 1] = signature
    end
    return transaction(text, references, parse_outputs(out), signatures)
end
function M.create_transaction(inputs, outputs, secret)
    local body = "in=" .. table.concat(inputs, ",") .. ";out=" .. outputs_text(outputs)
    local signatures = {}
    for i = 1, #inputs do
        signatures[i] = wallets.sign(secret, i - 1, body)
    end
    return transaction(body .. ";sig=" .. table.concat(signatures, ","), {table.unpack(inputs)}, outputs, signatures)
end
function M.create_coinbase(height, outputs)
    return transaction("cb=" .. height .. ";out=" .. outputs_text(outputs), {}, outputs, {}, height)
end
function M.is_mature(coin, height, maturity)
    return not coin.coinbase or coin.height == 0 or height >= coin.height + maturity
end
function M.check_transaction(tx, utxo, spent, height, owners, maturity)
    for _, output in ipairs(tx.outputs) do
        if not owners[output.address] or output.amount == 0 then
            return "bad-output", 0
        end
    end
    local seen, total, body = {}, 0, tx:body()
    for i, reference in ipairs(tx.inputs) do
        if spent[reference] or seen[reference] then
            return "double-spend", 0
        end
        local coin = utxo[reference]
        if not coin then
            return "missing-input", 0
        end
        if not M.is_mature(coin, height, maturity) then
            return "immature", 0
        end
        if tx.signatures[i] ~= wallets.sign(owners[coin.address].secret, i - 1, body) then
            return "bad-sig", 0
        end
        seen[reference], total = true, total + coin.amount
    end
    local amount = tx:output_total()
    if total < amount then
        return "overspend", 0
    end
    return nil, total - amount
end
function M.apply_transaction(utxo, tx, height)
    for _, reference in ipairs(tx.inputs) do
        utxo[reference] = nil
    end
    for i, output in ipairs(tx.outputs) do
        utxo[tx.txid .. ":" .. (i - 1)] = {address = output.address, amount = output.amount, height = height, coinbase = tx:is_coinbase()}
    end
end
return M
