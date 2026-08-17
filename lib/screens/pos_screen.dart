import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../providers/pos_provider.dart';
import '../screens/customer_screen.dart';
import '../utils/app_theme.dart';
import '../widgets/cart_item_card.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/product_card.dart';
import '../widgets/skeleton_widget.dart';

/// Breakpoint untuk layout
/// - Desktop : ≥1400px (laptop 1080p ke atas, sidebar + wide cart)
/// - Tablet  : ≥800px  (Android tablet 1280x800, 2 panel tanpa sidebar)
/// - Phone   : <800px  (single column, bottom sheet cart)
class POSScreen extends ConsumerStatefulWidget {
  const POSScreen({super.key});

  @override
  ConsumerState<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends ConsumerState<POSScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Pastikan tidak ada fokus otomatis saat layar pertama kali dibangun
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // Optimized breakpoints for Android tablet 1280x800
    final isDesktop = width >= 1400;
    final isTablet = width >= 800 && width < 1400; // Tablet: 800-1399px
    final posState = ref.watch(posProvider);
    final notifier = ref.read(posProvider.notifier);

    // Tidak ada auto-focus; keyboard hanya muncul jika pengguna mengetuk field

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: isDesktop
          ? _buildDesktopLayout(posState, notifier)
          : isTablet
          ? _buildTabletLayout(posState, notifier)
          : _buildPhoneLayout(posState, notifier),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // DESKTOP LAYOUT (≥1400px) — Laptop 1080p & atas
  // ═══════════════════════════════════════════════════════════
  Widget _buildDesktopLayout(PosState posState, PosProvider notifier) {
    final products = notifier.filteredProducts(false);
    final categories = notifier.categories;

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Column(
            children: [
              _buildDesktopHeader(posState, notifier),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildCategoryChips(posState, categories, isDense: false),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: posState.isLoading
                    ? const SkeletonProductGrid(
                  crossAxisCount: 4,
                  itemCount: 12,
                )
                    : _buildProductGrid(
                  products,
                  crossAxisCount: _calculateGridColumns(context),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 520,
          child: _buildCartPanel(posState, notifier),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TABLET LAYOUT (800–1399px) — Android tablet 1280x800
  // ═══════════════════════════════════════════════════════════
  Widget _buildTabletLayout(PosState posState, PosProvider notifier) {
    final products = notifier.filteredProducts(false);
    final categories = notifier.categories;

    return RefreshIndicator(
      onRefresh: () => notifier.loadProducts(),
      color: AppColors.primaryGreen,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: _buildSearchBar(isDense: true),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _buildCategoryChips(posState, categories, isDense: true),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: posState.isLoading
                      ? const SkeletonProductGrid(
                    crossAxisCount: 3,
                    itemCount: 9,
                  )
                      : _buildProductGrid(
                    products,
                    crossAxisCount: _calculateGridColumns(context),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _buildCartPanel(posState, notifier),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // PHONE LAYOUT (<800px)
  // ═══════════════════════════════════════════════════════════
  Widget _buildPhoneLayout(PosState posState, PosProvider notifier) {
    final currencyFormat = NumberFormat.decimalPattern('id');
    final products = notifier.filteredProducts(false);
    final categories = notifier.categories;

    if (posState.isLoading) {
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _buildSearchBar(isDense: true),
        ),
        const SizedBox(height: 8),
        _buildCategoryChips(posState, categories, isDense: true),
        const SizedBox(height: 8),
        const Expanded(child: SkeletonProductGrid(crossAxisCount: 2)),
        _buildCartFooter(posState, notifier, currencyFormat),
      ]);
    }

    return RefreshIndicator(
      onRefresh: () => notifier.loadProducts(),
      color: AppColors.primaryGreen,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _buildSearchBar(isDense: true),
        ),
        const SizedBox(height: 8),
        _buildCategoryChips(posState, categories, isDense: true),
        const SizedBox(height: 8),
        Expanded(child: _buildProductGrid(products, crossAxisCount: 2)),
        _buildCartFooter(posState, notifier, currencyFormat),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // DESKTOP HEADER
  // ═══════════════════════════════════════════════════════════
  Widget _buildDesktopHeader(PosState posState, PosProvider notifier) {
    final heldCount = posState.heldOrders.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: _buildSearchBar(isDense: false, showHeldPill: false),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                if (heldCount > 0)
                  GestureDetector(
                    onTap: () => _showHeldOrders(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.pause_circle,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            '$heldCount Ditahan',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
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

  // ═══════════════════════════════════════════════════════════
  // SEARCH BAR
  // ═══════════════════════════════════════════════════════════
  Widget _buildSearchBar({required bool isDense, bool showHeldPill = true}) {
    final posState = ref.watch(posProvider);
    final heldCount = posState.heldOrders.length;

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
        const _SearchIntent(),
      },
      child: Actions(
        actions: {
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (_) {
              _searchFocusNode.requestFocus();
              return null;
            },
          ),
        },
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: isDense ? 42 : 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: (v) =>
                      ref.read(posProvider.notifier).setSearchQuery(v),
                  style: TextStyle(fontSize: isDense ? 14 : 15),
                  decoration: InputDecoration(
                    icon: Icon(
                      Icons.search,
                      color: Colors.grey.shade400,
                      size: isDense ? 20 : 22,
                    ),
                    hintText: 'Cari layanan atau produk...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: isDense ? 14 : 15,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: isDense ? 12 : 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _IconButton(
              icon: Icons.refresh,
              onTap: () {
                debugPrint('[POS] Manual refresh triggered');
                ref.read(posProvider.notifier).loadProducts();
              },
              size: isDense ? 40 : 48,
            ),
            if (showHeldPill && heldCount > 0) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _showHeldOrders(context),
                child: isDense
                    ? Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.pause_circle,
                          color: Colors.white, size: 20),
                      Positioned(
                        right: 1,
                        top: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$heldCount',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.orange,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                    : Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pause_circle,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '$heldCount Ditahan',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CATEGORY CHIPS
  // ═══════════════════════════════════════════════════════════
  Widget _buildCategoryChips(
      PosState posState,
      List<String> categories, {
        required bool isDense,
      }) {
    return SizedBox(
      height: isDense ? 38 : 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildChip('Semua', posState.selectedCategory.isEmpty,
              isDense: isDense),
          ...categories.map((cat) => Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _buildChip(
              cat,
              posState.selectedCategory == cat,
              isDense: isDense,
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildChip(String label, bool isActive, {required bool isDense}) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        ref
            .read(posProvider.notifier)
            .setSelectedCategory(label == 'Semua' ? '' : label);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isDense ? 16 : 20,
          vertical: isDense ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: isActive ? null : Border.all(color: Colors.grey.shade200),
          boxShadow: isActive
              ? [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
              : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.black87,
            fontSize: isDense ? 13 : 14,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // PRODUCT GRID
  // ═══════════════════════════════════════════════════════════
  int _calculateGridColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1600) return 5;
    if (width >= 1366) return 4;
    if (width >= 1200) return 3;
    if (width >= 900) return 3;
    return 2;
  }

  Widget _buildProductGrid(List<Product> products,
      {required int crossAxisCount}) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Tidak ada produk',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Coba ubah pencarian atau kategori',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: crossAxisCount >= 4 ? 1.8 : 1.6,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final branchId = ref.read(posProvider).currentUser?.branchId;
        return _ProductCardWithPrice(
          product: products[index],
          branchId: branchId,
          onTap: (isHomeVisit) {
            FocusScope.of(context).unfocus();
            ref
                .read(posProvider.notifier)
                .addToCart(products[index], isHomeVisit: isHomeVisit);
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CART PANEL — Desktop & Tablet
  // ═══════════════════════════════════════════════════════════
  Widget _buildCartPanel(PosState posState, PosProvider notifier) {
    final cartItems = posState.cartItems;
    final total = notifier.cartTotal;
    final itemCount = notifier.cartItemCount;
    final currencyFormat = NumberFormat.decimalPattern('id');

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(-2, 0),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shopping_cart,
                      color: AppColors.orange, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Keranjang',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkBlue,
                  ),
                ),
                const Spacer(),
                if (cartItems.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'No. ${posState.transactions.length + 1}',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.55),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.grayDivider),
          Expanded(
            child: cartItems.isEmpty
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 52,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Pilih menu untuk\nmemulai transaksi',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.40),
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(
                  vertical: 8, horizontal: 8),
              itemCount: cartItems.length,
              itemBuilder: (context, index) => CartItemCard(
                item: cartItems[index],
                index: index,
                onRemove: () => notifier.removeFromCart(index),
                onQuantityChanged: (qty) =>
                    notifier.updateCartItemQuantity(index, qty),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.grayDivider),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$itemCount items',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Rp ${currencyFormat.format(total)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkBlue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: ElevatedButton.icon(
                        onPressed: total > 0 ? () => _holdOrder(context) : null,
                        icon: const Icon(Icons.pause, size: 16),
                        label: const Text(
                          'Hold',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: total > 0
                            ? () => _showPaymentDialog(context)
                            : null,
                        icon: const Icon(Icons.payment, size: 18),
                        label: const Text(
                          'Bayar  •  F9',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CART FOOTER (Phone)
  // ═══════════════════════════════════════════════════════════
  Widget _buildCartFooter(
      PosState posState,
      PosProvider notifier,
      NumberFormat currencyFormat,
      ) {
    final total = notifier.cartTotal;
    final itemCount = notifier.cartItemCount;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$itemCount items',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.darkBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rp ${currencyFormat.format(total)}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (total > 0)
              IconButton(
                onPressed: () => _holdOrder(context),
                icon: const Icon(Icons.pause_circle,
                    color: AppColors.orange, size: 26),
                tooltip: 'Hold Order',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: total > 0 ? () => _showPaymentDialog(context) : null,
              icon: const Icon(Icons.shopping_cart_checkout,
                  color: Colors.white, size: 16),
              label: const Text(
                'Bayar',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // DIALOGS
  // ═══════════════════════════════════════════════════════════
  Future<void> _showPaymentDialog(BuildContext context) async {
    FocusScope.of(context).unfocus(); // Pastikan keyboard tidak muncul otomatis
    final posState = ref.read(posProvider);
    final notifier = ref.read(posProvider.notifier);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PaymentDialog(
        totalAmount: notifier.cartTotal,
        initialCustomerNames: posState.pendingCustomerNames,
        branchId: posState.currentUser?.branchId,
        onDismiss: () {},
      ),
    );
    if (result != null && context.mounted) {
      notifier.completeTransaction(
        amountPaid: result['amountPaid'] as int,
        paymentMethod: result['paymentMethod'] as PaymentMethod,
        discount: result['discount'] as int? ?? 0,
        customerNames: (result['customerNames'] as List<dynamic>?)?.cast<String>(),
        terapisIds: (result['terapisIds'] as List<dynamic>?)?.cast<String>(),
        terapisNames: (result['terapisNames'] as List<dynamic>?)?.cast<String>(),
        notes: result['notes'] as String?,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaksi berhasil!'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
    }
    if (mounted) FocusScope.of(context).unfocus(); // Bersihkan fokus setelah dialog
  }

  Future<void> _holdOrder(BuildContext context) async {
    FocusScope.of(context).unfocus(); // Hindari keyboard muncul otomatis
    final customerControllers = <TextEditingController>[TextEditingController()];
    final formKey = GlobalKey<FormState>();

    final names = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.pause_circle, color: AppColors.orange),
              SizedBox(width: 10),
              Text('Hold Order'),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pesanan akan ditahan dan bisa diambil kembali nanti.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < customerControllers.length; i++) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: customerControllers[i],
                            autofocus: false, // Tidak pernah autofocus
                            decoration: InputDecoration(
                              labelText: i == 0
                                  ? 'Nama Pelanggan'
                                  : 'Nama Pelanggan ${i + 1}',
                              hintText: 'Masukkan nama pelanggan...',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                              suffixIcon: TextButton.icon(
                                onPressed: () async {
                                  final customer = await showModalBottomSheet<Customer>(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => Container(
                                      height: MediaQuery.of(context).size.height * 0.75,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(20)),
                                      ),
                                      child: const CustomerScreen(isPicker: true),
                                    ),
                                  );
                                  if (customer != null) {
                                    setDialogState(() {
                                      customerControllers[i].text = customer.name;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.person_search, size: 18),
                                label: const Text('Pilih',
                                    style: TextStyle(fontSize: 13)),
                                style: TextButton.styleFrom(
                                  padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                                ),
                              ),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Nama pelanggan wajib diisi'
                                : null,
                          ),
                        ),
                        if (customerControllers.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 10, left: 4),
                            child: IconButton(
                              onPressed: () => setDialogState(() {
                                customerControllers.removeAt(i).dispose();
                              }),
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 20, color: Colors.redAccent),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextButton.icon(
                    onPressed: () => setDialogState(() {
                      customerControllers.add(TextEditingController());
                    }),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Tambah Pelanggan',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Batal, kembalikan null
              },
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final names = customerControllers
                    .map((c) => c.text.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                Navigator.pop(dialogContext, names); // Kembalikan daftar nama
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Hold', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    // Dispose controllers setelah dialog benar-benar ditutup
    for (final c in customerControllers) {
      c.dispose();
    }

    // Jika names tidak null (user menekan Hold), proses hold
    if (names != null && names.isNotEmpty && mounted) {
      ref.read(posProvider.notifier).holdCurrentOrder(customerNames: names);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pesanan ditahan'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
    }
  }

  void _showHeldOrders(BuildContext context) {
    FocusScope.of(context).unfocus(); // Hindari keyboard muncul otomatis
    final posState = ref.read(posProvider);
    final heldOrders = posState.heldOrders;
    final currencyFormat = NumberFormat.decimalPattern('id');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pesanan Ditahan',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkBlue,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${heldOrders.length} pesanan',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: heldOrders.isEmpty
                    ? Center(
                  child: Text(
                    'Tidak ada pesanan ditahan',
                    style:
                    TextStyle(color: Colors.grey[500], fontSize: 15),
                  ),
                )
                    : ListView.builder(
                  controller: scrollController,
                  itemCount: heldOrders.length,
                  itemBuilder: (context, index) {
                    final order = heldOrders[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color:
                            AppColors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.pause_circle,
                            color: AppColors.orange,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          order.customerName ?? "Tanpa nama",
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${order.totalItems} items  •  Rp ${currencyFormat.format(order.totalAmount)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _IconButton(
                              icon: Icons.shopping_cart,
                              color: AppColors.primaryGreen,
                              onTap: () {
                                ref
                                    .read(posProvider.notifier)
                                    .retrieveHeldOrder(index);
                                Navigator.pop(ctx);
                                FocusScope.of(context).unfocus(); // Bersihkan
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Pesanan diambil'),
                                    behavior: SnackBarBehavior.floating,
                                    margin: EdgeInsets.all(16),
                                  ),
                                );
                              },
                              size: 40,
                            ),
                            const SizedBox(width: 8),
                            _IconButton(
                              icon: Icons.delete_outline,
                              color: Colors.red,
                              onTap: () => ref
                                  .read(posProvider.notifier)
                                  .deleteHeldOrder(index),
                              size: 40,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// WIDGET HELPERS
// ═══════════════════════════════════════════════════════════

class _IconButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;
  final double size;

  const _IconButton({
    required this.icon,
    required this.onTap,
    this.color,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: color ?? AppColors.primaryGreen,
            size: size > 44 ? 22 : 20,
          ),
        ),
      ),
    );
  }
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

// ═══════════════════════════════════════════════════════════
// PRODUCT CARD WRAPPER
// ═══════════════════════════════════════════════════════════
class _ProductCardWithPrice extends StatelessWidget {
  final Product product;
  final void Function(bool isHomeVisit) onTap;
  final int? branchId;

  const _ProductCardWithPrice({
    required this.product,
    required this.onTap,
    this.branchId,
  });

  bool get _hasHomeVisit => product.priceHomeVisit != null;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _hasHomeVisit ? _showPriceOptions(context) : onTap(false),
        child: ProductCard(product: product, branchId: branchId),
      ),
    );
  }

  void _showPriceOptions(BuildContext context) {
    FocusScope.of(context).unfocus(); // Hindari keyboard muncul otomatis
    final screenWidth = MediaQuery.of(context).size.width;
    showModalBottomSheet(
      context: context,
      constraints: BoxConstraints(
        maxWidth: screenWidth > 800 ? 820 : double.infinity,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              product.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 19,
                color: AppColors.darkBlue,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pilih jenis layanan:',
              style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  onTap(false);
                },
                icon: const Icon(Icons.store, color: Colors.white, size: 20),
                label: Text(
                  'Klinik — Rp ${_fmt(product.getEffectivePriceClinic(branchId ?? 0))}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (_hasHomeVisit) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onTap(true);
                  },
                  icon: const Icon(Icons.home, color: Colors.white, size: 20),
                  label: Text(
                    'Home Visit — Rp ${_fmt(product.getEffectivePriceHomeVisit(branchId ?? 0))}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(int price) => price
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}