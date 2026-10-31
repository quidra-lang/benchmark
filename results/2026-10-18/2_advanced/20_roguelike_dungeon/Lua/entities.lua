local combat = require("combat")
local M = {}
local item_symbols = {weapon = ")", armor = "[", potion = "!", scroll = "?", food = "%", gold = "$", amulet = '"'}

function M.monster_type(tokens)
    local traits = tokens[12]
    return {name = tokens[1], symbol = tokens[2], min_depth = tonumber(tokens[3]), max_depth = tonumber(tokens[4]),
        weight = tonumber(tokens[5]), hp = combat.parse_dice(tokens[6]), to_hit = tonumber(tokens[7]), defense = tonumber(tokens[8]),
        damage = combat.parse_dice(tokens[9]), speed = tonumber(tokens[10]), xp = tonumber(tokens[11]),
        erratic = traits:find("E", 1, true) ~= nil, stationary = traits:find("S", 1, true) ~= nil,
        regenerates = traits:find("R", 1, true) ~= nil, poisonous = traits:find("P", 1, true) ~= nil}
end

function M.parse_item_type(tokens)
    local category = tokens[1]
    local kind = {category = category, name = tokens[2], min_depth = tonumber(tokens[3]),
        max_depth = tonumber(tokens[4]), weight = tonumber(tokens[5]), to_hit = 0, armor = 0, poison_turns = 0, nutrition = 0}
    if category == "weapon" then kind.dice, kind.to_hit = combat.parse_dice(tokens[6]), tonumber(tokens[7])
    elseif category == "armor" then kind.armor = tonumber(tokens[6])
    elseif category == "potion" then
        kind.effect = tokens[6]
        if kind.effect == "heal" then kind.dice = combat.parse_dice(tokens[7])
        elseif kind.effect == "poison" then kind.poison_turns = tonumber(tokens[7]) end
    elseif category == "scroll" then kind.effect = tokens[6]
    elseif category == "food" then kind.nutrition = tonumber(tokens[6])
    elseif category == "gold" then kind.dice = combat.parse_dice(tokens[6]) end
    return kind
end

function M.amulet_type() return {category = "amulet", name = "amulet", min_depth = 0, max_depth = 0, weight = 0} end

function M.monster(number, kind, x, y, hp, asleep)
    return {number = number, kind = kind, x = x, y = y, hp = hp, max_hp = hp,
        asleep = asleep, energy = 0, was_visible = false}
end

local Item = {}
Item.__index = Item
function Item.new(kind, x, y, amount)
    return setmetatable({kind = kind, x = x, y = y, amount = amount or 0, bonus = 0}, Item)
end
function Item:symbol() return item_symbols[self.kind.category] end
function Item:display_name()
    local name = self.kind.name:gsub("_", " ")
    if self.kind.category == "weapon" or self.kind.category == "armor" then return "+" .. self.bonus .. " " .. name end
    if self.kind.category == "gold" then return self.amount .. " gold" end
    return name
end
function Item:reference_name() return (self.kind.category == "gold" and "" or "the ") .. self:display_name() end

M.Item = Item
return M
