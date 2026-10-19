from math import exp, sqrt

from data_io import read_inputs, write_outputs
from fitting import golden, nelder_mead
from integrator import simulate
from models import age_seird, generation, seird, sir
from report import curve_plot, fmt


def ordered_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def squared_errors(series, coefficient, observations):
    total = 0.0
    for value, observed in zip(series, observations):
        difference = coefficient * value - observed
        total += difference * difference
    return total


def peak(series):
    return max(range(len(series)), key=series.__getitem__)


def multiplier_sequence(interventions, days):
    result = []
    index = 0
    for day in range(1, days + 1):
        while index + 1 < len(interventions) and interventions[index + 1][0] <= day:
            index += 1
        result.append(interventions[index][1])
    return result


def final_size(reproduction):
    if reproduction <= 1.0:
        return 0.0
    lo = 1.0 - 1.0 / reproduction
    hi = 1.0
    for _ in range(20):
        middle = (lo + hi) / 2.0
        value = 1.0 - middle - exp(-reproduction * middle)
        if value > 0.0:
            lo = middle
        else:
            hi = middle
    return (lo + hi) / 2.0


def power_method(matrix):
    size = len(matrix)
    vector = [1.0 / size] * size
    for _ in range(200):
        product = [ordered_sum(row[h] * vector[h] for h in range(size)) for row in matrix]
        eigenvalue = ordered_sum(product)
        vector = [value / eigenvalue for value in product]
    return eigenvalue, vector


