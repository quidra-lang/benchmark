const Reference = Tuple{String,Int}
const Output = Tuple{String,Int}
struct Transaction
    text::String
    txid::String
    size::Int
    inputs::Vector{Reference}
    outputs::Vector{Output}
    signatures::Vector{String}
    coinbase_height::Union{Nothing,Int}
end
struct Coin
    address::String
    amount::Int
    height::Int
    coinbase::Bool
end
is_coinbase(tx) = !isnothing(tx.coinbase_height)
is_mature(coin, height, maturity) = !coin.coinbase || coin.height == 0 || height >= coin.height + maturity
output_total(tx) = sum((v for (_,v) in tx.outputs); init=0)
transaction_body(tx) = first(split(tx.text, ";sig="))
function parse_transaction(text)
    parts = split(text, ';')
    pair(s) = ((a,b) = split(s, ':'); (String(a), parse(Int,b)))
    outputs = pair.(split(parts[2][5:end], ','))
    coinbase = startswith(parts[1], "cb=")
    inputs = coinbase ? Reference[] : pair.(split(parts[1][4:end], ','))
    signatures = coinbase ? String[] : String.(split(parts[3][5:end], ','))
    height = coinbase ? parse(Int, parts[1][4:end]) : nothing
    Transaction(text, digest(text), ncodeunits(text), inputs, outputs, signatures, height)
end
pairs_text(pairs) = join(("$a:$v" for (a,v) in pairs), ',')
function create_transaction(inputs, outputs, secret)
    body = "in=" * pairs_text(inputs) * ";out=" * pairs_text(outputs)
    parse_transaction(body * ";sig=" * join((signature(secret,i-1,body) for i in eachindex(inputs)), ','))
end
create_coinbase(height, outputs) = parse_transaction("cb=$height;out=" * pairs_text(outputs))
function check_transaction(tx, utxo, spent, height, owners, maturity)
    any(!haskey(owners,a) || v == 0 for (a,v) in tx.outputs) && return ("bad-output",0)
    seen = Set{Reference}()
    total = 0
    for (i,ref) in enumerate(tx.inputs)
        (ref in spent || ref in seen) && return ("double-spend",0)
        !haskey(utxo,ref) && return ("missing-input",0)
        coin = utxo[ref]
        !is_mature(coin,height,maturity) && return ("immature",0)
        tx.signatures[i] != signature(
            owners[coin.address].secret,
            i-1,
            transaction_body(tx)
        ) && return ("bad-sig",0)
        push!(seen,ref)
        total += coin.amount
    end
    total < output_total(tx) && return ("overspend",0)
    nothing, total - output_total(tx)
end
function apply_transaction!(utxo, tx, height)
    for ref in tx.inputs
        delete!(utxo,ref)
    end
    for (i,(address,amount)) in enumerate(tx.outputs)
        utxo[(tx.txid,i-1)] = Coin(address,amount,height,is_coinbase(tx))
    end
end
