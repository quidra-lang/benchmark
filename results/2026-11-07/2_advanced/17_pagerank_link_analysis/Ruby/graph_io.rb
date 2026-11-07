# frozen_string_literal: true

module GraphIO
  Page = Struct.new(:id, :host, :title, :words, keyword_init: true)
  Link = Struct.new(:line, :source, :destination, keyword_init: true)
  Query = Struct.new(:words, :seeds, keyword_init: true)
  Data = Struct.new(:pages, :links, :queries, :settings, keyword_init: true)

  def self.read
    pages = File.readlines('input/pages.csv', chomp: true).drop(1).map do |line|
      id, host, title = line.split(',')
      Page.new(id: id.to_i, host: host, title: title, words: title.split)
    end.sort_by(&:id)
    links = File.readlines('input/links.csv', chomp: true).drop(1).each_with_index.map do |line, index|
      source, destination = line.split(',').map(&:to_i)
      Link.new(line: index + 2, source: source, destination: destination)
    end
    queries = File.readlines('input/queries.txt', chomp: true).map do |line|
      words, seeds = line.split(' | ')
      Query.new(words: words.split, seeds: seeds.split.map(&:to_i))
    end
    settings = {}
    File.foreach('input/params.txt') do |line|
      name, *values = line.split
      settings[name.downcase.to_sym] = case name
                                      when 'DAMPING', 'TOLERANCE', 'SPAM_THRESHOLD' then values[0].to_f
                                      when 'DAMPING_SWEEP' then values.map(&:to_f)
                                      when 'TRUSTED' then values.map(&:to_i)
                                      else values[0].to_i
                                      end
    end
    Data.new(pages: pages, links: links, queries: queries, settings: settings)
  end
end
