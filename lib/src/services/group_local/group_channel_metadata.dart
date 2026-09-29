import '../../models/me_group_record.dart';
import 'group_local_store.dart';

/// IM owns ordinary group membership; REST owns the business channel flag.
/// Backend channels can be absent from the IM joined-group snapshot.
List<MeGroupRecord> mergeGroupChannelMetadata({
  required List<MeGroupRecord> sdkRecords,
  required List<MeGroupRecord> businessRecords,
}) {
  final metadata = {
    for (final record in businessRecords)
      GroupLocalStore.groupEquivalenceKey(record.groupId): record,
  };
  final result = <String, MeGroupRecord>{};
  for (final record in sdkRecords) {
    final key = GroupLocalStore.groupEquivalenceKey(record.groupId);
    final business = metadata[key];
    result[key] = business != null && business.hasSuppliedField('isChannel')
        ? record.copyWith(isChannel: business.isChannel)
        : record;
  }
  for (final record in businessRecords) {
    if (record.isChannel) {
      result.putIfAbsent(
          GroupLocalStore.groupEquivalenceKey(record.groupId), () => record);
    }
  }
  return result.values.toList(growable: false);
}
