module Decision
  Attribute = Data.define(:path, :origin, :med, :communities)
  Route = Data.define(:path, :origin, :med, :communities, :local_pref, :link) do
    def local? = link.nil?
    def neighbor = path.first

    def self.originated(origin, communities)
      new([].freeze, origin, 0, communities, nil, nil)
    end
  end

  def self.best(candidates, router_ids)
    remaining = candidates.dup
    return [remaining.first, 'ONLY'] if remaining.length == 1

    origin_order = { 'IGP' => 0, 'EGP' => 1, 'INCOMPLETE' => 2 }
    stages = [
      ['LOCALPREF', ->(route) { -route.local_pref }],
      ['ASPATH', ->(route) { route.path.length }],
      ['ORIGIN', ->(route) { origin_order.fetch(route.origin) }],
      ['MED', nil],
      ['ROUTERID', ->(route) { router_ids.fetch(route.neighbor) }],
      ['LINK', ->(route) { route.link.number }]
    ]
    stages.each do |reason, key|
      if reason == 'MED'
        minima = remaining.group_by(&:neighbor).transform_values { |routes| routes.map(&:med).min }
        remaining.select! { |route| route.med == minima.fetch(route.neighbor) }
      else
        minimum = remaining.map(&key).min
        remaining.select! { |route| key.call(route) == minimum }
      end
      return [remaining.first, reason] if remaining.length == 1
    end
  end
end
