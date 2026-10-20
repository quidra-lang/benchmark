module KeyValueStore

const WRONG_TYPE = "WRONGTYPE Operation against a key holding the wrong kind of value"
const NOT_INTEGER = "ERR value is not an integer or out of range"
const POSITIVE = "ERR value is out of range, must be positive"
struct CommandError <: Exception
    message::String
end
fail(message::String) = throw(CommandError(message))

abstract type Value end
struct TextValue <: Value
    text::String
end
struct ListValue <: Value
    items::Vector{String}
end
struct HashValue <: Value
    fields::Dict{String,String}
end
struct SetValue <: Value
    members::Set{String}
end
struct SortedSetValue <: Value
    scores::Dict{String,Int}
end
kind(::TextValue) = "string"
kind(::ListValue) = "list"
kind(::HashValue) = "hash"
kind(::SetValue) = "set"
kind(::SortedSetValue) = "zset"
empty_value(::TextValue) = false
empty_value(value::ListValue) = isempty(value.items)
empty_value(value::HashValue) = isempty(value.fields)
empty_value(value::SetValue) = isempty(value.members)
empty_value(value::SortedSetValue) = isempty(value.scores)

struct Entry
    value::Value
    expiry::Union{Nothing,Int}
end
const Database = Dict{String,Entry}
mutable struct Store
    database::Database
    clock::Int
    stack::Vector{Database}
    snapshots::Dict{String,Database}
end
Store() = Store(Database(), 0, Database[], Dict{String,Database}())

quoted(::Nothing) = "(nil)"
quoted(text::AbstractString) = "\"" * replace(text, '\\' => "\\\\", '"' => "\\\"") * "\""
integer_reply(value::Integer) = "(integer) $value"
function array_reply(values)
    isempty(values) && return ["(empty array)"]
    width = ndigits(length(values))
    [lpad(string(i), width) * ") " * quoted(value) for (i, value) in enumerate(values)]
end

function split_line(line::String)
    words = String[]
    i, n = 1, length(line)
    while i <= n
        if line[i] == ' '
            i += 1
            continue
        end
        if line[i] != '"'
            start = i
            while i <= n && line[i] != ' '
                i += 1
            end
            push!(words, line[start:i-1])
            continue
        end
        i += 1
        text = IOBuffer()
        closed = false
        while i <= n
            character = line[i]
            i += 1
            if character == '"'
                closed = true
                break
            end
            if character == '\\'
                i > n && return nothing
                character = line[i]
                i += 1
                character in ('\\', '"') || return nothing
            end
            print(text, character)
        end
        (!closed || (i <= n && line[i] != ' ')) && return nothing
        push!(words, String(take!(text)))
    end
    words
end

valid_integer(text::String) = occursin(r"^(0|-?[1-9][0-9]{0,8})$", text)
function number(text::String, message::String=NOT_INTEGER)
    valid_integer(text) || fail(message)
    parse(Int, text)
end
function incremented(previous::Int, delta::Int)
    value = previous + delta
    abs(value) <= 999999999 || fail("ERR increment or decrement would overflow")
    value
end
function normalized_range(n::Int, first::Int, last::Int)
    start = max(0, first < 0 ? first + n : first)
    stop = min(n - 1, last < 0 ? last + n : last)
    start <= stop ? (start+1:stop+1) : (1:0)
end
struct ScoreBound
    infinity::Int
    value::Int
    exclusive::Bool
end
function score_bound(text::String)
    text == "-inf" && return ScoreBound(-1, 0, false)
    text == "+inf" && return ScoreBound(1, 0, false)
    exclusive = startswith(text, "(")
    value = number(exclusive ? text[2:end] : text, "ERR min or max is not a float")
    ScoreBound(0, value, exclusive)
end
function within_bound(score::Int, bound::ScoreBound, lower::Bool)
    bound.infinity != 0 && return lower == (bound.infinity < 0)
    (lower ? score > bound.value : score < bound.value) || (!bound.exclusive && score == bound.value)
end

abstract type PatternPart end
struct Literal <: PatternPart
    value::Char
end
struct AnyCharacter <: PatternPart end
struct AnySequence <: PatternPart end
struct CharacterClass <: PatternPart
    members::BitSet
    negated::Bool
