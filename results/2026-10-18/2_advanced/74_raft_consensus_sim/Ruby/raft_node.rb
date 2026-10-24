require 'set'

Entry = Data.define(:term, :command, :request)

class RaftNode
  attr_reader :number, :stats, :log
  attr_accessor :term, :voted_for, :up, :role, :commit, :applied, :store,
                :known_leader, :votes, :election_deadline, :election_record,
                :next_index, :match, :heartbeat_deadline, :quorum_deadline,
                :heard, :transfer_target, :transfer_sent, :transfer_deadline

  def initialize(number)
    @number = number
    @term = 0
    @voted_for = nil
    @log = []
    @up = true
    @stats = Hash.new(0)
    reset_volatile
  end

  def reset_volatile
    @role = 'FOLLOWER'
    @commit = @applied = 0
    @store = {}
    @known_leader = @election_deadline = @election_record = nil
    @votes = Set.new
    @next_index = {}
    @match = {}
    @heartbeat_deadline = @quorum_deadline = nil
    @heard = Set.new
    cancel_transfer
  end

  def cancel_transfer
    @transfer_target = @transfer_deadline = nil
    @transfer_sent = false
  end

  def crash
    @up = false
    reset_volatile
  end

  def last_index = @log.length
  def last_term = @log.empty? ? 0 : @log.last.term
  def term_at(index) = index.zero? ? 0 : @log[index - 1].term

  def accepts_log(index, term)
    term > last_term || (term == last_term && index >= last_index)
  end

  def self.apply_command(store, command)
    operation, key, value = command
    case operation
    when 'NOOP' then nil
    when 'SET'
      store[key] = value
      'ok'
    when 'ADD'
      store[key] = store.fetch(key, 0) + value
    when 'DEL'
      return 'missing' unless store.key?(key)
      store.delete(key)
      'deleted'
    when 'GET' then store.fetch(key, 'missing')
    end
  end
end
