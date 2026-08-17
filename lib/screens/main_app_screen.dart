import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../providers/pos_provider.dart';
import '../utils/app_theme.dart';
import '../utils/responsive_utils.dart';
import '../widgets/bluetooth_status_widget.dart';
import 'pos_screen.dart';
import 'history_screen.dart';
import 'menu_screen.dart';
import 'customer_screen.dart';

class MainAppScreen extends ConsumerStatefulWidget {
  const MainAppScreen({super.key});

  @override
  ConsumerState<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends ConsumerState<MainAppScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        ref.read(posProvider.notifier).loadProducts();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveUtils.init(context);
    final posState = ref.watch(posProvider);
    final user = posState.currentUser;
    final today = DateTime.now();

    bool isToday(DateTime utc) {
      final wib = utc.toUtc().add(const Duration(hours: 7));
      return wib.year == today.year &&
          wib.month == today.month &&
          wib.day == today.day;
    }

    // Per-branch today stats (each cabang sees only its own transactions).
    final branchId = user?.branchId;
    final todayTrans = posState.transactions
        .where((t) =>
            isToday(t.createdAt) &&
            (branchId == null || t.branchId == branchId) &&
            t.status.name == 'completed')
        .length;
    final todayRev = posState.transactions
        .where((t) =>
            isToday(t.createdAt) &&
            (branchId == null || t.branchId == branchId) &&
            t.status.name == 'completed')
        .fold(0, (sum, t) => sum + t.totalAmount);
    final currencyFormat = NumberFormat.decimalPattern('id');

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: _buildAppBar(user),
      ),
      body: Column(
        children: [
          _buildStatsBanner(todayTrans, todayRev, currencyFormat),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                POSScreen(),
                HistoryScreen(),
                CustomerScreen(),
                MenuScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildAppBar(AppUser? user) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // === Logo + Branch Badge (Kiri) ===
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primaryGreen.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'lib/assets/logo-dhbh.png',
                        width: 56,
                        height: 22,
                        fit: BoxFit.contain,
                      ),
                      if (user?.branchName != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 1,
                          height: 16,
                          color: AppColors.primaryGreen.withValues(alpha: 0.25),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 100),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.store_outlined,
                                  size: 11,
                                  color: AppColors.primaryGreen,
                                ),
                                const SizedBox(width: 15),
                                Flexible(
                                  child: Text(
                                    user!.branchName!,
                                    style: const TextStyle(
                                      color: AppColors.primaryGreen,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                    
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // === Spacer: Mendorong elemen setelahnya ke ujung paling kanan ===
              const Spacer(),

              // === Right Side: Bluetooth + User Profile (Kanan / Flex End) ===
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const BluetoothStatusWidget(),
                  const SizedBox(width: 8),
                  _buildUserAvatar(
                    name: user?.name ?? 'User',
                    role: user?.role.name ?? '',
                    onTap: () => ref.read(posProvider.notifier).logout(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  

  Widget _buildUserAvatar({
    required String name,
    required String role,
    required VoidCallback onTap,
  }) {
    // Ambil 2 huruf pertama dari nama untuk avatar
    final initials = _getInitials(name);

    return Tooltip(
      message: '$name ($role)\nKetuk untuk logout',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar dengan inisial
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryGreen,
                      AppColors.primaryGreen.withOpacity(0.75),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Name + Role column
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        role.toUpperCase(),
                        style: TextStyle(
                          color: AppColors.primaryGreen,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        name,
                        style: const TextStyle(
                          color: AppColors.darkBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.logout,
                  color: Colors.red,
                  size: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) {
      return parts[0].substring(0, 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Widget _buildStatsBanner(int count, int revenue, NumberFormat format) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              icon: Icons.receipt_outlined,
              label: 'Transaksi Hari Ini',
              value: '$count',
              color: AppColors.primaryGreen,
              iconBg: AppColors.primaryGreen.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildStatCard(
              icon: Icons.monetization_on_outlined,
              label: 'Revenue Hari Ini',
              value: 'Rp ${format.format(revenue)}',
              color: AppColors.darkBlue,
              iconBg: AppColors.darkBlue.withValues(alpha: 0.08),
              valueSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color iconBg,
    double valueSize = 16,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: valueSize,
                    color: AppColors.darkBlue,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return SafeArea(
      child: Container(
        height: 70, // disesuaikan agar tidak kebesaran/kekecilan
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: TabBar(
          controller: _tabController,
          indicator: const BoxDecoration(),
          labelColor: AppColors.primaryGreen,
          unselectedLabelColor: const Color(0xFF999999),
          labelPadding: EdgeInsets.zero,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: [
            _buildNavItem(Icons.home_outlined, Icons.home, 'POS', 0),
            _buildNavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'History', 1),
            _buildNavItem(Icons.people_outline, Icons.people, 'Pelanggan', 2),
            _buildNavItem(Icons.menu_outlined, Icons.menu, 'Menu', 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    IconData iconOut,
    IconData iconFill,
    String label,
    int index,
  ) {
    return AnimatedBuilder(
      animation: _tabController.animation!,
      builder: (context, child) {
        final isSelected = _tabController.index == index;
        return Tab(
          height: 65, // Mengatur batas tinggi tab agar elemen didalamnya tidak overflow
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Active indicator dot
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  height: 3,
                  width: isSelected ? 24 : 0,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryGreen.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isSelected ? iconFill : iconOut,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Helper widget untuk animated tab item
class AnimatedBuilder extends StatelessWidget {
  final Animation<double> animation;
  final Widget Function(BuildContext, Widget?) builder;

  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder2(animation: animation, builder: builder);
  }
}

class AnimatedBuilder2 extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;

  const AnimatedBuilder2({
    super.key,
    required Animation<double> animation,
    required this.builder,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, null);
  }
}