end
accepts(part::Literal, character::Char) = part.value == character
accepts(::AnyCharacter, ::Char) = true
accepts(part::CharacterClass, character::Char) = (Int(character) in part.members) != part.negated
function parse_pattern(text::String)
    parts = PatternPart[]
    i, n = 1, length(text)
    while i <= n
        character = text[i]
        i += 1
        if character == '\\'
            i <= n || fail("ERR invalid pattern")
            push!(parts, Literal(text[i]))
            i += 1
        elseif character == '['
            finish = findnext(']', text, i)
            isnothing(finish) && fail("ERR invalid pattern")
            negated = i < finish && text[i] == '^'
            i += Int(negated)
            i < finish || fail("ERR invalid pattern")
            members = BitSet()
            while i < finish
                first = Int(text[i])
                if i + 2 < finish && text[i+1] == '-'
                    last = Int(text[i+2])
                    union!(members, min(first, last):max(first, last))
                    i += 3
                else
                    push!(members, first)
                    i += 1
                end
            end
            push!(parts, CharacterClass(members, negated))
            i = finish + 1
        elseif character == '*'
            push!(parts, AnySequence())
        elseif character == '?'
            push!(parts, AnyCharacter())
        else
            push!(parts, Literal(character))
        end
    end
    parts
end
function matches_pattern(parts::Vector{PatternPart}, text::String)
    previous = falses(length(text) + 1)
    previous[1] = true
    for part in parts
        following = falses(length(previous))
        if part isa AnySequence
            following[1] = previous[1]
            for i in eachindex(text)
                following[i+1] = previous[i+1] || following[i]
            end
        else
            for (i, character) in enumerate(text)
                following[i+1] = previous[i] && accepts(part, character)
            end
        end
        previous = following
    end
    last(previous)
end

# Stored payloads are never mutated; edits replace an Entry with a new value.
function read_value(store::Store, key::String, ::Type{T}, empty::T) where {T<:Value}
    entry = get(store.database, key, nothing)
    isnothing(entry) && return empty
    entry.value isa T || fail(WRONG_TYPE)
    entry.value::T
end
text_value(store::Store, key::String) = read_value(store, key, TextValue, TextValue("")).text
list_values(store::Store, key::String) = copy(read_value(store, key, ListValue, ListValue(String[])).items)
hash_fields(store::Store, key::String) = copy(read_value(store, key, HashValue, HashValue(Dict{String,String}())).fields)
set_members(store::Store, key::String) = copy(read_value(store, key, SetValue, SetValue(Set{String}())).members)
zset_scores(store::Store, key::String) = copy(read_value(store, key, SortedSetValue, SortedSetValue(Dict{String,Int}())).scores)
function replace_value!(store::Store, key::String, value::Value, expiry::Union{Nothing,Int}=nothing)
    if empty_value(value)
        delete!(store.database, key)
    else
        store.database[key] = Entry(value, expiry)
    end
end
function update_value!(store::Store, key::String, value::Value)
    old = get(store.database, key, nothing)
    replace_value!(store, key, value, isnothing(old) ? nothing : old.expiry)
end
function purge!(store::Store)
    before = length(store.database)
    filter!(pair -> isnothing(pair.second.expiry) || pair.second.expiry > store.clock, store.database)
    before - length(store.database)
end

struct CommandSpec
    minimum::Int
    maximum::Union{Nothing,Int}
    parity::Union{Nothing,Int}
end
const COMMANDS = let commands = Dict{String,CommandSpec}()
    function register!(names, minimum, maximum=minimum, parity=nothing)
        for name in split(names)
            commands[name] = CommandSpec(minimum, maximum, parity)
        end
    end
    register!("TIME DBSIZE FLUSH INFO BEGIN COMMIT ROLLBACK", 0)
    register!("GET INCR DECR STRLEN LLEN HGETALL HLEN HKEYS HVALS SMEMBERS SCARD ZCARD TYPE KEYS TTL PERSIST TICK SNAPSHOT RESTORE", 1)
    register!("INCRBY DECRBY APPEND LINDEX HGET HEXISTS SISMEMBER ZSCORE ZRANK RENAME RENAMENX", 2)
    register!("GETRANGE LRANGE LSET LREM LTRIM HINCRBY ZINCRBY", 3)
    register!("LINSERT", 4)
    register!("LPOP RPOP", 1, 2)
    register!("EXPIRE", 2, 3)
    register!("ZRANGE ZRANGEBYSCORE", 3, 4)
    register!("MGET SINTER SUNION SDIFF DEL EXISTS", 1, nothing)
    register!("SET LPUSH RPUSH HDEL SADD SREM ZREM SINTERSTORE SUNIONSTORE SDIFFSTORE", 2, nothing)
    register!("MSET", 2, nothing, 0)
    register!("HSET ZADD", 3, nothing, 1)
    commands
