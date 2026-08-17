import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/transaction.dart';
import '../utils/wib_time.dart';
import 'bluetooth_service.dart';

class ThermalPrinterService {
  static final ThermalPrinterService _instance = ThermalPrinterService._internal();

  factory ThermalPrinterService() {
    return _instance;
  }

  ThermalPrinterService._internal();

  final BluetoothService _bluetooth = BluetoothService();

  /// ESC/POS commands
  static const List<int> _initPrinter = [0x1B, 0x40];
  static const List<int> _centerAlign = [0x1B, 0x61, 0x01];
  static const List<int> _leftAlign = [0x1B, 0x61, 0x00];
  static const List<int> _bold = [0x1B, 0x45, 0x01];
  static const List<int> _unbold = [0x1B, 0x45, 0x00];
  static const List<int> _largeFontOn = [0x1B, 0x21, 0x08];
  static const List<int> _largeFontOff = [0x1B, 0x21, 0x00];
  static const List<int> _lineFeed = [0x0A];
  static const List<int> _cutPaper = [0x1D, 0x56, 0x42, 0x00];

  /// Lebar kertas thermal 58mm standar = 32 karakter (font normal)
  static const int _lineWidth = 32;

  /// Print transaction receipt
  Future<bool> printTransaction(Transaction transaction) async {
    try {
      if (!_bluetooth.isConnected) {
        debugPrint('[Printer] Not connected to printer');
        return false;
      }

      final receiptData = _generateReceipt(transaction);
      final result = await _bluetooth.sendData(receiptData);

      if (result) {
        debugPrint('[Printer] ✓ Receipt printed successfully');
      } else {
        debugPrint('[Printer] ✗ Failed to print receipt');
      }

      return result;
    } catch (e) {
      debugPrint('[Printer] Print error: $e');
      return false;
    }
  }

