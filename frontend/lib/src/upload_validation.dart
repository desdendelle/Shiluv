bool isXlsxFileName(String fileName) {
  final normalized = fileName.trim().toLowerCase();
  return normalized.length > '.xlsx'.length && normalized.endsWith('.xlsx');
}

bool shouldFetchSchedule(String programatsiaStatus) {
  return programatsiaStatus == 'converted';
}
