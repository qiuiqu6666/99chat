import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/controllers/history_pagination_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';

// K.11：候选 K + 零成本补全的烟雾测试

void main() {
  group('K.1 首屏动态 count', () {
    test('maxInitialFetchCount 已声明', () {
      expect(HistoryMessageDartConstant.maxInitialFetchCount, 80);
    });

    test('initialOpenFetchCount 保持 20', () {
      expect(HistoryMessageDartConstant.initialOpenFetchCount, 20);
    });

    test('动态 count 上限生效', () {
      // 模拟 entryUnreadCount = 100 → 100 + 10 = 110，但 clamp 到 80
      const baseCount = HistoryMessageDartConstant.initialOpenFetchCount;
      const maxCount = HistoryMessageDartConstant.maxInitialFetchCount;
      final unreadHint = 100;
      final dynamic = unreadHint > baseCount
          ? (unreadHint + 10).clamp(baseCount, maxCount)
          : baseCount;
      expect(dynamic, 80);
    });

    test('动态 count 不缩放', () {
      const baseCount = HistoryMessageDartConstant.initialOpenFetchCount;
      final unreadHint = 5;
      final dynamic = unreadHint > baseCount
          ? (unreadHint + 10).clamp(baseCount, 100)
          : baseCount;
      expect(dynamic, baseCount);
    });
  });

  group('K.2 / K.10 历史分页控制器枚举', () {
    test('ArchiveLoadingState 枚举值正确', () {
      expect(ArchiveLoadingState.values, contains(ArchiveLoadingState.idle));
      expect(ArchiveLoadingState.values,
          contains(ArchiveLoadingState.fetching));
      expect(ArchiveLoadingState.values,
          contains(ArchiveLoadingState.completed));
      expect(ArchiveLoadingState.values,
          contains(ArchiveLoadingState.exhausted));
      expect(ArchiveLoadingState.values, contains(ArchiveLoadingState.error));
    });

    test('HistoryPaginationController 初始状态', () {
      final controller = HistoryPaginationController();
      expect(controller.olderAvailability, HistoryAvailability.unknown);
      expect(controller.haveMoreLatestData, false);
      expect(controller.previousPaginationInFlight, false);
      expect(controller.archiveOlderExhausted, false);
      expect(controller.archiveLoadingState, ArchiveLoadingState.idle);
    });
  });
}