  /// Generate receipt data in ESC/POS format
  List<int> _generateReceipt(Transaction transaction) {
    final receipt = <int>[];

    // Initialize printer
    receipt.addAll(_initPrinter);
    receipt.addAll(_lineFeed);

    // === HEADER (centered, bold, large) ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_largeFontOn);
    receipt.addAll(_stringToBytes('DHBH POS'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_largeFontOff);

    // Branch name (centered)
    if (transaction.branchName != null && transaction.branchName!.isNotEmpty) {
      receipt.addAll(_stringToBytes(transaction.branchName!));
      receipt.addAll(_lineFeed);
    }
    receipt.addAll(_lineFeed);

    // === INFO SECTION (left aligned) ===
    receipt.addAll(_leftAlign);
    receipt.addAll(_printRow('Kasir', transaction.cashierName));
    receipt.addAll(_printRow('Tgl', _formatDateTime(WibTime.toWib(transaction.createdAt))));
    receipt.addAll(_printRow('No', '#${transaction.id}'));

    // Dotted divider
    receipt.addAll(_printDottedLine());

    // === ITEMS ===
    for (var item in transaction.items) {
      // Item name (truncated to 32 chars if too long)
      final itemName = _truncate(item.product.name, _lineWidth);
      receipt.addAll(_bold);
      receipt.addAll(_stringToBytes(itemName));
      receipt.addAll(_lineFeed);
      receipt.addAll(_unbold);

      // Type label + qty + price on one line: "(Klinik) x2          Rp50.000"
      final priceType = item.isHomeVisit ? 'Home Visit' : 'Klinik';
      final qtyStr = 'x${item.quantity}';
      final priceStr = _formatCurrency(item.totalPrice);
      final detailLine = '($priceType) $qtyStr';
      receipt.addAll(_stringToBytes(_padRow(detailLine, priceStr)));
      receipt.addAll(_lineFeed);

      // Unit price (small, indented)
      final unitPriceStr = _formatCurrency(item.unitPrice);
      receipt.addAll(_stringToBytes('  @$unitPriceStr'));
      receipt.addAll(_lineFeed);
    }

    // Double divider before total
    receipt.addAll(_printDoubleLine());

    // Subtotal & Diskon (if any)
    if (transaction.discount > 0) {
      receipt.addAll(_printRow('Subtotal', _formatCurrency(transaction.subtotal)));
      receipt.addAll(_printRow('Diskon', '-${_formatCurrency(transaction.discount)}'));
      receipt.addAll(_printDottedLine());
    }

    // === TOTAL (centered, large, bold) ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_largeFontOn);
    final totalStr = _formatCurrency(transaction.totalAmount);
    receipt.addAll(_stringToBytes('TOTAL'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_stringToBytes(totalStr));
    receipt.addAll(_lineFeed);
    receipt.addAll(_largeFontOff);
    receipt.addAll(_unbold);

    // Single divider
    receipt.addAll(_leftAlign);
    receipt.addAll(_printDottedLine());

    // === PAYMENT INFO (compact key-value) ===
    receipt.addAll(_printRow('Bayar', transaction.paymentMethod.displayName));
    if (transaction.paymentMethod == PaymentMethod.cash) {
      receipt.addAll(_printRow('Dibayar', _formatCurrency(transaction.amountPaid)));
      receipt.addAll(_printRow('Kembali', _formatCurrency(transaction.change)));
    }

    // Dotted divider before additional info
    receipt.addAll(_printDottedLine());

    // === ADDITIONAL INFO ===
    for (var i = 0; i < transaction.customerNames.length; i++) {
      if (i == 0) {
        receipt.addAll(_printRow('Pelanggan',
            _truncate(transaction.customerNames[i], _lineWidth - 10)));
      } else {
        receipt.addAll(_stringToBytes(
            '  ${_truncate(transaction.customerNames[i], _lineWidth - 2)}'));
        receipt.addAll(_lineFeed);
      }
    }
    for (var i = 0; i < transaction.terapisNames.length; i++) {
      if (i == 0) {
        receipt.addAll(_printRow('Terapis',
            _truncate(transaction.terapisNames[i], _lineWidth - 8)));
      } else {
        receipt.addAll(_stringToBytes(
            '  ${_truncate(transaction.terapisNames[i], _lineWidth - 2)}'));
        receipt.addAll(_lineFeed);
      }
    }
    if (transaction.notes != null && transaction.notes!.isNotEmpty) {
      receipt.addAll(_stringToBytes('Catatan:'));
      receipt.addAll(_lineFeed);
      receipt.addAll(_stringToBytes(' ${_truncate(transaction.notes!, _lineWidth - 1)}'));
      receipt.addAll(_lineFeed);
    }

    // === FOOTER ===
    receipt.addAll(_printDottedLine());
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('Terima Kasih!'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_stringToBytes('Selamat datang kembali'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_lineFeed);
    receipt.addAll(_lineFeed);

    // Cut paper
    receipt.addAll(_cutPaper);

    return receipt;
  }

  /// Generate closing report receipt
  List<int> generateClosingReport({
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
    final receipt = <int>[];

    receipt.addAll(_initPrinter);
    receipt.addAll(_lineFeed);

    // === TITLE ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_largeFontOn);
    receipt.addAll(_stringToBytes('LAPORAN TUTUP KASIR'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_largeFontOff);
    receipt.addAll(_stringToBytes('PENJUALAN & TRANSAKSI DHBH'));
    receipt.addAll(_lineFeed);

    // Double line
    receipt.addAll(_leftAlign);
    receipt.addAll(_printDoubleLine());

    // === INFO ===
    receipt.addAll(_printRow('Cabang', _truncate(branchName, 20)));
    receipt.addAll(_printRow('Kasir', _truncate(cashierName, 20)));
    receipt.addAll(_printRow('Buka', _formatDateTime(waktuBuka)));
    receipt.addAll(_printRow('Tutup', _formatDateTime(waktuTutup)));

    receipt.addAll(_printDoubleLine());

    // === TERAPIS ===
    if (terapis.isNotEmpty) {
      receipt.addAll(_centerAlign);
      receipt.addAll(_bold);
      receipt.addAll(_stringToBytes('TERAPIS'));
      receipt.addAll(_lineFeed);
      receipt.addAll(_unbold);
      receipt.addAll(_leftAlign);
      for (final t in terapis) {
        final name = (t['name'] as String?) ?? '';
        if (name.isNotEmpty) {
          receipt.addAll(_stringToBytes(_truncate(name, _lineWidth)));
          receipt.addAll(_lineFeed);
        }
      }
      receipt.addAll(_printDottedLine());
    }

    // === PRODUCTS SOLD ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('PRODUK TERJUAL'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_leftAlign);
    receipt.addAll(_printDottedLine());

    if (productsSold.isEmpty) {
      receipt.addAll(_centerAlign);
      receipt.addAll(_stringToBytes('(Tidak ada produk)'));
      receipt.addAll(_lineFeed);
      receipt.addAll(_leftAlign);
    } else {
      for (final product in productsSold) {
        final name = (product['name'] as String? ?? '');
        final qty = product['qty'] as int? ?? 0;
        final price = product['total'] as int? ?? 0;

        // Line 1: Name (truncated)
        receipt.addAll(_stringToBytes(_truncate(name, _lineWidth)));
        receipt.addAll(_lineFeed);
        // Line 2: " x{qty}              Rp{price}"
        receipt.addAll(_stringToBytes(_padRow('  x$qty', _formatCurrency(price))));
        receipt.addAll(_lineFeed);
      }
    }

    receipt.addAll(_printDottedLine());

    // === TOTAL PRODUK ===
    receipt.addAll(_bold);
    receipt.addAll(_printRow('Total Produk', _formatCurrency(totalPenerimaan)));
    receipt.addAll(_unbold);

    receipt.addAll(_printDoubleLine());

    // === MODAL AWAL ===
    receipt.addAll(_bold);
    receipt.addAll(_printRow('MODAL AWAL', _formatCurrency(modalAwal)));
    receipt.addAll(_unbold);

    receipt.addAll(_printDoubleLine());

    // === PENERIMAAN ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('PENERIMAAN'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_leftAlign);
    receipt.addAll(_printDottedLine());

    if (payments.isEmpty) {
      receipt.addAll(_centerAlign);
      receipt.addAll(_stringToBytes('(Tidak ada pembayaran)'));
      receipt.addAll(_lineFeed);
      receipt.addAll(_leftAlign);
    } else {
      for (final payment in payments) {
        final method = payment['method'] as String? ?? '';
        final amount = payment['amount'] as int? ?? 0;
        receipt.addAll(_printRow(method, _formatCurrency(amount)));
      }
    }

    receipt.addAll(_printDoubleLine());

    // === TOTAL PENERIMAAN (big) ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_largeFontOn);
    receipt.addAll(_stringToBytes('TOTAL PENERIMAAN'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_stringToBytes(_formatCurrency(totalPenerimaan)));
    receipt.addAll(_lineFeed);
    receipt.addAll(_largeFontOff);
    receipt.addAll(_unbold);

    // === SALDO AKHIR ===
    receipt.addAll(_leftAlign);
    receipt.addAll(_printDottedLine());
    receipt.addAll(_bold);
    receipt.addAll(_printRow('SALDO AKHIR', _formatCurrency(modalAwal + totalPenerimaan)));
    receipt.addAll(_unbold);

    receipt.addAll(_printDoubleLine());

    // === RINGKASAN TRANSAKSI ===
    final totalQty = productsSold.fold(0, (sum, p) => sum + (p['qty'] as int? ?? 0));
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('RINGKASAN'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_leftAlign);
    receipt.addAll(_printRow('Transaksi Selesai', '$totalTransaksiSelesai'));
    receipt.addAll(_printRow('Transaksi Hold', '$totalTransaksiHold'));
    receipt.addAll(_printRow('Total Item', '$totalQty'));

    // === FOOTER ===
    receipt.addAll(_printDoubleLine());
    receipt.addAll(_centerAlign);
    receipt.addAll(_stringToBytes('Terima kasih'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_lineFeed);
    receipt.addAll(_lineFeed);

    receipt.addAll(_cutPaper);
    return receipt;
  }

  /// Generate daily summary (ringkasan harian) receipt
  List<int> generateDailySummary({
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
    final receipt = <int>[];

    receipt.addAll(_initPrinter);
    receipt.addAll(_lineFeed);

    // === TITLE ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_largeFontOn);
    receipt.addAll(_stringToBytes('RINGKASAN HARIAN'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_largeFontOff);
    receipt.addAll(_stringToBytes('PENJUALAN & TRANSAKSI DHBH'));
    receipt.addAll(_lineFeed);

    receipt.addAll(_leftAlign);
    receipt.addAll(_printDoubleLine());

    // === INFO ===
    receipt.addAll(_printRow('Cabang', _truncate(branchName, 20)));
    receipt.addAll(_printRow('Kasir', _truncate(cashierName, 20)));
    receipt.addAll(_printRow('Tanggal', _formatDateTime(tanggal)));

    receipt.addAll(_printDoubleLine());

    // === TERAPIS ===
    if (terapis.isNotEmpty) {
      receipt.addAll(_centerAlign);
      receipt.addAll(_bold);
      receipt.addAll(_stringToBytes('TERAPIS'));
      receipt.addAll(_lineFeed);
      receipt.addAll(_unbold);
      receipt.addAll(_leftAlign);
      for (final t in terapis) {
        final name = (t['name'] as String?) ?? '';
        if (name.isNotEmpty) {
          receipt.addAll(_stringToBytes(_truncate(name, _lineWidth)));
          receipt.addAll(_lineFeed);
        }
      }
      receipt.addAll(_printDottedLine());
    }

    // === TOTALS ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('TOTAL HARI INI'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_leftAlign);
    receipt.addAll(_printRow('Jumlah Transaksi', '$totalTransaksi'));
    receipt.addAll(_printRow('Total Revenue', _formatCurrency(totalRevenue)));

    receipt.addAll(_printDoubleLine());

    // === PENERIMAAN PER METODE ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('METODE PEMBAYARAN'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_leftAlign);
    receipt.addAll(_printDottedLine());
    receipt.addAll(_printRow('Cash', _formatCurrency(cash)));
    receipt.addAll(_printRow('Transfer', _formatCurrency(transfer)));
    receipt.addAll(_printRow('QRIS', _formatCurrency(qris)));
    if (refund > 0) {
      receipt.addAll(_printRow('Refund', '-${_formatCurrency(refund)}'));
    }

    receipt.addAll(_printDoubleLine());

    // === TOTAL PENERIMAAN (big) ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_largeFontOn);
    receipt.addAll(_stringToBytes('TOTAL PENERIMAAN'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_stringToBytes(_formatCurrency(totalRevenue)));
    receipt.addAll(_lineFeed);
    receipt.addAll(_largeFontOff);
    receipt.addAll(_unbold);

    // === FOOTER ===
    receipt.addAll(_leftAlign);
    receipt.addAll(_printDoubleLine());
    receipt.addAll(_centerAlign);
    receipt.addAll(_stringToBytes('Terima kasih'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_lineFeed);
    receipt.addAll(_lineFeed);

    receipt.addAll(_cutPaper);
    return receipt;
  }

  /// Print closing report
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
  }) async {
    try {
      if (!_bluetooth.isConnected) {
        debugPrint('[Printer] Not connected');
        return false;
      }

      final data = generateClosingReport(
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
      );

      final result = await _bluetooth.sendData(data);
      debugPrint('[Printer] Closing report: ${result ? "✓" : "✗"}');
      return result;
    } catch (e) {
      debugPrint('[Printer] Closing report error: $e');
      return false;
    }
  }

  /// Print daily summary (ringkasan harian)
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
  }) async {
    try {
      if (!_bluetooth.isConnected) {
        debugPrint('[Printer] Not connected');
        return false;
      }

      final data = generateDailySummary(
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
      );

      final result = await _bluetooth.sendData(data);
      debugPrint('[Printer] Daily summary: ${result ? "✓" : "✗"}');
      return result;
    } catch (e) {
      debugPrint('[Printer] Daily summary error: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════
  //  HELPER METHODS - Formatting untuk 58mm printer
  // ════════════════════════════════════════════════

  /// Convert string to bytes (ASCII)
  List<int> _stringToBytes(String text) {
    return List<int>.from(text.codeUnits);
  }

  /// Membuat baris dengan label di kiri dan value di kanan, tepat 32 karakter.
  /// Contoh: "Kasir: John              Rp100.000"
  List<int> _printRow(String label, String value) {
    final row = _stringToBytes(_padRow('$label:', value));
    row.addAll(_lineFeed);
    return row;
  }

  /// Pad row: label di kiri, value di kanan, total 32 karakter.
  /// Jika total panjang melebihi 32, value dipotong dari kiri dengan "...".
  String _padRow(String left, String right) {
    final available = _lineWidth - left.length;
    if (available <= 0) {
      return left.substring(0, _lineWidth);
    }
    String trimmedRight = right;
    if (right.length > available) {
      trimmedRight = '...${right.substring(right.length - available + 3)}';
    }
    final spaces = ' ' * (available - trimmedRight.length);
    return '$left$spaces$trimmedRight';
  }

  /// Print dotted line (--------------------------------) 32 karakter.
  List<int> _printDottedLine() {
    final line = _stringToBytes('-' * _lineWidth);
    line.addAll(_lineFeed);
    return line;
  }

  /// Print double line (================================) untuk penekanan.
  List<int> _printDoubleLine() {
    final line = _stringToBytes('=' * _lineWidth);
    line.addAll(_lineFeed);
    return line;
  }

  /// Truncate text ke maxChars dengan menambahkan "..." di akhir.
  String _truncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    if (maxChars <= 3) return text.substring(0, maxChars);
    return '${text.substring(0, maxChars - 3)}...';
  }

  /// Format date time ke dd/MM/yyyy HH:mm
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/'
        '${dateTime.month.toString().padLeft(2, '0')}/'
        '${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Format currency dengan pemisah titik ribuan.
  String _formatCurrency(int amount) {
    final formatter = amount.toString();
    if (formatter.length <= 3) return 'Rp$formatter';

    final reversed = formatter.split('').reversed.toList();
    final chunks = <String>[];
    for (int i = 0; i < reversed.length; i += 3) {
      chunks.add(reversed.sublist(i, i + 3 < reversed.length ? i + 3 : reversed.length).reversed.join());
    }
    return 'Rp${chunks.reversed.join('.')}';
  }
}