class Invalid < StandardError
end

class Splitter
  def initialize
    @day = 1
    @serial = 0
    @members = {}
    @currencies = {}
    @expenses = []
    @settlements = []
    @budgets = {}
    @used = {}
  end

  def fail_with(message)
    raise Invalid, message
  end

  def amount(value)
    whole, cents = value.split(".")
    whole.to_i * 100 + cents.to_i
  end

  def money(value)
    format("%d.%02d", value.div(100), value % 100)
  end

  def signed(value)
    return "+" + money(value) if value.positive?
    return "-" + money(-value) if value.negative?
    "0.00"
  end

  def percent(part, whole)
    money((part * 10_000).div(whole)) + "%"
  end

  def rate_text(value)
    format("%d.%04d", value.div(10_000), value % 10_000)
  end

  def distribute(total, weights)
    sum = weights.sum
    portions = weights.map { |weight| (total * weight).div(sum) }
    order = weights.each_index.sort_by { |i| [-(total * weights[i] % sum), i] }
    (total - portions.sum).times { |i| portions[order[i]] += 1 }
    portions
  end

  def equal(total, count)
    q, m = total.divmod(count)
    Array.new(count) { |i| q + (i < m ? 1 : 0) }
  end

  def note(item)
    item[:currency].empty? ? "" : " [#{money(item[:amount])} #{item[:currency]}]"
  end

  def names(active = false)
    @members.keys.select { |name| !active || @members[name][:active] }.sort
  end

  def member(name, active = true)
    value = @members[name]
    fail_with("unknown member #{name}") unless value
    fail_with("inactive member #{name}") if active && !value[:active]
  end

  def involved?(expense, name)
    (expense[:payers] + expense[:participants]).any? { |person| person[:name] == name }
  end

  def net(expense, name)
    paid = expense[:payers].each_with_index.sum do |person, i|
      person[:name] == name ? expense[:contributions][i] : 0
    end
    share = expense[:participants].each_with_index.sum do |person, i|
      person[:name] == name ? expense[:shares][i] : 0
    end
    paid - share
  end

  def get_expense(id, frozen = false)
    expense = @expenses.find { |item| item[:id] == id }
    fail_with("unknown expense #{id}") unless expense
    if frozen
      (expense[:payers] + expense[:participants]).each do |person|
        fail_with("inactive member #{person[:name]}") unless @members[person[:name]][:active]
      end
    end
    expense
  end

  def convert(value, currency)
    return value if currency.empty?
    fail_with("unknown currency #{currency}") unless @currencies.key?(currency)
    (value * @currencies[currency] + 5000).div(10_000)
  end

  def specification(value)
    text, currency = value.split("@")
    currency ||= ""
    original = amount(text)
    total = convert(original, currency)
    fail_with("invalid amount") if original.zero? || total.zero?
    { amount: original, currency: currency, total: total }
  end

  def original_shares(expense, total)
    weights = expense[:participants].map { |person| person[:value] }
    portions = case expense[:mode]
               when "EQUAL"
                 equal(expense[:amount], weights.length)
               when "EXACT"
                 weights
               when "ADJUST"
                 equal(expense[:amount] - weights.sum, weights.length).each_with_index.map do |value, i|
                   value + weights[i]
                 end
               else
                 distribute(expense[:amount], weights)
               end
    distribute(total, portions)
  end

  def prepare(id, payer, spec, category, mode, parts, previous = nil)
    member(payer)
    converted = specification(spec)
    participants = []
    if mode == "EQUAL" && parts[0] == "ALL"
      participants = names(true).map { |name| { name: name, value: 0 } }
    else
      seen = {}
      parts.each do |part|
        name, value = part.split(":")
        member(name)
        fail_with("duplicate member #{name}") if seen[name]
        seen[name] = true
        specified = if value.nil?
                      0
                    elsif %w[EXACT ADJUST].include?(mode)
                      amount(value)
                    else
                      value.to_i
                    end
        participants << { name: name, value: specified }
      end
    end
    sum = participants.sum { |person| person[:value] }
    a = converted[:amount]
    if (mode == "EXACT" && sum != a) || (mode == "PERCENT" && sum != 10_000) ||
       (mode == "SHARES" && sum.zero?) || (mode == "ADJUST" && sum > a)
      fail_with("splits do not add up")
    end
    expense = {
      id: id, day: previous ? previous[:day] : @day,
      record: previous ? previous[:record] : 0, **converted,
      category: category, mode: mode, payers: [{ name: payer, value: a }],
      participants: participants, contributions: [converted[:total]],
      interval: previous ? previous[:interval] : 0,
      next: previous ? previous[:next] : 0,
      copies: previous ? previous[:copies] : 0
    }
    expense[:shares] = original_shares(expense, expense[:total])
    expense
  end

  def balances
    values = names.to_h { |name| [name, 0] }
    @expenses.each do |expense|
      expense[:payers].each_with_index do |person, i|
        values[person[:name]] += expense[:contributions][i]
      end
      expense[:participants].each_with_index do |person, i|
        values[person[:name]] -= expense[:shares][i]
      end
    end
    @settlements.each do |payment|
      values[payment[:from]] += payment[:total]
      values[payment[:to]] -= payment[:total]
    end
    values
  end

  def spent(category)
    @expenses.select { |expense| expense[:category] == category }.sum { |expense| expense[:total] }
  end

  def warning(expense)
    budget = @budgets[expense[:category]]
    total = spent(expense[:category])
    budget && total > budget ? ["  WARNING #{expense[:category]} over budget by #{money(total - budget)}"] : []
  end

  def debts
    result = Hash.new(0)
    @expenses.each do |expense|
      people = names.select { |name| involved?(expense, name) }
      nets = people.map { |name| { name: name, value: net(expense, name) } }
      borrowers = nets.select { |person| person[:value].negative? }
      lenders = nets.select { |person| person[:value].positive? }
      i = 0
      j = 0
      while i < borrowers.length && j < lenders.length
        value = [-borrowers[i][:value], lenders[j][:value]].min
        result[[borrowers[i][:name], lenders[j][:name]]] += value
        borrowers[i][:value] += value
        lenders[j][:value] -= value
        i += 1 if borrowers[i][:value].zero?
        j += 1 if lenders[j][:value].zero?
      end
    end
    @settlements.each do |payment|
      result[[payment[:from], payment[:to]]] -= payment[:total]
    end
    result
  end

  def greedy(balances)
    values = balances.dup
    result = []
    loop do
      debtors = values.select { |_, value| value.negative? }
      break if debtors.empty?
      from, debt = debtors.min_by { |name, value| [value, name] }
      to, credit = values.select { |_, value| value.positive? }.min_by { |name, value| [-value, name] }
      value = [-debt, credit].min
      result << { from: from, to: to, amount: value }
      values[from] += value
      values[to] -= value
    end
    result
  end

  def transfer_text(transfer, indent)
    "#{indent}#{transfer[:from]} -> #{transfer[:to]} #{money(transfer[:amount])}"
  end

  def optimal
    values = balances
    people = names.reject { |name| values[name].zero? }
    fail_with("too many members") if people.length > 12
    full = (1 << people.length) - 1
    sums = Array.new(full + 1, 0)
    (1..full).each do |mask|
      bit = mask & -mask
      index = bit.bit_length - 1
      sums[mask] = sums[mask ^ bit] + values[people[index]]
    end
    memo = { 0 => 0 }
    best = lambda do |mask|
      return memo[mask] if memo.key?(mask)
      first = mask & -mask
      maximum = 0
      sub = mask
      while sub.positive?
        if (sub & first).positive? && sums[sub].zero?
          maximum = [maximum, 1 + best.call(mask ^ sub)].max
        end
        sub = (sub - 1) & mask
      end
      memo[mask] = maximum
    end
    list = lambda do |mask|
      people.each_with_index.filter_map { |name, i| name if (mask & (1 << i)).positive? }
    end
    groups = []
    mask = full
    while mask.positive?
      first = mask & -mask
      candidates = []
      sub = mask
      while sub.positive?
        if (sub & first).positive? && sums[sub].zero? && 1 + best.call(mask ^ sub) == best.call(mask)
          candidates << sub
        end
        sub = (sub - 1) & mask
      end
      chosen = candidates.min_by { |candidate| list.call(candidate) }
      groups << list.call(chosen)
      mask ^= chosen
    end
    output = ["SIMPLIFY OPTIMAL transfers #{people.length - groups.length} groups #{groups.length}"]
    groups.each do |group|
      output << "  group " + group.join(" ")
      subset = group.to_h { |name| [name, values[name]] }
      output.concat(greedy(subset).map { |transfer| transfer_text(transfer, "    ") })
    end
    output
  end

  def command(line)
    name, *args = line.split(" ")
    output = []
    case name
    when "DAY"
      day = args[0].to_i
      fail_with("invalid day #{args[0]}") if day <= @day
      output << "DAY #{day}"
      loop do
        pending = @expenses.select { |expense| expense[:interval].positive? && expense[:next] <= day }
                           .min_by { |expense| [expense[:next], expense[:record]] }
        break unless pending
        template = pending
        active = (template[:payers] + template[:participants]).all? { |person| @members[person[:name]][:active] }
        total = convert(template[:amount], template[:currency])
        if !active || total.zero?
          template[:interval] = 0
          output << "  CANCEL #{template[:id]}"
          next
        end
        template[:copies] += 1
        id = "#{template[:id]}##{template[:copies] + 1}"
        @serial += 1
        copy = template.merge(
          id: id, day: template[:next], record: @serial, total: total,
          payers: template[:payers].map(&:dup), participants: template[:participants].map(&:dup),
          shares: original_shares(template, total),
          contributions: distribute(total, template[:payers].map { |person| person[:value] }),
          interval: 0, next: 0, copies: 0
        )
        @expenses << copy
        @used[id] = true
        template[:next] += template[:interval]
        output << "  RECUR #{id} #{money(total)}"
        output.concat(warning(copy))
      end
      @day = day
    when "MEMBER"
      old = @members[args[0]]
      fail_with("duplicate member #{args[0]}") if old && old[:active]
      @members[args[0]] = { active: true, day: @day }
      output << "MEMBER #{args[0]} #{old ? 'rejoined' : 'joined'}"
    when "LEAVE"
      member(args[0])
      fail_with("member has a balance #{args[0]}") unless balances[args[0]].zero?
      @members[args[0]] = { active: false, day: @day }
      output << "LEAVE #{args[0]}"
    when "CURRENCY"
      old = @currencies[args[0]]
      value = args[1].to_i
      @currencies[args[0]] = value
      output << "CURRENCY #{args[0]} #{rate_text(value)}" + (old ? " was #{rate_text(old)}" : "")
    when "EXPENSE", "EDIT"
      previous = nil
      if name == "EXPENSE"
        fail_with("duplicate id #{args[0]}") if @used[args[0]]
      else
        previous = get_expense(args[0], true)
      end
      expense = prepare(args[0], args[1], args[2], args[3], args[4], args.drop(5), previous)
      if previous
        index = @expenses.index { |item| item.equal?(previous) }
        @expenses[index] = expense
      else
        @serial += 1
        expense[:record] = @serial
        @expenses << expense
        @used[expense[:id]] = true
      end
      shares = expense[:participants].each_with_index.map do |person, i|
        "#{person[:name]} #{money(expense[:shares][i])}"
      end
      output << "#{name} #{expense[:id]} #{money(expense[:total])}#{note(expense)} = " + shares.join(" + ")
      output.concat(warning(expense))
    when "PAYERS"
      expense = get_expense(args[0], true)
      payers = []
      seen = {}
      args.drop(1).each do |part|
        payer, value = part.split(":")
        member(payer)
        fail_with("duplicate member #{payer}") if seen[payer]
        seen[payer] = true
        payers << { name: payer, value: amount(value) }
      end
      fail_with("payers do not add up") unless payers.sum { |person| person[:value] } == expense[:amount]
      expense[:payers] = payers
      expense[:contributions] = distribute(expense[:total], payers.map { |person| person[:value] })
      contributions = payers.each_with_index.map { |person, i| "#{person[:name]} #{money(expense[:contributions][i])}" }
      output << "PAYERS #{expense[:id]} #{money(expense[:total])}#{note(expense)} = " + contributions.join(" + ")
    when "DELETE"
      expense = get_expense(args[0], true)
      @expenses.delete_if { |item| item.equal?(expense) }
      output << "DELETE #{args[0]}"
    when "RECURRING"
      expense = get_expense(args[0])
      interval = args[1].to_i
      expense[:interval] = interval
      expense[:next] = @day + interval
      suffix = interval.positive? ? " interval #{interval} next #{expense[:next]}" : " stopped"
      output << "RECURRING #{args[0]}" + suffix
    when "SETTLE"
      member(args[0])
      member(args[1])
      fail_with("same member #{args[0]}") if args[0] == args[1]
      converted = specification(args[2])
      @serial += 1
      payment = { from: args[0], to: args[1], **converted, day: @day, record: @serial }
      @settlements << payment
      output << "SETTLE #{payment[:from]} -> #{payment[:to]} #{money(payment[:total])}#{note(payment)}"
    when "BUDGET"
      value = amount(args[1])
      if value.positive?
        @budgets[args[0]] = value
      else
        @budgets.delete(args[0])
      end
      output << "BUDGET #{args[0]} " + (value.positive? ? money(value) : "removed")
    when "BALANCES"
      values = balances
      output << "BALANCES"
      output.concat(names(true).map { |person| "  #{person} #{signed(values[person])}" })
    when "OWES", "MATRIX"
      member(args[0], false) if name == "OWES"
      values = debts
      debt = ->(a, b) { values[[a, b]] - values[[b, a]] }
      output << (name == "OWES" ? "OWES #{args[0]}" : "MATRIX")
      if name == "OWES"
        names.reject { |person| person == args[0] }.each do |person|
          value = debt.call(args[0], person)
          if value.positive?
            output << "  #{args[0]} owes #{person} #{money(value)}"
          elsif value.negative?
            output << "  #{person} owes #{args[0]} #{money(-value)}"
          end
        end
      else
        people = names(true)
        if people.empty?
          output << "  (none)"
        else
          cells = people.map { |a| people.map { |b| a == b ? "-" : money([0, debt.call(a, b)].max) } }
          l = people.map(&:length).max
          w = (people + cells.flatten).map(&:length).max
          output << " " * l + people.map { |person| "  " + person.rjust(w) }.join
          people.each_with_index do |person, i|
            output << person.ljust(l) + cells[i].map { |cell| "  " + cell.rjust(w) }.join
          end
        end
      end
    when "HISTORY"
      member(args[0], false)
      person = args[0]
      items = @expenses.select { |expense| involved?(expense, person) }.map do |expense|
        { day: expense[:day], record: expense[:record], label: expense[:id], change: net(expense, person) }
      end
      @settlements.select { |payment| payment[:from] == person || payment[:to] == person }.each do |payment|
        items << {
          day: payment[:day], record: payment[:record], label: "#{payment[:from]}->#{payment[:to]}",
          change: payment[:from] == person ? payment[:total] : -payment[:total]
        }
      end
      items.sort_by! { |item| [item[:day], item[:record]] }
      running = 0
      output << "HISTORY #{person}"
      items.each do |item|
        running += item[:change]
        output << "  day #{item[:day]} #{item[:label]} #{signed(item[:change])} balance #{signed(running)}"
      end
    when "CATEGORY"
      output << "CATEGORY"
      groups = @expenses.group_by { |expense| expense[:category] }
      category_totals = groups.transform_values { |group| group.sum { |expense| expense[:total] } }
      total = category_totals.values.sum
      category_totals.keys.sort_by { |category| [-category_totals[category], category] }.each do |category|
        value = category_totals[category]
        output << "  #{category} #{money(value)} #{percent(value, total)}"
        totals = Hash.new(0)
        groups[category].each do |expense|
          expense[:participants].each_with_index { |person, i| totals[person[:name]] += expense[:shares][i] }
        end
        totals.select { |_, share| share.positive? }.sort_by { |person, share| [-share, person] }.each do |person, share|
          output << "    #{person} #{money(share)} #{percent(share, value)}"
        end
      end
    when "BUDGETS"
      output << "BUDGETS"
      @budgets.keys.sort.each do |category|
        budget = @budgets[category]
        value = spent(category)
        suffix = value <= budget ? " left #{money(budget - value)}" : " over #{money(value - budget)}"
        output << "  #{category} spent #{money(value)} budget #{money(budget)} used #{percent(value, budget)}" + suffix
      end
    when "TOTALS"
      output << "TOTALS"
      names.each do |person|
        paid = 0
        share = 0
        @expenses.each do |expense|
          expense[:payers].each_with_index { |payer, i| paid += expense[:contributions][i] if payer[:name] == person }
          expense[:participants].each_with_index { |part, i| share += expense[:shares][i] if part[:name] == person }
        end
        sent = @settlements.select { |payment| payment[:from] == person }.sum { |payment| payment[:total] }
        received = @settlements.select { |payment| payment[:to] == person }.sum { |payment| payment[:total] }
        output << "  #{person} paid #{money(paid)} share #{money(share)} sent #{money(sent)} received #{money(received)}"
      end
      currencies = @expenses.map { |expense| expense[:currency] }.reject(&:empty?).uniq.sort
      currencies.each do |currency|
        selected = @expenses.select { |expense| expense[:currency] == currency }
        original = selected.sum { |expense| expense[:amount] }
        total = selected.sum { |expense| expense[:total] }
        output << "  currency #{currency} expenses #{selected.length} amount #{money(original)} base #{money(total)}"
      end
      total = @expenses.sum { |expense| expense[:total] }
      settled = @settlements.sum { |payment| payment[:total] }
      output << "  expenses #{@expenses.length} total #{money(total)} settlements #{@settlements.length} total #{money(settled)}"
    when "MEMBERS"
      output << "MEMBERS"
      names.each do |person|
        info = @members[person]
        count = @expenses.count { |expense| involved?(expense, person) }
        output << "  #{person} #{info[:active] ? 'active' : 'left'} day #{info[:day]} expenses #{count}"
      end
    when "EXPENSES"
      member(args[1], false) if args[0] == "MEMBER"
      selected = @expenses.select do |expense|
        args[0] == "ALL" ||
          (args[0] == "CATEGORY" && expense[:category] == args[1]) ||
          (args[0] == "MEMBER" && involved?(expense, args[1])) ||
          (args[0] == "DAYS" && expense[:day].between?(args[1].to_i, args[2].to_i))
      end.sort_by { |expense| [expense[:day], expense[:record]] }
      output << line
      selected.each do |expense|
        payers = expense[:payers].map { |person| person[:name] }.join(",")
        output << "  day #{expense[:day]} #{expense[:id]} #{expense[:category]} #{money(expense[:total])} by #{payers}"
      end
      output << "  count #{selected.length} total #{money(selected.sum { |expense| expense[:total] })}"
    when "PERIODS"
      k = args[0].to_i
      groups = @expenses.group_by { |expense| (expense[:day] - 1).div(k) }
      output << "PERIODS #{k}"
      groups.keys.sort.each do |index|
        group = groups[index]
        total = group.sum { |expense| expense[:total] }
        output << "  days #{index * k + 1}-#{index * k + k} expenses #{group.length} total #{money(total)}"
      end
    when "SHOW"
      expense = get_expense(args[0])
      output << "SHOW #{expense[:id]}"
      output << "  day #{expense[:day]} category #{expense[:category]} mode #{expense[:mode]} total #{money(expense[:total])}#{note(expense)}"
      expense[:payers].each_with_index do |person, i|
        output << "  paid #{person[:name]} #{money(expense[:contributions][i])}"
      end
      units = expense[:participants].sum { |person| person[:value] }
      expense[:participants].each_with_index do |person, i|
        suffix = case expense[:mode]
                 when "EXACT"
                   " " + money(person[:value])
                 when "PERCENT"
                   " " + money(person[:value]) + "%"
                 when "SHARES"
                   " #{person[:value]}/#{units}"
                 when "ADJUST"
                   " +" + money(person[:value])
                 else
                   ""
                 end
        output << "  share #{person[:name]} #{money(expense[:shares][i])}" + suffix
      end
      if expense[:interval].positive?
        output << "  recurring interval #{expense[:interval]} next #{expense[:next]}"
      end
    when "SIMPLIFY"
      return optimal if args[0] == "OPTIMAL"
      transfers = greedy(balances)
      output << "SIMPLIFY GREEDY transfers #{transfers.length}"
      output.concat(transfers.map { |transfer| transfer_text(transfer, "  ") })
    end
    if %w[BALANCES OWES HISTORY CATEGORY BUDGETS MEMBERS PERIODS].include?(name) && output.length == 1
      output << "  (none)"
    end
    output
  end
end

lines = STDIN.read.split("\n")
splitter = Splitter.new
output = []
lines[0].to_i.times do |i|
  begin
    output.concat(splitter.command(lines[i + 1]))
  rescue Invalid => error
    output << "ERROR " + error.message
  end
end
STDOUT.write(output.join("\n") + "\n")
