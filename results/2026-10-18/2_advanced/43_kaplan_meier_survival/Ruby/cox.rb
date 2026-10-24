require_relative "numerics"

module Cox
  module_function

  def evaluate(subjects, vectors, beta)
    size = beta.length
    predictors = vectors.map { |x| Numerics.total(beta.each_index.map { |c| beta[c] * x[c] }) }
    relative_risks = predictors.map { |value| Math.exp(value) }
    order = subjects.each_index.sort_by { |index| [-subjects[index].time, subjects[index].id] }
    s0 = 0.0
    s1 = Array.new(size, 0.0)
    s2 = Array.new(size) { Array.new(size, 0.0) }
    likelihood = 0.0
    score = Array.new(size, 0.0)
    information = Array.new(size) { Array.new(size, 0.0) }
    event_sums = {}
    order.chunk { |index| subjects[index].time }.each do |time, at_time|
      at_time.each do |index|
        risk, x = relative_risks[index], vectors[index]
        s0 += risk
        size.times do |c|
          s1[c] += risk * x[c]
          size.times { |d| s2[c][d] += risk * x[c] * x[d] }
        end
      end
      events = at_time.select { |index| subjects[index].event == 1 }
      next if events.empty?

      count = events.length
      likelihood += Numerics.total(events.map { |index| predictors[index] }) - count * Math.log(s0)
      size.times do |c|
        score[c] += events.sum { |index| vectors[index][c] } - count * s1[c] / s0
        size.times do |d|
          information[c][d] += count * (s2[c][d] / s0 - (s1[c] / s0) * (s1[d] / s0))
        end
      end
      event_sums[time] = { s0: s0, s1: s1.dup, events: count }
    end
    { loglik: likelihood, score: score, information: information,
      predictors: predictors, event_sums: event_sums }
  end

  def fit(subjects, vectors)
    beta = Array.new(vectors.first.length, 0.0)
    null = evaluate(subjects, vectors, beta)
    current = null
    iterations = []
    1.upto(25) do |iteration|
      change = Numerics.solve(current[:information], current[:score])
      beta = beta.each_index.map { |c| beta[c] + change[c] }
      iterations << [iteration, current[:loglik], beta.dup]
      current = evaluate(subjects, vectors, beta)
    end
    { beta: beta, null: null, final: current, iterations: iterations }
  end
end
