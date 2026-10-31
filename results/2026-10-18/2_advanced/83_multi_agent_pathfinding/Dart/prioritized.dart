part of 'main.dart';

(List<List<int>>?, int, int) prioritized(
  Grid grid,
  Parameters p,
  List<int> order,
  int number,
  Run run,
) {
  final b = Prohibitions(),
      paths = List.generate(grid.agents.length, (_) => <int>[]);
  var planned = 0;
  for (final agent in order) {
    final before = run.counter.expansions,
        path = lowLevel(
          grid,
          agent,
          grid.agents[agent].start,
          0,
          p.horizon,
          b,
          false,
          run.counter,
        );
    if (run.counter.aborted) return (null, planned, agent);
    final text = 'order $number agent ${agentName(agent)}';
    if (path == null) {
      run.trace.add(
        '$text failed expansions ${run.counter.expansions - before}',
      );
      return (null, planned, agent);
    }
    run.trace.add(
      '$text cost ${path.length - 1} expansions ${run.counter.expansions - before}',
    );
    paths[agent] = path;
    planned++;
    b.reserve(path, 0, true);
  }
  return (paths, planned, -1);
}
