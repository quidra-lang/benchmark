require_relative 'items'
require_relative 'bom'
require_relative 'lot_sizing'
require_relative 'capacity'
require_relative 'costing'
require_relative 'report'

class MRPPlanner
  DEMAND_ORDER = { MPS: 0, ORDER: 1, DEPENDENT: 2 }.freeze
  ROOT_ORDER = { MPS: 0, ORDER: 1, SAFETY: 2 }.freeze
  EXCEPTION_ORDER = %w[below_safety past_due release expedite defer cancel no_routing no_demand overload].freeze

  def initialize
    parameters = File.readlines('input/params.txt', chomp: true).map { |line| line.split(' ') }
    @horizon = parameters[0][1].to_i
    @pegged = parameters[1].drop(1)
    @tree_quantity = parameters[2][1].to_i
    @errors = []
    @items = Items.read(@errors)
    @bom = Bom::Structure.new(@items, @errors)
    @centers = Capacity.read_centers(@errors)
    @routings = Capacity.read_routings(@items, @bom, @centers, @errors)
    @mps = read_weekly('mps.csv', true)
    @receipts = read_weekly('receipts.csv', false)
    @inquiries = read_inquiries
    @receipts_by_item = @items.to_h { |id, _item| [id, []] }
    @receipts.each { |receipt| @receipts_by_item[receipt[:item]] << receipt }
    @receipts_by_item.each_value { |rows| rows.sort_by! { |row| [row[:week], row[:line]] } }
    @order = @bom.order
    @center_ids = @centers.keys.sort
  end

  def run
    @base = run_mrp([])
    @plan, @promises = promise_orders(@base)
    allocate_supplies
    collect_roots
    @costs = Costing.rollup(@items, @bom, @plan)
    Report.write('mrp_grid.txt', grid_lines)
    Report.write('pegging.txt', pegging_lines)
    Report.write('bom_tree.txt', tree_lines)
    Report.write('cost_rollup.csv', cost_lines)
    Report.write('exceptions.txt', exception_lines)
    Report.write('capacity.txt', capacity_lines)
    Report.write('promises.txt', promise_lines)
    Report.write('releases.txt', release_lines)
    Report.write('value_plan.csv', value_lines)
  end

  private

  def read_weekly(filename, unique)
    accepted = []
    seen = {}
    File.readlines("input/#{filename}", chomp: true).drop(1).each_with_index do |line, index|
      item, week, quantity = line.split(',')
      week = week.to_i
      quantity = quantity.to_i
      message = if !@items.key?(item)
                  "unknown item #{item}"
                elsif week < 1 || week > @horizon
                  "week #{week} outside horizon"
                elsif quantity < 1
                  "bad quantity #{quantity}"
                elsif unique && seen[[item, week]]
                  "duplicate #{item} week #{week}"
                end
      if message
        @errors << "#{filename} line #{index + 2}: #{message}"
        next
      end
      seen[[item, week]] = true
      accepted << { item: item, week: week, quantity: quantity, line: index + 2 }
    end
    accepted
  end

  def read_inquiries
    accepted = []
    seen = {}
    File.readlines('input/orders.csv', chomp: true).drop(1).each_with_index do |line, index|
      id, item, quantity, week = line.split(',')
      quantity = quantity.to_i
      week = week.to_i
      message = if seen[id]
                  "duplicate order #{id}"
                elsif !@items.key?(item)
                  "unknown item #{item}"
                elsif week < 1 || week > @horizon
                  "week #{week} outside horizon"
                elsif quantity < 1
                  "bad quantity #{quantity}"
                end
      if message
        @errors << "orders.csv line #{index + 2}: #{message}"
        next
      end
      seen[id] = true
      accepted << { id: id, item: item, quantity: quantity, week: week, line: index + 2 }
    end
    accepted
  end

  def empty_item_plan
    row = { demands: [], orders: [], past_due: 0 }
    %i[gross receipts on_hand net planned releases].each do |field|
      row[field] = Array.new(@horizon + 1, 0)
    end
    row
  end

  def run_mrp(promised)
    rows = @items.to_h { |id, _item| [id, empty_item_plan] }
    @mps.each { |demand| rows[demand[:item]][:demands] << demand.merge(kind: :MPS) }
    promised.each do |inquiry, week|
      rows[inquiry[:item]][:demands] << inquiry.merge(kind: :ORDER, week: week)
    end
    @order.each do |id|
      item = @items[id]
      row = rows[id]
      row[:demands].each { |demand| row[:gross][demand[:week]] += demand[:quantity] }
      @receipts_by_item[id].each { |receipt| row[:receipts][receipt[:week]] += receipt[:quantity] }
      row[:on_hand][0] = item.on_hand
      1.upto(@horizon) do |week|
        balance = row[:on_hand][week - 1] + row[:receipts][week] - row[:gross][week]
        if balance < item.safety
          net = item.safety - balance
          quantity = LotSizing.size(item, net, balance, week, row[:receipts], row[:gross], @horizon)
          original = week - item.lead_time
          release = [1, original].max
          row[:orders] << { item: id, number: row[:orders].length + 1, receipt: week,
                            quantity: quantity, original: original, release: release }
          row[:net][week] = net
          row[:planned][week] = quantity
          row[:releases][release] += quantity
          row[:past_due] += quantity if original < 1
          balance += quantity
        end
        row[:on_hand][week] = balance
      end
      row[:orders].each do |order|
        @bom.children[id].each do |edge|
          rows[edge.child][:demands] << { item: edge.child, kind: :DEPENDENT,
                                         week: order[:release], quantity: Bom.need(edge, order[:quantity]),
                                         parent: id, number: order[:number] }
        end
      end
    end
    loads = @center_ids.to_h { |id| [id, Array.new(@horizon + 1, 0)] }
    @order.each do |id|
      operations = @routings[id]
      rows[id][:orders].each do |order|
        operations.each_with_index do |operation, index|
          week = Capacity.week(order[:receipt], @items[id].lead_time, index, operations.length)
          loads[operation.center][week] += operation.setup + order[:quantity] * operation.run
        end
      end
    end
    overloads = @center_ids.to_h do |id|
      [id, loads[id].map { |load| [0, load - @centers[id].available].max }]
    end
    { items: rows, loads: loads, overloads: overloads }
  end

  def capacity_reason(trial, current)
    @center_ids.each do |id|
      1.upto(@horizon) do |week|
        return "#{id} week #{week}" if trial[:overloads][id][week] > current[:overloads][id][week]
      end
    end
    nil
  end

  def promise_orders(base)
    current = base
    promised = []
    results = []
    @inquiries.each do |inquiry|
      result = { inquiry: inquiry, promised: nil, material: nil, reason: nil }
      inquiry[:week].upto(@horizon) do |week|
        trial = run_mrp(promised + [[inquiry, week]])
        reason = @order.find { |id| trial[:items][id][:past_due] > current[:items][id][:past_due] }
        if reason.nil?
          result[:material] ||= week
          reason = capacity_reason(trial, current)
        end
        result[:reason] = reason if week == inquiry[:week]
        next if reason

        result[:promised] = week
        promised << [inquiry, week]
        current = trial
        break
      end
      results << result
    end
    [current, results]
  end

  def demand_key(demand)
    [demand[:week], DEMAND_ORDER[demand[:kind]], demand[:kind] == :ORDER ? demand[:line] : 0,
     demand[:parent] || '', demand[:number] || 0]
  end

  def allocate_supplies
    @order.each do |id|
      item = @items[id]
      row = @plan[:items][id]
      supplies = @receipts_by_item[id].map { |receipt| receipt.merge(kind: :RECEIPT) }
      row[:orders].each { |order| order[:kind] = :PLANNED }
      supplies.concat(row[:orders])
      supplies.sort_by! do |supply|
        [supply[:week] || supply[:receipt], supply[:kind] == :RECEIPT ? 0 : 1,
         supply[:line] || supply[:number]]
      end
      if item.on_hand > 0
        supplies.unshift({ item: id, kind: :STOCK, quantity: item.on_hand })
      end
      supplies.each do |supply|
        supply[:remaining] = supply[:quantity]
        supply[:allocations] = []
      end
      demands = row[:demands].sort_by { |demand| demand_key(demand) }
      if item.safety > 0
        demands.unshift({ item: id, kind: :SAFETY, quantity: item.safety })
      end
      supply_index = 0
      demands.each do |demand|
        remaining = demand[:quantity]
        while remaining > 0
          supply_index += 1 while supplies[supply_index][:remaining].zero?
          supply = supplies[supply_index]
          share = [remaining, supply[:remaining]].min
          supply[:allocations] << [demand, share]
          remaining -= share
          supply[:remaining] -= share
        end
      end
      row[:supplies] = supplies
    end
  end

  def root_key(demand)
    [demand[:item], ROOT_ORDER[demand[:kind]], demand[:week] || 0, demand[:id] || '']
  end

  def parent_order(demand)
    @plan[:items][demand[:parent]][:orders][demand[:number] - 1]
  end

  def collect_roots
    @order.each do |id|
      @plan[:items][id][:orders].each do |order|
        roots = {}
        order[:allocations].each do |demand, _share|
          inherited = demand[:kind] == :DEPENDENT ? parent_order(demand)[:roots] : [demand]
          inherited.each { |root| roots[root_key(root)] = root }
        end
        order[:roots] = roots.sort_by { |key, _root| key }.map { |_key, root| root }
      end
    end
  end

  def grid_lines
    lines = []
    @order.each do |id|
      item = @items[id]
      row = @plan[:items][id]
      lot = item.rule
      lot += " #{item.lot.join('/')}" unless item.rule == 'LFL'
      lines << "ITEM #{id} LLC #{@bom.low_level[id]} LT #{item.lead_time} LOT #{lot} SS #{item.safety} OH #{item.on_hand} #{item.description}"
      lines << Report.table('WEEK', (1..@horizon).to_a, 6)
      { 'GROSS' => :gross, 'RECEIPTS' => :receipts, 'ON_HAND' => :on_hand,
        'NET' => :net, 'PLAN_RCPT' => :planned, 'PLAN_REL' => :releases }.each do |label, field|
        lines << Report.table(label, row[field].drop(1), 6)
      end
      lines << "TOTAL gross #{row[:gross].sum} receipts #{row[:receipts].sum} planned #{row[:planned].sum} orders #{row[:orders].length} ending #{row[:on_hand][@horizon]}"
    end
    lines
  end

  def where_used(id, depth, cumulative, lines)
    @bom.parents[id].each do |edge|
      extended = cumulative * edge.quantity
      lines << "#{'.' * depth}#{depth} #{edge.parent} qty #{edge.quantity} ext #{extended}"
      where_used(edge.parent, depth + 1, extended, lines)
    end
  end

  def allocation_lines(supply, depth, recursive, lines)
    supply[:allocations].each do |demand, share|
      detail = case demand[:kind]
               when :SAFETY then "SAFETY #{demand[:item]}"
               when :MPS then "MPS #{demand[:item]} week #{demand[:week]}"
               when :ORDER then "ORDER #{demand[:id]} #{demand[:item]} week #{demand[:week]}"
               when :DEPENDENT then "#{demand[:parent]} order #{demand[:number]} week #{demand[:week]}"
               end
      lines << "#{' ' * (depth * 2)}ALLOC #{share} #{detail}"
      if recursive && demand[:kind] == :DEPENDENT
        allocation_lines(parent_order(demand), depth + 1, true, lines)
      end
    end
  end

  def supply_lines(supply, recursive, lines)
    header = case supply[:kind]
             when :STOCK then "STOCK quantity #{supply[:quantity]}"
             when :RECEIPT then "RECEIPT line #{supply[:line]} week #{supply[:week]} quantity #{supply[:quantity]}"
             when :PLANNED then "ORDER #{supply[:number]} receipt #{supply[:receipt]} release #{supply[:release]} quantity #{supply[:quantity]}"
             end
    lines << header
    allocation_lines(supply, 1, recursive, lines)
    lines << "  EXCESS #{supply[:remaining]}" if supply[:remaining] > 0
  end

  def pegging_lines
    lines = []
    @pegged.each do |id|
      row = @plan[:items][id]
      lines << "PEG #{id} orders #{row[:orders].length}"
      where_used(id, 1, 1, lines)
      row[:supplies].each do |supply|
        supply_lines(supply, false, lines) unless supply[:kind] == :PLANNED
      end
      row[:orders].each do |order|
        supply_lines(order, true, lines)
        order[:roots].each do |root|
          detail = case root[:kind]
                   when :SAFETY then "SAFETY #{root[:item]}"
                   when :MPS then "MPS #{root[:item]} week #{root[:week]}"
                   when :ORDER then "ORDER #{root[:id]} #{root[:item]} week #{root[:week]}"
                   end
          lines << "  ROOT #{detail}"
        end
      end
    end
    lines
  end

  def explode_tree(id, quantity, cumulative, depth, totals, lines)
    @bom.children[id].each do |edge|
      item = @items[edge.child]
      extended = cumulative * edge.quantity
      gross = Bom.need(edge, quantity)
      totals[edge.child] += gross
      lines << "#{'.' * depth}#{depth} #{edge.child} qty #{edge.quantity} scrap #{edge.scrap} ext #{extended} gross #{gross} lt #{item.lead_time} cum #{@bom.cumulative[edge.child]} #{item.description}"
      explode_tree(edge.child, gross, extended, depth + 1, totals, lines)
    end
  end

  def tree_lines
    lines = []
    @items.keys.sort.each do |id|
      next unless @bom.manufactured?(id) && @bom.parents[id].empty?

      item = @items[id]
      lines << "TREE #{id} quantity #{@tree_quantity}"
      lines << "0 #{id} ext 1 gross #{@tree_quantity} lt #{item.lead_time} cum #{@bom.cumulative[id]} #{item.description}"
      totals = Hash.new(0)
      explode_tree(id, @tree_quantity, 1, 1, totals, lines)
      totals.keys.sort.each { |child| lines << "SUM #{child} #{totals[child]}" }
      path = [id]
      while @bom.manufactured?(path[-1])
        edge = @bom.children[path[-1]].min_by { |row| [-@bom.cumulative[row.child], row.child] }
        path << edge.child
      end
      lines << "CRITICAL #{path.join(' -> ')} cum #{@bom.cumulative[id]}"
    end
    lines
  end

  def cost_lines
    lines = ['item,material,labor,total,usage,value,class']
    @items.keys.sort.each do |id|
      cost = @costs[id]
      lines << [id, Report.money(cost.material), Report.money(cost.labor), Report.money(cost.total),
                cost.usage, Report.money(cost.value), cost.classification].join(',')
    end
    lines
  end

  def exception_lines
    lines = @errors.map { |error| "ERROR #{error}" }
    counts = Hash.new(0)
    add = lambda do |kind, detail|
      counts[kind] += 1
      lines << "#{kind.upcase} #{detail}"
    end
    @order.each do |id|
      item = @items[id]
      row = @plan[:items][id]
      add.call('below_safety', "#{id} on hand #{item.on_hand} safety #{item.safety}") if item.on_hand < item.safety
      row[:orders].each do |order|
        prefix = "#{id} order #{order[:number]} receipt #{order[:receipt]}"
        if order[:original] < 1
          add.call('past_due', "#{prefix} release #{order[:original]} late #{1 - order[:original]} quantity #{order[:quantity]}")
        elsif order[:original] == 1
          add.call('release', "#{prefix} quantity #{order[:quantity]}")
        end
      end
      balance = item.on_hand
      before_receipts = Array.new(@horizon + 1, 0)
      1.upto(@horizon) do |week|
        balance -= row[:gross][week]
        before_receipts[week] = balance
      end
      earlier = 0
      @receipts_by_item[id].each do |receipt|
        need_week = (1..@horizon).find { |week| before_receipts[week] + earlier < item.safety }
        detail = "#{id} receipt line #{receipt[:line]} week #{receipt[:week]} quantity #{receipt[:quantity]}"
        if need_week.nil?
          add.call('cancel', detail)
        elsif need_week < receipt[:week]
          add.call('expedite', "#{detail} to #{need_week}")
        elsif need_week > receipt[:week]
          add.call('defer', "#{detail} to #{need_week}")
        end
        earlier += receipt[:quantity]
      end
      add.call('no_routing', id) if @bom.manufactured?(id) && @routings[id].empty?
      add.call('no_demand', "#{id} on hand #{item.on_hand}") if row[:gross].sum.zero? && item.on_hand > 0
    end
    @center_ids.each do |id|
      1.upto(@horizon) do |week|
        next if @plan[:overloads][id][week].zero?

        add.call('overload', "#{id} week #{week} load #{@plan[:loads][id][week]} available #{@centers[id].available}")
      end
    end
    totals = EXCEPTION_ORDER.map { |kind| "#{kind} #{counts[kind]}" }.join(' ')
    lines << "SUMMARY errors #{@errors.length} #{totals}"
    lines
  end

  def capacity_lines
    lines = []
    totals = {}
    utilization = {}
    @center_ids.each do |id|
      center = @centers[id]
      load = @plan[:loads][id]
      overload = @plan[:overloads][id]
      leveled = Capacity.level(load, center.available, @horizon)
      total = load.sum
      totals[id] = total
      utilization[id] = Report.percentage(total, center.available * @horizon)
      peak = total.zero? ? 0 : (1..@horizon).max_by { |week| [load[week], -week] }
      lines << "CENTER #{id} minutes #{center.minutes} efficiency #{center.efficiency} available #{center.available} #{center.description}"
      lines << Report.table('WEEK', (1..@horizon).to_a, 7)
      lines << Report.table('LOAD', load.drop(1), 7)
      lines << Report.table('UTIL', load.drop(1).map { |value| Report.percentage(value, center.available) }, 7)
      lines << Report.table('OVER', overload.drop(1), 7)
      lines << Report.table('LEVELED', leveled.drop(1), 7)
      lines << "TOTAL load #{total} available #{center.available * @horizon} utilization #{utilization[id]} overloaded #{overload.count { |value| value > 0 }} peak #{peak} backlog #{[0, leveled[1] - center.available].max}"
    end
    ranking = @center_ids.sort do |left, right|
      comparison = (totals[right] * @centers[left].available) <=> (totals[left] * @centers[right].available)
      comparison.zero? ? left <=> right : comparison
    end
    ranking.each_with_index do |id, index|
      lines << "RANK #{index + 1} #{id} load #{totals[id]} utilization #{utilization[id]}"
    end
    lines
  end

  def promise_lines
    lines = []
    counts = Hash.new(0)
    @promises.each do |result|
      inquiry = result[:inquiry]
      prefix = "ORDER #{inquiry[:id]} #{inquiry[:item]} quantity #{inquiry[:quantity]} requested #{inquiry[:week]}"
      if result[:promised].nil?
        counts[:rejected] += 1
        lines << "#{prefix} rejected material #{result[:material] || 'none'} reason #{result[:reason]}"
        next
      end
      if result[:promised] == inquiry[:week]
        counts[:on_time] += 1
        lines << "#{prefix} promised #{result[:promised]}"
      else
        counts[:late] += 1
        lines << "#{prefix} promised #{result[:promised]} late #{result[:promised] - inquiry[:week]} material #{result[:material]} reason #{result[:reason]}"
      end
      @order.each do |id|
        @plan[:items][id][:orders].each do |order|
          next unless order[:roots].any? { |root| root[:kind] == :ORDER && root[:id] == inquiry[:id] }

          lines << "  SUPPLY #{id} order #{order[:number]} receipt #{order[:receipt]} release #{order[:release]} quantity #{order[:quantity]}"
        end
      end
    end
    @order.each do |id|
      before = @base[:items][id]
      after = @plan[:items][id]
      first = (1..@horizon).find { |week| before[:planned][week] != after[:planned][week] }
      next unless first

      lines << "CHANGE #{id} from #{first} planned #{before[:planned].sum} -> #{after[:planned].sum} orders #{before[:orders].length} -> #{after[:orders].length}"
    end
    lines << "SUMMARY orders #{@inquiries.length} on_time #{counts[:on_time]} late #{counts[:late]} rejected #{counts[:rejected]}"
    lines
  end

  def release_lines
    lines = []
    available = @items.to_h { |id, item| [id, item.on_hand + @plan[:items][id][:receipts][1]] }
    orders = @order.flat_map { |id| @plan[:items][id][:orders].select { |order| order[:release] == 1 } }
    orders.sort_by! { |order| [order[:original], order[:item], order[:number]] }
    counts = Hash.new(0)
    purchase_value = 0
    orders.each do |order|
      id = order[:item]
      item = @items[id]
      lateness = order[:original] < 1 ? " late #{1 - order[:original]}" : ''
      detail = "#{id} order #{order[:number]} receipt #{order[:receipt]} quantity #{order[:quantity]}#{lateness}"
      unless @bom.manufactured?(id)
        counts[:buy] += 1
        value = order[:quantity] * item.material
        purchase_value += value
        lines << "BUY #{detail} value #{Report.money(value)}"
        next
      end
      counts[:make] += 1
      picks = @bom.children[id].map { |edge| [edge.child, Bom.need(edge, order[:quantity]), available[edge.child]] }
      ready = picks.all? { |_child, quantity, stock| quantity <= stock }
      counts[ready ? :ready : :short] += 1
      lines << "MAKE #{detail} #{ready ? 'READY' : 'SHORT'}"
      picks.each do |child, quantity, stock|
        lines << "  PICK #{child} need #{quantity} available #{stock} short #{[0, quantity - stock].max}"
        available[child] -= quantity if ready
      end
      operations = @routings[id]
      operations.each_with_index do |operation, index|
        week = Capacity.week(order[:receipt], item.lead_time, index, operations.length)
        minutes = operation.setup + order[:quantity] * operation.run
        lines << "  OPERATION #{operation.number} #{operation.center} week #{week} minutes #{minutes}"
      end
    end
    lines << "SUMMARY make #{counts[:make]} ready #{counts[:ready]} short #{counts[:short]} buy #{counts[:buy]} value #{Report.money(purchase_value)}"
    lines
  end

  def value_lines
    lines = ['week,inventory,purchases,labor']
    1.upto(@horizon) do |week|
      inventory = 0
      purchases = 0
      labor = 0
      @order.each do |id|
        item = @items[id]
        row = @plan[:items][id]
        inventory += row[:on_hand][week] * @costs[id].total
        if @bom.manufactured?(id)
          labor += row[:releases][week] * item.labor
        else
          purchases += row[:releases][week] * item.material
        end
      end
      lines << [week, Report.money(inventory), Report.money(purchases), Report.money(labor)].join(',')
    end
    lines
  end
end

MRPPlanner.new.run if $PROGRAM_NAME == __FILE__
