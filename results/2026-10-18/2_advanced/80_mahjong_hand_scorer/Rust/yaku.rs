pub const NAMES: [&str;30] = ["riichi","double_riichi","ippatsu","menzen_tsumo","pinfu","tanyao","iipeikou","haku","hatsu","chun","jikaze","bakaze","haitei","houtei","rinshan","chankan","chiitoitsu","toitoi","sanankou","sanshoku_doujun","sanshoku_doukou","ittsu","chanta","sankantsu","shousangen","honroutou","honitsu","junchan","ryanpeikou","chinitsu"];
const CLOSED: [i64;30] = [1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,3,3,3,6];
const OPEN: [i64;30] = [0,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,0,2,2,1,2,1,1,2,2,2,2,2,0,5];
pub const YAKUMAN: [&str;15] = ["tenhou","chiihou","kokushi","kokushi_13","suuankou","suuankou_tanki","daisangen","shousuushii","daisuushii","tsuuiisou","chinroutou","ryuuiisou","chuuren","junsei_chuuren","suukantsu"];
const MULTIPLIERS: [i64;15] = [1,1,1,2,1,2,1,1,2,1,1,1,1,2,1];
pub const FLAGS: [&str;9] = ["riichi","double_riichi","ippatsu","haitei","houtei","rinshan","chankan","tenhou","chiihou"];
pub const CATEGORIES: [&str;7] = ["none","mangan","haneman","baiman","sanbaiman","kazoe_yakuman","yakuman"];
pub const WAITS: [&str;7] = ["ryanmen","kanchan","penchan","shanpon","tanki","single","thirteen"];
pub fn ordinary(holds: &[bool;30], closed: bool) -> Vec<(usize,i64)> {
    (0..30).filter_map(|i| {
        let han = if closed {
            CLOSED[i]
        } else {
            OPEN[i]
        };
        if holds[i] && han > 0 {
            Some((i,han))
        } else {
            None
        }
    }).collect()
}
pub fn yakuman(holds: &[bool;15], double: bool) -> Vec<(usize,i64)> {
    (0..15).filter(|&i| holds[i]).map(|i| (i,if double {
        MULTIPLIERS[i]
    } else {
        1
    })).collect()
}
