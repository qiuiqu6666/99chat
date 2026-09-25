import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_startup.dart';

void main() {
  test('renewed Tencent signature keeps the current live stream', () {
    expect(
      groupLiveSameStreamSource(
        'https://live.example.com/room.flv?txSecret=old&txTime=100&quality=hd',
        'https://live.example.com/room.flv?quality=hd&txTime=200&txSecret=new',
      ),
      isTrue,
    );
  });

  test('a different stream path or playback option switches streams', () {
    const current =
        'https://live.example.com/room.flv?txSecret=old&txTime=100&quality=hd';
    expect(
      groupLiveSameStreamSource(
        current,
        'https://live.example.com/other.flv?txSecret=new&txTime=200&quality=hd',
      ),
      isFalse,
    );
    expect(
      groupLiveSameStreamSource(
        current,
        'https://live.example.com/room.flv?txSecret=new&txTime=200&quality=sd',
      ),
      isFalse,
    );
  });
}
