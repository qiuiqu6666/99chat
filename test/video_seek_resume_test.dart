import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_videoplayer.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_video_progress_bar.dart';

class TestController extends ChangeNotifier {
  TestController get value => this;
  bool get isInitialized => true;
  bool get isPlaying => false;
  Duration get duration => const Duration(seconds: 100);
  Duration get position => Duration.zero;
  Future<void> pause() async {}
}

class TestPlayer extends TIMUIKitVideoPlayer {
  TestPlayer({required super.key})
      : super(
            message: V2TimMessage.fromJson(
                {'message_server_time': 1, 'message_risk_type_identified': 0}),
            isSending: false,
            deferInitialization: true);
  @override
  TestPlayerState createState() => TestPlayerState();
}

class TestPlayerState extends TIMUIKitVideoPlayerState {
  final controller = TestController();
  Duration? sought;
  int starts = 0;
  @override
  dynamic get playbackController => controller;
  @override
  Future<void> seekPlaybackTo(Duration position) async {
    sought = position;
  }

  @override
  Future<void> startDeferredPlayback() async {
    starts++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  testWidgets('seeking a paused video requests playback at selected position',
      (tester) async {
    final key = GlobalKey<TIMUIKitVideoPlayerState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Stack(children: [
      TestPlayer(key: key),
      MediaPreviewVideoProgressBar(playerKey: key),
    ]))));
    await tester.pump(const Duration(milliseconds: 150));
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(0);
    slider.onChanged!(.6);
    slider.onChangeEnd!(.6);
    await tester.pump();
    final player = key.currentState! as TestPlayerState;
    expect(player.sought, const Duration(seconds: 60));
    expect(player.starts, 1);
    player.prepareForRouteClose();
    player.resumePlayback();
    expect(player.starts, 1, reason: 'Closing routes must not restart playback');
    await tester.pumpWidget(const SizedBox());
  });
}
