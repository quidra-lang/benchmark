module Snapshots
  def self.create(name, time, channels)
    { name: name, start: time, complete: nil, records: {},
      states: channels.to_h { |pair| [pair, []] }, markers: {}, accepted: {}, ignored: [] }
  end

  def self.record(snapshot, process, time, reason)
    snapshot[:records][process[:name]] = {
      time: time, reason: reason, balance: process[:balance], lamport: process[:lamport],
      vector: process[:vector].dup, pending: process[:holdback].dup
    }
  end

  def self.accept_marker(snapshot, pair, time)
    snapshot[:accepted][pair] = true
    snapshot[:markers][pair][:accepted] = time
    snapshot[:complete] = time if snapshot[:accepted].size == snapshot[:states].size
  end

  def self.cut(snapshot, names)
    names.each_with_index.map { |name, i| snapshot[:records][name][:vector][i] }
  end

  def self.details(cut, names, processes, copies)
    indices = names.each_with_index.to_h
    orphans = []
    transit = []
    copies.each do |copy|
      sent = copy[:send_event][:local] <= cut[indices[copy[:source]]]
      received = copy[:recv_event] && copy[:recv_event][:local] <= cut[indices[copy[:destination]]]
      orphans << copy if received && !sent
      transit << copy if sent && !received
    end
    balances = names.each_with_index.sum { |name, i| Processes.balance_at(processes[name], cut[i]) }
    { orphans: orphans, transit: transit, balances: balances,
      money: balances + transit.sum { |copy| copy[:amount] } }
  end

  def self.copy_label(copy) = "m#{copy[:message][:id]}->#{copy[:destination]}"

  def self.same_copies?(a, b)
    identify = ->(copies) { copies.map { |copy| [copy[:message][:id], copy[:destination]] }.tally }
    identify.call(a) == identify.call(b)
  end
end
