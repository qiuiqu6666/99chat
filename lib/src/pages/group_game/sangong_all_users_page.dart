import 'package:flutter/material.dart';
import 'sangong_user_detail_page.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_admin_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_admin_models.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/settings_widgets.dart';

class SangongAllUsersPage extends StatefulWidget {
  const SangongAllUsersPage({super.key});
  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        AppMaterialPageRoute(builder: (_) => const SangongAllUsersPage()),
      );
  @override
  State<SangongAllUsersPage> createState() => _SangongAllUsersPageState();
}

class _SangongAllUsersPageState extends State<SangongAllUsersPage> {
  static const int _pageSize = 50;

  final _searchController = TextEditingController();
  final List<SangongAdminUserReport> _users = [];
  String _query = '';
  String _lastAutoFillQuery = '';
  bool _pointsDescending = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;
  int _page = 0;
  int _totalPages = 0;

  bool get _hasMore => _page < _totalPages;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _failed = false;
      _loadingMore = false;
      _users.clear();
      _page = 0;
      _totalPages = 0;
    });
    try {
      final result = await SangongAdminApi.instance.fetchUserReports(
        page: 1,
        pageSize: _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _users.addAll(result.users);
        _page = result.page;
        _totalPages = result.totalPages;
        _loading = false;
      });
      _fillIfSearching();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final result = await SangongAdminApi.instance.fetchUserReports(
        page: _page + 1,
        pageSize: _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _users.addAll(result.users);
        _page = result.page;
        _totalPages = result.totalPages;
        _loadingMore = false;
      });
      _fillIfSearching();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingMore = false);
    }
  }

  void _fillIfSearching() {
    if (_query.isEmpty ||
        _query == _lastAutoFillQuery ||
        !_hasMore ||
        _loadingMore) {
      return;
    }
    _lastAutoFillQuery = _query;
    final visible = _visibleUsers();
    if (visible.length < 12) {
      _loadMore();
    }
  }

  List<SangongAdminUserReport> _visibleUsers() {
    final users = _users
        .where((user) =>
            _query.isEmpty ||
            user.nickname.toLowerCase().contains(_query) ||
            user.imUserId.toLowerCase().contains(_query))
        .toList();
    users.sort((a, b) => _pointsDescending
        ? b.balance.compareTo(a.balance)
        : a.balance.compareTo(b.balance));
    return users;
  }

  @override
  Widget build(BuildContext context) {
    final users = _visibleUsers();
    final header = Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() => _query = value.trim().toLowerCase());
                _fillIfSearching();
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 23),
                hintText: '搜索已加载的昵称或 IM UserID',
                isDense: true,
                filled: true,
                fillColor: Color(0xFFF1F3F6),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 15,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                  borderSide: BorderSide(color: Color(0xFF248BFF), width: 1.2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xFFF1F3F6),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              tooltip: _pointsDescending ? '积分从高到低' : '积分从低到高',
              onPressed: () =>
                  setState(() => _pointsDescending = !_pointsDescending),
              icon: Icon(
                _pointsDescending
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: const Color(0xFF3C4653),
              ),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('全部用户'), centerTitle: true),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount:
            1 + (_loading || _failed ? 1 : users.length + (_hasMore ? 1 : 0)),
        itemBuilder: (context, index) {
          if (index == 0) return header;
          if (_loading) return const Center(child: CircularProgressIndicator());
          if (_failed) {
            return TextButton(
                onPressed: _loadFirst, child: const Text('加载失败，点击重试'));
          }
          if (index == users.length + 1) {
            return TextButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(_loadingMore ? '加载中…' : '加载更多用户'));
          }
          return _userCell(context, users[index - 1]);
        },
      ),
    );
  }

  Widget _userCell(BuildContext context, SangongAdminUserReport user) {
    final nickname = user.nickname.trim();
    final id = user.imUserId.trim();
    final avatar = user.faceUrl.trim();
    return SettingsCell(
      onTap: id.isEmpty
          ? null
          : () => Navigator.of(context).push(
                AppMaterialPageRoute(
                  builder: (_) => SangongUserDetailPage(user: user),
                ),
              ),
      leading: CircleAvatar(
        radius: 22,
        backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
        child: avatar.isEmpty
            ? Text((nickname.isNotEmpty ? nickname : id)
                .characters
                .first
                .toUpperCase())
            : null,
      ),
      title: '',
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            nickname.isNotEmpty ? nickname : '未设置昵称',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            '下级 ${user.childrenCount}  ·  返水 ${user.rebatePer10000}',
            style: const TextStyle(color: Color(0xFF8792A2), fontSize: 12),
          ),
        ],
      ),
      trailing: Text(
        '积分 ${user.balance}',
        style: const TextStyle(
          color: Color(0xFFE53935),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      showArrow: false,
      showDivider: true,
    );
  }
}
