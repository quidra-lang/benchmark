local yaku = {}
yaku.ordinary_table = {
    {'riichi', 1}, {'double_riichi', 2}, {'ippatsu', 1}, {'menzen_tsumo', 1}, {'pinfu', 1}, {'tanyao', 1, 1}, {'iipeikou', 1},
    {'haku', 1, 1}, {'hatsu', 1, 1}, {'chun', 1, 1}, {'jikaze', 1, 1}, {'bakaze', 1, 1}, {'haitei', 1, 1}, {'houtei', 1, 1},
    {'rinshan', 1, 1}, {'chankan', 1, 1}, {'chiitoitsu', 2}, {'toitoi', 2, 2}, {'sanankou', 2, 2}, {'sanshoku_doujun', 2, 1},
    {'sanshoku_doukou', 2, 2}, {'ittsu', 2, 1}, {'chanta', 2, 1}, {'sankantsu', 2, 2}, {'shousangen', 2, 2}, {'honroutou', 2, 2},
    {'honitsu', 3, 2}, {'junchan', 3, 2}, {'ryanpeikou', 3}, {'chinitsu', 6, 5},
}
yaku.yakuman_table = {{'tenhou', 1}, {'chiihou', 1}, {'kokushi', 1}, {'kokushi_13', 2}, {'suuankou', 1}, {'suuankou_tanki', 2},
    {'daisangen', 1}, {'shousuushii', 1}, {'daisuushii', 2}, {'tsuuiisou', 1}, {'chinroutou', 1}, {'ryuuiisou', 1}, {'chuuren', 1}, {'junsei_chuuren', 2}, {'suukantsu', 1}}
yaku.flags = {'riichi', 'double_riichi', 'ippatsu', 'haitei', 'houtei', 'rinshan', 'chankan', 'tenhou', 'chiihou'}
yaku.categories = {'none', 'mangan', 'haneman', 'baiman', 'sanbaiman', 'kazoe_yakuman', 'yakuman'}
function yaku.ordinary(names, closed)
    local result = {}
    for _, entry in ipairs(yaku.ordinary_table) do
        local han = closed and entry[2] or entry[3]
        if names[entry[1]] and han ~= nil then result[#result + 1] = {name = entry[1], value = han} end
    end
    return result
end
function yaku.yakuman(names, double)
    local result = {}; for _, entry in ipairs(yaku.yakuman_table) do if names[entry[1]] then result[#result + 1] = {name = entry[1], value = double and entry[2] or 1} end end; return result
end
return yaku