end
function command_name(words::Vector{String})
    name = uppercase(words[1])
    spec = get(COMMANDS, name, nothing)
    isnothing(spec) && fail("ERR unknown command '$(words[1])'")
    n = length(words) - 1
    if n < spec.minimum || (!isnothing(spec.maximum) && n > spec.maximum) ||
       (!isnothing(spec.parity) && mod(n, 2) != spec.parity)
        fail("ERR wrong number of arguments for '$(lowercase(name))' command")
    end
    name
end

function set_string!(store::Store, args::Vector{String})
    key = args[1]
    options = Set{String}()
    seconds_text = nothing
    i = 3
    while i <= length(args)
        option = uppercase(args[i])
        i += 1
        option in ("NX", "XX", "EX", "KEEPTTL", "GET") && !(option in options) || fail("ERR syntax error")
        push!(options, option)
        if option == "EX"
            i <= length(args) || fail("ERR syntax error")
            seconds_text = args[i]
            i += 1
        end
    end
    (("NX" in options && "XX" in options) || ("EX" in options && "KEEPTTL" in options)) && fail("ERR syntax error")
    expiry = nothing
    if "EX" in options
        seconds = number(seconds_text)
        seconds > 0 || fail("ERR invalid expire time in 'set' command")
        expiry = store.clock + seconds
    end
    old = get(store.database, key, nothing)
    old_text = nothing
    if "GET" in options
        text = text_value(store, key)
        !isnothing(old) && (old_text = text)
    end
    blocked = ("NX" in options && !isnothing(old)) || ("XX" in options && isnothing(old))
    if !blocked
        "KEEPTTL" in options && !isnothing(old) && (expiry = old.expiry)
        replace_value!(store, key, TextValue(args[2]), expiry)
    end
    "GET" in options ? quoted(old_text) : blocked ? "(nil)" : "OK"
end
function string_command!(store::Store, command::String, args::Vector{String})
    key = args[1]
    command == "SET" && return set_string!(store, args)
    if command == "MSET"
        for i in 1:2:length(args)
            replace_value!(store, args[i], TextValue(args[i+1]))
        end
        return "OK"
    elseif command == "MGET"
        values = map(args) do name
            entry = get(store.database, name, nothing)
            !isnothing(entry) && entry.value isa TextValue ? entry.value.text : nothing
        end
        return array_reply(values)
    elseif command in ("INCR", "DECR", "INCRBY", "DECRBY")
        delta = length(args) == 2 ? number(args[2]) : 1
        startswith(command, "DECR") && (delta = -delta)
        text = text_value(store, key)
        previous = haskey(store.database, key) ? number(text) : 0
        value = incremented(previous, delta)
        update_value!(store, key, TextValue(string(value)))
        return integer_reply(value)
    elseif command == "APPEND"
        value = text_value(store, key) * args[2]
        update_value!(store, key, TextValue(value))
        return integer_reply(length(value))
    elseif command == "GETRANGE"
        first = number(args[2])
        last = number(args[3])
        value = text_value(store, key)
        return quoted(value[normalized_range(length(value), first, last)])
    end
    value = text_value(store, key)
    command == "STRLEN" ? integer_reply(length(value)) : quoted(haskey(store.database, key) ? value : nothing)
end

