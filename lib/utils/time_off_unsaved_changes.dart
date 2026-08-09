bool hasUnsavedTimeOffChanges({
  required bool hasSelectedDates,
  required bool hasNotes,
  required bool isEditing,
  required bool typeChanged,
  required bool datesChanged,
}) {
  if (isEditing) {
    return hasNotes || datesChanged;
  }
  return hasSelectedDates || hasNotes || typeChanged;
}

int projectedTimeOffBalance({
  required int availableDays,
  required int requestedDays,
}) {
  return (availableDays - requestedDays).clamp(0, 9999);
}
