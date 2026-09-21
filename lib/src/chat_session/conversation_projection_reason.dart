/// Why a conversation projection was written.
///
/// Services use this contract to describe SDK projection writes without
/// importing a concrete list controller.
enum ConversationStoreProjectionReason {
  coldStart,
  authBootstrap,
  accountSwitch,
  pinHydration,
  snapshotBootstrap,
  backgroundDrain,
  sdkProjectionRestore,
  archiveRestore,
  localPurge,
  chatLeaveRecovery,
  testOnly,
}
