struct Team {
    name: String,
    played: i32,
    wins: i32,
    draws: i32,
    losses: i32,
    gf: i32,
    ga: i32,
    points: i32
}

fn record(t: &mut Team,
gf: i32,
ga: i32) {
    t.played += 1;
    t.gf += gf;
    t.ga += ga;
    if gf > ga {
        t.wins += 1;
        t.points += 3;
    } else if gf == ga {
        t.draws += 1;
        t.points += 1;
    } else {
        t.losses += 1;
    }
}

fn main() {
    let mut teams: Vec<Team> = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"].iter().map(|&name| Team {
        name: name.to_string(),
        played: 0,
        wins: 0,
        draws: 0,
        losses: 0,
        gf: 0,
        ga: 0,
        points: 0
    }).collect();
    for game in ["Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",
        "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",
        "Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"] {
        let parts: Vec<&str> = game.split(' ').collect();
        let goals: Vec<i32> = parts[1].split('-').map(|n| n.parse().unwrap()).collect();
        let x = teams.iter().position(|t| t.name == parts[0]).unwrap();
        let y = teams.iter().position(|t| t.name == parts[2]).unwrap();
        record(&mut teams[x], goals[0], goals[1]);
        record(&mut teams[y], goals[1], goals[0]);
    }
    teams.sort_by(|a, b| b.points.cmp(&a.points).then((b.gf - b.ga).cmp(&(a.gf - a.ga))).then(b.gf.cmp(&a.gf)).then(a.name.cmp(&b.name)));
    for (i, t) in teams.iter().enumerate() {
        let gd = t.gf - t.ga;
        println!("{}. {} P={} W={} D={} L={} GF={} GA={} GD={}{} Pts={}", i + 1, t.name, t.played, t.wins,
            t.draws, t.losses, t.gf, t.ga, if gd> 0 {
            "+"
        } else {
            ""
        }, gd, t.points);
    }
}
