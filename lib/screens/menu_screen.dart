import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/pos_provider.dart';
import '../services/thermal_printer_service.dart';
import '../services/bluetooth_service.dart';
import '../services/windows_printer_service.dart';
import '../services/windows_bluetooth_printer_service.dart';
import '../utils/app_theme.dart';
import '../utils/input_formatters.dart';
import '../utils/responsive_utils.dart';
import '../utils/wib_time.dart';
import '../widgets/skeleton_widget.dart';
import 'backup_screen.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _allTxns = [];
  bool _loadingSummary = false;
  bool _loadingTxns = false;
  bool _loadingClosingReport = false;
  final _dateFormat = DateFormat('dd/MM/yy');
  final _currencyFormat = NumberFormat.decimalPattern('id');
  DateTime _closingDate = DateTime.now();
  List<Map<String, dynamic>> _productsSold = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _terapis = []; // terapis utk tanggal laporan
  List<Map<String, dynamic>> _summaryTerapis = []; // terapis hari ini (ringkasan)
  Map<String, int> _txCounts = {'completed': 0, 'held': 0};
  int _modalAwal = 0;
  bool _closingReportLoaded = false;

  Future<void> _loadClosingReport() async {
    final supabase = ref.read(supabaseServiceProvider);
    final branchId = ref.read(posProvider).currentUser?.branchId;
    setState(() => _loadingClosingReport = true);
    try {
      final results = await Future.wait([
        supabase.getProductsSold(_closingDate, branchId: branchId),
        supabase.getPaymentBreakdown(_closingDate, branchId: branchId),
        supabase.getTransactionCounts(_closingDate, branchId: branchId),
        supabase.getTerapisForDate(_closingDate, branchId: branchId),
      ]);
      if (mounted) {
        setState(() {
          _productsSold = results[0] as List<Map<String, dynamic>>;
          _payments = results[1] as List<Map<String, dynamic>>;
          _txCounts = results[2] as Map<String, int>;
          _terapis = results[3] as List<Map<String, dynamic>>;
          _closingReportLoaded = true;
          _loadingClosingReport = false;
        });
      }
    } catch (e) {
      debugPrint('[Menu] Closing report error: $e');
      if (mounted) setState(() => _loadingClosingReport = false);
    }
  }

  Future<void> _printClosingReport() async {
    if (!_closingReportLoaded) return;
    await _dispatchPrint(
      messageOk: 'Laporan berhasil dicetak',
      messageFail: 'Cetak laporan gagal',
      waktuTutup: DateTime(
        _closingDate.year,
        _closingDate.month,
        _closingDate.day,
        21,
        0,
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _closingDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _closingDate) {
      setState(() => _closingDate = picked);
      _loadClosingReport();
    }
  }

  Future<void> _printDailySummary() async {
    final user = ref.read(posProvider).currentUser;
    final tanggal = _summary['tanggal'] as DateTime? ?? DateTime.now();
    final totalTransaksi = _summary['total_transaksi'] as int? ?? 0;
    final totalRevenue = _summary['total_revenue'] as int? ?? 0;
    final cash = _summary['cash'] as int? ?? 0;
    final transfer = _summary['transfer'] as int? ?? 0;
    final qris = _summary['qris'] as int? ?? 0;
    final refund = _summary['total_refund'] as int? ?? 0;

    bool success;

    if (WindowsBluetoothPrinterService.isSupported) {
      final btPrinter = WindowsBluetoothPrinterService();
      if (btPrinter.isConnected) {
        success = await btPrinter.printDailySummary(
          branchName: user?.branchName ?? '',
          cashierName: user?.name ?? '',
          tanggal: tanggal,
          totalTransaksi: totalTransaksi,
          totalRevenue: totalRevenue,
          cash: cash,
          transfer: transfer,
          qris: qris,
          refund: refund,
          terapis: _summaryTerapis,
        );
      } else if (await WindowsPrinterService().isPrinterReady) {
        success = await WindowsPrinterService().printDailySummary(
          branchName: user?.branchName ?? '',
          cashierName: user?.name ?? '',
          tanggal: tanggal,
          totalTransaksi: totalTransaksi,
          totalRevenue: totalRevenue,
          cash: cash,
          transfer: transfer,
          qris: qris,
          refund: refund,
          terapis: _summaryTerapis,
        );
      } else {
        _showNoPrinterMessage();
        return;
      }
      _showPrintMessage(success, 'Ringkasan berhasil dicetak', 'Cetak ringkasan gagal');
      return;
    }

    final bluetooth = BluetoothService();
    if (!bluetooth.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printer Bluetooth tidak terhubung')),
      );
      return;
    }
    success = await ThermalPrinterService().printDailySummary(
      branchName: user?.branchName ?? '',
      cashierName: user?.name ?? '',
      tanggal: tanggal,
      totalTransaksi: totalTransaksi,
      totalRevenue: totalRevenue,
      cash: cash,
      transfer: transfer,
      qris: qris,
      refund: refund,
      terapis: _summaryTerapis,
    );
    _showPrintMessage(success, 'Ringkasan berhasil dicetak', 'Cetak ringkasan gagal');
  }

  Future<void> _dispatchPrint({
    required String messageOk,
    required String messageFail,
    required DateTime waktuTutup,
  }) async {
    final user = ref.read(posProvider).currentUser;
    final totalPenerimaan =
        _payments.fold<int>(0, (s, p) => s + (p['amount'] as int? ?? 0));
    final waktuBuka = DateTime(
      _closingDate.year,
      _closingDate.month,
      _closingDate.day,
      7,
      0,
    );

    if (WindowsBluetoothPrinterService.isSupported) {
      final btPrinter = WindowsBluetoothPrinterService();
      bool success;
      if (btPrinter.isConnected) {
        success = await btPrinter.printClosingReport(
          branchName: user?.branchName ?? '',
          cashierName: user?.name ?? '',
          waktuBuka: waktuBuka,
          waktuTutup: waktuTutup,
          modalAwal: _modalAwal,
          productsSold: _productsSold,
          payments: _payments,
          terapis: _terapis,
          totalPenerimaan: totalPenerimaan,
          totalTransaksiSelesai: _txCounts['completed'] ?? 0,
          totalTransaksiHold: _txCounts['held'] ?? 0,
        );
      } else if (await WindowsPrinterService().isPrinterReady) {
        success = await WindowsPrinterService().printClosingReport(
          branchName: user?.branchName ?? '',
          cashierName: user?.name ?? '',
          waktuBuka: waktuBuka,
          waktuTutup: waktuTutup,
          modalAwal: _modalAwal,
          productsSold: _productsSold,
          payments: _payments,
          terapis: _terapis,
          totalPenerimaan: totalPenerimaan,
          totalTransaksiSelesai: _txCounts['completed'] ?? 0,
          totalTransaksiHold: _txCounts['held'] ?? 0,
        );
      } else {
        _showNoPrinterMessage();
        return;
      }
      _showPrintMessage(success, messageOk, messageFail);
      return;
    }

    final bluetooth = BluetoothService();
    if (!bluetooth.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printer Bluetooth tidak terhubung')),
      );
      return;
    }
    final printer = ThermalPrinterService();
    final success = await printer.printClosingReport(
      branchName: user?.branchName ?? '',
      cashierName: user?.name ?? '',
      waktuBuka: waktuBuka,
      waktuTutup: waktuTutup,
      modalAwal: _modalAwal,
      productsSold: _productsSold,
      payments: _payments,
      terapis: _terapis,
      totalPenerimaan: totalPenerimaan,
      totalTransaksiSelesai: _txCounts['completed'] ?? 0,
      totalTransaksiHold: _txCounts['held'] ?? 0,
    );
    _showPrintMessage(success, messageOk, messageFail);
  }

  void _showPrintMessage(bool success, String ok, String fail) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? ok : fail),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  void _showNoPrinterMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tidak ada printer terhubung'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final supabase = ref.read(supabaseServiceProvider);
    final branchId = ref.read(posProvider).currentUser?.branchId;

    setState(() {
      _loadingSummary = true;
      _loadingTxns = true;
    });

    final results = await Future.wait([
      supabase.fetchDailySummary(branchId: branchId),
      supabase.fetchAllTransactions(branchId: branchId),
      supabase.getTerapisForDate(WibTime.now(), branchId: branchId),
    ]);

    if (mounted) {
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _allTxns = results[1] as List<Map<String, dynamic>>;
        _summaryTerapis = results[2] as List<Map<String, dynamic>>;
        _loadingSummary = false;
        _loadingTxns = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveUtils.init(context);
    final posState = ref.watch(posProvider);
    final user = posState.currentUser;

    ref.listen<int>(
      posProvider.select((s) => s.transactions.length),
      (prev, next) {
        if (prev != next) _loadAll();
      },
    );

    if (user == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Silakan login terlebih dahulu', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primaryGreen,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          _buildSectionHeader(
            'Ringkasan Harian',
            Icons.bar_chart,
            AppColors.primaryGreen,
            subtitle: user?.branchName,
          ),
          const SizedBox(height: 14),
          if (_loadingSummary)
            const _SkeletonCard(height: 320)
          else
            _buildSummarySection(),
          const SizedBox(height: 28),

          _buildSectionHeader('Laporan Tutup Kasir', Icons.receipt, AppColors.orange),
          const SizedBox(height: 14),
          _buildClosingReportSection(),
          const SizedBox(height: 28),

          _buildSectionHeader('Backup Data', Icons.backup, Colors.orange),
          const SizedBox(height: 14),
          _buildBackupSection(),
          const SizedBox(height: 28),

          _buildSectionHeader('Transaksi', Icons.receipt_long, AppColors.darkBlue),
          const SizedBox(height: 14),
          if (_loadingTxns)
            const _SkeletonCard(height: 240)
          else
            _buildTransactionList(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, {String? subtitle}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkBlue,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryGreen,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackupSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.backup, color: Colors.orange, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Backup Data',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Produk, pelanggan, & transaksi ke penyimpanan lokal',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _BackupScreenWrapper(),
                ),
              );
            },
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Buka', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClosingReportSection() {
    return Column(
      children: [
        // Controls card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date + Modal Awal row
              Row(
                children: [
                  Expanded(
                    child: _buildFieldCard(
                      icon: Icons.calendar_today,
                      label: 'Tanggal',
                      value: _dateFormat.format(_closingDate),
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildModalAwalField(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Load / Print button
              SizedBox(
                width: double.infinity,
                child: _loadingClosingReport
                    ? ElevatedButton.icon(
                        onPressed: null,
                        icon: const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        label: const Text('Memuat data...', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade400,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      )
                    : _closingReportLoaded
                        ? ElevatedButton.icon(
                            onPressed: _printClosingReport,
                            icon: const Icon(Icons.print, size: 16),
                            label: const Text('Print Laporan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _loadClosingReport,
                            icon: const Icon(Icons.cloud_download, size: 16),
                            label: const Text('Muat Data Laporan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
              ),
            ],
          ),
        ),

        if (_closingReportLoaded) ...[
          const SizedBox(height: 12),
          // Summary stats card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Penerimaan',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      'Rp ${_currencyFormat.format(_payments.fold<int>(0, (s, p) => s + (p['amount'] as int? ?? 0)))}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatChip(
                        label: 'Selesai',
                        value: '${_txCounts['completed'] ?? 0}',
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatChip(
                        label: 'Hold',
                        value: '${_txCounts['held'] ?? 0}',
                        color: AppColors.orange,
                      ),
                    ),
                  ],
                ),
                if (_terapis.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Terapis: '
                    '${_terapis.map((t) => t['name']).join(', ')}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ],
            ),
          ),

          if (_productsSold.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildProductsSoldCard(),
          ],

          if (_payments.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildPaymentBreakdownCard(),
          ],
        ],
      ],
    );
  }

  Widget _buildFieldCard({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkBlue,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalAwalField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modal Awal',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
                SizedBox(
                  height: 24,
                  child: TextField(
                    onChanged: (v) {
                      final parsed = int.tryParse(v.replaceAll('.', ''));
                      if (parsed != null) _modalAwal = parsed;
                    },
                    keyboardType: TextInputType.number,
                    inputFormatters: const [ThousandsInputFormatter()],
                    decoration: const InputDecoration(
                      hintText: '0',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 2),
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkBlue,
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

  Widget _buildStatChip({required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsSoldCard() {
    final topProducts = _productsSold.take(15).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shopping_bag_outlined, size: 14, color: AppColors.orange),
              ),
              const SizedBox(width: 8),
              const Text(
                'Produk Terjual',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkBlue,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${topProducts.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...topProducts.asMap().entries.map((entry) {
            final p = entry.value;
            final isLast = entry.key == topProducts.length - 1;
            return Container(
              padding: EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: isLast
                      ? BorderSide.none
                      : BorderSide(color: Colors.grey.shade100),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p['name'] as String? ?? '',
                      style: const TextStyle(fontSize: 13, color: AppColors.darkBlue),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'x${p['qty']}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Rp ${_currencyFormat.format(p['total'] as int? ?? 0)}',
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
    );
  }

  Widget _buildPaymentBreakdownCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.payment_outlined, size: 14, color: Colors.blue),
              ),
              const SizedBox(width: 8),
              const Text(
                'Penerimaan per Metode',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._payments.asMap().entries.map((entry) {
            final p = entry.value;
            final isLast = entry.key == _payments.length - 1;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: isLast
                      ? BorderSide.none
                      : BorderSide(color: Colors.grey.shade100),
                ),
              ),
              child: Row(
                children: [
                  _buildPaymentMethodIcon(p['method'] as String? ?? ''),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p['method'] as String? ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkBlue,
                      ),
                    ),
                  ),
                  Text(
                    'Rp ${_currencyFormat.format(p['amount'] as int? ?? 0)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkBlue,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodIcon(String method) {
    IconData icon;
    Color color;
    switch (method.toLowerCase()) {
      case 'cash':
        icon = Icons.money;
        color = Colors.green;
        break;
      case 'transfer':
        icon = Icons.currency_exchange;
        color = Colors.blue;
        break;
      case 'qris':
        icon = Icons.qr_code;
        color = Colors.purple;
        break;
      default:
        icon = Icons.payment;
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 14, color: color),
    );
  }

  Widget _buildSummarySection() {
    final revenue = _summary['total_revenue'] as int? ?? 0;
    final txCount = _summary['total_transaksi'] as int? ?? 0;
    final refund = _summary['total_refund'] as int? ?? 0;
    final cash = _summary['cash'] as int? ?? 0;
    final transfer = _summary['transfer'] as int? ?? 0;
    final qris = _summary['qris'] as int? ?? 0;

    return Column(
      children: [
        // Hero revenue card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primaryGreen,
                AppColors.primaryGreen.withOpacity(0.75),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.trending_up, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Total Pendapatan',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Rp ${_currencyFormat.format(revenue)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.receipt_outlined, size: 13, color: Colors.white.withOpacity(0.9)),
                  const SizedBox(width: 4),
                  Text(
                    '$txCount transaksi hari ini',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Payment method cards
        Row(
          children: [
            Expanded(
              child: _buildPaymentMethodCard(
                icon: Icons.money,
                label: 'Cash',
                amount: cash,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPaymentMethodCard(
                icon: Icons.currency_exchange,
                label: 'Transfer',
                amount: transfer,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPaymentMethodCard(
                icon: Icons.qr_code,
                label: 'QRIS',
                amount: qris,
                color: Colors.purple,
              ),
            ),
          ],
        ),

        if (_summaryTerapis.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.darkBlue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.darkBlue.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.healing,
                    size: 18, color: AppColors.darkBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Terapis Hari Ini',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final t in _summaryTerapis)
                            Text(
                              '• ${t['name']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        if (refund > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.replay, size: 16, color: Colors.red),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Refund',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.darkBlue,
                        ),
                      ),
                      Text(
                        '$refund transaksi',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Text(
                  '-Rp ${_currencyFormat.format(refund)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _printDailySummary,
            icon: const Icon(Icons.print, size: 16),
            label: const Text('Print Ringkasan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard({
    required IconData icon,
    required String label,
    required int amount,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Rp ${_currencyFormat.format(amount)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.darkBlue,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_allTxns.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.receipt_long, size: 40, color: Colors.grey.shade300),
              ),
              const SizedBox(height: 12),
              Text(
                'Belum ada transaksi',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _allTxns.take(20).map((t) => _buildTransactionCard(t)).toList(),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> t) {
    final status = t['status'] as String? ?? '';
    final isRefunded = status == 'refunded';
    final method = t['payment_method'] as String? ?? '';
    final methodLabel = switch (method) {
      'cash' => 'Cash',
      'transfer' => 'Transfer',
      'qris' => 'QRIS',
      _ => method,
    };

    final accentColor = isRefunded ? Colors.red : AppColors.primaryGreen;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isRefunded ? Colors.red.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRefunded ? Colors.red.withValues(alpha: 0.2) : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showTransactionDetail(t),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isRefunded ? Icons.replay : Icons.receipt,
                  size: 18,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Order #${t['order_no']}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.darkBlue,
                              decoration: isRefunded ? TextDecoration.lineThrough : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isRefunded)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Refund',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t['customer_name'] ?? 'Tanpa nama',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 11, color: Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            '${_dateFormat.format(WibTime.toWib(DateTime.parse(t['created_at'] as String)))} • $methodLabel',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Rp ${_currencyFormat.format(t['total_amount'] ?? 0)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isRefunded ? Colors.red : AppColors.darkBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionDetail(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt, size: 20, color: AppColors.primaryGreen),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${t['order_no']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.darkBlue,
                        ),
                      ),
                      Text(
                        _dateFormat.format(WibTime.toWib(DateTime.parse(t['created_at'] as String))),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _detailRow('Pelanggan', t['customer_name'] as String? ?? '-'),
                    _detailRow('Kasir', t['cashier_name'] as String? ?? '-'),
                    _detailRow('Metode', t['payment_method'] as String? ?? '-'),
                    _detailRow('Status', t['status'] as String? ?? '-'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    _detailRow('Total', 'Rp ${_currencyFormat.format(t['total_amount'] ?? 0)}', isBold: true),
                    _detailRow('Dibayar', 'Rp ${_currencyFormat.format(t['amount_paid'] ?? 0)}'),
                    _detailRow('Kembalian', 'Rp ${_currencyFormat.format(t['change_amount'] ?? 0)}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              fontSize: 13,
              color: AppColors.darkBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double height;
  const _SkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(height: height, borderRadius: 16);
  }
}

/// Wrapper widget that provides Riverpod context for BackupScreen
class _BackupScreenWrapper extends ConsumerWidget {
  const _BackupScreenWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const BackupScreen();
  }
}