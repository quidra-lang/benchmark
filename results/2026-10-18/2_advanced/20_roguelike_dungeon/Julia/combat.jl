struct Dice
    count::Int
    sides::Int
end
function Dice(text::AbstractString)
    words = split(text, 'd')
    Dice(parse(Int, words[1]), parse(Int, words[2]))
end
roll!(generator::Minstd, dice::Dice) = roll!(generator, dice.count, dice.sides)
@enum AttackOutcome attack_miss attack_hit attack_critical
function resolve_attack!(generator::Minstd, to_hit::Int, defense::Int, dice::Dice, bonus::Int)
    rolled = 1 + random_index!(generator, 20)
    rolled == 1 && return (attack_miss, 0)
    rolled == 20 && return (attack_critical, max(1, roll!(generator, dice) + roll!(generator, dice) + bonus))
    rolled + to_hit >= defense && return (attack_hit, max(1, roll!(generator, dice) + bonus))
    (attack_miss, 0)
end
