struct MonsterType
    name::String
    symbol::Char
    min_depth::Int
    max_depth::Int
    weight::Int
    hp::Dice
    to_hit::Int
    defense::Int
    damage::Dice
    speed::Int
    xp::Int
    erratic::Bool
    stationary::Bool
    regenerates::Bool
    poisonous::Bool
end
function MonsterType(words::AbstractVector{<:AbstractString})
    MonsterType(words[1], only(words[2]), parse(Int, words[3]), parse(Int, words[4]), parse(Int, words[5]), Dice(words[6]),
        parse(Int, words[7]), parse(Int, words[8]), Dice(words[9]), parse(Int, words[10]), parse(Int, words[11]),
        occursin('E', words[12]), occursin('S', words[12]), occursin('R', words[12]), occursin('P', words[12]))
end
abstract type PotionEffect end
struct HealEffect <: PotionEffect
    dice::Dice
end
struct PoisonEffect <: PotionEffect
    turns::Int
end
struct LevelEffect <: PotionEffect end
@enum ScrollEffect mapping_scroll teleport_scroll weapon_scroll armor_scroll
abstract type ItemCategory end
struct WeaponType <: ItemCategory
    damage::Dice
    to_hit::Int
end
struct ArmorType <: ItemCategory
    defense::Int
end
struct PotionType <: ItemCategory
    effect::PotionEffect
end
struct ScrollType <: ItemCategory
    effect::ScrollEffect
end
struct FoodType <: ItemCategory
    nutrition::Int
end
struct GoldType <: ItemCategory
    dice::Dice
end
struct AmuletType <: ItemCategory end
struct ItemType
    name::String
    min_depth::Int
    max_depth::Int
    weight::Int
    category::ItemCategory
end
function ItemType(words::AbstractVector{<:AbstractString})
    category = if words[1] == "weapon"
        WeaponType(Dice(words[6]), parse(Int, words[7]))
    elseif words[1] == "armor"
        ArmorType(parse(Int, words[6]))
    elseif words[1] == "potion"
        effect = if words[6] == "heal"
            HealEffect(Dice(words[7]))
        elseif words[6] == "poison"
            PoisonEffect(parse(Int, words[7]))
        else
            LevelEffect()
        end
        PotionType(effect)
    elseif words[1] == "scroll"
        effects = Dict("mapping" => mapping_scroll, "teleport" => teleport_scroll, "enchant_weapon" => weapon_scroll, "enchant_armor" => armor_scroll)
        ScrollType(effects[words[6]])
    elseif words[1] == "food"
        FoodType(parse(Int, words[6]))
    else
        GoldType(Dice(words[6]))
    end
    ItemType(words[2], parse(Int, words[3]), parse(Int, words[4]), parse(Int, words[5]), category)
end
item_symbol(::WeaponType) = ')'
item_symbol(::ArmorType) = '['
item_symbol(::PotionType) = '!'
item_symbol(::ScrollType) = '?'
item_symbol(::FoodType) = '%'
item_symbol(::GoldType) = '$'
item_symbol(::AmuletType) = '"'
mutable struct Monster
    number::Int
    kind::Int
    x::Int
    y::Int
    hp::Int
    max_hp::Int
    asleep::Bool
    energy::Int
    was_visible::Bool
end
mutable struct Item
    kind::Int
    x::Int
    y::Int
    bonus::Int
    amount::Int
end
Item(kind::Int, x::Int, y::Int, amount::Int = 0) = Item(kind, x, y, 0, amount)
function display_name(item::Item, types::Vector{ItemType})
    kind = types[item.kind]
    name = replace(kind.name, '_' => ' ')
    kind.category isa Union{WeaponType,ArmorType} && return "+$(item.bonus) $name"
    kind.category isa GoldType && return "$(item.amount) gold"
    name
end
function reference_name(item::Item, types::Vector{ItemType})
    name = display_name(item, types)
    types[item.kind].category isa GoldType ? name : "the $name"
end
