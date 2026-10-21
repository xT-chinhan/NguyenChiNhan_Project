class TeamMember {
  final String name;
  final String studentId;
  final String role;
  final String department;
  final String email;
  final String phone;
  final String avatarUrl;
  final List<String> contributions;

  const TeamMember({
    required this.name,
    required this.studentId,
    required this.role,
    required this.department,
    required this.email,
    required this.phone,
    required this.avatarUrl,
    required this.contributions,
  });
}
