import 'package:cloud_firestore/cloud_firestore.dart';

typedef FirestoreRecords = List<Map<String, dynamic>>;

FirestoreRecords firestoreRecords(QuerySnapshot snapshot) {
  return snapshot.docs
      .map((document) {
        final rawData = document.data();
        final data = rawData is Map<String, dynamic>
            ? rawData
            : Map<String, dynamic>.from(rawData as Map);
        return {...data, 'id': document.id};
      })
      .toList(growable: false);
}

FirestoreRecords sortedFirestoreRecords(
  Iterable<Map<String, dynamic>> records, {
  String field = 'createdAt',
  bool newestFirst = true,
  bool nullsLast = true,
}) {
  final sorted = records.toList();
  sorted.sort((a, b) {
    final aValue = a[field];
    final bValue = b[field];
    if (aValue == null && bValue == null) return 0;
    if (aValue == null) return nullsLast ? 1 : -1;
    if (bValue == null) return nullsLast ? -1 : 1;
    if (aValue is! Timestamp || bValue is! Timestamp) return 0;
    return newestFirst ? bValue.compareTo(aValue) : aValue.compareTo(bValue);
  });
  return sorted;
}
