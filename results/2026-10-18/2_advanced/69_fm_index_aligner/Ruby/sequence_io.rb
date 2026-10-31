module SequenceIO
  Reference = Data.define(:name, :bases, :masked)
  Read = Data.define(:name, :bases, :quality)
  def self.reverse_complement(sequence) = sequence.tr('ACGTN', 'TGCAN').reverse

  def self.read_fasta(path)
    records = []
    name, bases, masked = nil, +'', 0
    File.foreach(path, chomp: true) do |line|
      if line.start_with?('>')
        records << Reference.new(name, bases, masked) if name
        name, bases, masked = line[1..].split(' ', 2).first, +'', 0
      else
        masked += line.count('a-z')
        bases << line.upcase
      end
    end
    records << Reference.new(name, bases, masked) if name
    records
  end

  def self.read_fastq(path)
    File.readlines(path, chomp: true).each_slice(4).map do |name, bases, _, quality|
      Read.new(name[1..], bases, quality)
    end
  end

  def self.read_inputs
    params = File.readlines('input/params.txt', chomp: true).to_h do |line|
      name, *values = line.split
      [name, values.map(&:to_i)]
    end
    [read_fasta('input/reference.fasta'), read_fastq('input/reads.fastq'), params]
  end
end
