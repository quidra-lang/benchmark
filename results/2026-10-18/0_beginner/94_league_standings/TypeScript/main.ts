const teams = "Lions Tigers Eagles Sharks Wolves Bears".split(" ");
const matches = [
  "Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks",
  "Wolves 2-1 Eagles", "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions",
  "Sharks 2-2 Wolves", "Bears 3-1 Wolves", "Lions 2-0 Sharks", "Tigers 2-1 Eagles",
  "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"
];
const stats = new Map(teams.map(name => [name, {played: 0, wins: 0, draws: 0, losses: 0, gf: 0, ga: 0, points: 0}]));
for (const match of matches) {
  const [home, score, away] = match.split(" ");
  const [h, a] = score.split("-").map(Number);
  for (const {name, goals, conceded} of [{name: home, goals: h, conceded: a}, {name: away, goals: a, conceded: h}]) {
    const s = stats.get(name)!;
    s.played++;
    s.gf += goals;
    s.ga += conceded;
    if (goals > conceded) {
      s.wins++;
      s.points += 3;
    } else if (goals === conceded) {
      s.draws++;
      s.points++;
    } else {
      s.losses++;
    }
  }
}
teams.sort((a, b) => {
  const x = stats.get(a)!, y = stats.get(b)!;
  return y.points - x.points || (y.gf - y.ga) - (x.gf - x.ga) || y.gf - x.gf || (a < b ? -1 : a > b ? 1 : 0);
});
teams.forEach((name, position) => {
  const s = stats.get(name)!, difference = s.gf - s.ga;
  const gd = difference > 0 ? `+${difference}` : String(difference);
  console.log(
    `${position + 1}. ${name} P=${s.played} W=${s.wins} D=${s.draws} L=${s.losses} ` +
    `GF=${s.gf} GA=${s.ga} GD=${gd} Pts=${s.points}`
  );
});
