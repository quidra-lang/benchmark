using Printf

function main()
    teams = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]
    records = Dict(team=>zeros(Int, 7) for team in teams)
    matches = [
        "Lions 0-3 Bears",
        "Tigers 2-2 Wolves",
        "Eagles 4-0 Sharks",
        "Bears 0-1 Sharks",
        "Wolves 2-1 Eagles",
        "Lions 0-1 Tigers",
        "Tigers 3-3 Bears",
        "Eagles 2-2 Lions",
        "Sharks 2-2 Wolves",
        "Bears 3-1 Wolves",
        "Lions 2-0 Sharks",
        "Tigers 2-1 Eagles",
        "Eagles 1-0 Bears",
        "Sharks 2-0 Tigers",
        "Wolves 2-1 Lions",
    ]
    for match in matches
        home, score, away = split(match)
        h, a = parse.(Int, split(score, '-'))
        for (team, gf, ga) in [(home, h, a), (away, a, h)]
            record = records[team]
            record[1] += 1
            record[5] += gf
            record[6] += ga
            if gf > ga
                record[2] += 1
                record[7] += 3
            elseif gf == ga
                record[3] += 1
                record[7] += 1
            else
                record[4] += 1
            end
        end
    end
    sort!(
        teams;
        by = team -> (
            -records[team][7],
            -(records[team][5]-records[team][6]),
            -records[team][5],
            team,
        ),
    )
    for (position, team) in enumerate(teams)
        played, wins, draws, losses, gf, ga, points = records[team]
        difference = gf-ga
        signed = difference > 0 ? string("+", difference) : string(difference)
        @printf(
            "%d. %s P=%d W=%d D=%d L=%d GF=%d GA=%d GD=%s Pts=%d\n",
            position,
            team,
            played,
            wins,
            draws,
            losses,
            gf,
            ga,
            signed,
            points
        )
    end
end

main()
