import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _phoneController = TextEditingController(text: '0987654321');
  bool _isEditingPhone = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _makePhoneCall() async {
    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.isEmpty) {
      _showFeedback(
        'Vui lòng nhập số điện thoại trước khi gọi!',
        isSuccess: false,
      );
      return;
    }

    final url = Uri.parse('tel:$phoneNumber');
    try {
      final launched = await launchUrl(url, mode: LaunchMode.platformDefault);
      if (!launched) {
        _showFeedback('Không thể khởi chạy cuộc gọi đến $phoneNumber', isSuccess: false);
      } else {
        _showFeedback('Đang chuyển hướng tới trình gọi điện: $phoneNumber', isSuccess: true);
      }
    } catch (e) {
      _showFeedback('Lỗi khi gọi điện: $e', isSuccess: false);
    }
  }

  Future<void> _openYouTubeApp() async {
    // Try opening native YouTube app first
    final appUri = Uri.parse('vnd.youtube:');
    final webUri = Uri.parse('https://www.youtube.com');

    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        _showFeedback('Đang mở ứng dụng YouTube...', isSuccess: true);
      } else {
        // Fallback to web browser
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        _showFeedback('Mở YouTube trên trình duyệt...', isSuccess: true);
      }
    } catch (e) {
      try {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (e2) {
        _showFeedback('Không thể mở YouTube: $e2', isSuccess: false);
      }
    }
  }

  void _showFeedback(String message, {required bool isSuccess}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isSuccess ? Colors.green.shade700 : Colors.redAccent.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Profile Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppTheme.primaryBlue, Colors.purple.shade400],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const CircleAvatar(
                          radius: 46,
                          backgroundColor: Colors.white,
                          child: Icon(
                            Icons.person_rounded,
                            size: 52,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, size: 14, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Sinh Viên HUTECH',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Khoa Công Nghệ Thông Tin • ĐH HUTECH',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'BÀI TẬP VẬN DỤNG {3}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Requirement 2 Actions Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.stars_rounded, color: Colors.amber.shade900, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Yêu Cầu 2: Tương Tác Ứng Dụng (3.5đ)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Setting Phone Number Box
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Số Điện Thoại Cài Đặt:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _isEditingPhone = !_isEditingPhone;
                          });
                        },
                        icon: Icon(_isEditingPhone ? Icons.check : Icons.edit, size: 16),
                        label: Text(_isEditingPhone ? 'Lưu' : 'Đổi SĐT'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_isEditingPhone)
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Nhập số điện thoại...',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.contact_phone_rounded, color: AppTheme.primaryBlue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _phoneController.text.isEmpty ? 'Chưa thiết lập' : _phoneController.text,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Button 1: Make Phone Call (url_launcher)
          ElevatedButton.icon(
            onPressed: _makePhoneCall,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981), // Emerald Green
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 3,
            ),
            icon: const Icon(Icons.phone_in_talk_rounded, size: 24),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Gọi Điện Đến SĐT Đã Cài Đặt',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Button 2: Open YouTube App (url_launcher)
          ElevatedButton.icon(
            onPressed: _openYouTubeApp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444), // YouTube Red
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 3,
            ),
            icon: const Icon(Icons.smart_display_rounded, size: 26),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Gọi Tới Ứng Dụng YouTube',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Additional info banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.blueGrey.shade900 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.blueGrey.shade700 : Colors.blue.shade200,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: AppTheme.primaryBlue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Các nút trên sử dụng package "url_launcher" phiên bản mới nhất, tự động gọi Intent hệ thống Android theo đúng yêu cầu đề bài.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark ? Colors.white70 : Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
