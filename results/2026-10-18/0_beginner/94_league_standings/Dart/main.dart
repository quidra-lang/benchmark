import 'dart:io';

class Team {
    final String name;
    int played = 0, wins = 0, draws = 0, losses = 0, gf = 0, ga = 0, points = 0;
    Team(this.name);
    int get gd => gf - ga;
}

void main() {
    final out = StringBuffer();
    final teams = {
        for (final name in ['Lions', 'Tigers', 'Eagles', 'Sharks', 'Wolves', 'Bears'])
            name: Team(name)
        };
    const matches = ['Lions 0-3 Bears', 'Tigers 2-2 Wolves', 'Eagles 4-0 Sharks', 'Bears 0-1 Sharks',
        'Wolves 2-1 Eagles', 'Lions 0-1 Tigers', 'Tigers 3-3 Bears', 'Eagles 2-2 Lions', 'Sharks 2-2 Wolves',
        'Bears 3-1 Wolves', 'Lions 2-0 Sharks', 'Tigers 2-1 Eagles', 'Eagles 1-0 Bears', 'Sharks 2-0 Tigers',
        'Wolves 2-1 Lions'];
    for (final match in matches) {
        final f = match.split(' '), goals = f[1].split('-'), h = int.parse(goals[0]), a = int.parse(goals[1]),
            home = teams[f[0]]!, away = teams[f[2]]!;
        home.played++;
        away.played++;
        home.gf += h;
        home.ga += a;
        away.gf += a;
        away.ga += h;
        if (h > a) {
            home.wins++;
            away.losses++;
            home.points += 3;
        } else if (h < a) {
            away.wins++;
            home.losses++;
            away.points += 3;
        } else {
            home.draws++;
            away.draws++;
            home.points++;
            away.points++;
        }
    }
    final order = teams.values.toList()..sort((a, b) {
        var c = b.points.compareTo(a.points);
        if (c != 0)
            return c;
        c = b.gd.compareTo(a.gd);
        if (c != 0)
            return c;
        c = b.gf.compareTo(a.gf);
        return c != 0 ? c : a.name.compareTo(b.name);
    });
    for (var i = 0; i < order.length; i++) {
        final t = order[i];
        out.writeln('${i+1}. ${t.name} P=${t.played} W=${t.wins} D=${t.draws} L=${t.losses} GF=${t.gf} GA=${t.ga} GD=${t.gd>0?'+':''}${t.gd} Pts=${t.points}');
    }
    stdout.write(out);
}
