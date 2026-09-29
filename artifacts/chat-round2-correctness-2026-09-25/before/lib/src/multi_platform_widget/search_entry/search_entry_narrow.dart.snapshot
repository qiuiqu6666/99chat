import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_search_bar.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/search.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';

class SearchEntryNarrow extends StatefulWidget{
  final TIMUIKitConversationController conversationController;
  const SearchEntryNarrow({Key? key, required this.conversationController}) : super(key: key);

  @override
  State<SearchEntryNarrow> createState() => _SearchEntryNarrowState();
}

class _SearchEntryNarrowState extends State<SearchEntryNarrow> {
  late TIMUIKitConversationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.conversationController;
  }

  void _handleOnConvItemTapedWithPlace(V2TimConversation? selectedConv,
      [MessageAnchor? anchor]) async {
    await openChatWithAnchor(context, selectedConv!, anchor: anchor);
    _controller.reloadData(count: 40);
  }

  Future<void> _openSearch() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      AppMaterialPageRoute(
        settings: const RouteSettings(name: AppRoutes.search),
        builder: (context) => Search(
          onTapConversation: _handleOnConvItemTapedWithPlace,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      ConversationSearchBar(onTap: _openSearch);
}
