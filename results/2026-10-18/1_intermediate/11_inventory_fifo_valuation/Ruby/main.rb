CATEGORIES = %w[received returned adjusted-in adjusted-out shipped written-down expired recalled].freeze
Item = Struct.new(:code, :level, :name, :last_cost, :card)
Lot = Struct.new(:number, :item, :day, :initial_quantity, :initial_cost, :warehouse, :kind, :removed)
StockLot = Struct.new(:lot, :quantity, :cost) do
  def value
    quantity * cost
  end
end
Part = Struct.new(:lot, :quantity, :cost)
Order = Struct.new(:number, :warehouse, :item, :day, :price, :ordered,
                   :shipped, :backorder, :cancelled, :returned, :revenue, :cogs, :issues)
class CommandError < StandardError; end

def cents(text)
  whole, fraction = text.split('.')
  whole.to_i * 100 + fraction.to_i
end

def money(value)
  (value.negative? ? '-' : '') + format('%d.%02d', value.abs / 100, value.abs % 100)
end

def signed_quantity(value)
  value.positive? ? "+#{value}" : value.to_s
end

def signed_money(value)
  (value.positive? ? '+' : '') + money(value)
end

def margin(profit, revenue)
  return 'n/a' if revenue.zero?
  q = profit.abs * 1000 / revenue
  (profit.negative? && q.positive? ? '-' : '') + "#{q / 10}.#{q % 10}%"
end

