local hashing = require("hashing")
local M = {}
function M.address_of(secret)
    return hashing.digest("addr:" .. secret):sub(1, 16)
end
function M.sign(secret, index, body)
    return hashing.digest(secret .. ":" .. index .. ":" .. body):sub(1, 16)
end
function M.read_wallets(path)
    local wallets = {}
    for line in io.lines(path) do
        local name, secret = line:match("^(%S+) (%S+)$")
        wallets[#wallets + 1] = {name = name, secret = secret, address = M.address_of(secret)}
    end
    return wallets
end
return M
