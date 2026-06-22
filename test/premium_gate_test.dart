import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/premium_gate.dart';

void main() {
  group('PremiumGate', () {
    test('allows first two entries for free users', () {
      expect(PremiumGate.canAddEntry(currentEntryCount: 0, isPremium: false, isGuest: false), isTrue);
      expect(PremiumGate.canAddEntry(currentEntryCount: 1, isPremium: false, isGuest: false), isTrue);
      expect(PremiumGate.canAddEntry(currentEntryCount: 2, isPremium: false, isGuest: false), isFalse);
    });

    test('allows unlimited entries for premium and guests', () {
      expect(PremiumGate.canAddEntry(currentEntryCount: 10, isPremium: true, isGuest: false), isTrue);
      expect(PremiumGate.canAddEntry(currentEntryCount: 10, isPremium: false, isGuest: true), isTrue);
    });
  });
}
