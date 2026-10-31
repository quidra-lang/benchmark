use std::fs;
#[derive(Clone)] pub struct Bid{
    pub id:usize,
    pub bidder:usize,
    pub bundle:u16,
    pub amount:i64,
    pub xor:bool
}
#[derive(Clone)] pub struct BidLine{
    pub name:String,
    pub language:String,
    pub bids:Vec<String>
}
pub struct Auction{
    pub name:String,
    pub offered:Vec<String>,
    pub lines:Vec<BidLine>
}
pub struct Participant{
    pub name:String,
    pub value:i64,
    pub bid:i64
}
pub struct Group{
    pub lot:bool,
    pub name:String,
    pub args:Vec<String>,
    pub people:Vec<Participant>
}
pub struct Params{
    pub run:Vec<String>,
    pub bundle:usize,
    pub bids:usize,
    pub core:usize,
    pub increment:i64,
    pub cap:usize,
    pub seed:i64,
    pub english:i64,
    pub dutch_start:i64,
    pub dutch_decrement:i64
}
pub struct Input{
    pub names:Vec<String>,
    pub reserves:Vec<i64>,
    pub auctions:Vec<Auction>,
    pub groups:Vec<Group>,
    pub params:Params
}
pub fn read()->Input{
    let mut names=Vec::new();
    let mut reserves=Vec::new();
    for line in fs::read_to_string("input/items.txt").unwrap().lines(){
        let(a,b)=line.split_once(' ').unwrap();
        names.push(a.into());
        reserves.push(b.parse().unwrap());
    }
    let mut auctions:Vec<Auction>=Vec::new();
    for line in fs::read_to_string("input/bids.txt").unwrap().lines(){
        let a:Vec<_>=line.split(' ').collect();
        if a[0]=="auction"{
            auctions.push(Auction{
                name:a[1].into(),
                offered:a[2..].iter().map(|s|s.to_string()).collect(),
                lines:Vec::new()
            });
        }else{
            auctions.last_mut().unwrap().lines.push(BidLine{
                name:a[1].into(),
                language:a[2].into(),
                bids:a[3..].iter().map(|s|s.to_string()).collect()
            });
        }
    }
    let mut groups:Vec<Group>=Vec::new();
    for line in fs::read_to_string("input/single_item.txt").unwrap().lines(){
        let a:Vec<_>=line.split(' ').collect();
        if a[0]=="lot"||a[0]=="slots"{
            groups.push(Group{
                lot:a[0]=="lot",
                name:a[1].into(),
                args:a[2..].iter().map(|s|s.to_string()).collect(),
                people:Vec::new()
            });
        }else{
            groups.last_mut().unwrap().people.push(Participant{
                name:a[1].into(),
                value:a[2].parse().unwrap(),
                bid:a[3].parse().unwrap()
            });
        }
    }
    let text=fs::read_to_string("input/params.txt").unwrap();
    let a:Vec<Vec<_>>=text.lines().map(|s|s.split(' ').collect()).collect();
    let v=|i:usize|a[i][1].parse::<i64>().unwrap();
    let params=Params{
        run:a[0][1..].iter().map(|s|s.to_string()).collect(),
        bundle:v(1)as usize,
        bids:v(2)as usize,
        core:v(3)as usize,
        increment:v(4),
        cap:v(5)as usize,
        seed:v(6),
        english:v(7),
        dutch_start:v(8),
        dutch_decrement:v(9)
    };
    Input{
        names,
        reserves,
        auctions,
        groups,
        params
    }
}
