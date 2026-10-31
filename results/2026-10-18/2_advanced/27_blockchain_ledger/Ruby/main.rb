require_relative 'hashing'
require_relative 'wallets'
require_relative 'transactions'
require_relative 'blocks'
require_relative 'chain'

module Ledger
  MempoolEntry = Struct.new(:transaction, :fee, :arrival)
  Orphan = Struct.new(:block, :peer)
  Peer = Struct.new(:blocks, :block_rejected, :orphans, :txs, :tx_rejected, :ignored, :score)

  class Program
    def read_settings
      @settings = {}
      File.readlines('input/params.txt', chomp: true).each do |line|
        name, *values = line.split
        if name == 'GENESIS'
          @distribution = values.each_slice(2).map { |wallet, amount| [wallet, amount.to_i] }
        else
          integers = values.map(&:to_i)
          @settings[name] = integers.length == 1 ? integers.first : integers
        end
      end
      @maturity = @settings.fetch('MATURITY')
      @ban_limit, @block_penalty, @transaction_penalty = @settings.fetch('BAN')
    end

    def initialize_state
      @wallets = Wallets.new('input/wallets.txt')
      read_settings
      @chain = Chain.new(@settings)
      @tree = {}
      @mempool = []
      @orphans = []
      @rejected = {}
      @drops = {}
      @peers = {}
      @rejections = Hash.new(0)
      @reorganizations = []
      @log = []
      @time = 0
      outputs = @distribution.map { |name, amount| [@wallets[name].address, amount] }
      transaction = Transaction.coinbase(0, outputs)
      block = Block.new(0, '0' * 32, transaction.txid, 0, 0, 0, [transaction])
      @tip = store_block(block, nil, transaction.apply({}, 0), 0, [0], 'genesis')
      update_main_chain
    end

    def store_block(block, parent, utxo, fees, transaction_fees, source)
      work = parent ? parent.work + 16**block.difficulty : 1
      record = StoredBlock.new(block: block, parent: parent, work: work, utxo: utxo,
                               fees: fees, transaction_fees: transaction_fees, source: source)
      @tree[block.id] = record
      record
    end

    def update_main_chain
      @main_chain = @chain.sequence(@tip)
      @main_transactions = {}
      @main_chain.each do |record|
        record.block.transactions.each do |transaction|
          @main_transactions[transaction.txid] = [record.block.height, transaction]
        end
      end
    end

    def next_height
      @tip.block.height + 1
    end

    def log(line)
      @log << "#{@time} #{line}"
    end

    def tally(category, reason)
      @rejections[[category, reason]] += 1
    end

    def priority_order(entries = @mempool)
      entries.sort do |first, second|
        order = (second.fee * first.transaction.size) <=> (first.fee * second.transaction.size)
        order.zero? ? first.transaction.txid <=> second.transaction.txid : order
      end
    end

    def locked_references
      @mempool.each_with_object({}) do |entry, locked|
        entry.transaction.inputs.each { |reference| locked[reference] = true }
      end
    end

    def accept(transaction)
      return ['coinbase'] if transaction.coinbase?
      if @main_transactions.key?(transaction.txid) ||
         @mempool.any? { |entry| entry.transaction.txid == transaction.txid }
        return ['duplicate']
      end
      reason, fee = transaction.check(@tip.utxo, {}, next_height, @wallets, @maturity)
      return [reason] if reason
      return ['low-fee'] if fee * 1000 < @settings['MINFEERATE'] * transaction.size

      references = transaction.inputs.to_h { |reference| [reference, true] }
      conflicts = @mempool.select do |entry|
        entry.transaction.inputs.any? { |reference| references[reference] }
      end
      unless conflicts.empty?
        higher_total = fee > conflicts.sum(&:fee)
        higher_rates = conflicts.all? { |entry| fee * entry.transaction.size > entry.fee * transaction.size }
        return ['conflict'] unless higher_total && higher_rates
      end
      [nil, fee, conflicts]
    end

    def record_drop(txid, reason)
      @drops[txid] = reason
      log("DROP #{Hashing.short(txid)} #{reason}")
    end

    def drop(entry, reason)
      @mempool.delete(entry)
      record_drop(entry.transaction.txid, reason)
    end

    def register(transaction, fee, conflicts, arrival)
      conflicts.each { |entry| drop(entry, 'replaced') }
      @mempool << MempoolEntry.new(transaction, fee, arrival)
      drop(priority_order.last, 'mempool-full') if @mempool.length > @settings['MEMPOOL']
    end

    def rebuild(returned)
      old = @mempool
      @mempool = []
      candidates = returned.map { |transaction| [transaction, @time, true] }
      candidates.concat(old.map { |entry| [entry.transaction, entry.arrival, false] })
      candidates.each do |transaction, arrival, returning|
        next if @main_transactions.key?(transaction.txid)

        reason, fee, conflicts = accept(transaction)
        if reason
          record_drop(transaction.txid, reason)
        else
          log("RETURN #{Hashing.short(transaction.txid)}") if returning
          register(transaction, fee, conflicts, arrival)
        end
      end
    end

    def switch_tip(record)
      previous_tip = @tip
      fork = @chain.fork(@tip, record)
      disconnected = @tip.block.height - fork.block.height
      connected = record.block.height - fork.block.height
      if disconnected > @settings['MAXREORG']
        log("REFUSE #{record.block.height} #{Hashing.short(record.block.id)} work #{record.work} fork #{fork.block.height} depth #{disconnected}")
        return
      end
      returned = @main_chain.select { |old| old.block.height > fork.block.height }
                            .flat_map { |old| old.block.transactions.drop(1) }
      @tip = record
      update_main_chain
      if disconnected.zero?
        log("TIP #{record.block.height} #{Hashing.short(record.block.id)} work #{record.work}")
      else
        log("REORG #{record.block.height} #{Hashing.short(record.block.id)} work #{record.work} fork #{fork.block.height} disconnected #{disconnected} connected #{connected}")
        @reorganizations << [@time, fork.block.height, disconnected, connected,
                             previous_tip.block.id, record.block.id]
      end
      rebuild(returned)
    end

    def penalize(name, points)
      peer = @peers.fetch(name)
      previous = peer.score
      peer.score += points
      log("BAN #{name} score #{peer.score}") if previous < @ban_limit && peer.score >= @ban_limit
    end

    def expire
      @mempool.dup.each do |entry|
        drop(entry, 'expired') if @time - entry.arrival >= @settings['EXPIRY']
      end
    end

    def pay(fields)
      sender, fee_text, *destinations = fields
      fee = fee_text.to_i
      outputs = destinations.each_slice(2).map { |name, amount| [@wallets[name].address, amount.to_i] }
      total = outputs.sum { |_, amount| amount }
      need = total + fee
      wallet = @wallets[sender]
      locked = locked_references
      coins = @tip.utxo.select do |reference, coin|
        coin.address == wallet.address && !locked[reference] && coin.mature?(next_height, @maturity)
      end.sort_by { |reference, coin| [-coin.amount, reference[0], reference[1]] }
      selected = []
      amount = 0
      coins.each do |reference, coin|
        selected << reference
        amount += coin.amount
        break if amount >= need
      end
      prefix = "PAY #{sender} fee #{fee} total #{total}"
      if amount < need
        log("#{prefix} rejected insufficient-funds")
        tally('pay', 'insufficient-funds')
        return
      end
      outputs << [wallet.address, amount - need] if amount > need
      transaction = Transaction.create(selected, outputs, wallet.secret)
      prefix += " tx #{Hashing.short(transaction.txid)}"
      reason, checked_fee, conflicts = accept(transaction)
      if reason
        log("#{prefix} rejected #{reason}")
        tally('pay', reason)
      else
        log("#{prefix} accepted inputs #{transaction.inputs.length} outputs #{transaction.outputs.length} size #{transaction.size}")
        register(transaction, checked_fee, conflicts, @time)
      end
    end

    def bump(txid, fee)
      prefix = "BUMP #{Hashing.short(txid)} fee #{fee}"
      entry = @mempool.find { |candidate| candidate.transaction.txid == txid }
      unless entry
        log("#{prefix} rejected unknown")
        tally('bump', 'unknown')
        return
      end
      previous = entry.transaction
      address, amount = previous.outputs.last
      changed_amount = amount - (fee - entry.fee)
      same_owner = previous.inputs.all? { |reference| @tip.utxo.fetch(reference).address == address }
      if !same_owner || changed_amount < 1
        log("#{prefix} rejected no-change")
        tally('bump', 'no-change')
        return
      end
      outputs = previous.outputs.map(&:dup)
      outputs.last[1] = changed_amount
      transaction = Transaction.create(previous.inputs, outputs, @wallets.owner(address).secret)
      prefix += " tx #{Hashing.short(transaction.txid)}"
      reason, checked_fee, conflicts = accept(transaction)
      if reason
        log("#{prefix} rejected #{reason}")
        tally('bump', reason)
      else
        log("#{prefix} accepted size #{transaction.size}")
        register(transaction, checked_fee, conflicts, @time)
      end
    end

    def receive_transaction(name, text)
      transaction = Transaction.new(text)
      reason, fee, conflicts = accept(transaction)
      peer = @peers.fetch(name)
      if reason
        peer.tx_rejected += 1
        tally('tx', reason)
        log("TX #{name} #{Hashing.short(transaction.txid)} rejected #{reason}")
        penalize(name, @transaction_penalty) if %w[coinbase bad-output bad-sig overspend].include?(reason)
      else
        peer.txs += 1
        log("TX #{name} #{Hashing.short(transaction.txid)} accepted fee #{fee} size #{transaction.size}")
        register(transaction, fee, conflicts, @time)
      end
    end

    def mine(name)
      selected = []
      size = 0
      priority_order.each do |entry|
        next if size + entry.transaction.size > @settings['MAXBLOCK']

        selected << entry
        size += entry.transaction.size
      end
      height = next_height
      fees = selected.sum(&:fee)
      coinbase = Transaction.coinbase(height, [[@wallets[name].address, @chain.reward(height) + fees]])
      transactions = [coinbase] + selected.map(&:transaction)
      timestamp = [@time, @chain.median_time(@tip) + 1].max
      block = Block.mine(height, @tip.block.id, timestamp, @chain.required(@tip), transactions)
      utxo = @tip.utxo.dup
      transactions.each { |transaction| transaction.apply(utxo, height) }
      record = store_block(block, @tip, utxo, fees, [0] + selected.map(&:fee), 'local')
      log("MINE #{name} #{height} #{Hashing.short(block.id)} bits #{block.difficulty} nonce #{block.nonce} txs #{transactions.length} size #{block.size} fees #{fees} work #{record.work}")
      switch_tip(record)
    end

    def reject_block(kind, block, name, reason)
      @rejected[block.id] = true
      @peers.fetch(name).block_rejected += 1
      tally('block', reason.split.first)
      log("#{kind} #{name} #{block.height} #{Hashing.short(block.id)} rejected #{reason}")
      penalize(name, @block_penalty) unless reason == 'time-too-new'
    end

    def connect_block(kind, block, name)
      parent = @tree.fetch(block.previous)
      reason = if block.height != parent.block.height + 1
                 'bad-height'
               elsif block.difficulty != @chain.required(parent)
                 'bad-difficulty'
               elsif block.timestamp <= @chain.median_time(parent)
                 'time-too-old'
               elsif block.timestamp > @time + @settings['DRIFT']
                 'time-too-new'
               end
      return reject_block(kind, block, name, reason) if reason

      utxo = parent.utxo.dup
      spent = {}
      fees = 0
      transaction_fees = [0]
      block.transactions.drop(1).each_with_index do |transaction, index|
        failure, fee = transaction.check(utxo, spent, block.height, @wallets, @maturity)
        return reject_block(kind, block, name, "#{failure} tx #{index + 2}") if failure

        transaction.inputs.each { |reference| spent[reference] = true }
        transaction.apply(utxo, block.height)
        fees += fee
        transaction_fees << fee
      end
      coinbase = block.transactions.first
      if coinbase.bad_outputs?(@wallets)
        return reject_block(kind, block, name, 'bad-output tx 1')
      end
      if coinbase.output_amount > @chain.reward(block.height) + fees
        return reject_block(kind, block, name, 'bad-coinbase')
      end
      coinbase.apply(utxo, block.height)
      record = store_block(block, parent, utxo, fees, transaction_fees, name)
      @peers.fetch(name).blocks += 1
      log("#{kind} #{name} #{block.height} #{Hashing.short(block.id)} accepted work #{record.work}")
      switch_tip(record) if record.work > @tip.work
    end

    def resolve_orphans(starting_hash)
      queue = [starting_hash]
      cursor = 0
      while cursor < queue.length
        parent_hash = queue[cursor]
        cursor += 1
        children = @orphans.select { |orphan| orphan.block.previous == parent_hash }
        children.each do |orphan|
          @orphans.delete(orphan)
          if @rejected[parent_hash]
            reject_block('UNORPHAN', orphan.block, orphan.peer, 'bad-parent')
          else
            connect_block('UNORPHAN', orphan.block, orphan.peer)
          end
          queue << orphan.block.id
        end
      end
    end

    def receive_block(name, fields, transaction_lines)
      block = Block.parse(fields, transaction_lines)
      if @tree.key?(block.id) || @rejected[block.id] ||
         @orphans.any? { |orphan| orphan.block.id == block.id }
        @peers.fetch(name).block_rejected += 1
        tally('block', 'duplicate')
        log("BLOCK #{name} #{block.height} #{Hashing.short(block.id)} rejected duplicate")
        return
      end
      reason = block.context_error(@settings['MAXBLOCK'])
      reason = 'bad-parent' if reason.nil? && @rejected[block.previous]
      if reason
        reject_block('BLOCK', block, name, reason)
        resolve_orphans(block.id)
      elsif !@tree.key?(block.previous)
        @orphans << Orphan.new(block, name)
        @peers.fetch(name).orphans += 1
        log("BLOCK #{name} #{block.height} #{Hashing.short(block.id)} orphan parent #{Hashing.short(block.previous)}")
        if @orphans.length > @settings['ORPHANS']
          removed = @orphans.shift
          log("EVICT #{Hashing.short(removed.block.id)} orphan-limit")
        end
      else
        connect_block('BLOCK', block, name)
        resolve_orphans(block.id)
      end
    end

    def status(txid)
      prefix = "STATUS #{Hashing.short(txid)}"
      if @main_transactions.key?(txid)
        height = @main_transactions[txid][0]
        log("#{prefix} confirmed #{height} confirmations #{next_height - height}")
      elsif (index = priority_order.index { |entry| entry.transaction.txid == txid })
        log("#{prefix} mempool rank #{index + 1} of #{@mempool.length}")
      elsif @drops.key?(txid)
        log("#{prefix} dropped #{@drops[txid]}")
      elsif @tree.values.any? { |record| record.block.transactions.any? { |transaction| transaction.txid == txid } }
        log("#{prefix} stale")
      else
        log("#{prefix} unknown")
      end
    end

    def print_state
      size = @mempool.sum { |entry| entry.transaction.size }
      log("PRINT height #{@tip.block.height} tip #{Hashing.short(@tip.block.id)} work #{@tip.work} bits #{@chain.required(@tip)} reward #{@chain.reward(next_height)} mempool #{@mempool.length} size #{size} orphans #{@orphans.length}")
      priority_order.each_with_index do |entry, index|
        log("MEMPOOL #{index + 1} #{Hashing.short(entry.transaction.txid)} fee #{entry.fee} size #{entry.transaction.size}")
      end
      @wallets.all.each do |wallet|
        amount = @tip.utxo.values.sum { |coin| coin.address == wallet.address ? coin.amount : 0 }
        log("BALANCE #{wallet.name} #{amount}")
      end
    end

    def process_events
      lines = File.readlines('input/events.txt', chomp: true)
      cursor = 0
      while cursor < lines.length
        fields = lines[cursor].split
        cursor += 1
        @time = fields.shift.to_i
        kind = fields.shift
        transaction_lines = nil
        if kind == 'BLOCK'
          count = fields.last.to_i
          transaction_lines = lines.slice(cursor, count)
          cursor += count
        end
        expire
        if %w[TX BLOCK].include?(kind)
          name = fields.first
          peer = @peers[name] ||= Peer.new(0, 0, 0, 0, 0, 0, 0)
          if peer.score >= @ban_limit
            peer.ignored += 1
            log("IGNORE #{name} #{kind}")
            next
          end
        end
        case kind
        when 'PAY' then pay(fields)
        when 'BUMP' then bump(fields[0], fields[1].to_i)
        when 'TX' then receive_transaction(fields[0], fields[1])
        when 'MINE' then mine(fields[0])
        when 'BLOCK' then receive_block(fields[0], fields.drop(1), transaction_lines)
        when 'STATUS' then status(fields[0])
        when 'PRINT' then print_state
        end
      end
    end

    def miner(record)
      return '-' if record.block.height.zero?

      @wallets.owner(record.block.transactions.first.outputs.first[0]).name
    end

    def chain_lines
      lines = ["TIP #{@tip.block.height} #{@tip.block.id} work #{@tip.work} stored #{@tree.length} orphans #{@orphans.length}"]
      @main_chain.each do |record|
        block = record.block
        lines << "BLOCK #{block.height} #{block.id} prev #{Hashing.short(block.previous)} time #{block.timestamp} bits #{block.difficulty} nonce #{block.nonce} txs #{block.transactions.length} size #{block.size} fees #{record.fees} miner #{miner(record)} source #{record.source} work #{record.work}"
        block.transactions.each_with_index do |transaction, index|
          if transaction.coinbase?
            category = block.height.zero? ? 'genesis' : 'coinbase'
            lines << "TX #{index + 1} #{transaction.txid} #{category} out #{transaction.outputs.length} amount #{transaction.output_amount}"
          else
            lines << "TX #{index + 1} #{transaction.txid} payment in #{transaction.inputs.length} out #{transaction.outputs.length} size #{transaction.size} fee #{record.transaction_fees[index]}"
          end
        end
      end
      main_hashes = @main_chain.to_h { |record| [record.block.id, true] }
      stale = @tree.values.reject { |record| main_hashes[record.block.id] }
      stale.sort_by { |record| [record.block.height, record.block.id] }.each do |record|
        block = record.block
        lines << "STALE #{block.height} #{block.id} prev #{Hashing.short(block.previous)} source #{record.source} work #{record.work}"
      end
      @orphans.each do |orphan|
        block = orphan.block
        lines << "ORPHAN #{block.height} #{block.id} prev #{Hashing.short(block.previous)} source #{orphan.peer}"
      end
      @reorganizations.each do |time, fork, disconnected, connected, old_tip, new_tip|
        lines << "REORG #{time} fork #{fork} disconnected #{disconnected} connected #{connected} old #{Hashing.short(old_tip)} new #{Hashing.short(new_tip)}"
      end
      mined = @main_chain.drop(1)
      @wallets.all.each do |wallet|
        records = mined.select { |record| miner(record) == wallet.name }
        next if records.empty?

        coinbase = records.sum { |record| record.block.transactions.first.output_amount }
        lines << "MINER #{wallet.name} blocks #{records.length} coinbase #{coinbase} fees #{records.sum(&:fees)}"
      end
      mined.chunk { |record| record.block.difficulty }.each do |difficulty, records|
        lines << "BITS #{difficulty} heights #{records.first.block.height}-#{records.last.block.height} blocks #{records.length}"
      end
      @peers.keys.sort.each do |name|
        peer = @peers[name]
        state = peer.score >= @ban_limit ? 'banned' : 'ok'
        lines << "PEER #{name} blocks #{peer.blocks} rejected #{peer.block_rejected} orphans #{peer.orphans} txs #{peer.txs} rejected #{peer.tx_rejected} ignored #{peer.ignored} score #{peer.score} #{state}"
      end
      priority_order.each_with_index do |entry, index|
        lines << "MEMPOOL #{index + 1} #{entry.transaction.txid} fee #{entry.fee} size #{entry.transaction.size} time #{entry.arrival}"
      end
      @rejections.sort.each do |(category, reason), count|
        lines << "REJECT #{category} #{reason} #{count}"
      end
      genesis = @main_chain.first.block.transactions.first.output_amount
      rewards = mined.sum { |record| @chain.reward(record.block.height) }
      fees = mined.sum(&:fees)
      coinbase = mined.sum { |record| record.block.transactions.first.output_amount }
      amount = @tip.utxo.values.sum(&:amount)
      lines << "SUPPLY genesis #{genesis} rewards #{rewards} fees #{fees} burned #{rewards + fees - coinbase} utxo #{amount}"
      lines
    end

    def balance_lines
      lines = ['wallet,address,balance,immature,locked,incoming,utxos']
      locked = locked_references
      @wallets.all.each do |wallet|
        coins = @tip.utxo.select { |_, coin| coin.address == wallet.address }
        balance = coins.values.sum(&:amount)
        immature = coins.values.sum { |coin| coin.mature?(next_height, @maturity) ? 0 : coin.amount }
        locked_amount = coins.sum { |reference, coin| locked[reference] ? coin.amount : 0 }
        incoming = @mempool.sum do |entry|
          entry.transaction.outputs.sum { |address, amount| address == wallet.address ? amount : 0 }
        end
        lines << [wallet.name, wallet.address, balance, immature, locked_amount, incoming, coins.length].join(',')
      end
      lines
    end

    def utxo_lines
      locked = locked_references
      lines = @tip.utxo.sort_by { |reference, _| reference }.map do |reference, coin|
        category = coin.height.zero? ? 'genesis' : (coin.coinbase ? 'coinbase' : 'payment')
        state = if !coin.mature?(next_height, @maturity)
                  'immature'
                elsif locked[reference]
                  'locked'
                else
                  'free'
                end
        "#{reference.join(':')} #{@wallets.owner(coin.address).name} #{coin.amount} height #{coin.height} #{category} #{state}"
      end
      root = Hashing.merkle(lines.map { |line| Hashing.digest(line) })
      lines << "TOTAL #{@tip.utxo.length} #{@tip.utxo.values.sum(&:amount)}"
      lines << "ROOT #{root}"
      lines
    end

    def history_lines
      lines = []
      pending = priority_order
      @wallets.all.each do |wallet|
        lines << "WALLET #{wallet.name} #{wallet.address}"
        count = 0
        total_spent = 0
        total_received = 0
        balance = 0
        @main_chain.each do |record|
          record.block.transactions.each do |transaction|
            spent = transaction.inputs.sum do |txid, index|
              address, amount = @main_transactions.fetch(txid)[1].outputs[index]
              address == wallet.address ? amount : 0
            end
            received = transaction.outputs.sum { |address, amount| address == wallet.address ? amount : 0 }
            next if spent.zero? && received.zero?

            count += 1
            total_spent += spent
            total_received += received
            balance += received - spent
            category = if record.block.height.zero?
                         'genesis'
                       elsif transaction.coinbase?
                         'coinbase'
                       else
                         'payment'
                       end
            lines << "#{record.block.height} #{Hashing.short(transaction.txid)} #{category} spent #{spent} received #{received} net #{format('%+d', received - spent)} balance #{balance}"
          end
        end
        pending_count = 0
        pending.each do |entry|
          transaction = entry.transaction
          spent = transaction.inputs.sum do |reference|
            coin = @tip.utxo.fetch(reference)
            coin.address == wallet.address ? coin.amount : 0
          end
          received = transaction.outputs.sum { |address, amount| address == wallet.address ? amount : 0 }
          next if spent.zero? && received.zero?

          pending_count += 1
          lines << "pending #{Hashing.short(transaction.txid)} spent #{spent} received #{received} net #{format('%+d', received - spent)}"
        end
        lines << "END #{wallet.name} txs #{count} spent #{total_spent} received #{total_received} balance #{balance} pending #{pending_count}"
      end
      lines
    end

    def write(name, lines)
      text = lines.empty? ? '' : lines.join("\n") + "\n"
      File.binwrite(File.join('output', name), text)
    end

    def run
      initialize_state
      process_events
      Dir.mkdir('output') unless Dir.exist?('output')
      write('log.txt', @log)
      write('chain.txt', chain_lines)
      write('balances.csv', balance_lines)
      write('utxo.txt', utxo_lines)
      write('history.txt', history_lines)
    end
  end
end

Ledger::Program.new.run
