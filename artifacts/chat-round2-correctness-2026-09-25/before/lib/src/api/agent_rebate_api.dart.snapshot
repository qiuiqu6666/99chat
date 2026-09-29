import 'package:dio/dio.dart';
import 'group_query_endpoint.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_http.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';
import 'package:tencent_cloud_chat_demo/src/utils/agent_rebate_date_range.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

class AgentRebateApi {
  AgentRebateApi({Dio? dio}) : _dio = dio ?? GroupQueryEndpoint.client;

  static final AgentRebateApi instance = AgentRebateApi();

  final Dio _dio;

  Options get _groupOptions => AgentRebateHttp.options();

  Options get _skipGroupOptions => AgentRebateHttp.options(skipGroup: true);

  /// 绑定接口约定不接收 `@`；提交前统一删除全部 `@` 字符。
  static String normalizeAgentChatGroupId(String input) {
    var value = input.trim();
    if (value.toLowerCase().startsWith('group_')) {
      value = value.substring('group_'.length).trim();
    }
    return value.replaceAll('@', '').trim();
  }

  /// 三公服务聚合判定：不传租户头，由登录用户与 IM 群定位租户。
  Future<AgentEntryContextDto> fetchEntryContext(String imGroupId) async {
    final groupId = imGroupId.trim();
    if (groupId.isEmpty) {
      throw ArgumentError.value(imGroupId, 'imGroupId', 'must not be empty');
    }
    final response = await SangongGameHttp.client.get(
      '/api/v1/agent/entry-context',
      queryParameters: <String, dynamic>{'imGroupId': groupId},
      options: Options(
        extra: const <String, dynamic>{
          SangongGameHttp.extraSkipTenant: true,
        },
      ),
    );
    return AgentEntryContextDto.fromJson(_unwrapMap(response.data));
  }

  Future<SangongTeamMembersDto> fetchSangongTeamMembers({
    bool direct = false,
    String? batchNo,
    int? sessionId,
    String? agentImUserId,
  }) async {
    final batch = batchNo?.trim() ?? '';
    final response = await SangongGameHttp.client.get(
      '/api/v1/me/team/members',
      queryParameters: <String, dynamic>{
        'direct': direct,
        if (agentImUserId != null && agentImUserId.trim().isNotEmpty)
          'agentImUserId': agentImUserId.trim(),
        if (batch.isNotEmpty)
          'batchNo': batch
        else if (sessionId != null && sessionId > 0)
          'sessionId': sessionId,
      },
    );
    return SangongTeamMembersDto.fromJson(_unwrapMap(response.data));
  }

  Future<Map<String, dynamic>> fetchSangongTeamDashboard({
    bool direct = false,
    String? batchNo,
  }) async {
    final batch = batchNo?.trim() ?? '';
    final response = await SangongGameHttp.client.get(
      '/api/v1/me/team/dashboard',
      queryParameters: <String, dynamic>{
        'direct': direct,
        if (batch.isNotEmpty) 'batchNo': batch,
      },
    );
    return _unwrapMap(response.data);
  }

  Future<Map<String, dynamic>> fetchSangongMemberDashboard({
    required String imUserId,
  }) async {
    final id = imUserId.trim();
    if (id.isEmpty) throw ArgumentError('成员 IM 用户 ID 不能为空');
    final response = await SangongGameHttp.client.get(
      '/api/v1/me/team/member-dashboard',
      queryParameters: {'imUserId': id},
    );
    return _unwrapMap(response.data);
  }

  Future<Map<String, dynamic>> fetchSangongMemberDaily({
    required String imUserId,
    String? batchNo,
    String? from,
    String? to,
  }) async {
    final id = imUserId.trim();
    if (id.isEmpty) throw ArgumentError('成员 IM 用户 ID 不能为空');
    final response = await SangongGameHttp.client.get(
      '/api/v1/me/member-daily',
      queryParameters: {
        'imUserId': id,
        if (batchNo != null && batchNo.trim().isNotEmpty)
          'batchNo': batchNo.trim(),
        if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
        if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
      },
    );
    return _unwrapMap(response.data);
  }

  Future<Map<String, dynamic>> transferToChild({
    required String toImUserId,
    required num amount,
    String note = '团队划转',
  }) async {
    final target = toImUserId.trim();
    if (target.isEmpty) throw ArgumentError('下级 IM 用户 ID 不能为空');
    if (amount <= 0) throw ArgumentError('划转积分必须大于 0');
    final response = await SangongGameHttp.client.post(
      '/api/v1/me/transfer-to-child',
      data: <String, dynamic>{
        'toImUserId': target,
        'amount': amount,
        'note': note.trim().isEmpty ? '团队划转' : note.trim(),
      },
    );
    return _unwrapMap(response.data);
  }

