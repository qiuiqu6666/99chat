class RecoveryLogFile {
  RecoveryLogFile(
      {int maxBytes = 256 * 1024, String folderName = 'chat_recovery'});
  Future<void> append(List<String> events) async {}
  Future<String> read() async => '';
}