class Inventory
  attr_reader :output

  def initialize
    @day = 1
    @stock = {}
    @items = {}
    @lots = []
    @orders = []
    @totals = CATEGORIES.to_h { |category| [category, [0, 0]] }
    @output = []
  end

  def emit(indent, *parts)
    @output << ' ' * indent + parts.join(' ')
  end

  def warehouse(code)
    raise CommandError, "unknown warehouse #{code}" unless @stock.key?(code)
    code
  end

  def item(code)
    raise CommandError, "unknown item #{code}" unless @items.key?(code)
    @items[code]
  end

  def pair(w, code)
    warehouse(w)
    item(code)
  end

  def order(text)
    number = text.to_i
    raise CommandError, "unknown order #{text}" unless (1..@orders.length).cover?(number)
    @orders[number - 1]
  end

  def lot(text)
    number = text.to_i
    raise CommandError, "unknown lot #{text}" unless (1..@lots.length).cover?(number)
    @lots[number - 1]
  end

  def require_quantity(q)
    raise CommandError, 'invalid quantity' if q.zero?
  end

  def holdings(w, code)
    @stock[w].fetch(code, {})
  end

  def stocks(w, code)
    holdings(w, code).values
  end

  def quantity(w, code)
    stocks(w, code).sum(&:quantity)
  end

  def total_quantity(code)
    @stock.keys.sum { |w| quantity(w, code) }
  end

  def backorder(code)
    @orders.select { |o| o.item == code }.sum(&:backorder)
  end

  def all_stocks
    @stock.values.flat_map { |pairs| pairs.values.flat_map(&:values) }
  end

  def require_stock(w, code, q)
    held = quantity(w, code)
    raise CommandError, "insufficient stock #{w} #{code} #{held}" if held < q
  end

  def card_entry(code, kind, w, q, value)
    @items[code].card << [@day, kind, w, q, value]
  end

  def accumulate(category, q, value)
    @totals[category][0] += q
    @totals[category][1] += value
  end

  def add_stock(w, lot, q, cost)
    pairs = (@stock[w][lot.item] ||= {})
    if pairs.key?(lot.number)
      pairs[lot.number].quantity += q
    else
      pairs[lot.number] = StockLot.new(lot, q, cost)
    end
  end

  def create_lot(w, code, day, q, cost, kind)
    lot = Lot.new(@lots.length + 1, code, day, q, cost, w, kind, 0)
    @lots << lot
    add_stock(w, lot, q, cost)
    lot
  end

  def fifo(w, code)
    stocks(w, code).sort_by { |s| [s.lot.day, s.lot.number] }
  end

  def issue(w, code, q)
    parts = []
    cost = 0
    fifo(w, code).each do |s|
      break if q.zero?
      taken = [q, s.quantity].min
      parts << Part.new(s.lot, taken, s.cost)
      cost += taken * s.cost
      s.quantity -= taken
      q -= taken
      holdings(w, code).delete(s.lot.number) if s.quantity.zero?
    end
    [parts, cost]
  end

  def fulfil(o, q, kind)
    return 0 if q.zero?
    parts, cost = issue(o.warehouse, o.item, q)
    o.shipped += q
    o.backorder -= q
    o.revenue += q * o.price
    o.cogs += cost
    o.issues.concat(parts)
    accumulate('shipped', q, cost)
    card_entry(o.item, kind, o.warehouse, -q, -cost)
    cost
  end

  def allocate(w, code)
    available = quantity(w, code)
    @orders.each do |o|
      break if available.zero?
      next if o.warehouse != w || o.item != code || o.backorder.zero?
      q = [available, o.backorder].min
      cost = fulfil(o, q, 'fill')
      revenue = q * o.price
      available -= q
      emit(2, 'FILL', 'order', o.number, 'qty', q, 'revenue', money(revenue),
           'cogs', money(cost), 'profit', money(revenue - cost), 'backorder', o.backorder)
    end
  end

  def remove_parts(parts)
    parts.each { |part| part.lot.removed += part.quantity }
  end

  def sales
    rows = {}
    @orders.each do |o|
      row = (rows[o.item] ||= [0, 0, 0])
      row[0] += o.shipped - o.returned
      row[1] += o.revenue
      row[2] += o.cogs
    end
    rows
  end

  def margin_line(label, row)
    q, revenue, cost = row
    emit(2, label, 'sold', q, 'revenue', money(revenue), 'cogs', money(cost),
         'profit', money(revenue - cost), 'margin', margin(revenue - cost, revenue))
  end

  def aging_line(label, buckets, monetary = false)
    parts = [label]
    %w[0-30 31-60 61-90 91+].zip(buckets).each do |name, value|
      parts.push(name, monetary ? money(value) : value)
    end
    emit(2, *parts)
  end

  def command(cmd, a)
    case cmd
    when 'DAY'
      day = a[0].to_i
      raise CommandError, "invalid day #{a[0]}" if day <= @day
      @day = day
      emit(0, 'DAY', day)
    when 'WAREHOUSE'
      raise CommandError, "duplicate warehouse #{a[0]}" if @stock.key?(a[0])
      @stock[a[0]] = {}
      emit(0, 'WAREHOUSE', a[0])
    when 'ITEM'
      product = @items[a[0]]
      action = product ? 'updated' : 'added'
      if product
        product.level = a[1].to_i
        product.name = a[2]
      else
        @items[a[0]] = Item.new(a[0], a[1].to_i, a[2], nil, [])
      end
      emit(0, 'ITEM', a[0], action, a[2], 'level', a[1].to_i)
    when 'RECEIVE'
      w, code = a
      product = pair(w, code)
      q = a[2].to_i
      cost = cents(a[3])
      day = a[4].to_i
      require_quantity(q)
      raise CommandError, "future day #{a[4]}" if day > @day
      lot = create_lot(w, code, day, q, cost, 'receive')
      amount = q * cost
      product.last_cost = cost
      accumulate('received', q, amount)
      card_entry(code, 'receive', w, q, amount)
      emit(0, 'RECEIVE', w, code, 'lot', lot.number, 'qty', q, 'cost', money(cost), 'day', day, 'value', money(amount))
      allocate(w, code)
    when 'SHIP'
      w, code = a
      pair(w, code)
      q = a[2].to_i
      require_quantity(q)
      o = Order.new(@orders.length + 1, w, code, @day, cents(a[3]), q, 0, q, 0, 0, 0, 0, [])
      @orders << o
      filled = [q, quantity(w, code)].min
      cost = fulfil(o, filled, 'ship')
      emit(0, 'SHIP', 'order', o.number, w, code, 'shipped', filled, 'revenue', money(o.revenue),
           'cogs', money(cost), 'profit', money(o.revenue - cost), 'backorder', o.backorder)
    when 'CANCEL'
      o = order(a[0])
      raise CommandError, "no backorder #{a[0]}" if o.backorder.zero?
      o.cancelled += o.backorder
      o.backorder = 0
      emit(0, 'CANCEL', 'order', o.number, 'qty', o.cancelled)
    when 'TRANSFER'
      source, destination, code = a
      warehouse(source)
      warehouse(destination)
      raise CommandError, "same warehouse #{source}" if source == destination
      item(code)
      q = a[3].to_i
      require_quantity(q)
      require_stock(source, code, q)
      parts, cost = issue(source, code, q)
      parts.each { |part| add_stock(destination, part.lot, part.quantity, part.cost) }
      card_entry(code, 'transfer-out', source, -q, -cost)
      card_entry(code, 'transfer-in', destination, q, cost)
      emit(0, 'TRANSFER', source, '->', destination, code, 'qty', q, 'value', money(cost), 'lots', parts.length)
      allocate(destination, code)
    when 'ADJUST'
      w, code, change = a
      pair(w, code)
      q = change[1..].to_i
      require_quantity(q)
      if change[0] == '+'
        cost = cents(a[3])
        amount = q * cost
        lot = create_lot(w, code, @day, q, cost, 'adjust')
        accumulate('adjusted-in', q, amount)
        card_entry(code, 'adjust', w, q, amount)
        emit(0, 'ADJUST', w, code, "+#{q}", 'lot', lot.number, 'value', money(amount))
        allocate(w, code)
      else
        require_stock(w, code, q)
        parts, cost = issue(w, code, q)
        remove_parts(parts)
        accumulate('adjusted-out', q, cost)
        card_entry(code, 'adjust', w, -q, -cost)
        emit(0, 'ADJUST', w, code, "-#{q}", 'value', money(cost))
      end
    when 'RETURN'
      o = order(a[0])
      q = a[1].to_i
      cost = cents(a[2])
      require_quantity(q)
      available = o.shipped - o.returned
      raise CommandError, "return exceeds shipped #{a[0]} #{available}" if q > available
      lot = create_lot(o.warehouse, o.item, @day, q, cost, 'return')
      amount = q * cost
      refund = q * o.price
      o.returned += q
      o.revenue -= refund
      o.cogs -= amount
      accumulate('returned', q, amount)
      card_entry(o.item, 'return', o.warehouse, q, amount)
      emit(0, 'RETURN', 'order', o.number, o.warehouse, o.item, 'qty', q,
           'lot', lot.number, 'refund', money(refund), 'value', money(amount))
      allocate(o.warehouse, o.item)
    when 'COUNT'
      w, code = a
      product = pair(w, code)
      actual = a[2].to_i
      held = quantity(w, code)
      if actual == held
        emit(0, 'COUNT', w, code, 'qty', actual, 'ok')
      elsif actual < held
        q = held - actual
        parts, cost = issue(w, code, q)
        remove_parts(parts)
        accumulate('adjusted-out', q, cost)
        card_entry(code, 'count', w, -q, -cost)
        emit(0, 'COUNT', w, code, 'qty', held, '->', actual, 'shortage', q, 'value', money(cost))
      else
        q = actual - held
        cost = product.last_cost || 0
        amount = q * cost
        lot = create_lot(w, code, @day, q, cost, 'count')
        accumulate('adjusted-in', q, amount)
        card_entry(code, 'count', w, q, amount)
        emit(0, 'COUNT', w, code, 'qty', held, '->', actual, 'surplus', q, 'lot', lot.number, 'value', money(amount))
        allocate(w, code)
      end
    when 'MARKET'
      item(a[0])
      price = cents(a[1])
      changed = 0
      q = 0
      loss = 0
      @stock.keys.sort.each do |w|
        warehouse_loss = 0
        stocks(w, a[0]).each do |s|
          next if s.cost <= price
          warehouse_loss += s.quantity * (s.cost - price)
          changed += 1
          q += s.quantity
          s.cost = price
        end
        card_entry(a[0], 'writedown', w, 0, -warehouse_loss) if warehouse_loss.positive?
        loss += warehouse_loss
      end
      accumulate('written-down', q, loss)
      emit(0, 'MARKET', a[0], 'price', money(price), 'lots', changed, 'qty', q, 'loss', money(loss))
    when 'RECALL'
      lot = lot(a[0])
      held = @stock.keys.sort.filter_map do |w|
        s = holdings(w, lot.item)[lot.number]
        [w, s] if s
      end
      raise CommandError, "nothing to recall #{a[0]}" if held.empty?
      q = held.sum { |_, s| s.quantity }
      amount = held.sum { |_, s| s.value }
      held.each do |w, s|
        holdings(w, lot.item).delete(lot.number)
        card_entry(lot.item, 'recall', w, -s.quantity, -s.value)
      end
      lot.removed += q
      accumulate('recalled', q, amount)
      emit(0, 'RECALL', 'lot', lot.number, lot.item, 'qty', q, 'value', money(amount))
      held.each { |w, s| emit(2, w, 'qty', s.quantity, 'value', money(s.value)) }
    when 'EXPIRE'
      days = a[0].to_i
      emit(0, 'EXPIRE', days)
      total_q = 0
      total_v = 0
      @items.keys.sort.each do |code|
        @stock.keys.sort.each do |w|
          expired = stocks(w, code).select { |s| @day - s.lot.day > days }
          next if expired.empty?
          q = expired.sum(&:quantity)
          amount = expired.sum(&:value)
          expired.each do |s|
            s.lot.removed += s.quantity
            holdings(w, code).delete(s.lot.number)
          end
          accumulate('expired', q, amount)
          card_entry(code, 'expire', w, -q, -amount)
          total_q += q
          total_v += amount
          emit(2, code, w, 'lots', expired.length, 'qty', q, 'value', money(amount))
        end
      end
      emit(2, 'total', 'qty', total_q, 'value', money(total_v))
    when 'VALUE', 'AGING'
      warehouses = a.empty? ? @stock.keys.sort : [warehouse(a[0])]
      cmd == 'VALUE' ? emit(0, 'VALUE', *a) : emit(0, 'AGING', *a, 'day', @day)
      total_q = 0
      total_v = 0
      bucket_q = Array.new(4, 0)
      bucket_v = Array.new(4, 0)
      @items.keys.sort.each do |code|
        rows = warehouses.map { |w| [w, stocks(w, code)] }
        stock_lots = rows.flat_map(&:last)
        q = stock_lots.sum(&:quantity)
        amount = stock_lots.sum(&:value)
        next if q.zero?
        if cmd == 'VALUE'
          emit(2, code, 'qty', q, 'value', money(amount), 'avg', money(amount / q))
          if a.empty?
            rows.each do |w, lots|
              held = lots.sum(&:quantity)
              emit(4, w, 'qty', held, 'value', money(lots.sum(&:value))) if held.positive?
            end
          end
        else
          item_buckets = Array.new(4, 0)
          stock_lots.each do |s|
            age = @day - s.lot.day
            bucket = age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3
            item_buckets[bucket] += s.quantity
            bucket_q[bucket] += s.quantity
            bucket_v[bucket] += s.value
          end
          aging_line(code, item_buckets)
        end
        total_q += q
        total_v += amount
      end
      if cmd == 'VALUE'
        emit(2, 'total', 'qty', total_q, 'value', money(total_v))
      else
        aging_line('total', bucket_q)
        aging_line('value', bucket_v, true)
      end
    when 'LOTS'
      w, code = a
      pair(w, code)
      emit(0, 'LOTS', w, code)
      lots = fifo(w, code)
      orders = @orders.select { |o| o.warehouse == w && o.item == code && o.backorder.positive? }
      lots.each do |s|
        emit(2, 'lot', s.lot.number, 'day', s.lot.day, 'qty', s.quantity,
             'cost', money(s.cost), 'value', money(s.value), 'age', @day - s.lot.day)
      end
      orders.each { |o| emit(2, 'backorder', 'order', o.number, 'qty', o.backorder) }
      emit(2, '(none)') if lots.empty? && orders.empty?
    when 'REORDER', 'ITEMS'
      emit(0, cmd)
      found = false
      @items.keys.sort.each do |code|
        product = @items[code]
        q = total_quantity(code)
        pending = backorder(code)
        if cmd == 'REORDER'
          next if q - pending > product.level
          emit(2, code, product.name, 'onhand', q, 'backorder', pending, 'level', product.level)
        else
          emit(2, code, product.name, 'level', product.level, 'onhand', q,
               'backorder', pending, 'cost', product.last_cost.nil? ? 'none' : money(product.last_cost))
        end
        found = true
      end
      emit(2, '(none)') unless found
    when 'MARGIN', 'TOP'
      rows = sales
      if cmd == 'MARGIN'
        emit(0, 'MARGIN')
        total = [0, 0, 0]
        rows.keys.sort.each do |code|
          margin_line(code, rows[code])
          3.times { |i| total[i] += rows[code][i] }
        end
        margin_line('total', total)
      else
        emit(0, 'TOP', a[0].to_i)
        ids = rows.keys.sort_by { |code| [-(rows[code][1] - rows[code][2]), -rows[code][1], code] }
        ids.first(a[0].to_i).each_with_index do |code, i|
          _, revenue, cost = rows[code]
          emit(2, i + 1, code, 'profit', money(revenue - cost), 'revenue', money(revenue), 'margin', margin(revenue - cost, revenue))
        end
        emit(2, '(none)') if ids.empty?
      end
    when 'BACKORDERS'
      emit(0, 'BACKORDERS')
      orders = @orders.select { |o| o.backorder.positive? }
      orders.each do |o|
        emit(2, 'order', o.number, o.warehouse, o.item, 'qty', o.backorder, 'day', o.day, 'price', money(o.price))
      end
      emit(2, '(none)') if orders.empty?
    when 'ORDER'
      o = order(a[0])
      emit(0, 'ORDER', o.number, o.warehouse, o.item, 'day', o.day, 'price', money(o.price))
      emit(2, 'ordered', o.ordered, 'shipped', o.shipped, 'backorder', o.backorder, 'cancelled', o.cancelled, 'returned', o.returned)
      o.issues.each { |p| emit(2, 'lot', p.lot.number, 'qty', p.quantity, 'cost', money(p.cost)) }
      emit(2, 'revenue', money(o.revenue), 'cogs', money(o.cogs), 'profit', money(o.revenue - o.cogs))
    when 'TRACE'
      lot = lot(a[0])
      emit(0, 'TRACE', 'lot', lot.number, lot.item, lot.kind, lot.warehouse,
           'day', lot.day, 'qty', lot.initial_quantity, 'cost', money(lot.initial_cost))
      @stock.keys.sort.each do |w|
        s = holdings(w, lot.item)[lot.number]
        emit(2, 'held', w, 'qty', s.quantity, 'cost', money(s.cost)) if s
      end
      @orders.each do |o|
        q = o.issues.select { |p| p.lot.number == lot.number }.sum(&:quantity)
        emit(2, 'order', o.number, 'qty', q) if q.positive?
      end
      emit(2, 'removed', 'qty', lot.removed) if lot.removed.positive?
    when 'CARD'
      product = item(a[0])
      emit(0, 'CARD', product.code, product.name)
      q = 0
      amount = 0
      product.card.each do |day, kind, w, change_q, change_v|
        q += change_q
        amount += change_v
        emit(2, 'day', day, kind, w, signed_quantity(change_q), signed_money(change_v), 'balance', q, money(amount))
      end
      emit(2, '(none)') if product.card.empty?
    when 'STATUS'
      emit(0, 'STATUS')
      @stock.keys.sort.each do |w|
        pairs = @stock[w]
        stock_lots = pairs.values.flat_map(&:values)
        skus = pairs.values.count { |lots| !lots.empty? }
        pending = @orders.select { |o| o.warehouse == w }.sum(&:backorder)
        emit(2, w, 'skus', skus, 'qty', stock_lots.sum(&:quantity), 'value', money(stock_lots.sum(&:value)), 'backorder', pending)
      end
      emit(2, '(none)') if @stock.empty?
    when 'SUMMARY'
      emit(0, 'SUMMARY')
      CATEGORIES.each do |category|
        q, amount = @totals[category]
        emit(2, category, 'qty', q, 'value', money(amount))
      end
      stock_lots = all_stocks
      emit(2, 'on-hand', 'qty', stock_lots.sum(&:quantity), 'value', money(stock_lots.sum(&:value)))
      emit(2, 'orders', @orders.length, 'open', @orders.count { |o| o.backorder.positive? },
           'backorder', @orders.sum(&:backorder))
    end
  end

  def execute(line)
    cmd, *args = line.split
    begin
      command(cmd, args)
    rescue CommandError => error
      emit(0, 'ERROR', error.message)
    end
  end
end

inventory = Inventory.new
STDIN.gets.to_i.times { inventory.execute(STDIN.gets.chomp) }
STDOUT.write(inventory.output.join("\n") + "\n")
