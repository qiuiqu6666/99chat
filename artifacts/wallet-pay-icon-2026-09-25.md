# 红包页“我的钱包”图标切换

## 原因与修改

- `RedPacketController.pay` 初值是 `WalletPayMethodDto.empty`，其展示币种是 USDT、余额为 0。付款方式和保存的默认币种异步返回前，页面会把这些占位字段当作真实展示数据。
- `WalletPayCoinIcon` 原来只要 `logoUrl` 非空就优先加载网络图片，只有无 URL 或下载失败才用内置的 `assets/img/platform_99.webp`；下载期间没有币种专用的 placeholder。
- 99 币现在直接使用内置 logo，与已有支付密码弹窗的策略一致。按实际显示尺寸和设备像素比解码，避免小图标解码完整 1024 × 1024 图片。徽标不再随 logoUrl 有无变化。
- 其他币种加载或下载失败时显示对应币种的备用图。币种切换时不保留上一币种的网络图像。
- 尚未确认付款币种时显示中性的“钱包”图标；红包余额显示“—”，转账页也不再显示空 DTO 的币种和零余额。没有把默认币种猜成 99，也没有构造余额。

第一次没有付款方式缓存时仍需等待接口确认币种；本次去除的是品牌图的额外下载和错误的初始币种展示，并不承诺在币种资料未知时立即展示真实币种。

## 影响分析

仓库：`C:/Users/ASUS/Downloads/Telegram Desktop/99999999`，GitNexus 注册名 `99chat-ios-actions-precommit`；所用索引快照时间 2026-09-25 14:29:14 UTC。这三个文件在本次修改前无工作区差异。

编辑前已执行 WalletPayCoinIcon、_fallbackCoinFace、_PayCard、_CoinPill 的 upstream impact。符号解析返回 UNKNOWN / not found，不能作为无调用证据；随后补做文件级图谱分析，并核对当前源代码及全部符号引用。

- pay_method_sheet.dart：文件级 MEDIUM，6 个直接导入者、3 层共 14 个关联文件。直接导入者为红包页、转账页、红包付款弹层包装、电费缴费、手机充值、utility_account_flow。
- red_packet_screen.dart、wallet_transfer_screen.dart：文件级 LOW，分别 1 个直接导入者、3 层 25 个关联文件。
- 文件节点没有流程归属，图谱的 processes_affected=0 不代表业务流程无影响。源代码确认图标用于红包入口、转账入口及共用付款方式列表，后者也被生活缴费入口使用。
- 修改范围仅为三个文件内的显示逻辑，支付选择、金额计算和提交逻辑不变。

## 验证

- flutter analyze：三个修改文件，无问题。
- 现有回归测试 16 项通过：red_packet_member_test、wallet_detail_coin_code_test、wallet_red_packet_card_amount_test。
- git diff --check 通过。
- 确认内置 logo 文件存在，且 assets/img/ 已被 pubspec.yaml 收录；人工对照素材与用户截图。
- 尚未进行真机弱网加载或页面录屏验证；以上现有测试不等同于图标切换的真机视觉验证。
- 未提交、未发布。

## 后续：付款方式行底部溢出

用户截图中余额/法币折算列底部溢出。原因是 `_PayMethodRow` 高度固定为 `132.h`，扣除上下 padding 后，要放下 `34.w` 的选择标记、`30.sp` 余额、`22.sp` 折算金额及间距。屏幕宽高缩放比例和文字缩放独立，正常字体在 375 × 667 的组件复现中也超出约 12 px。

修改为最小行高，由内容决定最终高度；两侧 Column 使用 mainAxisSize.min，移除依赖固定高度的 Spacer。左右文字列都有宽度约束，长金额可以换行完整显示。原有列表滚动和确认选择流程保留。

编辑前对 `_PayMethodRow` 做 context/impact，符号仍为 UNKNOWN；文件 impact 为 MEDIUM、6 个直接导入者、3 层共 14 个关联文件，与上文范围相同。源代码确认私有行组件仅由本文件的付款方式列表创建。文件级 0 个流程不能代表业务流程无影响。

验证：新增 `wallet_pay_method_sheet_layout_test.dart`，修复前 375 × 667 普通字体能复现 RenderFlex bottom overflow；修复后 320 × 568 / 375 × 667 × 1.0 / 2.0 字体共 4 组通过，检查余额及法币文本位于各自卡片内，并验证选择 USDT 后确认返回正确币种。包含长余额及滚动后确认。未进行真机验收。
