import 'package:lpinyin/lpinyin.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/bounded_lru_map.dart';

/// Page-owned search fields. A changed display name invalidates just one row.
class FriendSearchCache {
  FriendSearchCache({int capacity = 24000, String Function(String)? toPinyin})
      : _entries = BoundedLruMap(capacity),
        _toPinyin = toPinyin ?? PinyinHelper.getPinyinE;

  final BoundedLruMap<String, ({String name, String text})> _entries;
  final String Function(String) _toPinyin;
  int conversions = 0;

  bool matches(String id, String name, String keyword) {
    if (keyword.isEmpty) return true;
    var entry = _entries[id];
    if (entry == null || entry.name != name) {
      final pinyin = _toPinyin(name).toLowerCase();
      conversions++;
      entry = (name: name, text: '$id $name $pinyin'.toLowerCase());
      _entries[id] = entry;
    }
    return entry.text.contains(keyword.toLowerCase());
  }

  int get length => _entries.length;
  void clear() => _entries.clear();
}
