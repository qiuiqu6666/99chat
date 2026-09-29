import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_msg_create_info_result.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

bool isOutgoingMediaMessage(V2TimMessage message) => const <int>{
      MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
      MessageElemType.V2TIM_ELEM_TYPE_VIDEO,
      MessageElemType.V2TIM_ELEM_TYPE_SOUND,
      MessageElemType.V2TIM_ELEM_TYPE_FILE,
    }.contains(message.elemType);

Future<V2TimMsgCreateInfoResult?> recreateOutgoingMessage(
  MessageService service,
  V2TimMessage message,
) async {
  V2TimMsgCreateInfoResult? result;
  switch (message.elemType) {
    case MessageElemType.V2TIM_ELEM_TYPE_TEXT:
      final text = message.textElem?.text ?? '';
      final atUsers = (message.groupAtUserList ?? const <String>[])
          .where((user) => user.trim().isNotEmpty)
          .toList(growable: false);
      result = atUsers.isEmpty
          ? await service.createTextMessage(text: text)
          : await service.createTextAtMessage(text: text, atUserList: atUsers);
      break;
    case MessageElemType.V2TIM_ELEM_TYPE_CUSTOM:
      result = await service.createCustomMessage(
        data: message.customElem?.data ?? '',
      );
      break;
    case MessageElemType.V2TIM_ELEM_TYPE_FACE:
      result = await service.createFaceMessage(
        index: message.faceElem?.index ?? 0,
        data: message.faceElem?.data ?? '',
      );
      break;
    case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
      final path = message.imageElem?.path?.trim() ?? '';
      if (path.isEmpty) return null;
      result = await service.createImageMessage(
        imageName: _fileName(path),
        imagePath: path,
      );
      break;
    case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
      final elem = message.videoElem;
      final path = elem?.videoPath?.trim() ?? '';
      final snapshot = elem?.snapshotPath?.trim() ?? '';
      if (path.isEmpty || snapshot.isEmpty) return null;
      result = await service.createVideoMessage(
        videoPath: path,
        type: (elem?.videoType?.trim().isNotEmpty ?? false)
            ? elem!.videoType
            : _extension(path, fallback: 'mp4'),
        duration: elem?.duration ?? 0,
        snapshotPath: snapshot,
      );
      break;
    case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
      final elem = message.soundElem;
      final path = elem?.path?.trim() ?? '';
      if (path.isEmpty) return null;
      result = await service.createSoundMessage(
        soundPath: path,
        duration: elem?.duration ?? 0,
      );
      break;
    case MessageElemType.V2TIM_ELEM_TYPE_FILE:
      final elem = message.fileElem;
      final path = elem?.path?.trim() ?? '';
      if (path.isEmpty) return null;
      result = await service.createFileMessage(
        filePath: path,
        fileName: elem?.fileName?.trim().isNotEmpty == true
            ? elem!.fileName!
            : _fileName(path),
      );
      break;
    case MessageElemType.V2TIM_ELEM_TYPE_LOCATION:
      final elem = message.locationElem;
      if (elem == null) return null;
      result = await service.createLocationMessage(
        desc: elem.desc ?? '',
        longitude: elem.longitude,
        latitude: elem.latitude,
      );
      break;
    case MessageElemType.V2TIM_ELEM_TYPE_MERGER:
      final elem = message.mergerElem;
      final ids = _nativeMergerMessages(elem)
          .map((item) => item.msgID?.trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (ids.isEmpty) return null;
      result = await service.createMergerMessage(
        msgIDList: ids,
        title: elem?.title ?? '',
        abstractList: elem?.abstractList ?? const <String>[],
        compatibleText: _nativeMergerCompatibleText(elem),
      );
      break;
    default:
      result = await service.createForwardMessage(
        msgID: message.msgID,
        message: message,
        webMessageInstance: message.messageFromWeb,
      );
      break;
  }
  final id = result?.id?.trim() ?? '';
  final created = result?.messageInfo;
  if (id.isEmpty || created == null) return null;
  created.id = id;
  final cloudCustomData = message.cloudCustomData?.trim() ?? '';
  if (cloudCustomData.isNotEmpty) {
    created.cloudCustomData = message.cloudCustomData;
  }
  return result;
}

List<V2TimMessage> _nativeMergerMessages(Object? elem) {
  try {
    final dynamic nativeElem = elem;
    return (nativeElem.messageList as List<dynamic>?)
            ?.whereType<V2TimMessage>()
            .toList(growable: false) ??
        const <V2TimMessage>[];
  } catch (_) {
    return const <V2TimMessage>[];
  }
}

String _nativeMergerCompatibleText(Object? elem) {
  try {
    final dynamic nativeElem = elem;
    return nativeElem.compatibleText?.toString() ?? '';
  } catch (_) {
    return '';
  }
}

String _fileName(String path) => path.replaceAll('\\', '/').split('/').last;

String _extension(String path, {required String fallback}) {
  final name = _fileName(path);
  final dot = name.lastIndexOf('.');
  return dot >= 0 && dot < name.length - 1
      ? name.substring(dot + 1).toLowerCase()
      : fallback;
}
