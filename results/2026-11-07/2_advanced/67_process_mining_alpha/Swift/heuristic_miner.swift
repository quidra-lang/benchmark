import Foundation

func dependency(_ counts: Counts, _ first: String, _ second: String) -> Rational { let forward = counts[NamePair(first, second), default: 0], backward = counts[NamePair(second, first), default: 0]; return Rational(forward - backward, forward + backward + 1) }
func loopMeasure(_ count: Int) -> Rational { Rational(count, count + 1) }
func splitMeasure(_ counts: Counts, _ activity: String, _ first: String, _ second: String) -> Rational { Rational(counts[NamePair(first, second), default: 0] + counts[NamePair(second, first), default: 0], counts[NamePair(activity, first), default: 0] + counts[NamePair(activity, second), default: 0] + 1) }
func joinMeasure(_ counts: Counts, _ activity: String, _ first: String, _ second: String) -> Rational { Rational(counts[NamePair(first, second), default: 0] + counts[NamePair(second, first), default: 0], counts[NamePair(first, activity), default: 0] + counts[NamePair(second, activity), default: 0] + 1) }
