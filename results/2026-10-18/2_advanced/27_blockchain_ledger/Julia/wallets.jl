struct Wallet
    name::String
    secret::String
    address::String
end
Wallet(name, secret) = Wallet(name, secret, digest("addr:" * secret)[1:16])
signature(secret, index, body) = digest("$secret:$index:$body")[1:16]
read_wallets(path) = [Wallet(split(line)...) for line in readlines(path)]
