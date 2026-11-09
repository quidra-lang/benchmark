use crate::tiles;
pub struct Block {
    pub kind: usize,
    pub notation: String,
    pub kan: bool,
    pub concealed: bool
}
pub struct Fu {
    pub items: Vec<(String,i64)>,
    pub total: i64,
    pub rounded: i64
}
pub fn block_fu(block: &Block) -> i64 {
    let base = if block.kan {
        if block.concealed {
            16
        } else {
            8
        }
    } else if block.concealed {
        4
    } else {
        2
    };
    base*if tiles::yaochuu(block.kind) {
        2
    } else {
        1
    }
}
pub fn fu(chiitoitsu: bool, closed: bool, ron: bool, pinfu: bool, pair: usize, seat: usize, round: usize, blocks: &[Block], wait: &str) -> Fu {
    if chiitoitsu {
        return Fu {
            items: vec![("chiitoitsu".to_owned(),25)],
            total: 25,
            rounded: 25
        };
    }
    let mut items = vec![("base".to_owned(),20)];
    if closed && ron {
        items.push(("closed_ron".to_owned(),10));
    }
    if !ron && !pinfu {
        items.push(("tsumo".to_owned(),2));
    }
    let pair_fu = 2*i64::from(pair >= 31)+2*i64::from(pair == 27+seat)+2*i64::from(pair == 27+round);
    if pair_fu > 0 {
        items.push((format!("pair {}",tiles::block(&[pair,pair])),pair_fu));
    }
    for block in blocks {
        let kind = if block.kan {
            if block.concealed {
                "closed_kan"
            } else {
                "open_kan"
            }
        } else if block.concealed {
            "closed_triplet"
        } else {
            "open_triplet"
        };
        items.push((format!("{} {}",kind,block.notation),block_fu(block)));
    }
    if ["kanchan","penchan","tanki"].contains(&wait) {
        items.push((format!("wait {}",wait),2));
    }
    let mut total: i64 = items.iter().map(|i| i.1).sum();
    if !closed && total == 20 {
        items.push(("open_pinfu".to_owned(),10));
        total += 10;
    }
    Fu {
        items,
        total,
        rounded: (total+9)/10*10
    }
}
pub fn base(han: i64, fu: i64, kazoe: bool, kiriage: bool) -> (usize,i64) {
    if han >= 13 && kazoe {
        (5,8000)
    } else if han >= 11 {
        (4,6000)
    } else if han >= 8 {
        (3,4000)
    } else if han >= 6 {
        (2,3000)
    } else {
        let base = fu*(1i64<<(han+2));
        if han == 5 || base >= 2000 || (kiriage && base == 1920) {
            (1,2000)
        } else {
            (0,base)
        }
    }
}
pub fn hundred(value: i64) -> i64 {
    (value+99)/100*100
}
pub struct Payment {
    pub first: i64,
    pub second: i64,
    pub total: i64
}
pub fn payments(base: i64, dealer: bool, ron: bool) -> Payment {
    if ron {
        let first = hundred(if dealer {
            6*base
        } else {
            4*base
        });
        Payment {
            first,
            second: 0,
            total: first
        }
    } else if dealer {
        let first = hundred(2*base);
        Payment {
            first,
            second: 0,
            total: 3*first
        }
    } else {
        let first = hundred(2*base);
        let second = hundred(base);
        Payment {
            first,
            second,
            total: first+2*second
        }
    }
}
