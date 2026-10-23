class VcsError < StandardError; end

Commit = Struct.new(:id, :seq, :parents, :tree, :message)

class MiniVcs
  def initialize
    @commits = {}
    @next_sequence = 0
    root = create([], {}, 'init')
    @branches = { 'main' => root }
    @tags = {}
    @branch = 'main'
    @detached = nil
    @work = {}
    @index = {}
    @conflicts = []
    @operation = nil
    @stash = []
    @ignores = []
  end

  def head
    @branch ? @branches[@branch] : @detached
  end

  def move_head(commit)
    if @branch
      @branches[@branch] = commit
    else
      @detached = commit
    end
  end

  def paths(*trees)
    trees.flat_map(&:keys).uniq.sort
  end

  def differences(a, b)
    paths(a, b).select { |p| a[p] != b[p] }
  end

  def match_path(destination, source, path)
    if source.key?(path)
      destination[path] = source[path]
    else
      destination.delete(path)
    end
  end

  def create(parents, tree, message)
    seq = @next_sequence
    text = "commit #{seq}\n"
    parents.each { |p| text << "parent #{p.id}\n" }
    tree.keys.sort.each { |p| text << "file #{p} #{tree[p]}\n" }
    text << "message #{message}\n"
    hash = text.each_byte.reduce(0) { |h, c| (h * 131 + c) % 2_147_483_647 }
    commit = Commit.new(format('%08x', hash), seq, parents.dup, tree.dup, message)
    @commits[commit.id] = commit
    @next_sequence += 1
    commit
  end

  def record(parents, tree, message)
    old = parents.first.tree
    added = differences(old, tree).count { |p| !old.key?(p) }
    deleted = differences(old, tree).count { |p| !tree.key?(p) }
    modified = differences(old, tree).length - added - deleted
    commit = create(parents, tree, message)
    move_head(commit)
    puts "[#{@branch || 'detached HEAD'} #{commit.id}] #{message} (#{added} added, #{modified} modified, #{deleted} deleted)"
  end

  def resolve(revision)
    anchor, steps = revision.split('~')
    commit = if anchor == 'HEAD'
               head
             else
               @branches[anchor] || @tags[anchor] || @commits[anchor]
             end
    steps.to_i.times { commit = commit&.parents&.first }
    raise VcsError, "unknown revision '#{revision}'" unless commit
    commit
  end

  def distances(commit)
    result = { commit.id => 0 }
    queue = [commit]
    queue.each do |current|
      current.parents.each do |parent|
        next if result.key?(parent.id)
        result[parent.id] = result[current.id] + 1
        queue << parent
      end
    end
    result
  end

  def ancestor?(ancestor, descendant)
    distances(descendant).key?(ancestor.id)
  end

  def merge_base(a, b)
    da = distances(a)
    db = distances(b)
    common = (da.keys & db.keys).map { |id| @commits[id] }
    candidates = common.reject do |x|
      common.any? { |y| x != y && ancestor?(x, y) }
    end
    candidates.min_by { |x| [[da[x.id], db[x.id]].max, -x.seq] }
  end

  def summary(commit)
    refs = []
    if head == commit
      refs << (@branch ? "HEAD -> #{@branch}" : 'HEAD')
    end
    @branches.keys.sort.each do |name|
      refs << name if @branches[name] == commit && name != @branch
    end
    @tags.keys.sort.each { |name| refs << "tag: #{name}" if @tags[name] == commit }
    "#{commit.id}#{refs.empty? ? '' : " (#{refs.join(', ')})"} #{commit.message}"
  end

  def changes(a, b)
    changed = differences(a, b)
    puts '(no changes)' if changed.empty?
    changed.each do |p|
      if !a.key?(p)
        puts "A #{p}: #{b[p]}"
      elsif !b.key?(p)
        puts "D #{p}: #{a[p]}"
      else
        puts "M #{p}: #{a[p]} -> #{b[p]}"
      end
    end
  end

  def check_progress
    raise VcsError, "#{@operation[0]} in progress" if @operation
  end

  def uncommitted?
    @index != head.tree || @index.any? { |p, value| @work[p] != value }
  end

  def check_uncommitted
    raise VcsError, 'uncommitted changes' if uncommitted?
  end

  def check_overwrite(selected)
    selected.uniq.sort.each do |p|
      if @index[p] != head.tree[p] || @work[p] != head.tree[p]
        raise VcsError, "local changes to '#{p}' would be overwritten"
      end
    end
  end

  def switch_tree(tree)
    changed = differences(head.tree, tree)
    check_overwrite(changed)
    changed.each do |p|
      match_path(@index, tree, p)
      match_path(@work, tree, p)
    end
  end

  def merge_trees(base, ours, theirs)
    result = {}
    conflicts = []
    markers = {}
    paths(base, ours, theirs).each do |p|
      if theirs[p] == base[p] || ours[p] == theirs[p]
        match_path(result, ours, p)
      elsif ours[p] == base[p]
        match_path(result, theirs, p)
      else
        conflicts << p
        match_path(result, ours, p)
        markers[p] = "<<<<<<< #{ours[p] || '(deleted)'} ======= #{theirs[p] || '(deleted)'} >>>>>>>"
      end
    end
    [result, conflicts, markers]
  end

  def apply(base, theirs, kind, target, message, parents, merge_base = nil)
    result, conflicts, markers = merge_trees(base, head.tree, theirs)
    changed = differences(head.tree, result)
    check_overwrite(changed + conflicts)
    puts "Merge base #{merge_base.id}" if kind == 'merge'
    if kind != 'merge' && conflicts.empty? && result == head.tree
      puts 'nothing to commit'
      return
    end
    changed.each do |p|
      match_path(@index, result, p)
      match_path(@work, result, p)
    end
    if conflicts.empty?
      record(parents, result, message)
    else
      conflicts.each do |p|
        @work[p] = markers[p]
        puts "CONFLICT #{p}"
      end
      @conflicts = conflicts
      @operation = [kind, target]
      puts case kind
           when 'merge' then 'Automatic merge failed; fix conflicts and then commit the result.'
           when 'revert' then "error: could not revert #{target.id}"
           else "error: could not apply #{target.id}"
           end
    end
  end

  def ignored?(path)
    !@index.key?(path) && !@conflicts.include?(path) && @ignores.any? { |pattern| pattern.match?(path) }
  end

  def pathspec(path)
    raise VcsError, "pathspec '#{path}' did not match any files"
  end

  def missing_path(path, revision)
    raise VcsError, "path '#{path}' does not exist in '#{revision}'"
  end

  def head_report
    puts "HEAD is now at #{head.id} #{head.message}"
  end

  def status
    puts(@branch ? "On branch #{@branch}" : "HEAD detached at #{head.id}")
    if @operation
      label = { 'merge' => 'Merging', 'revert' => 'Reverting', 'cherry-pick' => 'Cherry-picking' }
      puts "#{label[@operation[0]]} #{@operation[1].id}"
    end
    lines = []
    (paths(head.tree, @index, @work) | @conflicts).sort.each do |p|
      if @conflicts.include?(p)
        lines << "UU #{p}"
      elsif @index.key?(p)
        x = !head.tree.key?(p) ? 'A' : (head.tree[p] != @index[p] ? 'M' : '.')
        y = !@work.key?(p) ? 'D' : (@work[p] != @index[p] ? 'M' : '.')
        lines << "#{x}#{y} #{p}" unless x == '.' && y == '.'
      else
        lines << "D. #{p}" if head.tree.key?(p)
        lines << "?? #{p}" if @work.key?(p) && !ignored?(p)
      end
    end
    puts(lines.empty? ? ['nothing to commit, working tree clean'] : lines)
  end

  def rebase(target)
    check_progress
    if ancestor?(target, head)
      puts 'Already up to date'
      return
    end
    check_uncommitted
    list = []
    current = head
    until ancestor?(current, target)
      list << current
      current = current.parents.first
    end
    list.reverse!
    tree = target.tree
    actions = list.map do |old|
      result, conflicts, = merge_trees(old.parents.first.tree, tree, old.tree)
      unless conflicts.empty?
        raise VcsError, "could not rebase #{old.id}: conflict in '#{conflicts.first}'"
      end
      if result == tree
        [old, nil]
      else
        tree = result
        [old, result]
      end
    end
    switch_tree(tree)
    actions.each do |old, result|
      if result
        fresh = create([target], result, old.message)
        puts "pick #{old.id} -> #{fresh.id} #{old.message}"
        target = fresh
      else
        puts "skip #{old.id} #{old.message}"
      end
    end
    move_head(target)
    head_report
  end

  def stash_command(action)
    if action == 'LIST'
      puts '(no stash entries)' if @stash.empty?
      @stash.each_with_index { |entry, i| puts "stash@{#{i}}: #{entry[0]}" }
    elsif action == 'DROP'
      raise VcsError, 'no stash entries' if @stash.empty?
      puts "Dropped stash@{0}: #{@stash.shift[0]}"
    elsif action == 'POP'
      raise VcsError, 'no stash entries' if @stash.empty?
      check_progress
      check_uncommitted
      label, base, saved = @stash.first
      result, conflicts, = merge_trees(base.tree, head.tree, saved)
      raise VcsError, "stash conflict in '#{conflicts.first}'" unless conflicts.empty?
      changed = differences(head.tree, result)
      check_overwrite(changed)
      changed.each { |p| match_path(@work, result, p) }
      @stash.shift
      puts "Restored stash@{0}: #{label}"
      changes(head.tree, result)
    else
      check_progress
      unless uncommitted?
        puts 'No local changes to save'
        return
      end
      selected = paths(@index, head.tree)
      saved = @work.select { |p, _| selected.include?(p) }
      selected.each { |p| match_path(@work, head.tree, p) }
      @index = head.tree.dup
      label = "WIP on #{@branch || '(no branch)'}: #{head.id} #{head.message}"
      @stash.unshift([label, head, saved])
      puts "Saved stash@{0}: #{label}"
    end
  end

  def reachable(roots)
    roots.each_with_object({}) do |root, result|
      distances(root).each_key { |id| result[id] = true }
    end
  end

  def graph
    live = reachable([head] + @branches.values + @tags.values)
    lanes = []
    live.keys.map { |id| @commits[id] }.sort_by { |c| -c.seq }.each do |commit|
      lanes << commit unless lanes.include?(commit)
      first = lanes.index(commit)
      symbols = lanes.each_with_index.map { |c, i| c == commit ? (i == first ? '*' : '/') : '|' }
      puts "#{symbols.join(' ')} #{summary(commit)}"
      lanes = lanes.each_with_index.reject { |c, i| c == commit && i != first }.map(&:first)
      if commit.parents.empty?
        lanes.delete_at(first)
      else
        lanes[first] = commit.parents.first
        second = commit.parents[1]
        lanes.insert(first + 1, second) if second && !lanes.include?(second)
      end
    end
  end

  def execute(line)
    command, rest = line.split(' ', 2)
    args = rest ? rest.split(' ') : []
    path = args[0]
    case command
    when 'WRITE'
      path, text = rest.split(' ', 2)
      @work[path] = text
    when 'REMOVE'
      raise VcsError, "no such file '#{path}'" unless @work.key?(path)
      @work.delete(path)
    when 'ADD'
      if path == 'ALL'
        selected = paths(@work, @index).reject { |p| ignored?(p) }
        selected.each { |p| match_path(@index, @work, p) }
        @conflicts.clear
      else
        raise VcsError, "path '#{path}' is ignored" if @work.key?(path) && ignored?(path)
        pathspec(path) unless @work.key?(path) || @index.key?(path) || @conflicts.include?(path)
        match_path(@index, @work, path)
        @conflicts.delete(path)
      end
    when 'RM'
      pathspec(path) unless @index.key?(path)
      @index.delete(path)
      @work.delete(path)
      @conflicts.delete(path)
    when 'UNSTAGE'
      pathspec(path) unless @index.key?(path) || head.tree.key?(path)
      match_path(@index, head.tree, path)
    when 'RESTORE'
      if args.length == 1
        pathspec(path) unless @index.key?(path)
        @work[path] = @index[path]
      else
        tree = resolve(args[1]).tree
        missing_path(path, args[1]) unless tree.key?(path)
        @index[path] = @work[path] = tree[path]
        @conflicts.delete(path)
      end
    when 'IGNORE'
      regex = path.each_char.map { |c| c == '*' ? '.*' : (c == '?' ? '.' : Regexp.escape(c)) }.join
      @ignores << Regexp.new("\\A#{regex}\\z")
    when 'COMMIT'
      raise VcsError, 'unresolved conflicts' unless @conflicts.empty?
      if @operation && @operation[0] == 'merge'
        record([head, @operation[1]], @index, rest)
        @operation = nil
      elsif @index == head.tree
        puts 'nothing to commit'
      else
        record([head], @index, rest)
        @operation = nil
      end
    when 'AMEND'
      check_progress
      raise VcsError, 'cannot amend the root commit' if head.parents.empty?
      record(head.parents, @index, rest)
    when 'STATUS'
      status
    when 'LS', 'CAT'
      revision = command == 'LS' ? args[0] : args[1]
      tree = revision ? resolve(revision).tree : @work
      if command == 'LS'
        puts '(empty)' if tree.empty?
        tree.keys.sort.each { |p| puts "#{p} #{tree[p]}" }
      else
        unless tree.key?(path)
          missing_path(path, revision) if revision
          raise VcsError, "no such file '#{path}'"
        end
        puts tree[path]
      end
    when 'DIFF'
      if args.empty?
        changes(@index, @work.select { |p, _| @index.key?(p) })
      elsif path == 'STAGED'
        changes(head.tree, @index)
      else
        a = resolve(path)
        b = resolve(args[1])
        changes(a.tree, b.tree)
      end
    when 'LOG'
      current = head
      count = 0
      loop do
        puts summary(current)
        count += 1
        break if current.parents.empty? || (path && count == path.to_i)
        current = current.parents.first
      end
    when 'SHOW'
      commit = resolve(path || 'HEAD')
      puts "commit #{summary(commit)}"
      puts "parents: #{commit.parents.empty? ? 'none' : commit.parents.map(&:id).join(' ')}"
      changes(commit.parents.empty? ? {} : commit.parents.first.tree, commit.tree)
    when 'BLAME'
      missing_path(path, 'HEAD') unless head.tree.key?(path)
      value = head.tree[path]
      commit = head
      commit = commit.parents.first while !commit.parents.empty? && commit.parents.first.tree[path] == value
      puts "#{commit.id} (#{commit.message}) #{value}"
    when 'BRANCH', 'TAG'
      refs = command == 'BRANCH' ? @branches : @tags
      kind = command.downcase
      if path == '-d'
        name = args[1]
        raise VcsError, "no such #{kind} '#{name}'" unless refs.key?(name)
        if command == 'BRANCH'
          raise VcsError, "cannot delete current branch '#{name}'" if @branch == name
          raise VcsError, "branch '#{name}' is not fully merged" unless ancestor?(refs[name], head)
        end
        old = refs.delete(name)
        puts "Deleted #{kind} #{name} (was #{old.id})"
      else
        raise VcsError, "#{kind} '#{path}' already exists" if refs.key?(path)
        commit = resolve(args[1] || 'HEAD')
        refs[path] = commit
        puts "Created #{kind} #{path} at #{commit.id}"
      end
    when 'BRANCHES'
      puts "* (HEAD detached at #{head.id})" unless @branch
      @branches.keys.sort.each do |name|
        commit = @branches[name]
        puts "#{name == @branch ? '*' : ' '} #{name} #{commit.id} #{commit.message}"
      end
    when 'TAGS'
      puts '(no tags)' if @tags.empty?
      @tags.keys.sort.each do |name|
        commit = @tags[name]
        puts "#{name} #{commit.id} #{commit.message}"
      end
    when 'SWITCH'
      raise VcsError, "no such branch '#{path}'" unless @branches.key?(path)
      if @branch == path
        puts "Already on '#{path}'"
      else
        check_progress
        switch_tree(@branches[path].tree)
        @branch = path
        puts "Switched to branch '#{path}'"
      end
    when 'DETACH'
      commit = resolve(path)
      check_progress
      switch_tree(commit.tree)
      @branch = nil
      @detached = commit
      head_report
    when 'MERGE'
      target = resolve(path)
      check_progress
      old = head
      if ancestor?(target, old)
        puts 'Already up to date'
      elsif ancestor?(old, target)
        switch_tree(target.tree)
        move_head(target)
        puts "Fast-forward #{old.id}..#{target.id}"
      else
        check_uncommitted
        base = merge_base(old, target)
        apply(base.tree, target.tree, 'merge', target, "Merge #{path}", [old, target], base)
      end
    when 'MERGEBASE'
      a = resolve(path)
      b = resolve(args[1])
      puts merge_base(a, b).id
    when 'REBASE'
      rebase(resolve(path))
    when 'RESET'
      target = resolve(args[1])
      if path == 'HARD'
        (paths(@index, target.tree) | @conflicts).each { |p| match_path(@work, target.tree, p) }
      end
      @index = target.tree.dup unless path == 'SOFT'
      move_head(target)
      @conflicts.clear
      @operation = nil
      head_report
    when 'REVERT', 'CHERRYPICK'
      target = resolve(path)
      check_progress
      check_uncommitted
      parent_tree = target.parents.empty? ? {} : target.parents.first.tree
      if command == 'REVERT'
        apply(target.tree, parent_tree, 'revert', target, "Revert \"#{target.message}\"", [head])
      else
        apply(parent_tree, target.tree, 'cherry-pick', target, target.message, [head])
      end
    when 'STASH'
      stash_command(path)
    when 'GRAPH'
      graph
    when 'DESCRIBE'
      commit = resolve(path || 'HEAD')
      distance = distances(commit)
      candidates = @tags.keys.select { |name| distance.key?(@tags[name].id) }
      raise VcsError, "no tag can describe '#{commit.id}'" if candidates.empty?
      name = candidates.min_by { |tag| [distance[@tags[tag].id], tag] }
      d = distance[@tags[name].id]
      puts(d.zero? ? name : "#{name}-#{d}-g#{commit.id}")
    when 'GC'
      roots = [head] + @branches.values + @tags.values + @stash.map { |entry| entry[1] }
      roots << @operation[1] if @operation
      live = reachable(roots)
      old_size = @commits.length
      @commits.select! { |id, _| live.key?(id) }
      puts "Removed unreachable commits: #{old_size - @commits.length}"
    end
  rescue VcsError => error
    puts "error: #{error.message}"
  end
end

vcs = MiniVcs.new
STDIN.each_line do |line|
  line = line.chomp
  break if line == 'EXIT'
  vcs.execute(line)
end
