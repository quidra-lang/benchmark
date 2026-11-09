teams = %w[Lions Tigers Eagles Sharks Wolves Bears]
matches = [
  'Lions 0-3 Bears', 'Tigers 2-2 Wolves', 'Eagles 4-0 Sharks', 'Bears 0-1 Sharks',
  'Wolves 2-1 Eagles', 'Lions 0-1 Tigers', 'Tigers 3-3 Bears', 'Eagles 2-2 Lions',
  'Sharks 2-2 Wolves', 'Bears 3-1 Wolves', 'Lions 2-0 Sharks', 'Tigers 2-1 Eagles',
  'Eagles 1-0 Bears', 'Sharks 2-0 Tigers', 'Wolves 2-1 Lions'
]
stats = teams.to_h { |name| [name, {played: 0, wins: 0, draws: 0, losses: 0, gf: 0, ga: 0, points: 0}] }
matches.each do |match|
  home, score, away = match.split
  h, a = score.split('-').map(&:to_i)
  [[home, h, a], [away, a, h]].each do |name, goals, conceded|
    s = stats[name]
    s[:played] += 1
    s[:gf] += goals
    s[:ga] += conceded
    if goals > conceded
      s[:wins] += 1
      s[:points] += 3
    elsif goals == conceded
      s[:draws] += 1
      s[:points] += 1
    else
      s[:losses] += 1
    end
  end
end
ordered = teams.sort_by do |name|
  s = stats[name]
  [-s[:points], s[:ga] - s[:gf], -s[:gf], name]
end
ordered.each_with_index do |name, position|
  s = stats[name]
  difference = s[:gf] - s[:ga]
  gd = difference.positive? ? "+#{difference}" : difference.to_s
  puts "#{position + 1}. #{name} P=#{s[:played]} W=#{s[:wins]} D=#{s[:draws]} L=#{s[:losses]} " \
       "GF=#{s[:gf]} GA=#{s[:ga]} GD=#{gd} Pts=#{s[:points]}"
end
