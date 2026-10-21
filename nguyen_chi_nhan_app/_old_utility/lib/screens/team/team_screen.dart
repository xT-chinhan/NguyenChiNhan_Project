import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/team_member.dart';
import '../../theme/app_theme.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.88);
  int _currentPage = 0;

  final List<TeamMember> _members = const [
    TeamMember(
      name: 'Nguyễn Chí Nhân',
      studentId: '2180600001',
      role: 'Nhóm Trưởng & Core Developer',
      department: 'Khoa Công Nghệ Thông Tin - HUTECH',
      email: 'nhan.nc21@hutech.edu.vn',
      phone: '0987654321',
      avatarUrl: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400',
      contributions: [
        'Điều phối dự án & Thiết kế kiến trúc Swarm 10 Agent',
        'Cấu hình AndroidManifest, BottomNavigationBar & Module Cá Nhân',
        'Tối ưu hóa Responsive toàn diện trên mọi màn hình',
      ],
    ),
    TeamMember(
      name: 'Bùi Nguyễn Công Nghiệp',
      studentId: '2180600002',
      role: 'Mobile Developer (Voice & Alarm)',
      department: 'Khoa Công Nghệ Thông Tin - HUTECH',
      email: 'nghiep.bnc21@hutech.edu.vn',
      phone: '0902345678',
      avatarUrl: 'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=400',
      contributions: [
        'Yêu Cầu 3: Báo thức giọng nói đa ngôn ngữ (Việt - Anh)',
        'Tích hợp Android Intent gọi Đồng hồ hệ thống thật',
        'Xử lý bộ lọc nhận diện âm thanh & sóng nhạc Equalizer',
      ],
    ),
    TeamMember(
      name: 'Lưu Văn Lương',
      studentId: '2180600003',
      role: 'AI & Machine Learning Engineer',
      department: 'Khoa Công Nghệ Thông Tin - HUTECH',
      email: 'luong.lv21@hutech.edu.vn',
      phone: '0903456789',
      avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
      contributions: [
        'Yêu Cầu 4 & 5: Tích hợp Google ML Kit On-Device',
        'Pipeline dịch Realtime Camera chọn ngôn ngữ Anh - Việt',
        'Bộ lọc làm sạch OCR, chống nhiễu và đóng băng khung hình',
      ],
    ),
    TeamMember(
      name: 'Võ Thành Nhân',
      studentId: '2180600004',
      role: 'UI/UX & Integration Developer',
      department: 'Khoa Công Nghệ Thông Tin - HUTECH',
      email: 'nhan.vt21@hutech.edu.vn',
      phone: '0904567890',
      avatarUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
      contributions: [
        'Yêu Cầu 2: Tương tác gọi điện SĐT cài đặt & gọi app YouTube',
        'Yêu Cầu 6: Tab thông tin nhóm thành viên HUTECH & hiệu ứng lướt thẻ 3D',
        'Kiểm thử QA toàn diện trên máy ảo và máy thật Realme 6i',
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        const SizedBox(height: 8),

        // Header Instruction
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.pink.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.pink.withAlpha(60)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swipe_rounded, color: Colors.pink, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lướt qua trái / phải để xem từng thành viên (Yêu Cầu 6)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: Colors.pink,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Swipeable PageView Cards
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _members.length,
            onPageChanged: (idx) {
              setState(() => _currentPage = idx);
            },
            itemBuilder: (context, index) {
              final m = _members[index];
              return AnimatedScale(
                scale: _currentPage == index ? 1.0 : 0.94,
                duration: const Duration(milliseconds: 300),
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Member Avatar with decorative ring
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Colors.pink.shade400, AppTheme.primaryBlue],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.white,
                            backgroundImage: NetworkImage(m.avatarUrl),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Name
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            m.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Student ID Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'MSSV: ${m.studentId}',
                            style: const TextStyle(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Role & Department
                        Text(
                          m.role,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Colors.deepPurple,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          m.department,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white60 : Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 6),

                        // Contributions List
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Nhiệm vụ & Đóng góp:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            itemCount: m.contributions.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 4),
                            itemBuilder: (ctx, i) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 15,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      m.contributions[i],
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Quick Call Button
                        ElevatedButton.icon(
                          onPressed: () => _makeCall(m.phone),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            minimumSize: const Size.fromHeight(40),
                          ),
                          icon: const Icon(Icons.phone_rounded, size: 16),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Liên hệ: ${m.phone}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 10),

        // Page Indicator Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_members.length, (idx) {
            final isSel = _currentPage == idx;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isSel ? 22 : 8,
              height: 7,
              decoration: BoxDecoration(
                color: isSel ? AppTheme.primaryBlue : Colors.grey.withAlpha(80),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),

        const SizedBox(height: 12),
      ],
    );
  }
}