function list_command!(store::Store, command::String, args::Vector{String})
    key = args[1]
    if command in ("LPUSH", "RPUSH")
        values = list_values(store, key)
        for value in args[2:end]
            command == "LPUSH" ? pushfirst!(values, value) : push!(values, value)
        end
        update_value!(store, key, ListValue(values))
        return integer_reply(length(values))
    elseif command in ("LPOP", "RPOP")
        count = length(args) == 2 ? number(args[2], POSITIVE) : nothing
        !isnothing(count) && count < 0 && fail(POSITIVE)
        values = list_values(store, key)
        haskey(store.database, key) || return "(nil)"
        removed = String[]
        for _ in 1:min(something(count, 1), length(values))
            push!(removed, command == "LPOP" ? popfirst!(values) : pop!(values))
        end
        update_value!(store, key, ListValue(values))
        return isnothing(count) ? quoted(removed[1]) : array_reply(removed)
    elseif command in ("LRANGE", "LTRIM")
        first = number(args[2])
        last = number(args[3])
        values = list_values(store, key)
        kept = values[normalized_range(length(values), first, last)]
        command == "LRANGE" && return array_reply(kept)
        update_value!(store, key, ListValue(kept))
        return "OK"
    elseif command == "LLEN"
        return integer_reply(length(list_values(store, key)))
    elseif command in ("LINDEX", "LSET")
        index = number(args[2])
        values = list_values(store, key)
        command == "LSET" && !haskey(store.database, key) && fail("ERR no such key")
        index < 0 && (index += length(values))
        if !(0 <= index < length(values))
            command == "LINDEX" && return "(nil)"
            fail("ERR index out of range")
        end
        command == "LINDEX" && return quoted(values[index+1])
        values[index+1] = args[3]
        update_value!(store, key, ListValue(values))
        return "OK"
    elseif command == "LREM"
        count = number(args[2])
        values = list_values(store, key)
        positions = findall(==(args[3]), values)
        if count > 0
            positions = positions[1:min(count, length(positions))]
        elseif count < 0
            positions = positions[end-min(-count, length(positions))+1:end]
        end
        deleteat!(values, positions)
        update_value!(store, key, ListValue(values))
        return integer_reply(length(positions))
    end
    position = uppercase(args[2])
    position in ("BEFORE", "AFTER") || fail("ERR syntax error")
    values = list_values(store, key)
    isempty(values) && return integer_reply(0)
    index = findfirst(==(args[3]), values)
    isnothing(index) && return integer_reply(-1)
    insert!(values, index + Int(position == "AFTER"), args[4])
    update_value!(store, key, ListValue(values))
    integer_reply(length(values))
end

function hash_command!(store::Store, command::String, args::Vector{String})
    key = args[1]
    if command == "HINCRBY"
        delta = number(args[3])
        fields = hash_fields(store, key)
        previous = haskey(fields, args[2]) ? number(fields[args[2]], "ERR hash value is not an integer") : 0
        value = incremented(previous, delta)
        fields[args[2]] = string(value)
        update_value!(store, key, HashValue(fields))
        return integer_reply(value)
    end
    fields = hash_fields(store, key)
    if command == "HSET"
        before = length(fields)
        for i in 2:2:length(args)
            fields[args[i]] = args[i+1]
        end
        update_value!(store, key, HashValue(fields))
        return integer_reply(length(fields) - before)
    elseif command == "HDEL"
        before = length(fields)
        for field in args[2:end]
            delete!(fields, field)
        end
        update_value!(store, key, HashValue(fields))
        return integer_reply(before - length(fields))
    elseif command == "HGET"
        return quoted(get(fields, args[2], nothing))
    elseif command == "HEXISTS"
        return integer_reply(Int(haskey(fields, args[2])))
    elseif command == "HLEN"
        return integer_reply(length(fields))
    end
    ordered = sort!(collect(keys(fields)))
    command == "HKEYS" && return array_reply(ordered)
    command == "HVALS" && return array_reply([fields[field] for field in ordered])
    array_reply([item for field in ordered for item in (field, fields[field])])
end

