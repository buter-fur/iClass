import 'package:flutter/material.dart';

/// 自定义颜色对话框（手写实现，不依赖第三方取色器——后者在 Windows 显示缩放下
/// 布局溢出、滑块无法拖动）：
/// - 上方色块：左右调饱和度、上下调明暗（只改变已选基础色的深浅，不改变色相）
/// - 中间色相条：拖动选择基础色
/// - 下方：颜色预览 + 十六进制色值输入
class ColorPickerDialog extends StatefulWidget {
  final Color initial;

  const ColorPickerDialog({super.key, required this.initial});

  /// 弹出对话框；确定返回所选颜色，取消返回 null。
  static Future<Color?> show(BuildContext context, {required Color initial}) {
    return showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initial: initial),
    );
  }

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  static const double _squareW = 300;
  static const double _squareH = 180;
  static const double _barW = 300;

  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex =
      TextEditingController(text: _toHex(widget.initial));

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static String _toHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// 色块拖动：横向 = 饱和度，纵向 = 明度（上亮下暗），色相不变。
  void _updateSv(Offset pos) {
    final s = (pos.dx / _squareW).clamp(0.0, 1.0).toDouble();
    final v = 1 - (pos.dy / _squareH).clamp(0.0, 1.0).toDouble();
    setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
    _syncHex();
  }

  /// 色相条拖动：改变基础色。
  void _updateHue(Offset pos) {
    final h = (pos.dx / _barW * 360).clamp(0.0, 359.9).toDouble();
    setState(() => _hsv = _hsv.withHue(h));
    _syncHex();
  }

  /// 拖动时同步十六进制输入框（仅拖动时写入，不与手动输入打架）。
  void _syncHex() {
    final hex = _toHex(_hsv.toColor());
    if (_hex.text != hex) _hex.text = hex;
  }

  void _onHexInput(String text) {
    final t = text.trim().replaceFirst('#', '');
    if (t.length != 6) return;
    final v = int.tryParse(t, radix: 16);
    if (v != null) setState(() => _hsv = HSVColor.fromColor(Color(v)));
  }

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    return AlertDialog(
      title: const Text('自定义卡片颜色'),
      content: SizedBox(
        width: _squareW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSvSquare(hueColor),
            const SizedBox(height: 14),
            _buildHueBar(),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _hsv.toColor(),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    onChanged: _onHexInput,
                    decoration: const InputDecoration(
                      labelText: '十六进制色值',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _hsv.toColor()),
          child: const Text('确定'),
        ),
      ],
    );
  }

  /// 饱和度/明度色块：横渐变白→基础色，上叠纵渐变透明→黑。
  Widget _buildSvSquare(Color hueColor) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) => _updateSv(d.localPosition),
      onPanUpdate: (d) => _updateSv(d.localPosition),
      child: SizedBox(
        width: _squareW,
        height: _squareH,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(colors: [Colors.white, hueColor]),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black],
                  ),
                ),
              ),
            ),
            // 位置指示点（s=左右位置，v=上下位置）
            Positioned(
              left: _hsv.saturation * _squareW - 8,
              top: (1 - _hsv.value) * _squareH - 8,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hsv.toColor(),
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 色相条：彩虹渐变横条 + 指示点。
  Widget _buildHueBar() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) => _updateHue(d.localPosition),
      onPanUpdate: (d) => _updateHue(d.localPosition),
      child: SizedBox(
        width: _barW,
        height: 18,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: _hsv.hue / 360 * _barW - 9,
              top: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
