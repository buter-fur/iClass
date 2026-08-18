import 'data_store.dart';

/// 统一的时间来源：设置里开了"模拟时间"（调试用）就用模拟时间，否则用真实时间。
///
/// 提醒引擎、周次计算、界面倒计时都要通过这里取时间，
/// 这样调试提醒时机时不用真的等待。
class TimeService {
  TimeService._();
  static final TimeService instance = TimeService._();

  DateTime now() {
    final sim = DataStore.instance.settings.simulatedNow;
    return sim ?? DateTime.now();
  }
}
