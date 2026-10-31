struct MahjongTile
    kind::Int
    red::Bool
end

const TILE_SUITS = "mpsz"
const WINDS = ("E", "S", "W", "N")
const WIND_TILES = Dict(wind => 26 + index for (index, wind) in enumerate(WINDS))
const YAOCHUU = (0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33)
const GREEN_TILES = Set([19, 20, 21, 23, 25, 32])

function parse_tiles(text; allow_empty=false)
    text == "-" && return allow_empty ? MahjongTile[] : nothing
    result, digits = MahjongTile[], Int[]
    for character in text
        if '0' <= character <= '9'
            push!(digits, Int(character - '0'))
        elseif character in TILE_SUITS && !isempty(digits)
            suit = findfirst(==(character), TILE_SUITS) - 1
            for digit in digits
                suit == 3 && !(1 <= digit <= 7) && return nothing
                number = digit == 0 ? 5 : digit
                push!(result, MahjongTile(suit * 9 + number - 1, digit == 0))
            end
            empty!(digits)
        else
            return nothing
        end
    end
    return !isempty(result) && isempty(digits) ? result : nothing
end

tile_name(kind) = string(kind % 9 + 1, TILE_SUITS[kind ÷ 9 + 1])
function block_notation(kinds)
    ordered = sort!(collect(kinds))
    return join(kind % 9 + 1 for kind in ordered) * string(TILE_SUITS[ordered[1] ÷ 9 + 1])
end

function tile_counts(tiles)
    counts = zeros(Int, 34)
    for tile in tiles
        counts[tile.kind + 1] += 1
    end
    return counts
end

is_honor(kind) = kind >= 27
is_terminal(kind) = kind < 27 && kind % 9 in (0, 8)
is_yaochuu(kind) = is_honor(kind) || is_terminal(kind)
function next_dora(kind)
    kind < 27 && return kind ÷ 9 * 9 + (kind % 9 + 1) % 9
    kind < 31 && return 27 + (kind - 26) % 4
    return 31 + (kind - 30) % 3
end
