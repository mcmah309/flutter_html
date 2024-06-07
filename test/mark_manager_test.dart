import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("removeRangesFromRange", () {
    List<(int, int)> remainingRanges;
    remainingRanges = removeRangesFromRange(0, 10, [(0, 1), (3, 5), (9, 10)]);
    expect(remainingRanges, [(1, 3), (5, 9)]);
    remainingRanges = removeRangesFromRange(0, 10, [(9, 10), (0, 1), (3, 5)]);
    expect(remainingRanges, [(1, 3), (5, 9)]);

    remainingRanges = removeRangesFromRange(0, 10, [(0, 3), (2, 5), (1, 10)]);
    expect(remainingRanges, []);
    remainingRanges = removeRangesFromRange(0, 10, [(0, 3), (2, 5), (5, 6)]);
    expect(remainingRanges, [(6, 10)]);

    remainingRanges = removeRangesFromRange(371, 434, [(131, 135),(199,261),(507,565),(2181,2252)]);
    expect(remainingRanges, [(371,434)]);
  });

  group('isFullyInRanges', () {
    test('returns true if start and end are fully inside a range', () {
      expect(isFullyInRanges(5, 10, [(0, 15), (20, 30)]), isTrue);
      expect(isFullyInRanges(25, 28, [(0, 15), (20, 30)]), isTrue);
    });

    test('returns false if start and end are not fully inside any range', () {
      expect(isFullyInRanges(5, 16, [(0, 15), (20, 30)]), isFalse);
      expect(isFullyInRanges(15, 25, [(0, 15), (20, 30)]), isFalse);
    });

    test('misc', () {
      var truthy = isFullyInRanges(0, 10, [(1, 3), (5, 9)]);
      expect(truthy, isFalse);
      truthy = isFullyInRanges(1, 4, [(1, 3), (5, 9)]);
      expect(truthy, isFalse);
      truthy = isFullyInRanges(0, 3, [(1, 3), (5, 9)]);
      expect(truthy, isFalse);
      truthy = isFullyInRanges(1, 3, [(1, 3), (5, 9)]);
      expect(truthy, isTrue);
      truthy = isFullyInRanges(1, 2, [(1, 3), (5, 9)]);
      expect(truthy, isTrue);
      truthy = isFullyInRanges(2, 3, [(1, 3), (5, 9)]);
      expect(truthy, isTrue);
    });
  });

  group('isPartiallyInRanges', () {
    test('returns true if start and end are partially inside a range', () {
      expect(isPartiallyInRanges(10, 20, [(0, 15), (18, 30)]), isTrue);
      expect(isPartiallyInRanges(15, 25, [(0, 15), (20, 30)]), isTrue);
    });

    test('returns false if start and end are not partially inside any range', () {
      expect(isPartiallyInRanges(16, 19, [(0, 15), (20, 30)]), isFalse);
      expect(isPartiallyInRanges(31, 35, [(0, 15), (20, 30)]), isFalse);
    });

     test('misc', () {
      var truthy = isPartiallyInRanges(0, 10, [(1, 3), (5, 9)]);
      expect(truthy, isTrue);
      truthy = isPartiallyInRanges(1, 4, [(1, 3), (5, 9)]);
      expect(truthy, isTrue);
      truthy = isPartiallyInRanges(0, 3, [(1, 3), (5, 9)]);
      expect(truthy, isTrue);
      truthy = isPartiallyInRanges(1, 3, [(1, 3), (5, 9)]);
      expect(truthy, isTrue);
      truthy = isPartiallyInRanges(1, 2, [(1, 3), (5, 9)]);
      expect(truthy, isTrue);
      truthy = isPartiallyInRanges(2, 3, [(1, 3), (5, 9)]);
      expect(truthy, isTrue);

      truthy = isPartiallyInRanges(3, 4, [(1, 3), (5, 9)]);
      expect(truthy, isFalse);
      truthy = isPartiallyInRanges(0, 1, [(1, 3), (5, 9)]);
      expect(truthy, isFalse);
    });
  });
}