  Future<Map<String, dynamic>> claimSangongRebate() async {
    final response = await SangongGameHttp.client.post(
      '/api/v1/me/rebate/claim',
    );
    return _unwrapMap(response.data);
  }

  /// 群绑定状态（只需 JWT，path 内群 ID 需 encode）。
  Future<RobotGroupBindingDto> fetchRobotGroup(String groupId) async {
    final id = _encodeGroupId(groupId);
    final response = await _dio.get(
      '/me/robot/groups/$id',
      options: _skipGroupOptions,
    );
    return RobotGroupBindingDto.fromJson(_unwrapMap(response.data));
  }

  /// 与 Windows「配对」等价（联调用）。
  Future<RobotGroupBindingDto> bindRobotGroup({
    required String groupId,
    required String machineCode,
  }) async {
    final id = _encodeGroupId(groupId);
    final response = await _dio.post(
      '/me/robot/groups/$id/bind',
      data: <String, dynamic>{'machineCode': machineCode.trim()},
      options: _skipGroupOptions,
    );
    return RobotGroupBindingDto.fromJson(_unwrapMap(response.data));
  }

  /// 开启群机器人（联调用）。
  Future<RobotGroupBindingDto> enableRobotGroup({
    required String groupId,
    required String robotId,
  }) async {
    final id = _encodeGroupId(groupId);
    final response = await _dio.post(
      '/me/robot/groups/$id/enable',
      data: <String, dynamic>{'robotId': robotId.trim()},
      options: _skipGroupOptions,
    );
    return RobotGroupBindingDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentPlayerDto> fetchPlayer() async {
    final response = await _dio.get(
      '/me/agent/player',
      options: _groupOptions,
    );
    return AgentPlayerDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentRebateCurrentDto> fetchCurrent() async {
    final response = await _dio.get(
      '/me/agent/rebate/current',
      options: _groupOptions,
    );
    return AgentRebateCurrentDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentRebateApplyDto> submitAgentRebateApply() async {
    final response = await _dio.post(
      '/me/agent/rebate/apply',
      options: _groupOptions,
    );
    return AgentRebateApplyDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentRebateApplyDto> fetchAgentRebateApplyStatus() async {
    final response = await _dio.get(
      '/me/agent/rebate/apply/status',
      options: _groupOptions,
    );
    return AgentRebateApplyDto.fromJson(_unwrapMap(response.data));
  }

  /// 申请个人待反水结算（`remainingFlow` 维度）。
  Future<AgentRebateApplyDto> submitPersonalRebateApply() async {
    final response = await _dio.post(
      '/me/rebate/apply',
      options: _groupOptions,
    );
    return AgentRebateApplyDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentRebateApplyDto> fetchPersonalRebateApplyStatus() async {
    final response = await _dio.get(
      '/me/rebate/apply/status',
      options: _groupOptions,
    );
    return AgentRebateApplyDto.fromJson(_unwrapMap(response.data));
  }

  /// 「历」入口调试日志：请求前打印 method / url / query / X-Group-Id，
  /// 响应后打印 statusCode；仅 debug 构建输出。
  void _debugLogHistoryRequest({
    required String tag,
    required String path,
    required Map<String, dynamic> query,
    required Options options,
    Response<dynamic>? response,
  }) {
    if (!kDebugMode) return;
    final groupId = options.headers?[AgentRebateHttp.groupHeader] ??
        AgentRebateHttp.groupId ??
        '';
    final url = '${_dio.options.baseUrl}$path';
    if (response == null) {
      debugPrint(
        '[AgentRebate][$tag] request GET $url '
        'query=$query ${AgentRebateHttp.groupHeader}=$groupId',
      );
      return;
    }
    debugPrint(
      '[AgentRebate][$tag] response GET $url '
      'status=${response.statusCode} query=$query '
      '${AgentRebateHttp.groupHeader}=$groupId',
    );
  }

  Future<AgentRebateHistoryDto> fetchHistory(AgentRebateDateRange range) async {
    const path = '/me/agent/rebate/history';
    final query = <String, dynamic>{
      'startDate': range.startApiValue,
      'endDate': range.endApiValue,
    };
    final options = _groupOptions;
    _debugLogHistoryRequest(
      tag: 'fetchHistory',
      path: path,
      query: query,
      options: options,
    );
    final response = await _dio.get(
      path,
      queryParameters: query,
      options: options,
    );
    _debugLogHistoryRequest(
      tag: 'fetchHistory',
      path: path,
      query: query,
      options: options,
      response: response,
    );
    return AgentRebateHistoryDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentRebateHistoryDto> fetchPersonalHistory(
    AgentRebateDateRange range,
  ) async {
    const path = '/me/agent/rebate/personal-history';
    final query = <String, dynamic>{
      'startDate': range.startApiValue,
      'endDate': range.endApiValue,
    };
    final options = _groupOptions;
    _debugLogHistoryRequest(
      tag: 'fetchPersonalHistory',
      path: path,
      query: query,
      options: options,
    );
    final response = await _dio.get(
      path,
      queryParameters: query,
      options: options,
    );
    _debugLogHistoryRequest(
      tag: 'fetchPersonalHistory',
      path: path,
      query: query,
      options: options,
      response: response,
    );
    return AgentRebateHistoryDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentDescendantsDto> fetchDescendants({
    AgentDescendantScope scope = AgentDescendantScope.all,
    int? page,
    int? pageSize,
  }) async {
    final query = <String, dynamic>{'scope': scope.apiValue};
    if (page != null) {
      query['page'] = page < 1 ? 1 : page;
    }
    if (pageSize != null) {
      query['pageSize'] = pageSize.clamp(1, 200);
    }
    final response = await _dio.get(
      '/me/agent/descendants',
      queryParameters: query,
      options: _groupOptions,
    );
    return AgentDescendantsDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentFirstLevelAgentsDto> fetchFirstLevelAgents() async {
    final response = await _dio.get(
      '/me/agent/first-level-agents',
      options: _groupOptions,
    );
    return AgentFirstLevelAgentsDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentDescendantDetailDto> fetchDescendantDetail(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    final response = await _dio.get(
      '/me/agent/descendants/${Uri.encodeComponent(id)}',
      options: _groupOptions,
    );
    return AgentDescendantDetailDto.fromJson(_unwrapMap(response.data));
  }

  /// 设置直属下级返水，输入单位为万分比：300 = 一万返 300。
  /// 后端接口：PUT /api/v1/me/children/{userId}/rebate。
  Future<Map<String, dynamic>> setChildRebate({
    required String userId,
    required num rebatePer10000,
  }) async {
    final id = userId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    if (rebatePer10000 < 0) {
      throw ArgumentError.value(
        rebatePer10000,
        'rebatePer10000',
        'must not be negative',
      );
    }
    final tenant = SangongGameHttp.tenantId?.trim() ?? '';
    if (tenant.isEmpty) {
      throw StateError('三公租户未设置，无法修改用户返水');
    }
    final response = await SangongGameHttp.adminClient.put(
      '/api/v1/me/children/${Uri.encodeComponent(id)}/rebate',
      data: <String, dynamic>{'rebatePer10000': rebatePer10000},
      options: Options(
        headers: <String, dynamic>{
          SangongGameHttp.tenantHeader: tenant,
          'Content-Type': 'application/json',
        },
      ),
    );
    return _unwrapMap(response.data);
  }

  Future<Map<String, dynamic>> bindAgentChatGroup(
      {required String agentImUserId, required String agentImGroupId}) async {
    final tenant = SangongGameHttp.tenantId?.trim() ?? '';
    if (tenant.isEmpty) throw StateError('三公租户未设置');
    final normalizedGroupId = normalizeAgentChatGroupId(agentImGroupId);
    final response = await SangongGameHttp.adminClient.put(
      '/api/v1/admin/agent/chat-binding',
      data: {
        'agentImUserId': agentImUserId.trim(),
        'agentImGroupId': normalizedGroupId,
        'isActive': true
      },
      options: Options(headers: {
        SangongGameHttp.tenantHeader: tenant,
        'Content-Type': 'application/json'
      }),
    );
    return _unwrapMap(response.data);
  }

  Future<void> removeAgentChatGroup(String agentImUserId) async {
    final tenant = SangongGameHttp.tenantId?.trim() ?? '';
    await SangongGameHttp.adminClient.delete('/api/v1/admin/agent/chat-binding',
        queryParameters: {'agentImUserId': agentImUserId.trim()},
        options: Options(headers: {SangongGameHttp.tenantHeader: tenant}));
  }

  /// 查询指定用户返水信息，单位为万分比。
  Future<Map<String, dynamic>> fetchMyRebate(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) throw ArgumentError('用户 ID 不能为空');
    final tenant = SangongGameHttp.tenantId?.trim() ?? '';
    if (tenant.isEmpty) {
      throw StateError('三公租户未设置，无法查询用户返水');
    }
    final response = await SangongGameHttp.client.get(
      '/api/v1/me/children/${Uri.encodeComponent(id)}/rebate',
      options: Options(headers: <String, dynamic>{
        SangongGameHttp.tenantHeader: tenant,
        'Content-Type': 'application/json',
      }),
    );
    return _unwrapMap(response.data);
  }

  /// 查询指定用户的上级代理。
  Future<Map<String, dynamic>> fetchUserParent(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) throw ArgumentError('用户 ID 不能为空');
    final tenant = SangongGameHttp.tenantId?.trim() ?? '';
    if (tenant.isEmpty) throw StateError('三公租户未设置，无法查询上级');
    final response = await SangongGameHttp.client.get(
      GroupQueryEndpoint.resolve(
          '/api/v1/me/users/${Uri.encodeComponent(id)}/parent'),
      options: Options(headers: <String, dynamic>{
        SangongGameHttp.tenantHeader: tenant,
      }),
    );
    return _unwrapMap(response.data);
  }

  Future<Map<String, dynamic>> setChildParent({
    required String childUserId,
    required String parentUserId,
  }) async {
    final child = childUserId.trim();
    final parent = parentUserId.trim();
    if (child.isEmpty || parent.isEmpty) {
      throw ArgumentError('用户 ID 不能为空');
    }
    final tenant = SangongGameHttp.tenantId?.trim() ?? '';
    if (tenant.isEmpty) throw StateError('三公租户未设置');
    final response = await SangongGameHttp.client.put(
      '/api/v1/me/hierarchy/${Uri.encodeComponent(child)}/parent',
      data: <String, dynamic>{'parentUserId': parent},
      options: Options(headers: <String, dynamic>{
        SangongGameHttp.tenantHeader: tenant,
        'Content-Type': 'application/json',
      }),
    );
    return _unwrapMap(response.data);
  }

  Future<Map<String, dynamic>> removeChildParent(String childUserId) async {
    final child = childUserId.trim();
    if (child.isEmpty) throw ArgumentError('用户 ID 不能为空');
    final tenant = SangongGameHttp.tenantId?.trim() ?? '';
    if (tenant.isEmpty) throw StateError('三公租户未设置');
    final response = await SangongGameHttp.client.delete(
      '/api/v1/me/hierarchy/${Uri.encodeComponent(child)}',
      options: Options(headers: <String, dynamic>{
        SangongGameHttp.tenantHeader: tenant,
      }),
    );
    return _unwrapMap(response.data);
  }

  Future<AgentDescendantsHistoryDto> fetchDescendantsHistory(
    AgentRebateDateRange range, {
    String? userId,
  }) async {
    final target = userId?.trim() ?? '';
    final response = await _dio.get(
      '/me/agent/descendants/history',
      queryParameters: <String, dynamic>{
        'startDate': range.startApiValue,
        'endDate': range.endApiValue,
        if (target.isNotEmpty) 'userId': target,
      },
      options: _groupOptions,
    );
    return AgentDescendantsHistoryDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentRebateExportTaskDto> submitHistoryExport(
    AgentRebateDateRange range,
  ) async {
    final response = await _dio.post(
      '/me/agent/rebate/history/export',
      data: <String, dynamic>{
        'startDate': range.startApiValue,
        'endDate': range.endApiValue,
        'fileType': 'CSV',
        'includeDetail': true,
      },
      options: _groupOptions,
    );
    return AgentRebateExportTaskDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentRebateExportTaskDto> fetchHistoryExportTask(
    String taskNo,
  ) async {
    final response = await _dio.get(
      '/me/agent/rebate/history/export/${Uri.encodeComponent(taskNo)}',
      options: _groupOptions,
    );
    return AgentRebateExportTaskDto.fromJson(_unwrapMap(response.data));
  }

  Future<AgentRebateDownload> downloadHistoryExport(
    String taskNo, {
    required String fallbackFileName,
  }) async {
    final response = await _dio.get<List<int>>(
      '/me/agent/rebate/history/export/${Uri.encodeComponent(taskNo)}/download',
      options: AgentRebateHttp.options(responseType: ResponseType.bytes),
    );
    return AgentRebateDownload(
      bytes: response.data ?? const <int>[],
      fileName: _downloadFileName(
        response.headers.value('content-disposition'),
        fallback: fallbackFileName,
      ),
    );
  }

  String _encodeGroupId(String groupId) {
    final normalized = ChatIdFormat.normalizeGroupId(groupId.trim());
    final id = normalized.isNotEmpty ? normalized : groupId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(groupId, 'groupId', 'must not be empty');
    }
    return Uri.encodeComponent(id);
  }

  String _downloadFileName(String? disposition, {required String fallback}) {
    final raw = disposition?.trim() ?? '';
    final encoded = RegExp(
      r'''filename\*\s*=\s*UTF-8''([^;]+)''',
      caseSensitive: false,
    ).firstMatch(raw)?.group(1);
    if (encoded != null && encoded.isNotEmpty) {
      try {
        return Uri.decodeComponent(encoded.trim());
      } catch (_) {}
    }
    final plain = RegExp(
      r'''filename\s*=\s*"?([^";]+)"?''',
      caseSensitive: false,
    ).firstMatch(raw)?.group(1);
    return plain?.trim().isNotEmpty == true ? plain!.trim() : fallback;
  }

  Map<String, dynamic> _unwrapMap(dynamic raw) {
    final payload = unwrapApiPayload(raw);
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    throw const FormatException('Agent rebate response data must be an object');
  }
}
