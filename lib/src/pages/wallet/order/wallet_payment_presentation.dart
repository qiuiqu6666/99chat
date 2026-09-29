import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'wallet_order.dart';

/// Payment and transport are independent facts. A successful HTTP/auth flow is
/// not evidence of a committed payment or of a delivered chat card.
class WalletPaymentPresentation {
  final WalletOrderState state;
  final WalletOrderResult? result;
  const WalletPaymentPresentation(this.state, this.result);

  bool get paymentCommitted => state == WalletOrderState.success;
  bool get deliveryPending =>
      paymentCommitted &&
      result?.data['serverManagedCard'] == true &&
      result?.data['cardDeliveryState'] != 'SENT';

  String title(AppI18n i18n) => paymentCommitted
      ? i18n.t(
          zhHans: '支付成功',
          zhHant: '支付成功',
          en: 'Payment successful',
          ja: '支払いが完了しました',
          ko: '결제가 완료되었습니다')
      : i18n.t(
          zhHans: '正在确认支付',
          zhHant: '正在確認支付',
          en: 'Confirming payment',
          ja: '支払いを確認しています',
          ko: '결제를 확인하고 있습니다');

  String message(AppI18n i18n) {
    if (!paymentCommitted) {
      return i18n.t(
          zhHans: '结果确认中，请勿重复付款，可在钱包记录查看',
          zhHant: '結果確認中，請勿重複付款，可在錢包記錄查看',
          en: 'Confirmation pending. Do not pay again. Check wallet history.',
          ja: '確認中です。再度支払わず、ウォレット履歴で確認してください。',
          ko: '확인 중입니다. 다시 결제하지 말고 지갑 내역을 확인하세요.');
    }
    return '';
  }
}
