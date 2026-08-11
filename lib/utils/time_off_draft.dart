class PendingTimeOffDraft {
  final String leaveType;
  final String? editingId;
  final Map<String, dynamic>? editingRecord;
  final Set<DateTime> selectedDates;
  final String notes;
  final bool typeChanged;
  final bool datesChanged;
  final bool notesChanged;

  const PendingTimeOffDraft({
    required this.leaveType,
    required this.editingId,
    required this.editingRecord,
    required this.selectedDates,
    required this.notes,
    required this.typeChanged,
    required this.datesChanged,
    required this.notesChanged,
  });

  bool get hasChanges {
    if (editingId != null) {
      return typeChanged || datesChanged || notesChanged;
    }
    return selectedDates.isNotEmpty ||
        notes.isNotEmpty ||
        typeChanged ||
        datesChanged ||
        notesChanged;
  }
}
