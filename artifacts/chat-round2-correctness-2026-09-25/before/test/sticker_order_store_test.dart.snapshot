import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/sticker_models.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_constants.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_order_store.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_panel_packages.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = StickerOrderStore.instance;
  StickerItem item(String id, {int sort = 0}) =>
      StickerItem(stickerId: id, thumbUrl: '', originUrl: '', sortOrder: sort);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('saved order survives reload and accounts remain separate', () async {
    SharedPreferences.setMockInitialValues({
      'sticker_item_order_v1_restored': ['c', 'a', 'b'],
    });
    await store.load('restored');
    final items = [item('a'), item('b'), item('c')];
    expect(store.apply(items, owner: 'restored').map((s) => s.stickerId),
        ['c', 'a', 'b']);
    expect(store.apply(items, owner: 'another').map((s) => s.stickerId),
        ['a', 'b', 'c']);
    await store.save('another', ['b', 'a', 'c']);
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getStringList('sticker_item_order_v1_another'), ['b', 'a', 'c']);
    expect(store.apply(items, owner: 'restored').first.stickerId, 'c');
  });

  test('removed items disappear and new items append without disturbing order',
      () async {
    await store.save('membership', ['b', 'deleted', 'a', 'a']);
    final items = [item('a'), item('new'), item('b')];
    expect(store.apply(items, owner: 'membership').map((s) => s.stickerId),
        ['b', 'a', 'new']);
  });

  test('rapid saves retain last order on disk', () async {
    await Future.wait([
      store.save('rapid', ['b', 'a']),
      store.save('rapid', ['a', 'b']),
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('sticker_item_order_v1_rapid'), ['a', 'b']);
  });

  test('chat panel preserves manual order across favorites and uploads',
      () async {
    await ApiClient.instance.saveToken('test-token', userId: 'panel-order');
    addTearDown(() => ApiClient.instance.clearToken());
    await store.save('panel-order', ['upload', 'favorite']);
    final favorites = [
      FavoriteSticker(stickerId: 'favorite', thumbUrl: '', originUrl: '')
    ];
    final packs = buildWeChatStickerPanelPackages(
      StickerPanelConfig(
        useQQStickerPackage: false,
        useTencentCloudChatStickerPackage: false,
        unicodeEmojiList: const [],
      ),
      favorites: favorites,
      extraServerPacks: [
        StickerPack(
          packId: StickerConstants.userUploadPackId,
          name: 'Uploads',
          iconUrl: '',
          source: 'custom',
          removable: true,
          sortOrder: 0,
          stickers: [item('upload', sort: 99)],
        )
      ],
    );
    final pack = packs
        .singleWhere((p) => p.name == StickerConstants.virtualPackFavorites);
    expect(pack.stickerList.map((s) => s.name), ['upload', 'favorite']);
  });
}