function set_command!(store::Store, command::String, args::Vector{String})
    key = args[1]
    if startswith(command, "SINTER") || startswith(command, "SUNION") || startswith(command, "SDIFF")
        saving = endswith(command, "STORE")
        sources = [set_members(store, name) for name in (saving ? args[2:end] : args)]
        operation = startswith(command, "SINTER") ? intersect : startswith(command, "SUNION") ? union : setdiff
        result = foldl(operation, sources)
        !saving && return array_reply(sort!(collect(result)))
        replace_value!(store, key, SetValue(result))
        return integer_reply(length(result))
    end
    values = set_members(store, key)
    if command in ("SADD", "SREM")
        before = length(values)
        command == "SADD" ? union!(values, args[2:end]) : setdiff!(values, args[2:end])
        update_value!(store, key, SetValue(values))
        return integer_reply(abs(length(values) - before))
    elseif command == "SCARD"
        return integer_reply(length(values))
    elseif command == "SISMEMBER"
        return integer_reply(Int(args[2] in values))
    end
    array_reply(sort!(collect(values)))
end

function zset_command!(store::Store, command::String, args::Vector{String})
    key = args[1]
    if command == "ZADD"
        numbers = [number(args[i]) for i in 2:2:length(args)]
        scores = zset_scores(store, key)
        before = length(scores)
        for (i, score) in enumerate(numbers)
            scores[args[2i+1]] = score
        end
        update_value!(store, key, SortedSetValue(scores))
        return integer_reply(length(scores) - before)
    elseif command == "ZINCRBY"
        delta = number(args[2])
        scores = zset_scores(store, key)
        value = incremented(get(scores, args[3], 0), delta)
        scores[args[3]] = value
        update_value!(store, key, SortedSetValue(scores))
        return quoted(string(value))
    end
    with_scores = false
    first, last = 0, 0
    minimum, maximum = nothing, nothing
    if command in ("ZRANGE", "ZRANGEBYSCORE")
        with_scores = length(args) == 4
        with_scores && uppercase(args[4]) != "WITHSCORES" && fail("ERR syntax error")
        if command == "ZRANGE"
            first = number(args[2])
            last = number(args[3])
        else
            minimum = score_bound(args[2])
            maximum = score_bound(args[3])
        end
    end
    scores = zset_scores(store, key)
    if command == "ZREM"
        before = length(scores)
        for member in args[2:end]
            delete!(scores, member)
        end
        update_value!(store, key, SortedSetValue(scores))
        return integer_reply(before - length(scores))
    elseif command == "ZCARD"
        return integer_reply(length(scores))
    elseif command == "ZSCORE"
        return quoted(haskey(scores, args[2]) ? string(scores[args[2]]) : nothing)
    end
    ordered = sort!(collect(scores); by=pair -> (pair.second, pair.first))
    if command == "ZRANK"
        index = findfirst(pair -> pair.first == args[2], ordered)
        return isnothing(index) ? "(nil)" : integer_reply(index - 1)
    end
    selected = command == "ZRANGE" ? ordered[normalized_range(length(ordered), first, last)] :
        filter(pair -> within_bound(pair.second, minimum, true) && within_bound(pair.second, maximum, false), ordered)
    items = with_scores ? [item for (member, score) in selected for item in (member, string(score))] :
        [pair.first for pair in selected]
    array_reply(items)
end

