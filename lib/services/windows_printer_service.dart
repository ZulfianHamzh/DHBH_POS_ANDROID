import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/transaction.dart';
import '../utils/wib_time.dart';

/// Prints receipts via the standard Windows printing subsystem using the
/// `printing` package. Used on Windows desktop where the Bluetooth ESC/POS
/// path is unavailable (flutter_bluetooth_serial has no Windows support).
///
/// Receipts are rendered as a PDF page sized for 80mm thermal paper and sent
/// to the default Windows printer (no dialog) via [Printing.directPrintPdf].
class WindowsPrinterService {
  static final WindowsPrinterService _instance = WindowsPrinterService._internal();

  factory WindowsPrinterService() => _instance;

  WindowsPrinterService._internal();

  static const String _tag = '[WinPrinter]';

  /// Name of the preferred thermal receipt printer on Windows.
  static const String preferredPrinterName = 'XP-58';

  /// 80mm thermal roll paper.
  static final PdfPageFormat _receiptFormat =
      PdfPageFormat(80 * PdfPageFormat.mm, 297 * PdfPageFormat.mm);

  /// Whether this platform uses the Windows print subsystem.
  static bool get isAvailable => !kIsWeb && Platform.isWindows;

  /// Whether the preferred Windows printer (XP-58) is available.
  Future<bool> get isPrinterReady async {
    try {
      final info = await Printing.info();
      if (!info.canPrint) {
        debugPrint('$_tag printer ready: false (cannot print)');
        return false;
      }
      final printer = await _targetPrinter();
      if (printer == null) {
        debugPrint('$_tag printer ready: false (no target printer)');
        return false;
      }
      debugPrint('$_tag printer ready: true -> ${printer.name}');
      return true;
    } catch (e) {
      debugPrint('$_tag printer check error: $e');
      return false;
    }
  }

  /// Print a transaction receipt (same content as the Android ESC/POS version).
  Future<bool> printTransaction(Transaction t) {
    debugPrint('$_tag printTransaction: id=${t.id}, orderNo=${t.orderNo}');
    return _printDoc(
      name: 'Struk-${t.orderNo ?? t.id}',
      build: (ctx) => _receiptContent(t),
    );
  }

  /// Print a closing report / daily summary (same content as the ESC/POS one).
  Future<bool> printClosingReport({
    required String branchName,
    required String cashierName,
    required DateTime waktuBuka,
    required DateTime waktuTutup,
    required int modalAwal,
    required List<Map<String, dynamic>> productsSold,
    required List<Map<String, dynamic>> payments,
    required List<Map<String, dynamic>> terapis,
    required int totalPenerimaan,
    required int totalTransaksiSelesai,
    required int totalTransaksiHold,
  }) {
    debugPrint('$_tag printClosingReport');
    return _printDoc(
      name: 'Laporan-Tutup-Kasir',
      build: (ctx) => _closingReportContent(
        branchName: branchName,
        cashierName: cashierName,
        waktuBuka: waktuBuka,
        waktuTutup: waktuTutup,
        modalAwal: modalAwal,
        productsSold: productsSold,
        payments: payments,
        terapis: terapis,
        totalPenerimaan: totalPenerimaan,
        totalTransaksiSelesai: totalTransaksiSelesai,
        totalTransaksiHold: totalTransaksiHold,
      ),
    );
  }

  /// Print the daily summary (ringkasan harian) — compact totals, distinct
  /// from the closing report.
  Future<bool> printDailySummary({
    required String branchName,
    required String cashierName,
    required DateTime tanggal,
    required int totalTransaksi,
    required int totalRevenue,
    required int cash,
    required int transfer,
    required int qris,
    required int refund,
    required List<Map<String, dynamic>> terapis,
  }) {
    debugPrint('$_tag printDailySummary');
    return _printDoc(
      name: 'Ringkasan-Harian',
      build: (ctx) => _dailySummaryContent(
        branchName: branchName,
        cashierName: cashierName,
        tanggal: tanggal,
        totalTransaksi: totalTransaksi,
        totalRevenue: totalRevenue,
        cash: cash,
        transfer: transfer,
        qris: qris,
        refund: refund,
        terapis: terapis,
      ),
    );
  }