class Study:
    def __init__(self, cases, deaths, groups, contacts, interventions, params):
        self.cases = cases
        self.deaths = deaths
        self.groups = groups
        self.contacts = contacts
        self.interventions = interventions
        self.params = params
        self.days = len(cases)
        self.group_count = len(groups)
        self.populations = [group[1] for group in groups]
        self.fatalities = [group[2] for group in groups]
        self.population = sum(self.populations)
        self.case_total = sum(cases)
        self.death_total = sum(deaths)
        self.fatality = ordered_sum(group[1] * group[2] for group in groups) / self.population
        self.sigma = params["sigma"]
        self.gamma0 = params["gamma"]
        exposed, infectious = params["initial"]
        self.initial = (self.population - exposed - infectious, exposed, infectious, 0.0, 0.0, 0.0)
        self.sir_initial = (self.population - exposed - infectious, exposed + infectious, 0.0, 0.0)
        self.age_initial = []
        for population in self.populations:
            e = exposed * population / self.population
            i = infectious * population / self.population
            self.age_initial.extend((population - e - i, e, i, 0.0, 0.0, 0.0))
        self.multipliers = multiplier_sequence(interventions, self.days)
        self.week_ranges = [(start, min(start + 6, self.days)) for start in range(1, self.days + 1, 7)]
        self.incidence_cache = {}
        self.fit_lines = []
        self.reproduction_lines = []

    def rmse(self, error, count=None):
        return sqrt(error / (self.days if count is None else count))

    def seird_states(self, beta, gamma, multipliers=None, initial=None, sigma=None):
        rates = seird(self.population, self.sigma if sigma is None else sigma,
                      self.fatality, beta, gamma)
        return simulate(rates, self.initial if initial is None else initial,
                        self.multipliers if multipliers is None else multipliers, (5,))

    def incidence_for(self, beta, gamma):
        key = beta, gamma
        if key not in self.incidence_cache:
            self.incidence_cache[key] = [state[5] for state in self.seird_states(beta, gamma)]
        return self.incidence_cache[key]

    def error(self, beta, gamma, rho):
        return squared_errors(self.incidence_for(beta, gamma), rho, self.cases)

    def golden_records(self, round_number, name, search):
        result, value, records = search
        for index, (a, b, c, d, fc, fd) in enumerate(records):
            self.fit_lines.append(
                f"golden {round_number} {name} {index} a {fmt(a, 6)} b {fmt(b, 6)} "
                f"c {fmt(c, 6)} d {fmt(d, 6)} rmse {fmt(self.rmse(fc))} {fmt(self.rmse(fd))}"
            )
        self.fit_lines.append(f"golden_result {round_number} {name} {fmt(result, 6)} sse {fmt(value, 1)}")

    def fit_model(self):
        beta_min, beta_max, n_beta = self.params["beta_grid"]
        rho_min, rho_max, n_rho = self.params["rho_grid"]
        betas = [beta_min + (beta_max - beta_min) * i / (n_beta - 1) for i in range(n_beta)]
        rhos = [rho_min + (rho_max - rho_min) * j / (n_rho - 1) for j in range(n_rho)]
        self.delta_beta = (beta_max - beta_min) / (n_beta - 1)
        self.delta_rho = (rho_max - rho_min) / (n_rho - 1)
        self.fit_lines.append(f"data days {self.days} cases {self.case_total} deaths {self.death_total} "
                              f"population {self.population} fatality {fmt(self.fatality, 6)}")
        self.fit_lines.append(f"grid gamma {fmt(self.gamma0)} rho " + " ".join(fmt(value) for value in rhos))
        best = None
        for i, beta in enumerate(betas):
            errors = []
            for j, rho in enumerate(rhos):
                value = self.error(beta, self.gamma0, rho)
                errors.append(value)
                candidate = value, i, j
                if best is None or candidate < best:
                    best = candidate
            self.fit_lines.append(f"grid beta {fmt(beta)} rmse "
                                  + " ".join(fmt(self.rmse(value), 2) for value in errors))
        self.sse_grid, i, j = best
        self.beta_grid, self.rho_grid = betas[i], rhos[j]
        self.fit_lines.append(f"grid_best beta {fmt(self.beta_grid)} rho {fmt(self.rho_grid)} "
                              f"sse {fmt(self.sse_grid, 1)} rmse {fmt(self.rmse(self.sse_grid))}")
        beta, rho = self.beta_grid, self.rho_grid
        iterations, rounds = self.params["golden"]
        for round_number in range(1, rounds + 1):
            search = golden(lambda value: self.error(value, self.gamma0, rho),
                            beta - self.delta_beta, beta + self.delta_beta, iterations)
            self.golden_records(round_number, "beta", search)
            beta = search[0]
            search = golden(lambda value: self.error(beta, self.gamma0, value),
                            rho - self.delta_rho, rho + self.delta_rho, iterations)
            self.golden_records(round_number, "rho", search)
            rho, self.sse_golden = search[:2]
        self.beta_golden, self.rho = beta, rho
        initial, records, final = nelder_mead(
            lambda b, g: self.error(b, g, rho), beta, self.gamma0,
            *self.params["simplex"], *self.params["nelder_mead"]
        )
        for number, b, g, value in initial:
            self.fit_lines.append(f"simplex {number} beta {fmt(b, 6)} gamma {fmt(g, 6)} "
                                  f"rmse {fmt(self.rmse(value))}")
        for iteration, (operation, vertex) in enumerate(records, 1):
            _, b, g, value = vertex
            self.fit_lines.append(f"nelder_mead {iteration} {operation} beta {fmt(b, 6)} "
                                  f"gamma {fmt(g, 6)} rmse {fmt(self.rmse(value))}")
        for rank, (_, b, g, value) in enumerate(final, 1):
            self.fit_lines.append(f"final_simplex {rank} beta {fmt(b, 6)} gamma {fmt(g, 6)} "
                                  f"rmse {fmt(self.rmse(value))}")
        _, self.beta, self.gamma, self.sse_nm = final[0]
        self.r0 = self.beta / self.gamma
        mean = self.case_total / self.days
        sst = ordered_sum((value - mean) * (value - mean) for value in self.cases)
        self.fit_lines.append(f"fitted beta {fmt(self.beta, 6)} gamma {fmt(self.gamma, 6)} "
                              f"rho {fmt(self.rho, 6)} sigma {fmt(self.sigma, 6)} r0 {fmt(self.r0)}")
        self.fit_lines.append(f"sse grid {fmt(self.sse_grid, 1)} golden {fmt(self.sse_golden, 1)} "
                              f"nelder_mead {fmt(self.sse_nm, 1)} rmse {fmt(self.rmse(self.sse_nm))} "
                              f"r2 {fmt(1.0 - self.sse_nm / sst)}")
        stages = (("grid", self.beta_grid, self.gamma0, self.rho_grid, self.sse_grid),
                  ("golden", self.beta_golden, self.gamma0, self.rho, self.sse_golden),
                  ("nelder_mead", self.beta, self.gamma, self.rho, self.sse_nm))
        for name, b, g, r, value in stages:
            self.fit_lines.append(f"stage {name} beta {fmt(b, 6)} gamma {fmt(g, 6)} rho {fmt(r, 6)} "
                                  f"r0 {fmt(b / g)} rmse {fmt(self.rmse(value))}")

    def fitted_diagnostics(self):
        self.states = [self.initial, *self.seird_states(self.beta, self.gamma)]
        self.incidence = [state[5] for state in self.states[1:]]
        self.reported = [self.rho * value for value in self.incidence]
        self.residuals = [observed - fitted for observed, fitted in zip(self.cases, self.reported)]
        self.model_deaths = [self.states[day][4] - self.states[day - 1][4]
                             for day in range(1, self.days + 1)]
        self.rt = [self.r0 * self.multipliers[index] * self.states[index][0] / self.population
                   for index in range(self.days)]
        self.averages = [sum(self.cases[max(0, index - 6):index + 1]) / min(index + 1, 7)
                         for index in range(self.days)]
        self.cumulative_cases = []
        self.cumulative_reported = []
        observed_total = 0
        reported_total = 0.0
        for observed, fitted in zip(self.cases, self.reported):
            observed_total += observed
            reported_total += fitted
            self.cumulative_cases.append(observed_total)
            self.cumulative_reported.append(reported_total)
        self.reported_total = reported_total
        residual_sum = ordered_sum(self.residuals)
        absolute = [abs(value) for value in self.residuals]
        largest = peak(absolute)
        positive = sum(value > 0.0 for value in self.residuals)
        runs = 1 + sum((self.residuals[index] > 0.0) != (self.residuals[index - 1] > 0.0)
                       for index in range(1, self.days))
        residual_square = ordered_sum(value * value for value in self.residuals)
        differences = [self.residuals[index] - self.residuals[index - 1] for index in range(1, self.days)]
        durbin_watson = ordered_sum(value * value for value in differences) / residual_square
        self.fit_lines.append(f"residuals sum {fmt(residual_sum, 1)} "
                              f"mae {fmt(ordered_sum(absolute) / self.days, 1)} "
                              f"max {fmt(self.residuals[largest], 1)} day {largest + 1} "
                              f"positive {positive} runs {runs} durbin_watson {fmt(durbin_watson)}")
        correlations = [ordered_sum(self.residuals[index] * self.residuals[index + lag]
                                    for index in range(self.days - lag)) / residual_square
                        for lag in range(1, 8)]
        self.fit_lines.append("autocorrelation " + " ".join(fmt(value) for value in correlations))
        outliers = 0
        for index, residual in enumerate(self.residuals):
            z = residual / sqrt(self.reported[index])
            if abs(z) > self.params["outlier"]:
                self.fit_lines.append(f"outlier {index + 1} observed {self.cases[index]} "
                                      f"fitted {fmt(self.reported[index], 1)} z {fmt(z)}")
                outliers += 1
        self.fit_lines.append(f"outliers {outliers}")
        weekday_factors = []
        for weekday in range(7):
            observed = sum(self.cases[index] for index in range(weekday, self.days, 7))
            fitted = ordered_sum(self.reported[index] for index in range(weekday, self.days, 7))
            factor = observed / fitted
            weekday_factors.append(factor)
            self.fit_lines.append(f"weekday {weekday + 1} observed {observed} fitted {fmt(fitted, 1)} "
                                  f"factor {fmt(factor)}")
        adjusted = [value * weekday_factors[index % 7] for index, value in enumerate(self.reported)]
        self.fit_lines.append(f"weekday_adjusted rmse {fmt(self.rmse(squared_errors(adjusted, 1.0, self.cases)))}")
        infections = ordered_sum(self.incidence)
        self.fit_lines.append(f"burden infections {fmt(infections, 1)} "
                              f"ascertainment {fmt(self.case_total / infections)} "
                              f"deaths_per_infection {fmt(self.death_total / infections, 6)}")
        self.death_analysis()
        previous_observed = None
        for week, (first, last) in enumerate(self.week_ranges, 1):
            observed = sum(self.cases[first - 1:last])
            fitted = ordered_sum(self.reported[first - 1:last])
            dead = sum(self.deaths[first - 1:last])
            modeled = ordered_sum(self.model_deaths[first - 1:last])
            growth = "-" if previous_observed is None else fmt(observed / previous_observed)
            self.fit_lines.append(f"weekly {week} days {first} {last} observed {observed} "
                                  f"fitted {fmt(fitted, 1)} deaths_observed {dead} "
                                  f"deaths_model {fmt(modeled, 1)} growth {growth}")
            previous_observed = observed

    def death_analysis(self):
        numerator = ordered_sum(value * observed for value, observed in zip(self.model_deaths, self.deaths))
        denominator = ordered_sum(value * value for value in self.model_deaths)
        scale = numerator / denominator
        error = squared_errors(self.model_deaths, 1.0, self.deaths)
        self.fit_lines.append(f"deaths observed {self.death_total} model {fmt(self.states[-1][4], 1)} "
                              f"rmse {fmt(self.rmse(error))} scale {fmt(scale)} "
                              f"implied_fatality {fmt(self.fatality * scale, 6)} "
                              f"cfr {fmt(self.death_total / self.case_total)}")
        correlations = []
        for lag in range(self.params["death_lag"] + 1):
            a = sum(self.cases[index] * self.deaths[index + lag] for index in range(self.days - lag))
            b = sum(value * value for value in self.cases[:self.days - lag])
            y = sum(value * value for value in self.deaths[lag:])
            correlation = a / sqrt(float(b) * float(y))
            correlations.append(correlation)
            cfr = sum(self.deaths[lag:]) / sum(self.cases[:self.days - lag])
            self.fit_lines.append(f"death_lag {lag} correlation {fmt(correlation)} cfr {fmt(cfr)}")
        self.fit_lines.append(f"death_best_lag {peak(correlations)}")

    def profiles(self):
        self.standard_errors = {}
        fitted = (self.beta, self.gamma, self.rho)
        variance = self.sse_nm / (self.days - 3)
        for index, name in enumerate(("beta", "gamma", "rho")):
            value = fitted[index]
            errors = {}
            for offset in range(-5, 6):
                point = value * (1.0 + offset / 100.0)
                parameters = list(fitted)
                parameters[index] = point
                error = self.error(*parameters)
                errors[offset] = error
                self.fit_lines.append(f"profile {name} {offset} value {fmt(point, 6)} "
                                      f"rmse {fmt(self.rmse(error))}")
            h = value / 100.0
            curvature = (errors[1] - 2.0 * errors[0] + errors[-1]) / (h * h)
            standard_error = sqrt(2.0 * variance / curvature)
            self.standard_errors[name] = standard_error
            self.fit_lines.append(f"profile_se {name} {fmt(standard_error, 6)}")

    def backtest(self):
        holdout = self.params["holdout"]
        training = self.days - holdout
        multipliers = self.multipliers[:training]
        cases = self.cases[:training]
        cache = {}

        def training_error(beta, rho):
            if beta not in cache:
                cache[beta] = [state[5] for state in self.seird_states(beta, self.gamma, multipliers)]
            return squared_errors(cache[beta], rho, cases)

        iterations = self.params["golden"][0]
        beta, _, _ = golden(lambda value: training_error(value, self.rho),
                            self.beta - self.delta_beta, self.beta + self.delta_beta, iterations)
        rho, error, _ = golden(lambda value: training_error(beta, value),
                               self.rho - self.delta_rho, self.rho + self.delta_rho, iterations)
        forecasts = [rho * value for value in self.incidence_for(beta, self.gamma)[training:]]
        test_error = squared_errors(forecasts, 1.0, self.cases[training:])
        full_error = squared_errors(self.reported[training:], 1.0, self.cases[training:])
        self.fit_lines.append(f"backtest train_days {training} beta {fmt(beta, 6)} rho {fmt(rho, 6)} "
                              f"train_rmse {fmt(self.rmse(error, training))} "
                              f"test_rmse {fmt(self.rmse(test_error, holdout))} "
                              f"full_fit_test_rmse {fmt(self.rmse(full_error, holdout))}")
        for index, forecast in enumerate(forecasts, training):
            self.fit_lines.append(f"backtest_day {index + 1} observed {self.cases[index]} "
                                  f"forecast {fmt(forecast, 1)} error {fmt(self.cases[index] - forecast, 1)}")

    def estimate_effects(self):
        estimated = self.interventions.copy()
        after = self.sse_nm
        width = self.params["effect_width"]
        for index in range(1, len(self.interventions)):
            day, given = self.interventions[index]

            def objective(value):
                changed = estimated.copy()
                changed[index] = day, value
                multipliers = multiplier_sequence(changed, self.days)
                incidence = [state[5] for state in self.seird_states(self.beta, self.gamma, multipliers)]
                return squared_errors(incidence, self.rho, self.cases)

            value, after, _ = golden(objective, given - width, given + width, self.params["golden"][0])
            estimated[index] = day, value
            self.fit_lines.append(f"effect {index + 1} day {day} given {fmt(given)} "
                                  f"estimated {fmt(value, 6)} sse {fmt(after, 1)}")
        self.fit_lines.append(f"effect_sse before {fmt(self.sse_nm, 1)} after {fmt(after, 1)} "
                              f"rmse {fmt(self.rmse(after))}")

    def sensitivity(self):
        fitted = (self.beta, self.gamma, self.sigma, self.rho)
        for index, name in enumerate(("beta", "gamma", "sigma", "rho")):
            for factor in (0.9, 1.1):
                values = list(fitted)
                values[index] = values[index] * factor
                beta, gamma, sigma, rho = values
                states = self.seird_states(beta, gamma, sigma=sigma)
                incidence = [state[5] for state in states]
                day = peak(incidence)
                error = squared_errors(incidence, rho, self.cases)
                attack = (self.population - states[-1][0]) / self.population
                self.fit_lines.append(f"sensitivity {name} {fmt(factor, 2)} r0 {fmt(beta / gamma)} "
                                      f"rmse {fmt(self.rmse(error))} peak_day {day + 1} "
                                      f"peak {fmt(rho * incidence[day], 1)} attack {fmt(attack)}")

    def age_states_for(self, contacts=None, multipliers=None, initial=None):
        rates = age_seird(self.populations, self.fatalities, self.sigma, self.beta, self.gamma,
                          self.normalized_contacts if contacts is None else contacts)
        return simulate(rates, self.age_initial if initial is None else initial,
                        self.multipliers if multipliers is None else multipliers,
                        range(5, 6 * self.group_count, 6))

    def next_generation(self, contacts):
        return [[self.r0 * contacts[g][h] * self.populations[g] / self.populations[h]
                 for h in range(self.group_count)] for g in range(self.group_count)]

    def analyze_age(self):
        row_totals = [ordered_sum(row) for row in self.contacts]
        self.kbar = ordered_sum(self.populations[g] * row_totals[g] for g in range(self.group_count)) / self.population
        self.normalized_contacts = [[value / self.kbar for value in row] for row in self.contacts]
        matrix = self.next_generation(self.normalized_contacts)
        reproduction, eigenvector = power_method(matrix)
        self.age_lines = []
        for group, row in zip(self.groups, matrix):
            self.age_lines.append(f"ngm {group[0]} " + " ".join(fmt(value) for value in row))
        self.age_lines.append(f"r0_age {fmt(reproduction)} ratio {fmt(reproduction / self.r0)} "
                              f"kbar {fmt(self.kbar)} eigenvector " + " ".join(fmt(value) for value in eigenvector))
        final = [1.0] * self.group_count
        for _ in range(100):
            final = [1.0 - exp(-ordered_sum(self.r0 * row[h] * final[h] for h in range(self.group_count)))
                     for row in self.normalized_contacts]
        long_states = self.age_states_for(multipliers=[1.0] * 730)
        simulated = [(population - long_states[-1][6 * g]) / population
                     for g, population in enumerate(self.populations)]
        for g, group in enumerate(self.groups):
            self.age_lines.append(f"final_size_age {group[0]} equation {fmt(final[g])} simulated {fmt(simulated[g])}")
        final_total = ordered_sum(self.populations[g] * final[g] for g in range(self.group_count)) / self.population
        simulated_total = ordered_sum(self.populations[g] * simulated[g] for g in range(self.group_count)) / self.population
        self.age_lines.append(f"final_size_age total equation {fmt(final_total)} simulated {fmt(simulated_total)}")
        self.age_states = [tuple(self.age_initial), *self.age_states_for()]
        self.age_incidence = [ordered_sum(state[5::6]) for state in self.age_states[1:]]
        for day in range(1, self.days + 1, 7):
            previous = self.age_states[day - 1]
            matrix = [[self.multipliers[day - 1] * self.r0 * self.normalized_contacts[g][h]
                       * previous[6 * g] / self.populations[h]
                       for h in range(self.group_count)] for g in range(self.group_count)]
            reproduction, _ = power_method(matrix)
            self.age_lines.append(f"age_rt {day} {fmt(reproduction)} homogeneous {fmt(self.rt[day - 1])}")
        for week, (first, last) in enumerate(self.week_ranges, 1):
            totals = [ordered_sum(self.age_states[day][6 * g + 5] for day in range(first, last + 1))
                      for g in range(self.group_count)]
            self.age_lines.append(f"age_weekly {week} days {first} {last} "
                                  + " ".join(fmt(value, 1) for value in totals))
        infections = [ordered_sum(state[6 * g + 5] for state in self.age_states[1:])
                      for g in range(self.group_count)]
        infection_total = ordered_sum(infections)
        for g, (name, population, _) in enumerate(self.groups):
            incidence = [state[6 * g + 5] for state in self.age_states[1:]]
            day = peak(incidence)
            attack = (population - self.age_states[-1][6 * g]) / population
            deaths = self.age_states[-1][6 * g + 4]
            self.age_lines.append(f"age {name} attack {fmt(attack)} infections {fmt(infections[g], 1)} "
                                  f"share {fmt(infections[g] / infection_total)} deaths {fmt(deaths, 1)} "
                                  f"peak_day {day + 1} peak {fmt(incidence[day], 1)}")
        group_numbers = {group[0]: g for g, group in enumerate(self.groups)}
        for name, target, factor in self.params["contact_change"]:
            target_number = group_numbers[target]
            tau = [factor if g == target_number else 1.0 for g in range(self.group_count)]
            contacts = [[self.normalized_contacts[g][h] * tau[g] * tau[h]
                         for h in range(self.group_count)] for g in range(self.group_count)]
            reproduction, _ = power_method(self.next_generation(contacts))
            states = self.age_states_for(contacts=contacts)
            infections = ordered_sum(ordered_sum(state[5::6]) for state in states)
            deaths = ordered_sum(states[-1][4::6])
            attack = ordered_sum(self.populations[g] - states[-1][6 * g]
                                 for g in range(self.group_count)) / self.population
            self.age_lines.append(f"contact_change {name} group {target} factor {fmt(factor)} "
                                  f"r0_age {fmt(reproduction)} infections {fmt(infections, 1)} "
                                  f"deaths {fmt(deaths, 1)} attack {fmt(attack)}")

    def sir_incidence(self, beta):
        states = simulate(sir(self.population, beta, self.gamma), self.sir_initial, self.multipliers, (3,))
        return [state[3] for state in states]

    def compare_models(self):
        series = (("sir", self.sir_incidence(self.beta)), ("seir", self.incidence), ("age", self.age_incidence))
        for name, incidence in series:
            error = squared_errors(incidence, self.rho, self.cases)
            numerator = ordered_sum(observed * value for observed, value in zip(self.cases, incidence))
            denominator = ordered_sum(value * value for value in incidence)
            rho = numerator / denominator
            optimal = squared_errors(incidence, rho, self.cases)
            self.fit_lines.append(f"model {name} rmse {fmt(self.rmse(error))} peak_day {peak(incidence) + 1} "
                                  f"rho_opt {fmt(rho, 6)} rmse_opt {fmt(self.rmse(optimal))}")
        lower, upper, _ = self.params["beta_grid"]
        beta, error, _ = golden(lambda value: squared_errors(self.sir_incidence(value), self.rho, self.cases),
                                lower, upper, self.params["golden"][0])
        self.fit_lines.append(f"model sir_fit beta {fmt(beta, 6)} rmse {fmt(self.rmse(error))} "
                              f"peak_day {peak(self.sir_incidence(beta)) + 1}")

    def generation_interval(self):
        length = self.params["generation"]
        states = simulate(generation(self.sigma, self.gamma), (1.0, 0.0, 0.0), [1.0] * length, (2,))
        amounts = [state[2] for state in states]
        coverage = ordered_sum(amounts)
        weights = [value / coverage for value in amounts]
        mean = ordered_sum((day - 0.5) * weight for day, weight in enumerate(weights, 1))
        theoretical = 1.0 / self.sigma + 1.0 / self.gamma
        self.reproduction_lines.append(f"generation mean {fmt(mean)} theory {fmt(theoretical)} coverage {fmt(coverage)}")
        for day, weight in enumerate(weights, 1):
            self.reproduction_lines.append(f"generation_weight {day} {fmt(weight, 6)}")
        pressures = [ordered_sum(weights[lag - 1] * self.cases[index - lag]
                                 for lag in range(1, min(length, index) + 1))
                     for index in range(self.days)]
        self.empirical_rt = []
        for index in range(self.days):
            if index + 1 < length + 7:
                self.empirical_rt.append(None)
            else:
                observed = sum(self.cases[index - 6:index + 1])
                pressure = ordered_sum(pressures[index - 6:index + 1])
                self.empirical_rt.append(observed / pressure)

    def epidemic_peaks(self):
        incidence_day = peak(self.incidence)
        infectious = [state[2] for state in self.states[1:]]
        infectious_day = peak(infectious)
        observed_day = peak(self.cases)
        average_day = peak(self.averages)
        self.reproduction_lines.append(f"peak model day {incidence_day + 1} "
                                        f"incidence {fmt(self.incidence[incidence_day], 1)} "
                                        f"reported {fmt(self.reported[incidence_day], 1)} "
                                        f"infectious_day {infectious_day + 1} "
                                        f"infectious {fmt(infectious[infectious_day], 1)}")
        self.reproduction_lines.append(f"peak observed day {observed_day + 1} cases {self.cases[observed_day]} "
                                        f"average7_day {average_day + 1} average7 {fmt(self.averages[average_day], 2)}")

    def periods_and_milestones(self):
        for index, (first, multiplier) in enumerate(self.interventions):
            last = self.interventions[index + 1][0] - 1 if index + 1 < len(self.interventions) else self.days
            residuals = self.residuals[first - 1:last]
            error = ordered_sum(value * value for value in residuals)
            count = last - first + 1
            observed = sum(self.cases[first - 1:last])
            fitted = ordered_sum(self.reported[first - 1:last])
            bias = ordered_sum(residuals) / count
            self.reproduction_lines.append(
                f"period {index + 1} days {first} {last} multiplier {fmt(multiplier)} "
                f"rt_start {fmt(self.rt[first - 1])} rt_end {fmt(self.rt[last - 1])} "
                f"observed {observed} fitted {fmt(fitted, 1)} rmse {fmt(self.rmse(error, count))} bias {fmt(bias, 1)}"
            )
        for target in self.params["milestones"]:
            observed = next((index + 1 for index, value in enumerate(self.cumulative_cases) if value >= target), "never")
            fitted = next((index + 1 for index, value in enumerate(self.cumulative_reported) if value >= target), "never")
            self.reproduction_lines.append(f"milestone {target} observed {observed} fitted {fitted}")

    def counterfactual_reported(self, interventions):
        multipliers = multiplier_sequence(interventions, self.days)
        states = self.seird_states(self.beta, self.gamma, multipliers)
        return [self.rho * state[5] for state in states]

    def counterfactuals(self):
        reported = self.counterfactual_reported(self.interventions[:1])
        total = ordered_sum(reported)
        day = peak(reported)
        self.reproduction_lines.append(f"counterfactual none reported {fmt(total, 1)} peak_day {day + 1} "
                                        f"peak {fmt(reported[day], 1)} averted {fmt(total - self.reported_total, 1)}")
        for index in range(1, len(self.interventions)):
            changed = self.interventions[:index] + self.interventions[index + 1:]
            total = ordered_sum(self.counterfactual_reported(changed))
            self.reproduction_lines.append(f"counterfactual without {index + 1} reported {fmt(total, 1)} "
                                            f"averted {fmt(total - self.reported_total, 1)}")
        for index in range(1, len(self.interventions)):
            for shift in (-7, 7):
                changed = self.interventions.copy()
                day, multiplier = changed[index]
                changed[index] = day + shift, multiplier
                total = ordered_sum(self.counterfactual_reported(changed))
                self.reproduction_lines.append(f"timing {index + 1} shift {shift} reported {fmt(total, 1)} "
                                                f"change {fmt(total - self.reported_total, 1)}")

    def analyze_reproduction(self):
        self.reproduction_lines.append(f"r0 {fmt(self.r0)} herd_immunity {fmt(1.0 - 1.0 / self.r0)}")
        long_states = self.seird_states(self.beta, self.gamma, [1.0] * 730)
        attack = (self.population - long_states[-1][0]) / self.population
        self.reproduction_lines.append(f"final_size equation {fmt(final_size(self.r0))} simulated {fmt(attack)}")
        self.generation_interval()
        self.epidemic_peaks()
        self.periods_and_milestones()
        self.counterfactuals()
        for index in range(1, self.days):
            if (self.rt[index] < 1.0) != (self.rt[index - 1] < 1.0):
                direction = "down" if self.rt[index] < 1.0 else "up"
                self.reproduction_lines.append(f"rt_cross day {index + 1} {direction}")
        for index in range(self.days):
            empirical = "-" if self.empirical_rt[index] is None else fmt(self.empirical_rt[index])
            self.reproduction_lines.append(f"rt {index + 1} model {fmt(self.rt[index])} empirical {empirical}")
        self.reproduction_lines.extend(self.age_lines)

    def scenario_projections(self):
        horizon = self.params["horizon"]
        threshold = self.params["threshold"]
        self.scenario_rows = ["scenario,day,incidence,reported"]
        baseline = None
        for name, multiplier in self.params["scenario"]:
            future = [multiplier] * horizon
            states = self.seird_states(self.beta, self.gamma, future, self.states[-1])
            incidence = [state[5] for state in states]
            reported = [self.rho * value for value in incidence]
            for day, (value, count) in enumerate(zip(incidence, reported), self.days + 1):
                self.scenario_rows.append(f"{name},{day},{fmt(value, 1)},{fmt(count, 1)}")
            reproduction = self.r0 * multiplier * self.states[-1][0] / self.population
            total = ordered_sum(reported)
            if baseline is None:
                baseline = total
            day = peak(reported)
            attack = (self.population - states[-1][0]) / self.population
            below = next((self.days + index + 1 for index, value in enumerate(reported) if value < threshold), "never")
            above = sum(value >= threshold for value in reported)
            self.reproduction_lines.append(
                f"scenario {name} multiplier {fmt(multiplier)} rt {fmt(reproduction)} reported {fmt(total, 1)} "
                f"peak_day {self.days + day + 1} peak {fmt(reported[day], 1)} attack {fmt(attack)} "
                f"final_size {fmt(final_size(self.r0 * multiplier))} averted {fmt(baseline - total, 1)} "
                f"below {below} days_above {above}"
            )
            beta_low = self.beta - 2.0 * self.standard_errors["beta"]
            beta_high = self.beta + 2.0 * self.standard_errors["beta"]
            band = []
            for beta in (beta_low, beta_high):
                full = self.seird_states(beta, self.gamma, self.multipliers + future)
                band.append(ordered_sum(self.rho * state[5] for state in full[self.days:]))
            self.reproduction_lines.append(f"scenario_band {name} beta_low {fmt(beta_low, 6)} "
                                            f"reported_low {fmt(band[0], 1)} beta_high {fmt(beta_high, 6)} "
                                            f"reported_high {fmt(band[1], 1)}")
            age_states = self.age_states_for(multipliers=future, initial=self.age_states[-1])
            attacks = [(population - age_states[-1][6 * g]) / population
                       for g, population in enumerate(self.populations)]
            deaths = ordered_sum(age_states[-1][4::6])
            self.reproduction_lines.append(f"scenario_age {name} attack "
                                            + " ".join(fmt(value) for value in attacks)
                                            + f" deaths {fmt(deaths, 1)}")

    def trajectories(self):
        lines = ["day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported"]
        for index in range(self.days):
            values = [str(index + 1), *(fmt(value, 1) for value in self.states[index + 1])]
            values.extend((fmt(self.reported[index], 1), str(self.cases[index]), fmt(self.averages[index], 2),
                           str(self.cumulative_cases[index]), fmt(self.cumulative_reported[index], 1)))
            lines.append(",".join(values))
        return lines

    def analyze(self):
        self.fit_model()
        self.fitted_diagnostics()
        self.profiles()
        self.backtest()
        self.estimate_effects()
        self.sensitivity()
        self.analyze_age()
        self.compare_models()
        self.analyze_reproduction()
        self.scenario_projections()
        return {
            "fit.txt": self.fit_lines,
            "trajectories.csv": self.trajectories(),
            "scenarios.csv": self.scenario_rows,
            "reproduction.txt": self.reproduction_lines,
            "curve_plot.txt": curve_plot(self.cases, self.reported),
        }


def main():
    study = Study(*read_inputs())
    write_outputs(study.analyze())


if __name__ == "__main__":
    main()
