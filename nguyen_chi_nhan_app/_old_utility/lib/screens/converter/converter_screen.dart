import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/unit_category.dart';
import '../../theme/app_theme.dart';

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  UnitCategory _selectedCategory = UnitCategory.all.first;
  late String _fromUnitId;
  late String _toUnitId;

  final TextEditingController _inputController = TextEditingController(text: '37');
  double _inputValue = 37.0;
  double _resultValue = 98.6;
  SmartAlert? _currentAlert;

  @override
  void initState() {
    super.initState();
    _fromUnitId = _selectedCategory.units[0].id;
    _toUnitId = _selectedCategory.units.length > 1 ? _selectedCategory.units[1].id : _selectedCategory.units[0].id;
    _recalculate();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _onCategoryChanged(UnitCategory category) {
    setState(() {
      _selectedCategory = category;
      _fromUnitId = category.units[0].id;
      _toUnitId = category.units.length > 1 ? category.units[1].id : category.units[0].id;

      // Sensible initial values per category
      if (category.type == CategoryType.temperature) {
        _inputValue = 37.0;
        _inputController.text = '37';
      } else if (category.type == CategoryType.length) {
        _inputValue = 1000.0;
        _inputController.text = '1000';
      } else if (category.type == CategoryType.weight) {
        _inputValue = 70.0;
        _inputController.text = '70';
      } else if (category.type == CategoryType.speed) {
        _inputValue = 100.0;
        _inputController.text = '100';
      } else {
        _inputValue = 1.0;
        _inputController.text = '1';
      }

      _recalculate();
    });
  }

  void _recalculate() {
    final parsed = double.tryParse(_inputController.text.replaceAll(',', '.'));
    if (parsed == null) {
      setState(() {
        _resultValue = 0.0;
        _currentAlert = null;
      });
      return;
    }

    _inputValue = parsed;
    final converted = UnitCategory.convert(
      category: _selectedCategory.type,
      fromUnit: _fromUnitId,
      toUnit: _toUnitId,
      value: _inputValue,
    );

    final alert = UnitCategory.generateSmartAlert(
      category: _selectedCategory.type,
      fromUnit: _fromUnitId,
      inputValue: _inputValue,
      toUnit: _toUnitId,
      resultValue: converted,
    );

    setState(() {
      _resultValue = converted;
      _currentAlert = alert;
    });
  }

  void _swapUnits() {
    setState(() {
      final temp = _fromUnitId;
      _fromUnitId = _toUnitId;
      _toUnitId = temp;
      _recalculate();
    });
  }

  void _applyPreset(String label, double val, {String? fromUnit, String? toUnit}) {
    setState(() {
      if (fromUnit != null) {
        _fromUnitId = fromUnit;
        if (_toUnitId == fromUnit) {
          final other = _selectedCategory.units.firstWhere(
            (u) => u.id != fromUnit,
            orElse: () => _selectedCategory.units.first,
          );
          _toUnitId = other.id;
        }
      }
      if (toUnit != null) {
        _toUnitId = toUnit;
      }
      _inputController.text = label;
      _recalculate();
    });
  }

  void _copyResult() {
    final fromUnit = _selectedCategory.units.firstWhere((u) => u.id == _fromUnitId);
    final toUnit = _selectedCategory.units.firstWhere((u) => u.id == _toUnitId);
    final inputStr = _inputController.text.isNotEmpty ? _inputController.text : _formatNumber(_inputValue);
    final text = '$inputStr ${fromUnit.symbol} = ${_formatNumber(_resultValue)} ${toUnit.symbol}';
    Clipboard.setData(ClipboardData(text: text));

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Đã sao chép: $text')),
          ],
        ),
        backgroundColor: AppTheme.converterColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatNumber(double val) {
    if (val.abs() >= 1000000 || (val.abs() < 0.0001 && val != 0)) {
      return val.toStringAsExponential(4);
    }
    // If integer, don't show decimals
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quy Đổi & Đo Lường'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Thông tin quy chuẩn',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (ctx) => _buildInfoSheet(ctx),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Category Horizontal Tabs
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: UnitCategory.all.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = UnitCategory.all[index];
                  final isSelected = cat.type == _selectedCategory.type;
                  return ChoiceChip(
                    avatar: Icon(
                      cat.icon,
                      size: 18,
                      color: isSelected ? Colors.white : cat.color,
                    ),
                    label: Text(cat.name),
                    selected: isSelected,
                    selectedColor: cat.color,
                    backgroundColor: theme.cardColor,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(
                        color: isSelected ? Colors.transparent : theme.dividerColor.withAlpha(50),
                      ),
                    ),
                    onSelected: (selected) {
                      if (selected) _onCategoryChanged(cat);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Main Conversion Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: _selectedCategory.color.withAlpha(40)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // Input Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _inputController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Giá trị nhập',
                              labelStyle: TextStyle(color: _selectedCategory.color),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: _selectedCategory.color, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              suffixIcon: _inputController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 20),
                                      onPressed: () {
                                        _inputController.clear();
                                        _recalculate();
                                      },
                                    )
                                  : null,
                            ),
                            onChanged: (_) => _recalculate(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // From Dropdown
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('from_${_selectedCategory.type}_$_fromUnitId'),
                            initialValue: _fromUnitId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Từ',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            items: _selectedCategory.units.map((u) {
                              return DropdownMenuItem(
                                value: u.id,
                                child: Text('${u.symbol} (${u.name})', overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _fromUnitId = val;
                                  _recalculate();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Swap Button & Direction Indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 1,
                          width: 80,
                          color: theme.dividerColor.withAlpha(80),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: _selectedCategory.color.withAlpha(30),
                              foregroundColor: _selectedCategory.color,
                            ),
                            icon: const Icon(Icons.swap_vert_rounded, size: 26),
                            tooltip: 'Đảo chiều chuyển đổi',
                            onPressed: _swapUnits,
                          ),
                        ),
                        Container(
                          height: 1,
                          width: 80,
                          color: theme.dividerColor.withAlpha(80),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Result Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 3,
                          child: InkWell(
                            onTap: _copyResult,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: _selectedCategory.color.withAlpha(15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _selectedCategory.color.withAlpha(60)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Kết quả quy đổi',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _selectedCategory.color,
                                          ),
                                        ),
                                      ),
                                      Tooltip(
                                        message: 'Sao chép',
                                        child: Icon(Icons.copy_rounded, size: 14, color: _selectedCategory.color),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    _formatNumber(_resultValue),
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: theme.textTheme.titleLarge?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // To Dropdown
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('to_${_selectedCategory.type}_$_toUnitId'),
                            initialValue: _toUnitId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Sang',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            items: _selectedCategory.units.map((u) {
                              return DropdownMenuItem(
                                value: u.id,
                                child: Text('${u.symbol} (${u.name})', overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _toUnitId = val;
                                  _recalculate();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Copy Action Button
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _copyResult,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Sao chép kết quả'),
                        style: TextButton.styleFrom(
                          foregroundColor: _selectedCategory.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // SMART NOTIFICATION / REASONABLE ALERT BANNER
            if (_currentAlert != null) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _currentAlert!.backgroundColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _currentAlert!.color.withAlpha(120),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _currentAlert!.color.withAlpha(25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _currentAlert!.color.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _currentAlert!.icon,
                        color: _currentAlert!.color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentAlert!.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _currentAlert!.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currentAlert!.message,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: Colors.black87.withAlpha(200),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Quick Preset Chips for convenient testing
            Text(
              'Mốc Quy Chuẩn Nhanh',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.textTheme.bodyMedium?.color?.withAlpha(180),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _buildPresetsForCategory(),
            ),

            const SizedBox(height: 24),

            // Summary Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withAlpha(40)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded, color: _selectedCategory.color, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Hệ thống tự động phân tích và đưa ra thông báo cảnh báo hợp lý khi bạn nhập nhiệt độ tới hạn, điểm sôi, đóng băng hoặc vượt ngưỡng vật lý.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPresetsForCategory() {
    if (_selectedCategory.type == CategoryType.temperature) {
      return [
        _presetChip('-273.15', '0 Kelvin (Độ 0 tuyệt đối)', -273.15, fromUnit: 'c', toUnit: 'k'),
        _presetChip('0', '0°C (Nước đóng băng)', 0, fromUnit: 'c', toUnit: 'f'),
        _presetChip('25', '25°C (Nhiệt độ phòng)', 25, fromUnit: 'c', toUnit: 'f'),
        _presetChip('37', '37°C (Thân nhiệt chuẩn)', 37, fromUnit: 'c', toUnit: 'f'),
        _presetChip('39', '39°C (Sốt cao)', 39, fromUnit: 'c', toUnit: 'f'),
        _presetChip('100', '100°C (Nước sôi)', 100, fromUnit: 'c', toUnit: 'f'),
      ];
    } else if (_selectedCategory.type == CategoryType.speed) {
      return [
        _presetChip('60', '60 km/h (Đô thị)', 60, fromUnit: 'kmh', toUnit: 'ms'),
        _presetChip('120', '120 km/h (Cao tốc max)', 120, fromUnit: 'kmh', toUnit: 'mph'),
        _presetChip('1235', '1235 km/h (Mach 1)', 1235, fromUnit: 'kmh', toUnit: 'ms'),
      ];
    } else if (_selectedCategory.type == CategoryType.length) {
      return [
        _presetChip('1', '1 mét', 1, fromUnit: 'm', toUnit: 'ft'),
        _presetChip('1000', '1 km (1000m)', 1000, fromUnit: 'm', toUnit: 'km'),
        _presetChip('1', '1 Dặm (Mile)', 1, fromUnit: 'mi', toUnit: 'km'),
      ];
    } else if (_selectedCategory.type == CategoryType.weight) {
      return [
        _presetChip('1', '1 Kilôgam', 1, fromUnit: 'kg', toUnit: 'lb'),
        _presetChip('500', '500 Gam', 500, fromUnit: 'g', toUnit: 'kg'),
        _presetChip('1', '1 Tấn (1000kg)', 1, fromUnit: 'ton', toUnit: 'kg'),
      ];
    } else {
      return [
        _presetChip('1', '1 Lít', 1, fromUnit: 'l', toUnit: 'ml'),
        _presetChip('1', '1 Gallon', 1, fromUnit: 'gal', toUnit: 'l'),
      ];
    }
  }

  Widget _presetChip(String label, String tooltip, double val, {String? fromUnit, String? toUnit}) {
    return ActionChip(
      label: Text(label),
      tooltip: tooltip,
      onPressed: () => _applyPreset(label, val, fromUnit: fromUnit, toUnit: toUnit),
      avatar: const Icon(Icons.bolt_rounded, size: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildInfoSheet(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, color: _selectedCategory.color),
              const SizedBox(width: 8),
              Text(
                'Quy chuẩn thông báo hợp lý',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('• Cảnh báo đỏ: Khi nhiệt độ dưới 0 Kelvin hoặc sốt cao nguy hiểm (> 38.5°C).'),
          const SizedBox(height: 8),
          const Text('• Thông báo vàng: Khi nhiệt độ sốt nhẹ (37.5°C - 38.5°C) hoặc tốc độ vượt giới hạn cao tốc.'),
          const SizedBox(height: 8),
          const Text('• Thông báo xanh lá: Khi thân nhiệt nằm trong dải sinh lý bình thường khỏe mạnh (36.5°C - 37.5°C).'),
          const SizedBox(height: 8),
          const Text('• Thông báo xanh dương: Điểm mốc vật lý như nước sôi (100°C), nước đá (0°C), vận tốc âm thanh Mach 1.'),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
