import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../models/transaction.dart';
import '../providers/pos_provider.dart';
import '../services/supabase_service.dart';
import '../utils/app_theme.dart';
import '../utils/responsive_utils.dart';
import '../utils/wib_time.dart';
import '../widgets/skeleton_widget.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchController = TextEditingController();
  String _sortBy = 'terbaru';
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveUtils.init(context);
    final posState = ref.watch(posProvider);
    final notifier = ref.read(posProvider.notifier);
    final currencyFormat = NumberFormat.decimalPattern('id');
    final dateFormat = DateFormat('dd/MM/yy HH:mm');
    final supabaseService = ref.read(supabaseServiceProvider);
    final cashierId = posState.currentUser?.id ?? '';

    var transactions = posState.transactions.toList();
    final query = _searchController.text.toLowerCase().trim();
    if (query.isNotEmpty) {
      transactions = transactions.where((t) =>
        t.id.toLowerCase().contains(query) ||
        t.cashierName.toLowerCase().contains(query) ||
        (t.customerName?.toLowerCase().contains(query) ?? false)
      ).toList();
    }
    switch (_sortBy) {
      case 'tertua':
        transactions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'terbesar':
        transactions.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
        break;
      default:
        transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return RefreshIndicator(
      onRefresh: () => notifier.loadProducts(),
      color: AppColors.primaryGreen,
      child: _buildContent(posState, transactions, notifier, currencyFormat, dateFormat, supabaseService, cashierId),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppColors.primaryGreen,
              borderRadius: BorderRadius.all(Radius.circular(12)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGreen,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.history, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Riwayat Transaksi',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkBlue,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Pantau dan kelola semua transaksi',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndSort() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) setState(() {});
                });
              },
              decoration: InputDecoration(
                hintText: 'Cari ID, kasir, atau pelanggan...',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade600, size: 22),
                suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 18, color: Colors.grey.shade500),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'Urutkan:',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                _buildSortChip('terbaru', 'Terbaru', Icons.fiber_new),
                const SizedBox(width: 8),
                _buildSortChip('tertua', 'Tertua', Icons.history_edu),
                const SizedBox(width: 8),
                _buildSortChip('terbesar', 'Terbesar', Icons.trending_up),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String value, String label, IconData icon) {
    final isSelected = _sortBy == value;
    return InkWell(
      onTap: () => setState(() => _sortBy = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primaryGreen : Colors.grey.shade300,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(PosState posState, List<Transaction> transactions, PosProvider notifier,
      NumberFormat currencyFormat, DateFormat dateFormat,
      SupabaseService supabaseService, String cashierId) {
    if (posState.isLoading) {
      return const SkeletonHistoryList();
    }

    if (transactions.isEmpty && _searchController.text.isEmpty) {
      return _buildEmptyState(
        icon: Icons.receipt_long,
        title: 'Belum ada transaksi',
        subtitle: 'Transaksi baru akan muncul di sini',
      );
    }

    return Column(
      children: [
        _buildHeader(),
        _buildSearchAndSort(),
        Expanded(
          child: transactions.isEmpty
              ? _buildEmptyState(
                  icon: Icons.search_off,
                  title: 'Transaksi tidak ditemukan',
                  subtitle: 'Coba kata kunci pencarian lain',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final transaction = transactions[index];
                    return _TransactionCard(
                      transaction: transaction,
                      currencyFormat: currencyFormat,
                      dateFormat: dateFormat,
                      supabaseService: supabaseService,
                      cashierId: cashierId,
                      onRefund: () => notifier.loadProducts(),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade200, width: 2),
                    ),
                    child: Icon(
                      icon,
                      size: 64,
                      color: Colors.grey.shade300,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TransactionCard extends StatefulWidget {
  final Transaction transaction;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;
  final SupabaseService supabaseService;
  final String cashierId;
  final VoidCallback? onRefund;

  const _TransactionCard({
    required this.transaction,
    required this.currencyFormat,
    required this.dateFormat,
    required this.supabaseService,
    required this.cashierId,
    this.onRefund,
  });

  @override
  State<_TransactionCard> createState() => _TransactionCardState();
}

class _TransactionCardState extends State<_TransactionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(16),
              child: _buildCardHeader(t),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: _buildExpandedContent(t),
              crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
              sizeCurve: Curves.easeInOut,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardHeader(Transaction t) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildStatusIcon(t.status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '#${t.id}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkBlue,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor(t.status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        t.status.displayName,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _statusColor(t.status),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${widget.dateFormat.format(WibTime.toWib(t.createdAt))} • ${t.cashierName}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.payment_outlined, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      t.paymentMethod.displayName,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Rp ${widget.currencyFormat.format(t.totalAmount)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.darkBlue,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (t.printStatus == PrintStatus.printed)
                    Icon(Icons.check_circle, size: 12, color: Colors.green.shade700),
                  if (t.printStatus == PrintStatus.unprinted || t.printStatus == PrintStatus.failed)
                    Icon(
                      Icons.print_disabled,
                      size: 12,
                      color: t.printStatus == PrintStatus.failed ? Colors.orange : Colors.grey,
                    ),
                  const SizedBox(width: 3),
                  Text(
                    t.printStatus.displayName,
                    style: TextStyle(
                      fontSize: 9,
                      color: t.printStatus == PrintStatus.printed
                          ? Colors.green.shade700
                          : (t.printStatus == PrintStatus.failed ? Colors.orange : Colors.grey.shade500),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 250),
            child: Icon(
              Icons.keyboard_arrow_down,
              color: Colors.grey.shade400,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(Transaction t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          if (t.customerName != null)
            _buildInfoRow(Icons.person_outline, 'Pelanggan', t.customerName!),
          if (t.terapisName != null && t.terapisName!.isNotEmpty)
            _buildInfoRow(Icons.healing_outlined, 'Terapis', t.terapisName!),
          if (t.notes != null && t.notes!.isNotEmpty)
            _buildInfoRow(Icons.note_outlined, 'Catatan', t.notes!),

          if (t.items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 16, color: Colors.grey.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Detail Item (${t.items.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...t.items.asMap().entries.map((entry) {
                    final item = entry.value;
                    final isLast = entry.key == t.items.length - 1;
                    return Container(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
                      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: isLast
                              ? BorderSide.none
                              : BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.product.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.darkBlue,
                                  ),
                                ),
                                if (item.isHomeVisit)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.blue.shade200),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.home_outlined, size: 10, color: Colors.blue.shade700),
                                        const SizedBox(width: 2),
                                        Text(
                                          'Home Visit',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.blue.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${item.quantity}x',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 90,
                            child: Text(
                              'Rp ${widget.currencyFormat.format(item.totalPrice)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.darkBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Pembayaran',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      'Rp ${widget.currencyFormat.format(t.totalAmount)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkBlue,
                      ),
                    ),
                  ],
                ),
                if (t.paymentMethod == PaymentMethod.cash) ...[
                  const SizedBox(height: 8),
                  Divider(color: Colors.grey.shade300, height: 1),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Bayar', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      Text(
                        'Rp ${widget.currencyFormat.format(t.amountPaid)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Kembali', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      Text(
                        'Rp ${widget.currencyFormat.format(t.change)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryGreen),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          if (t.status == TransactionStatus.completed) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.replay,
                    label: 'Refund',
                    color: Colors.red,
                    onPressed: () => _showRefundDialog(t),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final isPrinted = t.printStatus == PrintStatus.printed;
                      return _ActionButton(
                        icon: isPrinted ? Icons.copy : Icons.print,
                        label: isPrinted ? 'Salin Cetak' : 'Cetak Ulang',
                        color: isPrinted ? AppColors.darkBlue : AppColors.primaryGreen,
                        onPressed: () async {
                          final success = await ref.read(posProvider.notifier).printTransaction(t);
                          if (success && widget.onRefund != null) {
                            widget.onRefund!();
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                    ? (isPrinted ? 'Copy printed successfully' : 'Print success')
                                    : 'Print failed - printer not connected',
                                ),
                                backgroundColor: success ? Colors.green : Colors.red,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRefundDialog(Transaction transaction) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Refund Transaksi',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkBlue),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt, size: 16, color: Colors.grey.shade700),
                        const SizedBox(width: 6),
                        Text('Order #${transaction.id}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total: Rp ${widget.currencyFormat.format(transaction.totalAmount)}',
                      style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Alasan Refund',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  hintText: 'Masukkan alasan refund...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Alasan refund wajib diisi')),
                  );
                }
                return;
              }
              try {
                await widget.supabaseService.processRefund(
                  transactionId: int.tryParse(transaction.id) ?? 0,
                  reason: reason,
                  refundAmount: transaction.totalAmount,
                  cashierId: widget.cashierId,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                widget.onRefund?.call();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Refund berhasil diproses')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Refund', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(TransactionStatus status) {
    IconData icon;
    Color color;
    switch (status) {
      case TransactionStatus.completed:
        icon = Icons.check_circle;
        color = AppColors.primaryGreen;
      case TransactionStatus.pending:
        icon = Icons.schedule;
        color = Colors.orange;
      case TransactionStatus.cancelled:
        icon = Icons.cancel;
        color = Colors.red;
      case TransactionStatus.refunded:
        icon = Icons.replay;
        color = Colors.blueGrey;
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Color _statusColor(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.completed:
        return AppColors.primaryGreen;
      case TransactionStatus.pending:
        return Colors.orange;
      case TransactionStatus.cancelled:
        return Colors.red;
      case TransactionStatus.refunded:
        return Colors.blueGrey;
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(label,
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    );
  }
}