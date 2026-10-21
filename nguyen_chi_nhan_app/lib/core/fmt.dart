import 'package:intl/intl.dart';

final _money = NumberFormat.decimalPattern('vi_VN');

/// 1200000 -> 1.200.000đ
String vnd(num v) => '${_money.format(v.round())}đ';

/// Đọc số tiền thành chữ (ngắn gọn): 1200000 -> "Một triệu hai trăm nghìn đồng"
String moneyWords(num value) {
  final n = value.round();
  if (n <= 0) return 'Không đồng';
  const units = ['', 'nghìn', 'triệu', 'tỷ'];
  const digits = ['không', 'một', 'hai', 'ba', 'bốn', 'năm', 'sáu', 'bảy', 'tám', 'chín'];
  String three(int x, bool full) {
    final h = x ~/ 100, t = (x % 100) ~/ 10, u = x % 10;
    final out = <String>[];
    if (full || h > 0) out.add('${digits[h]} trăm');
    if (t > 1) {
      out.add('${digits[t]} mươi');
      if (u == 1) {
        out.add('mốt');
      } else if (u == 5) {
        out.add('lăm');
      } else if (u > 0) {
        out.add(digits[u]);
      }
    } else if (t == 1) {
      out.add('mười');
      if (u == 5) {
        out.add('lăm');
      } else if (u > 0) {
        out.add(digits[u]);
      }
    } else if (u > 0) {
      if (full || h > 0) out.add('lẻ');
      out.add(digits[u]);
    }
    return out.join(' ');
  }

  final groups = <int>[];
  var x = n;
  while (x > 0) {
    groups.add(x % 1000);
    x ~/= 1000;
  }
  final parts = <String>[];
  for (var i = groups.length - 1; i >= 0; i--) {
    if (groups[i] == 0) continue;
    parts.add('${three(groups[i], i != groups.length - 1)} ${units[i % 4]}'.trim());
  }
  final s = '${parts.join(' ')} đồng';
  return s[0].toUpperCase() + s.substring(1);
}

DateTime _local(dynamic v) => (v is DateTime ? v : DateTime.parse(v.toString())).toLocal();

/// 09:12
String hm(dynamic v) => DateFormat('HH:mm').format(_local(v));

/// "Hôm nay, 09:12" / "Hôm qua" / "3 ngày trước" / 12/10/2026
String relative(dynamic v, {bool withTime = false}) {
  final d = _local(v);
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days == 0) return withTime ? 'Hôm nay, ${hm(d)}' : 'Hôm nay';
  if (days == 1) return withTime ? 'Hôm qua, ${hm(d)}' : 'Hôm qua';
  if (days < 7) return '$days ngày trước';
  return DateFormat('dd/MM/yyyy').format(d);
}