  /// Print a small sample receipt to verify the default Windows printer works.
  Future<bool> printTestReceipt() {
    debugPrint('$_tag printTestReceipt');
    return _printDoc(
      name: 'Struk-Uji',
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text('DHBH POS',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Center(child: pw.Text('Struk Uji / Test Receipt')),
          pw.SizedBox(height: 8),
          pw.Text('─' * 42),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Text('Printer Windows berfungsi!')),
          pw.Center(child: pw.Text('Windows printing is working!')),
          pw.SizedBox(height: 8),
          pw.Text('─' * 42),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Text('Terima kasih')),
        ],
      ),
    );
  }

  Future<bool> _printDoc({
    required String name,
    required pw.Widget Function(pw.Context ctx) build,
  }) async {
    try {
      final printer = await _targetPrinter();
      if (printer == null) {
        debugPrint('$_tag no target printer available');
        return false;
      }

      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: _receiptFormat,
          margin: const pw.EdgeInsets.all(6),
          build: (ctx) => build(ctx),
        ),
      );
      final bytes = await doc.save();
      final ok = await Printing.directPrintPdf(
        printer: printer,
        name: name,
        format: _receiptFormat,
        onLayout: (format) async => bytes,
      );
      debugPrint('$_tag ✓ printed: $name (ok=$ok)');
      return ok;
    } catch (e) {
      debugPrint('$_tag print error: $e');
      return false;
    }
  }

  /// Returns the XP-58 printer (preferred), or falls back to the default
  /// system printer. Works even when [Printing.listPrinters] returns an empty
  /// list by constructing the printer from its name — the native Windows
  /// implementation opens the printer by name via `CreateDC("WINSPOOL", ...)`.
  Future<Printer?> _targetPrinter() async {
    try {
      final printers = await Printing.listPrinters();
      if (printers.isNotEmpty) {
        final preferred = printers
            .where((p) =>
                p.name.toLowerCase().contains(preferredPrinterName.toLowerCase()))
            .toList();
        if (preferred.isNotEmpty) {
          debugPrint('$_tag found preferred printer: ${preferred.first.name}');
          return preferred.first;
        }
        return printers.firstWhere(
          (p) => p.isDefault,
          orElse: () => printers.first,
        );
      }
      debugPrint(
          '$_tag listPrinters empty -> targeting $preferredPrinterName by name');
    } catch (e) {
      debugPrint('$_tag list printers error: $e');
    }
    return Printer(url: preferredPrinterName, name: preferredPrinterName);
  }

  // ── TRANSACTION RECEIPT ─────────────────────────────────────────

  pw.Widget _receiptContent(Transaction t) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text('DHBH POS',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        ),
        if (t.branchName != null && t.branchName!.isNotEmpty)
          pw.Center(child: pw.Text(t.branchName!)),
        pw.SizedBox(height: 6),
        pw.Text('Kasir: ${t.cashierName}'),
        pw.Text('Tgl: ${_fmtDateTime(WibTime.toWib(t.createdAt))}'),
        pw.Text('ID: ${t.id}'),
        pw.SizedBox(height: 4),
        pw.Text('─' * 42),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('Qty', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('Harga', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 4),
        for (final item in t.items) ...[
          pw.Text(
            item.product.name.length > 20
                ? item.product.name.substring(0, 20)
                : item.product.name,
          ),
          pw.Text(
              '  ${item.isHomeVisit ? '(Home Visit)' : '(Klinik)'} @${_fmtCurrency(item.unitPrice)}'),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('x${item.quantity}'),
              pw.Text(_fmtCurrency(item.totalPrice)),
            ],
          ),
          pw.SizedBox(height: 4),
        ],
        pw.Text('─' * 42),
        pw.SizedBox(height: 4),
        if (t.discount > 0) ...[
          pw.Text('Subtotal: ${_fmtCurrency(t.subtotal)}'),
          pw.Text('Diskon: -${_fmtCurrency(t.discount)}'),
        ],
        pw.Center(
          child: pw.Text(
            'Total: ${_fmtCurrency(t.totalAmount)}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text('Metode: ${t.paymentMethod.displayName}'),
        if (t.customerNames.isNotEmpty)
          pw.Text('Pelanggan: ${t.customerNames.join(', ')}'),
        if (t.terapisNames.isNotEmpty)
          pw.Text('Terapis: ${t.terapisNames.join(', ')}'),
        if (t.notes != null && t.notes!.isNotEmpty)
          pw.Text('Catatan: ${t.notes}'),
        pw.SizedBox(height: 10),
        pw.Center(child: pw.Text('Terima kasih!')),
        pw.Center(child: pw.Text('Selamat datang kembali')),
      ],
    );
  }

  // ── CLOSING REPORT ──────────────────────────────────────────────

  pw.Widget _closingReportContent({
    required String branchName,
    required String cashierName,
    required DateTime waktuBuka,
    required DateTime waktuTutup,
    required int modalAwal,
    required List<Map<String, dynamic>> productsSold,
    required List<Map<String, dynamic>> payments,
    required List<Map<String, dynamic>> terapis,
    required int totalPenerimaan,
    required int totalTransaksiSelesai,
    required int totalTransaksiHold,
  }) {
    final totalQty =
        productsSold.fold<int>(0, (sum, p) => sum + (p['qty'] as int? ?? 0));
    final terapisNames = terapis
        .map((t) => (t['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text('LAPORAN TUTUP KASIR',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Center(child: pw.Text('PENJUALAN & TRANSAKSI DHBH')),
        pw.SizedBox(height: 6),
        pw.Text('Cabang: $branchName'),
        pw.Text('Kasir: $cashierName'),
        pw.Text('Waktu Buka: ${_fmtDateTime(waktuBuka)}'),
        pw.Text('Waktu Tutup: ${_fmtDateTime(waktuTutup)}'),
        if (terapisNames.isNotEmpty) pw.Text('Terapis: ${terapisNames.join(', ')}'),
        pw.SizedBox(height: 6),
        pw.Text('PRODUK TERJUAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Nama'),
            pw.Text('Qty'),
            pw.Text('Harga'),
          ],
        ),
        pw.Text('${'─' * 22} ${'─' * 5} ${'─' * 11}'),
        for (final product in productsSold)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(product['name'] as String? ?? ''),
              pw.Text('${product['qty'] as int? ?? 0}'),
              pw.Text(_fmtCurrency(product['total'] as int? ?? 0)),
            ],
          ),
        pw.Text('─' * 42),
        pw.Text('Total: ${_fmtCurrency(totalPenerimaan)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Modal Awal: ${_fmtCurrency(modalAwal)}'),
        pw.SizedBox(height: 4),
        pw.Text('PENERIMAAN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        for (final payment in payments)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(payment['method'] as String? ?? ''),
              pw.Text(_fmtCurrency(payment['amount'] as int? ?? 0)),
            ],
          ),
        pw.Text('─' * 42),
        pw.Text('Total Penerimaan: ${_fmtCurrency(totalPenerimaan)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text('Saldo Akhir: ${_fmtCurrency(modalAwal + totalPenerimaan)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Transaksi Selesai: $totalTransaksiSelesai'),
        pw.Text('Transaksi Hold: $totalTransaksiHold'),
        pw.Text('Total Item Terjual: $totalQty'),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text('─' * 42)),
        pw.Center(child: pw.Text('Terima kasih')),
      ],
    );
  }

  pw.Widget _dailySummaryContent({
    required String branchName,
    required String cashierName,
    required DateTime tanggal,
    required int totalTransaksi,
    required int totalRevenue,
    required int cash,
    required int transfer,
    required int qris,
    required int refund,
    required List<Map<String, dynamic>> terapis,
  }) {
    final terapisNames = terapis
        .map((t) => (t['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text('RINGKASAN HARIAN',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Center(child: pw.Text('PENJUALAN & TRANSAKSI DHBH')),
        pw.SizedBox(height: 6),
        pw.Text('Cabang: $branchName'),
        pw.Text('Kasir: $cashierName'),
        pw.Text('Tanggal: ${_fmtDateTime(tanggal)}'),
        if (terapisNames.isNotEmpty) pw.Text('Terapis: ${terapisNames.join(', ')}'),
        pw.SizedBox(height: 6),
        pw.Text('Total Transaksi: $totalTransaksi',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text('Total Revenue: ${_fmtCurrency(totalRevenue)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('PENERIMAAN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Cash'),
            pw.Text(_fmtCurrency(cash)),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Transfer'),
            pw.Text(_fmtCurrency(transfer)),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('QRIS'),
            pw.Text(_fmtCurrency(qris)),
          ],
        ),
        if (refund > 0)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Refund'),
              pw.Text('-${_fmtCurrency(refund)}'),
            ],
          ),
        pw.Text('─' * 42),
        pw.Text('Total Penerimaan: ${_fmtCurrency(totalRevenue)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text('─' * 42)),
        pw.Center(child: pw.Text('Terima kasih')),
      ],
    );
  }

  // ── HELPERS ─────────────────────────────────────────────────────

  String _fmtDateTime(DateTime d) {
    return '${d.day}/${d.month}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _fmtCurrency(int amount) {
    final s = amount.toString();
    if (s.length <= 3) return 'Rp$s';
    final reversed = s.split('').reversed.toList();
    final chunks = <String>[];
    for (int i = 0; i < reversed.length; i += 3) {
      chunks.add(
        reversed
            .sublist(i, i + 3 < reversed.length ? i + 3 : reversed.length)
            .reversed
            .join(),
      );
    }
    return 'Rp${chunks.reversed.join('.')}';
  }
}
