import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/runtime_ingress_processor.dart';

class Fixture {
  final stages = <String>[];
  bool current = true;
  bool outgoing = true;
  String? failAt;
  ImInboxStatus? refuse;
  Completer<void>? metadataGate;

  Future<void> step(String name) async {
    stages.add(name);
    if (name == 'metadata' && metadataGate != null) await metadataGate!.future;
    if (failAt == name) throw StateError(name);
  }

  Future<bool> run([ImInboxStatus status = ImInboxStatus.processing]) =>
      const RuntimeIngressProcessor().run(
        status: status,
        isCurrent: () => current,
        applyMetadata: () => step('metadata'),
        flushMetadata: () => step('flush'),
        advance: (from, to) async {
          stages.add('${from.name}>${to.name}');
          return refuse != to;
        },
        adoptOutgoing: () async {
          await step('adopt');
          return outgoing;
        },
        publish: () => step('publish'),
        completeOutgoing: () => step('outbox'),
      );
}

void main() {
  test('projection waits for durable metadata checkpoint', () async {
    final f = Fixture()..metadataGate = Completer<void>();
    final work = f.run();
    await Future<void>.delayed(Duration.zero);
    expect(f.stages, ['metadata']);
    f.metadataGate!.complete();
    expect(await work, isTrue);
    expect(f.stages, [
      'metadata',
      'flush',
      'processing>metadataCommitted',
      'adopt',
      'publish',
      'metadataCommitted>projectionPublished',
      'outbox',
      'projectionPublished>completed',
    ]);
  });
  for (final stage in ['metadata', 'flush', 'adopt', 'publish', 'outbox']) {
    test('failure at $stage never completes the inbox', () async {
      final f = Fixture()..failAt = stage;
      await expectLater(f.run(), throwsStateError);
      expect(f.stages.last, stage);
      expect(f.stages, isNot(contains('projectionPublished>completed')));
      if (stage == 'metadata' || stage == 'flush') {
        expect(f.stages, isNot(contains('publish')));
      }
    });
  }
  test('rejected metadata checkpoint cannot publish or adopt', () async {
    final f = Fixture()..refuse = ImInboxStatus.metadataCommitted;
    expect(await f.run(), isFalse);
    expect(f.stages, ['metadata', 'flush', 'processing>metadataCommitted']);
  });
  test('scope invalidation while metadata awaits prevents all later stages',
      () async {
    final f = Fixture()..metadataGate = Completer<void>();
    final work = f.run();
    f.current = false;
    f.metadataGate!.complete();
    expect(await work, isFalse);
    expect(f.stages, ['metadata']);
  });
  test(
      'recovery after metadata commit publishes without applying metadata again',
      () async {
    final f = Fixture();
    expect(await f.run(ImInboxStatus.metadataCommitted), isTrue);
    expect(f.stages, [
      'adopt',
      'publish',
      'metadataCommitted>projectionPublished',
      'outbox',
      'projectionPublished>completed'
    ]);
  });
  test(
      'recovery after publication finishes outgoing identity without republishing',
      () async {
    final f = Fixture();
    expect(await f.run(ImInboxStatus.projectionPublished), isTrue);
    expect(f.stages, ['adopt', 'outbox', 'projectionPublished>completed']);
  });
  test('ordinary incoming message never completes an unrelated Outbox',
      () async {
    final f = Fixture()..outgoing = false;
    expect(await f.run(ImInboxStatus.metadataCommitted), isTrue);
    expect(f.stages, isNot(contains('outbox')));
  });
  test('unclaimed work is rejected and completed work is inert', () async {
    final f = Fixture();
    await expectLater(f.run(ImInboxStatus.prepared), throwsStateError);
    expect(await f.run(ImInboxStatus.completed), isTrue);
    expect(f.stages, isEmpty);
  });
}