function key_command!(store::Store, command::String, args::Vector{String})
    command == "TIME" && return integer_reply(store.clock)
    command == "DBSIZE" && return integer_reply(length(store.database))
    if command == "FLUSH"
        empty!(store.database)
        return "OK"
    elseif command == "INFO"
        counts = [count(entry -> kind(entry.value) == name, values(store.database)) for name in ("string", "list", "hash", "set", "zset")]
        expires = count(entry -> !isnothing(entry.expiry), values(store.database))
        return "keys=$(length(store.database)),expires=$expires,string=$(counts[1]),list=$(counts[2]),hash=$(counts[3])," *
               "set=$(counts[4]),zset=$(counts[5]),time=$(store.clock),depth=$(length(store.stack)),snapshots=$(length(store.snapshots))"
    elseif command == "DEL"
        removed = 0
        for key in args
            removed += Int(!isnothing(pop!(store.database, key, nothing)))
        end
        return integer_reply(removed)
    elseif command == "EXISTS"
        return integer_reply(count(key -> haskey(store.database, key), args))
    elseif command == "KEYS"
        parts = parse_pattern(args[1])
        return array_reply(sort!([key for key in keys(store.database) if matches_pattern(parts, key)]))
    elseif command == "TICK"
        ticks = number(args[1])
        ticks > 0 || fail(POSITIVE)
        store.clock += ticks
        return integer_reply(purge!(store))
    end
    key = args[1]
    if command == "EXPIRE"
        condition = length(args) == 3 ? uppercase(args[3]) : nothing
        !isnothing(condition) && !(condition in ("NX", "XX", "GT", "LT")) && fail("ERR Unsupported option $(args[3])")
        seconds = number(args[2])
        entry = get(store.database, key, nothing)
        isnothing(entry) && return integer_reply(0)
        deadline = store.clock + seconds
        rejected = condition == "NX" ? !isnothing(entry.expiry) :
                   condition == "XX" ? isnothing(entry.expiry) :
                   condition == "GT" ? (isnothing(entry.expiry) || deadline <= entry.expiry) :
                   condition == "LT" ? (!isnothing(entry.expiry) && deadline >= entry.expiry) : false
        rejected && return integer_reply(0)
        if seconds <= 0
            delete!(store.database, key)
        else
            store.database[key] = Entry(entry.value, deadline)
        end
        return integer_reply(1)
    end
    entry = get(store.database, key, nothing)
    command == "TYPE" && return isnothing(entry) ? "none" : kind(entry.value)
    command == "TTL" && return integer_reply(isnothing(entry) ? -2 : isnothing(entry.expiry) ? -1 : entry.expiry - store.clock)
    if command == "PERSIST"
        (isnothing(entry) || isnothing(entry.expiry)) && return integer_reply(0)
        store.database[key] = Entry(entry.value, nothing)
        return integer_reply(1)
    end
    isnothing(entry) && fail("ERR no such key")
    destination = args[2]
    command == "RENAMENX" && haskey(store.database, destination) && return integer_reply(0)
    if key != destination
        delete!(store.database, key)
        store.database[destination] = entry
    end
    command == "RENAME" ? "OK" : integer_reply(1)
end
function control_command!(store::Store, command::String, args::Vector{String})
    if command == "BEGIN"
        push!(store.stack, copy(store.database))
    elseif command in ("COMMIT", "ROLLBACK")
        isempty(store.stack) && fail("ERR no transaction")
        saved = pop!(store.stack)
        if command == "ROLLBACK"
            store.database = saved
            purge!(store)
        end
    elseif command == "SNAPSHOT"
        store.snapshots[args[1]] = copy(store.database)
    else
        saved = get(store.snapshots, args[1], nothing)
        isnothing(saved) && fail("ERR no such snapshot")
        store.database = copy(saved)
        purge!(store)
    end
    "OK"
end
function execute!(store::Store, words::Vector{String})
    command = command_name(words)
    args = words[2:end]
    command in ("SET", "GET", "MSET", "MGET", "INCR", "DECR", "INCRBY", "DECRBY", "APPEND", "STRLEN", "GETRANGE") &&
        return string_command!(store, command, args)
    command in ("LPUSH", "RPUSH", "LPOP", "RPOP", "LRANGE", "LLEN", "LINDEX", "LSET", "LREM", "LTRIM", "LINSERT") &&
        return list_command!(store, command, args)
    command in ("HSET", "HGET", "HDEL", "HGETALL", "HLEN", "HEXISTS", "HKEYS", "HVALS", "HINCRBY") &&
        return hash_command!(store, command, args)
    command in ("SADD", "SREM", "SISMEMBER", "SMEMBERS", "SCARD", "SINTER", "SUNION", "SDIFF", "SINTERSTORE", "SUNIONSTORE", "SDIFFSTORE") &&
        return set_command!(store, command, args)
    command in ("ZADD", "ZSCORE", "ZINCRBY", "ZREM", "ZCARD", "ZRANK", "ZRANGE", "ZRANGEBYSCORE") &&
        return zset_command!(store, command, args)
    command in ("BEGIN", "COMMIT", "ROLLBACK", "SNAPSHOT", "RESTORE") && return control_command!(store, command, args)
    key_command!(store, command, args)
end

function main()
    store = Store()
    for _ in 1:parse(Int, readline())
        words = split_line(readline())
        reply = try
            isnothing(words) ? "Invalid argument(s)" : execute!(store, words)
        catch exception
            exception isa CommandError || rethrow()
            "(error) " * exception.message
        end
        reply isa String ? println(reply) : foreach(println, reply)
    end
end
main()

end
