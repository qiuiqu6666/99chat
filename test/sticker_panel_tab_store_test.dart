import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_panel_tab_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('last tab survives a fresh store and rapid selections', () async {
    final store = StickerPanelTabStore();
    final first = store.select('defaultEmoji');
    final last = store.select('favorites');
    expect(store.selectedName, 'favorites');
    await Future.wait([first, last]);
    final reopened = StickerPanelTabStore();
    await reopened.load();
    expect(reopened.selectedName, 'favorites');
  });

  test('a new selection wins over an in-flight restore', () async {
    SharedPreferences.setMockInitialValues({
      StickerPanelTabStore.preferenceKey: 'old',
    });
    final store = StickerPanelTabStore();
    final loading = store.load();
    final saving = store.select('new');
    await Future.wait([loading, saving]);
    expect(store.selectedName, 'new');
  });

  test('identity survives reorder, missing packs fall back and can load later',
      () {
    expect(
        StickerPanelTabStore.indexFor(['emoji', 'favorites'], 'favorites'), 1);
    expect(
        StickerPanelTabStore.indexFor(['favorites', 'emoji'], 'favorites'), 0);
    expect(StickerPanelTabStore.indexFor(['emoji'], 'favorites'), 0);
    expect(StickerPanelTabStore.indexFor([], 'favorites'), 0);
    expect(
        StickerPanelTabStore.indexFor(['emoji', 'favorites'], 'favorites'), 1);
    expect(StickerPanelTabStore.indexFor(['emoji'], null), 0);
  });
}
