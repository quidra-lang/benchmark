require_relative 'hashing'
require_relative 'transactions'

module Ledger
  class Block
    attr_reader :height, :previous, :root, :timestamp, :difficulty, :nonce, :transactions, :id, :size

    def initialize(height, previous, root, timestamp, difficulty, nonce, transactions)
      @height = height
      @previous = previous
      @root = root
      @timestamp = timestamp
      @difficulty = difficulty
      @nonce = nonce
      @transactions = transactions
      @id = Hashing.digest(header)
      @size = transactions.drop(1).sum(&:size)
    end

    def header
      [@height, @previous, @root, @timestamp, @difficulty, @nonce].join('|')
    end

    def proof_of_work?
      @id.start_with?('0' * @difficulty)
    end

    def self.parse(fields, transaction_lines)
      height, previous, root, timestamp, difficulty, nonce = fields
      new(height.to_i, previous, root, timestamp.to_i, difficulty.to_i, nonce.to_i,
          transaction_lines.map { |line| Transaction.new(line) })
    end

    def self.mine(height, previous, timestamp, difficulty, transactions)
      root = Hashing.merkle(transactions.map(&:txid))
      nonce = 0
      loop do
        block = new(height, previous, root, timestamp, difficulty, nonce, transactions)
        return block if block.proof_of_work?

        nonce += 1
      end
    end

    def context_error(maximum_size)
      return 'bad-pow' unless proof_of_work?
      return 'bad-merkle' unless Hashing.merkle(@transactions.map(&:txid)) == @root
      if !@transactions.first.coinbase? || @transactions.first.coinbase_height != @height ||
         @transactions.drop(1).any?(&:coinbase?)
        return 'bad-structure'
      end
      return 'too-large' if @size > maximum_size

      nil
    end
  end
end
