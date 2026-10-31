require_relative 'data_io'
require_relative 'models'
require_relative 'integrator'
require_relative 'fitting'
require_relative 'report'

class Study
  include Report

  def total(values)
    values.reduce(0) { |sum, value| sum + value }
  end

  def sse(series, coefficient, observations = @cases)
    error = 0.0
    series.each_with_index do |value, i|
      difference = coefficient * value - observations[i]
      error += difference * difference
    end
    error
  end

  def peak(series)
    best = 0
    series.each_index { |i| best = i if series[i] > series[best] }
    best
  end

  def multipliers(lines, days = @days)
    index = 0
    (1..days).map do |day|
      index += 1 while index + 1 < lines.length && lines[index + 1][0] <= day
      lines[index][1]
    end
  end

  def final_size(r)
    return 0.0 if r <= 1.0
    lo, hi = 1.0 - 1.0 / r, 1.0
    20.times do
      mid = (lo + hi) / 2.0
      g = 1.0 - mid - Math.exp(-r * mid)
      if g > 0.0
        lo = mid
      else
        hi = mid
      end
    end
    (lo + hi) / 2.0
  end

  def power(matrix)
    vector = Array.new(matrix.length, 1.0 / matrix.length)
    eigenvalue = nil
    200.times do
      product = matrix.map { |row| total(row.each_index.map { |h| row[h] * vector[h] }) }
      eigenvalue = total(product)
      vector = product.map { |x| x / eigenvalue }
    end
    [eigenvalue, vector]
  end

  def initialize(cases, deaths, groups, contacts, interventions, params)
    @cases, @deaths, @groups, @contacts, @interventions, @params = cases, deaths, groups, contacts, interventions, params
    @days, @g = cases.length, groups.length
    @populations = groups.map { |x| x[1] }
    @fatalities = groups.map { |x| x[2] }
    @population, @case_total, @death_total = total(@populations), total(cases), total(deaths)
    @fatality = total(groups.map { |x| x[1] * x[2] }) / @population
    @sigma, @gamma0 = params.values_at('sigma', 'gamma')
    e0, i0 = params['initial']
    @initial = [@population - e0 - i0, e0, i0, 0.0, 0.0, 0.0]
    @sir_initial = [@population - e0 - i0, e0 + i0, 0.0, 0.0]
    @age_initial = @populations.flat_map do |n|
      e, i = e0 * n / @population, i0 * n / @population
      [n - e - i, e, i, 0.0, 0.0, 0.0]
    end
    @multipliers = multipliers(interventions)
    @weeks = (1..@days).step(7).map { |first| [first, [first + 6, @days].min] }
    @cache, @fit, @reproduction = {}, [], []
  end

  def rmse(error, count = @days)
    Math.sqrt(error / count.to_f)
  end

  def states_for(beta, gamma, sequence = @multipliers, initial = @initial, sigma = @sigma)
    Integrator.simulate(Models.seird(@population, sigma, @fatality, beta, gamma), initial, sequence, [5])
  end

  def incidence_for(beta, gamma)
    @cache[[beta, gamma]] ||= states_for(beta, gamma).map { |state| state[5] }
  end

  def error(beta, gamma, rho)
    sse(incidence_for(beta, gamma), rho)
  end

  def golden_records(round, name, search)
    result, value, records = search
    records.each_with_index do |(a, b, c, d, fc, fd), i|
      @fit << "golden #{round} #{name} #{i} a #{fmt(a, 6)} b #{fmt(b, 6)} c #{fmt(c, 6)} d #{fmt(d, 6)} rmse #{fmt(rmse(fc))} #{fmt(rmse(fd))}"
    end
    @fit << "golden_result #{round} #{name} #{fmt(result, 6)} sse #{fmt(value, 1)}"
  end

  def fit_model
    bmin, bmax, nb = @params['beta_grid']
    rmin, rmax, nr = @params['rho_grid']
    betas = nb.times.map { |i| bmin + (bmax - bmin) * i / (nb - 1) }
    rhos = nr.times.map { |i| rmin + (rmax - rmin) * i / (nr - 1) }
    @db, @dr = (bmax - bmin) / (nb - 1), (rmax - rmin) / (nr - 1)
    @fit << "data days #{@days} cases #{@case_total} deaths #{@death_total} population #{@population} fatality #{fmt(@fatality, 6)}"
    @fit << "grid gamma #{fmt(@gamma0)} rho #{rhos.map { |x| fmt(x) }.join(' ')}"
    best = nil
    betas.each_with_index do |b, i|
      errors = rhos.each_with_index.map do |r, j|
        value = error(b, @gamma0, r)
        best = [value, i, j] if best.nil? || value < best[0]
        value
      end
      @fit << "grid beta #{fmt(b)} rmse #{errors.map { |x| fmt(rmse(x), 2) }.join(' ')}"
    end
    @sse_grid, i, j = best
    @beta_grid, @rho_grid = betas[i], rhos[j]
    @fit << "grid_best beta #{fmt(@beta_grid)} rho #{fmt(@rho_grid)} sse #{fmt(@sse_grid, 1)} rmse #{fmt(rmse(@sse_grid))}"
    b, r = @beta_grid, @rho_grid
    iterations, rounds = @params['golden']
    1.upto(rounds) do |round|
      search = Fitting.golden(->(x) { error(x, @gamma0, r) }, b - @db, b + @db, iterations)
      golden_records(round, 'beta', search)
      b = search[0]
      search = Fitting.golden(->(x) { error(b, @gamma0, x) }, r - @dr, r + @dr, iterations)
      golden_records(round, 'rho', search)
      r, @sse_golden = search
    end
    @beta_golden, @rho = b, r
    initial, records, final = Fitting.nelder_mead(->(beta, gamma) { error(beta, gamma, r) }, b, @gamma0,
                                                *@params['simplex'], *@params['nelder_mead'])
    initial.each do |number, beta, gamma, value|
      @fit << "simplex #{number} beta #{fmt(beta, 6)} gamma #{fmt(gamma, 6)} rmse #{fmt(rmse(value))}"
    end
    records.each_with_index do |(operation, vertex), index|
      _, beta, gamma, value = vertex
      @fit << "nelder_mead #{index + 1} #{operation} beta #{fmt(beta, 6)} gamma #{fmt(gamma, 6)} rmse #{fmt(rmse(value))}"
    end
    final.each_with_index do |(_, beta, gamma, value), index|
      @fit << "final_simplex #{index + 1} beta #{fmt(beta, 6)} gamma #{fmt(gamma, 6)} rmse #{fmt(rmse(value))}"
    end
    _, @beta, @gamma, @sse_nm = final[0]
    @r0 = @beta / @gamma
    mean = @case_total / @days.to_f
    sst = total(@cases.map { |x| (x - mean) * (x - mean) })
    @fit << "fitted beta #{fmt(@beta, 6)} gamma #{fmt(@gamma, 6)} rho #{fmt(@rho, 6)} sigma #{fmt(@sigma, 6)} r0 #{fmt(@r0)}"
    @fit << "sse grid #{fmt(@sse_grid, 1)} golden #{fmt(@sse_golden, 1)} nelder_mead #{fmt(@sse_nm, 1)} rmse #{fmt(rmse(@sse_nm))} r2 #{fmt(1.0 - @sse_nm / sst)}"
    [['grid', @beta_grid, @gamma0, @rho_grid, @sse_grid], ['golden', @beta_golden, @gamma0, @rho, @sse_golden],
     ['nelder_mead', @beta, @gamma, @rho, @sse_nm]].each do |name, beta, gamma, rho, value|
      @fit << "stage #{name} beta #{fmt(beta, 6)} gamma #{fmt(gamma, 6)} rho #{fmt(rho, 6)} r0 #{fmt(beta / gamma)} rmse #{fmt(rmse(value))}"
    end
  end

  def diagnostics
    @states = [@initial, *states_for(@beta, @gamma)]
    @incidence = @states.drop(1).map { |s| s[5] }
    @reported = @incidence.map { |x| @rho * x }
    @residuals = @cases.each_index.map { |i| @cases[i] - @reported[i] }
    @model_deaths = (1..@days).map { |d| @states[d][4] - @states[d - 1][4] }
    @rt = @days.times.map { |i| @r0 * @multipliers[i] * @states[i][0] / @population }
    @averages = @days.times.map { |i| total(@cases[[0, i - 6].max..i]) / [i + 1, 7].min.to_f }
    @cumulative_cases, @cumulative_reported = [], []
    observed_total, reported_total = 0, 0.0
    @days.times do |i|
      observed_total += @cases[i]
      reported_total += @reported[i]
      @cumulative_cases << observed_total
      @cumulative_reported << reported_total
    end
    @reported_total = reported_total
    absolute = @residuals.map(&:abs)
    largest = peak(absolute)
    positive = @residuals.count { |x| x > 0.0 }
    runs = 1 + (1...@days).count { |i| (@residuals[i] > 0.0) != (@residuals[i - 1] > 0.0) }
    square = total(@residuals.map { |x| x * x })
    differences = (1...@days).map { |i| @residuals[i] - @residuals[i - 1] }
    dw = total(differences.map { |x| x * x }) / square
    @fit << "residuals sum #{fmt(total(@residuals), 1)} mae #{fmt(total(absolute) / @days, 1)} max #{fmt(@residuals[largest], 1)} day #{largest + 1} positive #{positive} runs #{runs} durbin_watson #{fmt(dw)}"
    correlations = (1..7).map { |lag| total((0...@days - lag).map { |i| @residuals[i] * @residuals[i + lag] }) / square }
    @fit << "autocorrelation #{correlations.map { |x| fmt(x) }.join(' ')}"
    outliers = 0
    @residuals.each_with_index do |residual, i|
      z = residual / Math.sqrt(@reported[i])
      next unless z.abs > @params['outlier']
      @fit << "outlier #{i + 1} observed #{@cases[i]} fitted #{fmt(@reported[i], 1)} z #{fmt(z)}"
      outliers += 1
    end
    @fit << "outliers #{outliers}"
    factors = 7.times.map do |weekday|
      indices = (weekday...@days).step(7).to_a
      observed = total(indices.map { |i| @cases[i] })
      fitted = total(indices.map { |i| @reported[i] })
      factor = observed / fitted
      @fit << "weekday #{weekday + 1} observed #{observed} fitted #{fmt(fitted, 1)} factor #{fmt(factor)}"
      factor
    end
    adjusted = @reported.each_with_index.map { |x, i| x * factors[i % 7] }
    @fit << "weekday_adjusted rmse #{fmt(rmse(sse(adjusted, 1.0)))}"
    infections = total(@incidence)
    @fit << "burden infections #{fmt(infections, 1)} ascertainment #{fmt(@case_total / infections)} deaths_per_infection #{fmt(@death_total / infections, 6)}"
    death_analysis
    previous = nil
    @weeks.each_with_index do |(first, last), w|
      observed = total(@cases[first - 1...last])
      fitted = total(@reported[first - 1...last])
      dead = total(@deaths[first - 1...last])
      modeled = total(@model_deaths[first - 1...last])
      growth = previous.nil? ? '-' : fmt(observed / previous.to_f)
      @fit << "weekly #{w + 1} days #{first} #{last} observed #{observed} fitted #{fmt(fitted, 1)} deaths_observed #{dead} deaths_model #{fmt(modeled, 1)} growth #{growth}"
      previous = observed
    end
  end

  def death_analysis
    scale = total(@model_deaths.each_with_index.map { |v, i| v * @deaths[i] }) / total(@model_deaths.map { |v| v * v })
    @fit << "deaths observed #{@death_total} model #{fmt(@states[-1][4], 1)} rmse #{fmt(rmse(sse(@model_deaths, 1.0, @deaths)))} scale #{fmt(scale)} implied_fatality #{fmt(@fatality * scale, 6)} cfr #{fmt(@death_total / @case_total.to_f)}"
    correlations = (0..@params['death_lag']).map do |lag|
      a = total((0...@days - lag).map { |i| @cases[i] * @deaths[i + lag] })
      b = total(@cases.take(@days - lag).map { |x| x * x })
      y = total(@deaths.drop(lag).map { |x| x * x })
      correlation = a / Math.sqrt(b.to_f * y)
      cfr = total(@deaths.drop(lag)) / total(@cases.take(@days - lag)).to_f
      @fit << "death_lag #{lag} correlation #{fmt(correlation)} cfr #{fmt(cfr)}"
      correlation
    end
    @fit << "death_best_lag #{peak(correlations)}"
  end

  def profiles
    @se = {}
    fitted = [@beta, @gamma, @rho]
    variance = @sse_nm / (@days - 3)
    %w[beta gamma rho].each_with_index do |name, index|
      value = fitted[index]
      errors = {}
      (-5..5).each do |k|
        point = value * (1.0 + k / 100.0)
        parameters = fitted.dup
        parameters[index] = point
        errors[k] = error(*parameters)
        @fit << "profile #{name} #{k} value #{fmt(point, 6)} rmse #{fmt(rmse(errors[k]))}"
      end
      h = value / 100.0
      curvature = (errors[1] - 2.0 * errors[0] + errors[-1]) / (h * h)
      @se[name] = Math.sqrt(2.0 * variance / curvature)
      @fit << "profile_se #{name} #{fmt(@se[name], 6)}"
    end
  end

  def backtest
    holdout = @params['holdout']
    training = @days - holdout
    cache = {}
    objective = lambda do |beta, rho|
      cache[beta] ||= states_for(beta, @gamma, @multipliers.take(training)).map { |s| s[5] }
      sse(cache[beta], rho, @cases.take(training))
    end
    iterations = @params['golden'][0]
    beta = Fitting.golden(->(x) { objective.call(x, @rho) }, @beta - @db, @beta + @db, iterations)[0]
    rho, value = Fitting.golden(->(x) { objective.call(beta, x) }, @rho - @dr, @rho + @dr, iterations)
    forecasts = incidence_for(beta, @gamma).drop(training).map { |x| rho * x }
    test = sse(forecasts, 1.0, @cases.drop(training))
    full = sse(@reported.drop(training), 1.0, @cases.drop(training))
    @fit << "backtest train_days #{training} beta #{fmt(beta, 6)} rho #{fmt(rho, 6)} train_rmse #{fmt(rmse(value, training))} test_rmse #{fmt(rmse(test, holdout))} full_fit_test_rmse #{fmt(rmse(full, holdout))}"
    forecasts.each_with_index do |forecast, i|
      d = training + i
      @fit << "backtest_day #{d + 1} observed #{@cases[d]} forecast #{fmt(forecast, 1)} error #{fmt(@cases[d] - forecast, 1)}"
    end
  end

  def effects
    estimated, after = @interventions.dup, @sse_nm
    width = @params['effect_width']
    (1...@interventions.length).each do |i|
      day, given = @interventions[i]
      objective = lambda do |x|
        changed = estimated.dup
        changed[i] = [day, x]
        sse(states_for(@beta, @gamma, multipliers(changed)).map { |s| s[5] }, @rho)
      end
      value, after = Fitting.golden(objective, given - width, given + width, @params['golden'][0])
      estimated[i] = [day, value]
      @fit << "effect #{i + 1} day #{day} given #{fmt(given)} estimated #{fmt(value, 6)} sse #{fmt(after, 1)}"
    end
    @fit << "effect_sse before #{fmt(@sse_nm, 1)} after #{fmt(after, 1)} rmse #{fmt(rmse(after))}"
  end

  def sensitivity
    %w[beta gamma sigma rho].each_with_index do |name, index|
      [0.9, 1.1].each do |factor|
        values = [@beta, @gamma, @sigma, @rho]
        values[index] *= factor
        beta, gamma, sigma, rho = values
        states = states_for(beta, gamma, @multipliers, @initial, sigma)
        incidence = states.map { |s| s[5] }
        day = peak(incidence)
        attack = (@population - states[-1][0]) / @population
        @fit << "sensitivity #{name} #{fmt(factor, 2)} r0 #{fmt(beta / gamma)} rmse #{fmt(rmse(sse(incidence, rho)))} peak_day #{day + 1} peak #{fmt(rho * incidence[day], 1)} attack #{fmt(attack)}"
      end
    end
  end

  def age_states_for(contacts = @normalized, sequence = @multipliers, initial = @age_initial)
    rates = Models.age_seird(@populations, @fatalities, @sigma, @beta, @gamma, contacts)
    Integrator.simulate(rates, initial, sequence, (5...6 * @g).step(6))
  end

  def ngm(contacts)
    @g.times.map { |g| @g.times.map { |h| @r0 * contacts[g][h] * @populations[g] / @populations[h] } }
  end

  def analyze_age
    @kbar = total(@contacts.each_with_index.map { |row, g| @populations[g] * total(row) }) / @population
    @normalized = @contacts.map { |row| row.map { |x| x / @kbar } }
    matrix = ngm(@normalized)
    reproduction, vector = power(matrix)
    @age_lines = matrix.each_with_index.map { |row, g| "ngm #{@groups[g][0]} #{row.map { |x| fmt(x) }.join(' ')}" }
    @age_lines << "r0_age #{fmt(reproduction)} ratio #{fmt(reproduction / @r0)} kbar #{fmt(@kbar)} eigenvector #{vector.map { |x| fmt(x) }.join(' ')}"
    final = Array.new(@g, 1.0)
    100.times { final = @normalized.map { |row| 1.0 - Math.exp(-total(@g.times.map { |h| @r0 * row[h] * final[h] })) } }
    long = age_states_for(@normalized, Array.new(730, 1.0)).last
    simulated = @g.times.map { |g| (@populations[g] - long[6 * g]) / @populations[g] }
    @g.times { |g| @age_lines << "final_size_age #{@groups[g][0]} equation #{fmt(final[g])} simulated #{fmt(simulated[g])}" }
    overall = total(@g.times.map { |g| @populations[g] * final[g] }) / @population
    overall_sim = total(@g.times.map { |g| @populations[g] * simulated[g] }) / @population
    @age_lines << "final_size_age total equation #{fmt(overall)} simulated #{fmt(overall_sim)}"
    @age_states = [@age_initial, *age_states_for]
    @age_incidence = @age_states.drop(1).map { |s| total(@g.times.map { |g| s[6 * g + 5] }) }
    (1..@days).step(7) do |day|
      previous = @age_states[day - 1]
      matrix = @g.times.map do |g|
        @g.times.map { |h| @multipliers[day - 1] * @r0 * @normalized[g][h] * previous[6 * g] / @populations[h] }
      end
      @age_lines << "age_rt #{day} #{fmt(power(matrix)[0])} homogeneous #{fmt(@rt[day - 1])}"
    end
    @weeks.each_with_index do |(first, last), w|
      totals = @g.times.map { |g| total((first..last).map { |d| @age_states[d][6 * g + 5] }) }
      @age_lines << "age_weekly #{w + 1} days #{first} #{last} #{totals.map { |x| fmt(x, 1) }.join(' ')}"
    end
    infections = @g.times.map { |g| total(@age_states.drop(1).map { |s| s[6 * g + 5] }) }
    infection_total = total(infections)
    @groups.each_with_index do |(name, n, _), g|
      incidence = @age_states.drop(1).map { |s| s[6 * g + 5] }
      day = peak(incidence)
      attack = (n - @age_states[-1][6 * g]) / n
      @age_lines << "age #{name} attack #{fmt(attack)} infections #{fmt(infections[g], 1)} share #{fmt(infections[g] / infection_total)} deaths #{fmt(@age_states[-1][6 * g + 4], 1)} peak_day #{day + 1} peak #{fmt(incidence[day], 1)}"
    end
    @params['contact_change'].each do |name, target, factor|
      t = @groups.index { |group| group[0] == target }
      tau = @g.times.map { |g| g == t ? factor : 1.0 }
      contacts = @g.times.map { |g| @g.times.map { |h| @normalized[g][h] * tau[g] * tau[h] } }
      reproduction = power(ngm(contacts))[0]
      states = age_states_for(contacts)
      infections = total(states.map { |s| total(@g.times.map { |g| s[6 * g + 5] }) })
      deaths = total(@g.times.map { |g| states[-1][6 * g + 4] })
      attack = total(@g.times.map { |g| @populations[g] - states[-1][6 * g] }) / @population
      @age_lines << "contact_change #{name} group #{target} factor #{fmt(factor)} r0_age #{fmt(reproduction)} infections #{fmt(infections, 1)} deaths #{fmt(deaths, 1)} attack #{fmt(attack)}"
    end
  end

  def sir_incidence(beta)
    Integrator.simulate(Models.sir(@population, beta, @gamma), @sir_initial, @multipliers, [3]).map { |s| s[3] }
  end

  def compare_models
    [['sir', sir_incidence(@beta)], ['seir', @incidence], ['age', @age_incidence]].each do |name, incidence|
      numerator = total(@cases.each_with_index.map { |c, i| c * incidence[i] })
      rho = numerator / total(incidence.map { |x| x * x })
      @fit << "model #{name} rmse #{fmt(rmse(sse(incidence, @rho)))} peak_day #{peak(incidence) + 1} rho_opt #{fmt(rho, 6)} rmse_opt #{fmt(rmse(sse(incidence, rho)))}"
    end
    low, high = @params['beta_grid']
    beta, value = Fitting.golden(->(x) { sse(sir_incidence(x), @rho) }, low, high, @params['golden'][0])
    @fit << "model sir_fit beta #{fmt(beta, 6)} rmse #{fmt(rmse(value))} peak_day #{peak(sir_incidence(beta)) + 1}"
  end

  def analyze_reproduction
    @reproduction << "r0 #{fmt(@r0)} herd_immunity #{fmt(1.0 - 1.0 / @r0)}"
    long = states_for(@beta, @gamma, Array.new(730, 1.0)).last
    @reproduction << "final_size equation #{fmt(final_size(@r0))} simulated #{fmt((@population - long[0]) / @population)}"
    length = @params['generation']
    states = Integrator.simulate(Models.generation(@sigma, @gamma), [1.0, 0.0, 0.0], Array.new(length, 1.0), [2])
    amounts = states.map { |s| s[2] }
    coverage = total(amounts)
    weights = amounts.map { |x| x / coverage }
    mean = total(weights.each_with_index.map { |w, i| (i + 1 - 0.5) * w })
    @reproduction << "generation mean #{fmt(mean)} theory #{fmt(1.0 / @sigma + 1.0 / @gamma)} coverage #{fmt(coverage)}"
    weights.each_with_index { |w, i| @reproduction << "generation_weight #{i + 1} #{fmt(w, 6)}" }
    pressures = @days.times.map { |i| total((1..[length, i].min).map { |s| weights[s - 1] * @cases[i - s] }) }
    empirical = @days.times.map do |i|
      i + 1 < length + 7 ? '-' : fmt(total(@cases[i - 6..i]) / total(pressures[i - 6..i]))
    end
    incidence_day = peak(@incidence)
    infectious = @states.drop(1).map { |s| s[2] }
    infectious_day, observed_day, average_day = peak(infectious), peak(@cases), peak(@averages)
    @reproduction << "peak model day #{incidence_day + 1} incidence #{fmt(@incidence[incidence_day], 1)} reported #{fmt(@reported[incidence_day], 1)} infectious_day #{infectious_day + 1} infectious #{fmt(infectious[infectious_day], 1)}"
    @reproduction << "peak observed day #{observed_day + 1} cases #{@cases[observed_day]} average7_day #{average_day + 1} average7 #{fmt(@averages[average_day], 2)}"
    @interventions.each_with_index do |(first, multiplier), k|
      last = k + 1 < @interventions.length ? @interventions[k + 1][0] - 1 : @days
      residuals = @residuals[first - 1...last]
      count = last - first + 1
      @reproduction << "period #{k + 1} days #{first} #{last} multiplier #{fmt(multiplier)} rt_start #{fmt(@rt[first - 1])} rt_end #{fmt(@rt[last - 1])} observed #{total(@cases[first - 1...last])} fitted #{fmt(total(@reported[first - 1...last]), 1)} rmse #{fmt(rmse(total(residuals.map { |x| x * x }), count))} bias #{fmt(total(residuals) / count, 1)}"
    end
    @params['milestones'].each do |target|
      observed = @cumulative_cases.index { |x| x >= target }
      fitted = @cumulative_reported.index { |x| x >= target }
      @reproduction << "milestone #{target} observed #{observed ? observed + 1 : 'never'} fitted #{fitted ? fitted + 1 : 'never'}"
    end
    counterfactuals
    (1...@days).each do |i|
      next if (@rt[i] < 1.0) == (@rt[i - 1] < 1.0)
      @reproduction << "rt_cross day #{i + 1} #{@rt[i] < 1.0 ? 'down' : 'up'}"
    end
    @days.times { |i| @reproduction << "rt #{i + 1} model #{fmt(@rt[i])} empirical #{empirical[i]}" }
    @reproduction.concat(@age_lines)
  end

  def counterfactual_reported(lines)
    states_for(@beta, @gamma, multipliers(lines)).map { |s| @rho * s[5] }
  end

  def counterfactuals
    reported = counterfactual_reported(@interventions.take(1))
    value, day = total(reported), peak(reported)
    @reproduction << "counterfactual none reported #{fmt(value, 1)} peak_day #{day + 1} peak #{fmt(reported[day], 1)} averted #{fmt(value - @reported_total, 1)}"
    (1...@interventions.length).each do |k|
      value = total(counterfactual_reported(@interventions.each_with_index.reject { |_, i| i == k }.map(&:first)))
      @reproduction << "counterfactual without #{k + 1} reported #{fmt(value, 1)} averted #{fmt(value - @reported_total, 1)}"
    end
    (1...@interventions.length).each do |k|
      [-7, 7].each do |shift|
        changed = @interventions.dup
        day, multiplier = changed[k]
        changed[k] = [day + shift, multiplier]
        value = total(counterfactual_reported(changed))
        @reproduction << "timing #{k + 1} shift #{shift} reported #{fmt(value, 1)} change #{fmt(value - @reported_total, 1)}"
      end
    end
  end

  def scenarios
    @scenario_rows = ['scenario,day,incidence,reported']
    baseline = nil
    @params['scenario'].each do |name, multiplier|
      future = Array.new(@params['horizon'], multiplier)
      states = states_for(@beta, @gamma, future, @states[-1])
      reported = states.map { |s| @rho * s[5] }
      states.each_with_index { |s, i| @scenario_rows << "#{name},#{@days + i + 1},#{fmt(s[5], 1)},#{fmt(reported[i], 1)}" }
      reproduction = @r0 * multiplier * @states[-1][0] / @population
      value, day = total(reported), peak(reported)
      baseline ||= value
      below = reported.index { |x| x < @params['threshold'] }
      above = reported.count { |x| x >= @params['threshold'] }
      @reproduction << "scenario #{name} multiplier #{fmt(multiplier)} rt #{fmt(reproduction)} reported #{fmt(value, 1)} peak_day #{@days + day + 1} peak #{fmt(reported[day], 1)} attack #{fmt((@population - states[-1][0]) / @population)} final_size #{fmt(final_size(@r0 * multiplier))} averted #{fmt(baseline - value, 1)} below #{below ? @days + below + 1 : 'never'} days_above #{above}"
      low, high = @beta - 2.0 * @se['beta'], @beta + 2.0 * @se['beta']
      band = [low, high].map do |beta|
        total(states_for(beta, @gamma, @multipliers + future).drop(@days).map { |s| @rho * s[5] })
      end
      @reproduction << "scenario_band #{name} beta_low #{fmt(low, 6)} reported_low #{fmt(band[0], 1)} beta_high #{fmt(high, 6)} reported_high #{fmt(band[1], 1)}"
      age = age_states_for(@normalized, future, @age_states[-1]).last
      attacks = @g.times.map { |g| (@populations[g] - age[6 * g]) / @populations[g] }
      deaths = total(@g.times.map { |g| age[6 * g + 4] })
      @reproduction << "scenario_age #{name} attack #{attacks.map { |x| fmt(x) }.join(' ')} deaths #{fmt(deaths, 1)}"
    end
  end

  def trajectories
    lines = ['day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported']
    @days.times do |i|
      values = [i + 1, *@states[i + 1].map { |x| fmt(x, 1) }, fmt(@reported[i], 1), @cases[i],
                fmt(@averages[i], 2), @cumulative_cases[i], fmt(@cumulative_reported[i], 1)]
      lines << values.join(',')
    end
    lines
  end

  def analyze
    fit_model
    diagnostics
    profiles
    backtest
    effects
    sensitivity
    analyze_age
    compare_models
    analyze_reproduction
    scenarios
    { 'fit.txt' => @fit, 'trajectories.csv' => trajectories, 'scenarios.csv' => @scenario_rows,
      'reproduction.txt' => @reproduction, 'curve_plot.txt' => curve_plot(@cases, @reported) }
  end
end

DataIO.write_outputs(Study.new(*DataIO.read_inputs).analyze) if $PROGRAM_NAME == __FILE__
