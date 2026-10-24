require_relative 'bids_io'
require_relative 'wdp_solver'
require_relative 'payments'
require_relative 'auctions'
require_relative 'report'

BID_FORM = /\A[a-z]+(?:\+[a-z]+)*:(?:0|[1-9][0-9]{0,4})\z/
CTR_FORM = /\A[1-9][0-9]*\/[1-9][0-9]*\z/
FORMATS = %w[first_price second_price english dutch all_pay].freeze
OUTCOMES = %w[vcg greedy critical saa].freeze

class CombinatorialAuction
  include Report
  attr_reader :bid_count, :valid, :eligible, :optimal, :exact, :greedy, :saa,
              :vcg_revenue, :critical_revenue

  def initialize(raw, reserves, parameters)
    @name, @items, @reserves, @parameters = raw.name, raw.items, reserves, parameters
    @bidders, @valid, @eligible, @below, @rejected = [], [], [], [], []
    @bid_count = 0
    validate(raw.lines)
    @names = @bidders.map(&:name)
    @optimal = WDPSolver.solve(@items, reserves, @eligible)
    @exact = allocation(@optimal.winning)
    @order = WDPSolver.greedy_order(@eligible)
    @greedy = allocation(WDPSolver.greedy_select(@order))
    @critical = Payments.critical(@order, @greedy.winning, reserves)
    @vcg_details = Payments.vcg(@items, reserves, @eligible, @optimal, @names)
    @values = @names.to_h { |name| [name, @exact.winning.select { |bid| bid.bidder == name }.sum(&:amount)] }
    @greedy_values = @names.to_h { |name| [name, @greedy.winning.select { |bid| bid.bidder == name }.sum(&:amount)] }
    @vcg_paid = @names.to_h { |name| [name, @vcg_details[name]&.first || 0] }
    @vcg_utilities = @names.to_h { |name| [name, @values[name] - @vcg_paid[name]] }
    @critical_paid = @names.to_h do |name|
      [name, @greedy.winning.select { |bid| bid.bidder == name }.sum { |bid| @critical[bid.number][0] }]
    end
    @critical_utilities = @names.to_h { |name| [name, @greedy_values[name] - @critical_paid[name]] }
    @vcg_revenue, @critical_revenue = @vcg_paid.values.sum, @critical_paid.values.sum
    @saa = ascending
  end

  def numbers(values)
    values.empty? ? '-' : values.sort.join('+')
  end

  def allocation(bids)
    winning = bids.sort_by(&:number)
    owners = {}
    winning.each { |bid| bid.bundle.each { |item| owners[item] = bid.bidder } }
    unsold = @items.reject { |item| owners.key?(item) }
    accepted = winning.sum(&:amount)
    retained = unsold.sum { |item| @reserves[item] }
    OpenStruct.new(winning: winning, owners: owners, unsold: unsold,
                   accepted: accepted, retained: retained, welfare: accepted + retained)
  end

  def bid_error(text, bidder)
    return ['malformed bid'] unless BID_FORM.match?(text)
    names_text, amount_text = text.split(':')
    item_names, seen = names_text.split('+'), Set.new
    item_names.each do |name|
      return ["unknown item #{name}"] unless @reserves.key?(name)
      return ["item not offered #{name}"] unless @items.include?(name)
      return ["duplicate item #{name}"] if seen.include?(name)
      seen.add(name)
    end
    return ['bundle too large'] if item_names.size > @parameters['max_bundle_size']
    amount = amount_text.to_i
    return ['zero value'] if amount.zero?
    earlier = bidder.valid.find { |bid| bid.bundle == seen }
    return ["duplicate bundle #{earlier.number}"] if earlier
    return ['too many bids'] if bidder.valid.size >= @parameters['max_bids_per_bidder']
    [nil, seen, amount]
  end

  def validate(lines)
    seen = Set.new
    lines.each do |name, language, strings|
      error = seen.include?(name) ? 'duplicate bidder' : nil
      seen.add(name)
      error ||= "bad language #{language}" unless %w[XOR OR].include?(language)
      bidder = nil
      unless error
        bidder = OpenStruct.new(name: name, language: language, valid: [], eligible: [])
        @bidders << bidder
      end
      strings.each do |text|
        @bid_count += 1
        if error
          @rejected << [@bid_count, name, error]
          next
        end
        reason, items, amount = bid_error(text, bidder)
        if reason
          @rejected << [@bid_count, name, reason]
          next
        end
        bid = Bid.new(@bid_count, name, items, amount, language == 'XOR')
        bidder.valid << bid
        @valid << bid
        reserve = items.sum { |item| @reserves[item] }
        if amount >= reserve
          bidder.eligible << bid
          @eligible << bid
        else
          @below << [bid, reserve]
        end
      end
    end
  end

  def ascending
    increment = @parameters['saa_increment']
    choices = @bidders.to_h { |bidder| [bidder.name, Auctions.candidates(bidder.valid, bidder.language == 'XOR')] }
    eligibility = @names.to_h { |name| [name, choices[name].map { |candidate| candidate.bundle.size }.max || 0] }
    prices = @items.to_h { |item| [item, @reserves[item]] }
    holders = @items.to_h { |item| [item, nil] }
    bid_counts, bid_rounds, last_rounds = Hash.new(0), Hash.new(0), Hash.new(0)
    state = @parameters['seed']
    lines = ["AUCTION #{@name} increment #{increment}"]
    round_number, reason = 0, nil
    1.upto(@parameters['round_cap']) do |round|
      round_number = round
      activities, new_by_bidder = {}, {}
      new_by_item = @items.to_h { |item| [item, []] }
      @names.each do |name|
        held = @items.select { |item| holders[item] == name }.to_set
        asking = @items.to_h { |item| [item, prices[item] + (holders[item] && holders[item] != name ? increment : 0)] }
        chosen, surplus = nil, 0
        choices[name].each do |candidate|
          next if (candidate.bundle | held).size > eligibility[name]
          candidate_surplus = candidate.value - candidate.bundle.sum { |item| asking[item] }
          chosen, surplus = candidate, candidate_surplus if candidate_surplus > surplus
        end
        demanded = chosen ? chosen.bundle : Set.new
        activities[name] = (demanded | held).size
        new_by_bidder[name] = demanded - held
        @items.each { |item| new_by_item[item] << name if new_by_bidder[name].include?(item) }
      end
      demand = new_by_bidder.values.sum(&:size)
      if demand.positive?
        lines << "ROUND #{round} demand #{demand}" + @names.filter_map { |name| " #{name}:#{bundle(new_by_bidder[name], @items)}" unless new_by_bidder[name].empty? }.join
        @items.each do |item|
          bidders = new_by_item[item]
          next if bidders.empty?
          if bidders.size >= 2
            state = 48_271 * state % 2_147_483_647
            winner = bidders[state % bidders.size]
          else
            winner = bidders.first
          end
          prices[item] += increment if holders[item]
          holders[item] = winner
          bid_counts[item] += bidders.size
          bid_rounds[item] += 1
          last_rounds[item] = round
        end
        lines << 'STANDING' + @items.map { |item| " #{item}=#{prices[item]}@#{holders[item] || '-'}" }.join
      else
        lines << "ROUND #{round} none"
      end
      changed = @names.filter_map do |name|
        next unless activities[name] < eligibility[name]
        eligibility[name] = activities[name]
        "#{name}=#{eligibility[name]}"
      end
      lines << "ELIGIBILITY #{changed.join(' ')}" unless changed.empty?
      if demand.zero? || round == @parameters['round_cap']
        reason = demand.zero? ? 'quiet' : 'cap'
        break
      end
    end
    lines << "END rounds #{round_number} #{reason}"
    @items.each do |item|
      lines << if holders[item]
                 "ITEM #{item} price #{prices[item]} holder #{holders[item]} bids #{bid_counts[item]} rounds #{bid_rounds[item]} last #{last_rounds[item]}"
               else
                 "ITEM #{item} unsold reserve #{@reserves[item]}"
               end
    end
    payments, utilities = {}, {}
    values_total = exposure = exposed = 0
    @names.each do |name|
      won = @items.select { |item| holders[item] == name }.to_set
      paid = won.sum { |item| prices[item] }
      value = Auctions.value_of(choices[name], won)
      utility = value - paid
      payments[name], utilities[name] = paid, utility
      values_total += value
      if utility.negative?
        exposure -= utility
        exposed += 1
      end
      lines << "BIDDER #{name} won #{bundle(won, @items)} paid #{paid} value #{value} utility #{utility} eligibility #{eligibility[name]}" + (utility.negative? ? ' exposed' : '')
    end
    revenue = payments.values.sum
    retained = @items.reject { |item| holders[item] }.sum { |item| @reserves[item] }
    welfare = values_total + retained
    efficiency = Rational(welfare, @exact.welfare)
    lines << "TOTAL revenue #{revenue} welfare #{welfare} efficiency #{fraction(efficiency)} exposure #{exposure} exposed #{exposed}"
    OpenStruct.new(lines: lines, payments: payments, utilities: utilities, revenue: revenue, retained: retained,
                   welfare: welfare, efficiency: efficiency, rounds: round_number, reason: reason, exposure: exposure, exposed: exposed)
  end

  def wdp_report
    lines = ["AUCTION #{@name} items #{@items.size} bidders #{@bidders.size} bids #{@bid_count} valid #{@valid.size} eligible #{@eligible.size}"]
    @bidders.each { |bidder| lines << "BIDDER #{bidder.name} #{bidder.language} valid #{bidder.valid.size} eligible #{bidder.eligible.size}" }
    @rejected.each { |number, name, reason| lines << "REJECT #{number} #{name} #{reason}" }
    @below.each { |bid, reserve| lines << "BELOW_RESERVE #{bid.number} #{bid.bidder} value #{bid.amount} reserve #{reserve}" }
    @optimal.shares.each { |item, share, source| lines << "SHARE #{item} #{fraction(share)} #{source ? "bid #{source}" : 'reserve'}" }
    lines << "ROOT_BOUND #{fraction(@optimal.bound)}"
    @optimal.improvements.each { |nodes, welfare, chosen| lines << "IMPROVE #{nodes} welfare #{welfare} bids #{numbers(chosen)}" }
    lines << "OPTIMAL welfare #{@exact.welfare} accepted #{@exact.accepted} retained #{@exact.retained} winners #{@exact.winning.size}"
    @exact.winning.each { |bid| lines << "WIN #{bid.number} #{bid.bidder} #{bundle(bid.bundle, @items)} #{bid.amount}" }
    lines << "UNSOLD #{@exact.unsold.empty? ? '-' : @exact.unsold.join(' ')}"
    lines << "SEARCH nodes #{@optimal.nodes} pruned #{@optimal.pruned} leaves #{@optimal.leaves} improvements #{@optimal.improvements.size}"
    lines << "GREEDY_ORDER #{@order.empty? ? '-' : @order.map(&:number).join(' ')}"
    lines << "GREEDY welfare #{@greedy.welfare} accepted #{@greedy.accepted} retained #{@greedy.retained} winners #{@greedy.winning.size} efficiency #{fraction(Rational(@greedy.welfare, @exact.welfare))}"
    @greedy.winning.each do |bid|
      critical, rival = @critical[bid.number]
      lines << "GWIN #{bid.number} #{bid.bidder} #{bundle(bid.bundle, @items)} #{bid.amount} critical #{critical} against #{rival ? rival.number : '-'}"
    end
    lines << "GUNSOLD #{@greedy.unsold.empty? ? '-' : @greedy.unsold.join(' ')}"
    @items.each do |item|
      demand = @eligible.count { |bid| bid.bundle.include?(item) }
      lines << "ITEM #{item} reserve #{@reserves[item]} demand #{demand} optimal #{@exact.owners[item] || '-'} greedy #{@greedy.owners[item] || '-'}"
    end
    lines
  end

  def vcg_report
    lines = ["AUCTION #{@name} welfare #{@exact.welfare}"]
    @names.each do |name|
      unless @vcg_details.key?(name)
        lines << "BIDDER #{name} lost"
        next
      end
      paid, alternative = @vcg_details[name]
      won = @exact.winning.select { |bid| bid.bidder == name }.map(&:number)
      lines << "BIDDER #{name} won #{numbers(won)} value #{@values[name]} without #{alternative.welfare} alternative #{numbers(alternative.numbers)} payment #{paid} utility #{@vcg_utilities[name]}"
    end
    lines << "TOTAL revenue #{@vcg_revenue} pay_as_bid #{@exact.accepted} retained #{@exact.retained} seller #{@vcg_revenue + @exact.retained} bidders #{@vcg_utilities.values.sum}"
    @names.each { |name| lines << "PAYMENTS #{name} vcg #{@vcg_paid[name]} pay_as_bid #{@values[name]} greedy #{@greedy_values[name]} critical #{@critical_paid[name]} saa #{@saa.payments[name]}" }
    @names.each { |name| lines << "UTILITIES #{name} vcg #{@vcg_utilities[name]} critical #{@critical_utilities[name]} saa #{@saa.utilities[name]}" }
    lines
  end

  def core_report
    lines, counts = ["AUCTION #{@name} bidders #{@bidders.size}"], Hash.new(0)
    if @bidders.size > @parameters['core_max_bidders']
      lines << 'SKIPPED'
      counts['skipped'] = 1
      return [lines, counts]
    end
    counts['checked'] = 1
    coalitions = Payments.coalitions(@items, @reserves, @eligible, @names)
    lines << "COALITIONS #{coalitions.size}"
    outcomes = [['vcg', @vcg_revenue + @exact.retained, @vcg_utilities],
                ['greedy', @greedy.welfare, @names.to_h { |name| [name, 0] }],
                ['critical', @critical_revenue + @greedy.retained, @critical_utilities],
                ['saa', @saa.revenue + @saa.retained, @saa.utilities]]
    outcomes.each do |name, seller, utilities|
      lines << "OUTCOME #{name} seller #{seller} utilities #{@names.map { |bidder| utilities[bidder] }.join(' ')}"
      blocked, minimal = Payments.blocking(coalitions, seller, utilities)
      minimal.each do |record|
        coalition = record.coalition
        members = coalition.members.empty? ? '-' : coalition.members.join('+')
        lines << "BLOCK #{members} welfare #{coalition.welfare} payoff #{record.payoff} deficit #{record.deficit} bids #{numbers(coalition.numbers)}"
      end
      if blocked.empty?
        lines << 'RESULT core'
        counts[name] += 1
      else
        worst = blocked.each_with_index.min_by { |record, index| [-record.deficit, index] }.first
        members = worst.coalition.members.empty? ? '-' : worst.coalition.members.join('+')
        lines << "RESULT blocked #{blocked.size} minimal #{minimal.size} max_deficit #{worst.deficit} by #{members}"
      end
    end
    [lines, counts]
  end
end

class Laboratory
  include Report

  def initialize
    @reserves, @raw_auctions, @groups, @parameters = BidsIO.read_inputs
    @wdp_lines, @vcg_lines, @core_lines, @ascending_lines, @single_lines = [], [], [], [], []
    @summary_lines = ['mechanism,revenue,welfare,efficiency']
    @wdp_totals, @vcg_totals, @core_totals, @ascending_totals, @group_totals = Array.new(5) { Hash.new(0) }
  end

  def summary_row(name, mechanism, revenue, welfare, efficiency)
    @summary_lines << "#{name}/#{mechanism},#{fraction(revenue)},#{fraction(welfare)},#{fraction(efficiency)}"
  end

  def add_counts(totals, values)
    values.each { |key, value| totals[key] += value }
  end

  def process_auctions
    @parameters['run'].each do |name|
      auction = CombinatorialAuction.new(@raw_auctions[name], @reserves, @parameters)
      @wdp_lines.concat(auction.wdp_report)
      @vcg_lines.concat(auction.vcg_report)
      core_lines, counts = auction.core_report
      @core_lines.concat(core_lines)
      add_counts(@core_totals, counts)
      @ascending_lines.concat(auction.saa.lines)
      add_counts(@wdp_totals, 'auctions' => 1, 'bids' => auction.bid_count, 'valid' => auction.valid.size,
                 'eligible' => auction.eligible.size, 'nodes' => auction.optimal.nodes,
                 'greedy_optimal' => auction.greedy.welfare == auction.exact.welfare ? 1 : 0)
      revenues = {'vcg' => auction.vcg_revenue, 'pay_as_bid' => auction.exact.accepted,
                  'greedy' => auction.greedy.accepted, 'critical' => auction.critical_revenue, 'saa' => auction.saa.revenue}
      add_counts(@vcg_totals, revenues)
      add_counts(@ascending_totals, 'auctions' => 1, 'rounds' => auction.saa.rounds,
                 'capped' => auction.saa.reason == 'cap' ? 1 : 0, 'exposed' => auction.saa.exposed, 'exposure' => auction.saa.exposure)
      revenues.each do |mechanism, revenue|
        welfare = if %w[vcg pay_as_bid].include?(mechanism)
                    auction.exact.welfare
                  elsif mechanism == 'saa'
                    auction.saa.welfare
                  else
                    auction.greedy.welfare
                  end
        summary_row(name, mechanism, revenue, welfare, Rational(welfare, auction.exact.welfare))
      end
    end
  end

  def duplicate_name(participants)
    seen = Set.new
    participants.each do |participant|
      return participant.name if seen.include?(participant.name)
      seen.add(participant.name)
    end
    nil
  end

  def validate_lot(group)
    return 'no bidders' if group.participants.empty?
    duplicate = duplicate_name(group.participants)
    return "duplicate bidder #{duplicate}" if duplicate
    above = group.participants.find { |participant| participant.bid > participant.value }
    "bid above value #{above.name}" if above
  end

  def validate_slots(group)
    rates = []
    group.arguments.each do |text|
      return ["bad ctr #{text}", nil] unless CTR_FORM.match?(text)
      numerator, denominator = text.split('/').map(&:to_i)
      rate = Rational(numerator, denominator)
      return ["bad ctr #{text}", nil] if rate > 1 || (!rates.empty? && rate >= rates.last)
      rates << rate
    end
    return ['no advertisers', nil] if group.participants.empty?
    duplicate = duplicate_name(group.participants)
    return ["duplicate advertiser #{duplicate}", nil] if duplicate
    [nil, rates]
  end

  def lot(group)
    participants, reserve = group.participants, group.arguments.first.to_i
    eligible = participants.each_index.select { |index| participants[index].bid >= reserve }
    first = eligible.min_by { |index| [-participants[index].bid, index] }
    efficient = participants.each_index.min_by { |index| [-participants[index].value, index] }
    optimum = [reserve, participants[efficient].value].max
    efficient = nil if participants[efficient].value < reserve
    lines = ["LOT #{group.name} reserve #{reserve} bidders #{participants.size} efficient #{efficient ? participants[efficient].name : '-'} optimum #{optimum}"]
    first_price = first ? participants[first].bid : 0
    second_price = efficient ? ([reserve] + participants.each_index.filter_map { |index| participants[index].value if index != efficient && participants[index].value >= reserve }).max : 0
    ascending = Auctions.english(participants, reserve, @parameters['english_increment'])
    descending = Auctions.dutch(participants, reserve, @parameters['dutch_start'], @parameters['dutch_decrement'])
    mechanisms = [[first, first_price, nil], [efficient, second_price, nil],
                  [ascending.winner, ascending.price, ascending.steps], [descending.winner, descending.price, descending.steps],
                  [first, first_price, nil]]
    results = []
    FORMATS.zip(mechanisms).each do |name, (winner, price, steps)|
      utilities = Array.new(participants.size, 0)
      revenue = price
      if name == 'all_pay'
        revenue = eligible.sum { |index| participants[index].bid }
        eligible.each { |index| utilities[index] = -participants[index].bid }
      end
      if winner.nil?
        welfare = reserve
        line = "#{name.upcase} unsold"
      else
        utilities[winner] = participants[winner].value - price
        welfare = participants[winner].value
        line = "#{name.upcase} winner #{participants[winner].name} price #{price} utility #{utilities[winner]}"
      end
      line += " steps #{steps}" unless steps.nil?
      efficiency = Rational(welfare, optimum)
      lines << line + " revenue #{revenue} welfare #{welfare} efficiency #{fraction(efficiency)}"
      if name == 'english'
        lines << 'ENGLISH_DROPS' + participants.zip(ascending.drops).map { |participant, drop| " #{participant.name}=#{drop || '-'}" }.join
      end
      results << OpenStruct.new(name: name, utilities: utilities, revenue: revenue)
      summary_row(group.name, name, revenue, welfare, efficiency)
    end
    participants.each_with_index { |participant, index| lines << "UTILITY #{participant.name} #{results.map { |result| result.utilities[index] }.join(' ')}" }
    ranking = results.each_with_index.sort_by { |result, index| [-result.revenue, index] }.map { |result, _| result.name }
    lines << "RANKING #{ranking.join(' ')}"
    lines
  end

  def slots(group, rates)
    ranked_bids = group.participants.each_with_index.sort_by { |participant, index| [-participant.bid, index] }.map(&:first)
    ranked_values = group.participants.each_with_index.sort_by { |participant, index| [-participant.value, index] }.map(&:first)
    count, slot_count = group.participants.size, rates.size
    lines = ["SLOTS #{group.name} slots #{slot_count} advertisers #{count}"]
    gsp_revenue = gsp_welfare = vcg_revenue = optimum = Rational(0)
    [count, slot_count].min.times do |rank|
      bidder, rate = ranked_bids[rank], rates[rank]
      price = Payments.gsp_price(ranked_bids, rank)
      payment, utility = rate * price, rate * (bidder.value - price)
      gsp_revenue += payment
      gsp_welfare += rate * bidder.value
      optimum += rate * ranked_values[rank].value
      lines << "GSP #{rank + 1} #{bidder.name} ctr #{fraction(rate)} bid #{bidder.bid} price #{price} payment #{fraction(payment)} utility #{fraction(utility)}"
    end
    efficiency = gsp_welfare / optimum
    lines << "GSP_TOTAL revenue #{fraction(gsp_revenue)} welfare #{fraction(gsp_welfare)} efficiency #{fraction(efficiency)}"
    [count, slot_count].min.times do |rank|
      bidder, rate = ranked_values[rank], rates[rank]
      payment = Payments.slot_vcg(ranked_values, rates, rank)
      vcg_revenue += payment
      lines << "VCG #{rank + 1} #{bidder.name} ctr #{fraction(rate)} value #{bidder.value} payment #{fraction(payment)} price #{fraction(payment / rate)} utility #{fraction(rate * bidder.value - payment)}"
    end
    lines << "VCG_TOTAL revenue #{fraction(vcg_revenue)} welfare #{fraction(optimum)} efficiency 1"
    violations = 0
    (1...[count, slot_count + 1].min).each do |rank|
      bidder = ranked_bids[rank]
      stay = (rates[rank] || 0) * (bidder.value - Payments.gsp_price(ranked_bids, rank))
      swap = rates[rank - 1] * (bidder.value - bidder.bid)
      violated = stay < swap
      violations += 1 if violated
      lines << "ENVY #{rank + 1} #{bidder.name} stay #{fraction(stay)} swap #{fraction(swap)} #{violated ? 'violated' : 'ok'}"
    end
    lines << (violations.zero? ? 'ENVY_FREE yes' : "ENVY_FREE no violations #{violations}")
    deviations = 0
    ranked_bids.each_with_index do |bidder, rank|
      current = (rates[rank] || 0) * (bidder.value - Payments.gsp_price(ranked_bids, rank))
      slot_count.times do |target|
        next if target == rank
        price = target < rank ? (ranked_bids[target]&.bid || 0) : Payments.gsp_price(ranked_bids, target)
        payoff = rates[target] * (bidder.value - price)
        next unless payoff > current
        deviations += 1
        lines << "DEVIATE #{bidder.name} from #{rank + 1} to #{target + 1} gain #{fraction(payoff - current)}"
      end
    end
    lines << (deviations.zero? ? 'NASH yes' : "NASH no deviations #{deviations}")
    equilibrium = violations.zero? && deviations.zero?
    lines << "EQUILIBRIUM #{equilibrium ? 'yes' : 'no'}"
    add_counts(@group_totals, 'envy_free' => violations.zero? ? 1 : 0, 'nash' => deviations.zero? ? 1 : 0, 'equilibria' => equilibrium ? 1 : 0)
    summary_row(group.name, 'gsp', gsp_revenue, gsp_welfare, efficiency)
    summary_row(group.name, 'vcg', vcg_revenue, optimum, 1)
    lines
  end

  def process_groups
    @groups.each do |group|
      @group_totals[group.kind == 'lot' ? 'lots' : 'slot_groups'] += 1
      error, rates = group.kind == 'lot' ? [validate_lot(group), nil] : validate_slots(group)
      if error
        @single_lines << "#{group.kind.upcase} #{group.name} ERROR #{error}"
        @group_totals['errors'] += 1
      else
        @single_lines.concat(group.kind == 'lot' ? lot(group) : slots(group, rates))
      end
    end
  end

  def total_lines
    @wdp_lines << 'TOTAL' + %w[auctions bids valid eligible nodes greedy_optimal].map { |key| " #{key} #{@wdp_totals[key]}" }.join
    @vcg_lines << 'OVERALL' + %w[vcg pay_as_bid greedy critical saa].map { |key| " #{key} #{@vcg_totals[key]}" }.join
    @core_lines << 'SUMMARY' + %w[checked skipped vcg greedy critical saa].map { |key| " #{key} #{@core_totals[key]}" }.join
    @ascending_lines << 'SUMMARY' + %w[auctions rounds capped exposed exposure].map { |key| " #{key} #{@ascending_totals[key]}" }.join
    @single_lines << 'SUMMARY' + %w[lots slot_groups errors envy_free nash equilibria].map { |key| " #{key} #{@group_totals[key]}" }.join
  end

  def run
    process_auctions
    process_groups
    total_lines
    write_reports('wdp.txt' => @wdp_lines, 'vcg.txt' => @vcg_lines, 'core_check.txt' => @core_lines,
                  'ascending_log.txt' => @ascending_lines, 'single_item.txt' => @single_lines, 'summary.csv' => @summary_lines)
  end
end

Laboratory.new.run if $PROGRAM_NAME == __FILE__
