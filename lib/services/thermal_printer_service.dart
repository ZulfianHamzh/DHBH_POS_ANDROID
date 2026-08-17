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
  static const List<int> _rightAlign = [0x1B, 0x61, 0x02];
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

  /// Helper untuk mengekstrak nama terapis dari berbagai format
  List<String> _extractTherapistNames(dynamic data) {
    final names = <String>[];

    if (data == null) return names;

    // Jika data adalah List<String>
    if (data is List<String>) {
      for (final name in data) {
        // Split jika ada koma (misal: "Alan, Siti")
        if (name.contains(',')) {
          final parts = name.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
          names.addAll(parts);
        } else if (name.contains(' dan ')) {
          // Split jika ada " dan "
          final parts = name.split(' dan ').map((e) => e.trim()).where((e) => e.isNotEmpty);
          names.addAll(parts);
        } else {
          names.add(name.trim());
        }
      }
      return names;
    }

    // Jika data adalah List<Map>
    if (data is List<Map>) {
      for (final item in data) {
        final name = item['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          // Split jika ada koma
          if (name.contains(',')) {
            final parts = name.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
            names.addAll(parts);
          } else if (name.contains(' dan ')) {
            final parts = name.split(' dan ').map((e) => e.trim()).where((e) => e.isNotEmpty);
            names.addAll(parts);
          } else {
            names.add(name);
          }
        }
      }
      return names;
    }

    // Jika data adalah String
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isNotEmpty) {
        if (trimmed.contains(',')) {
          final parts = trimmed.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
          names.addAll(parts);
        } else if (trimmed.contains(' dan ')) {
          final parts = trimmed.split(' dan ').map((e) => e.trim()).where((e) => e.isNotEmpty);
          names.addAll(parts);
        } else {
          names.add(trimmed);
        }
      }
      return names;
    }

    return names;
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
    receipt.addAll(_printDoubleLine());

    // Branch name (centered, bold)
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    if (transaction.branchName != null && transaction.branchName!.isNotEmpty) {
      receipt.addAll(_stringToBytes(_truncate(transaction.branchName!, _lineWidth)));
    } else {
      receipt.addAll(_stringToBytes(_truncate('Cabang Utama', _lineWidth)));
    }
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_stringToBytes('DHBH POS'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_printDoubleLine());

    // === INFO SECTION (left aligned) ===
    receipt.addAll(_leftAlign);
    receipt.addAll(_printRow('Kasir', transaction.cashierName, _lineWidth));
    receipt.addAll(_printRow('Tanggal', _formatDateTime(WibTime.toWib(transaction.createdAt)), _lineWidth));
    receipt.addAll(_printRow('No. Transaksi', '#${transaction.id}', _lineWidth));
    receipt.addAll(_printDottedLine());

    // === ITEMS HEADER ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('DETAIL ITEM'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_leftAlign);
    receipt.addAll(_printDottedLine());

    // === ITEMS ===
    int itemNumber = 1;
    for (var item in transaction.items) {
      // Item number and name
      final itemName = _truncate(item.product.name, _lineWidth - 4);
      receipt.addAll(_stringToBytes('${itemNumber.toString().padLeft(2)}. $itemName'));
      receipt.addAll(_lineFeed);

      // Type, quantity, and unit price
      final priceType = item.isHomeVisit ? 'Home Visit' : 'Klinik';
      final qtyStr = '${item.quantity}x';
      final unitPriceStr = _formatCurrency(item.unitPrice);
      final detailLine = '   $priceType $qtyStr @ $unitPriceStr';
      receipt.addAll(_stringToBytes(_truncate(detailLine, _lineWidth)));
      receipt.addAll(_lineFeed);

      // Subtotal for this item (right aligned)
      final subtotalStr = _formatCurrency(item.totalPrice);
      receipt.addAll(_rightAlign);
      receipt.addAll(_stringToBytes('Subtotal: $subtotalStr'));
      receipt.addAll(_lineFeed);
      receipt.addAll(_leftAlign);

      // Divider between items
      if (itemNumber < transaction.items.length) {
        receipt.addAll(_stringToBytes('-' * _lineWidth));
        receipt.addAll(_lineFeed);
      }

      itemNumber++;
    }

    // Double divider before total
    receipt.addAll(_printDoubleLine());

    // Subtotal & Diskon (if any)
    receipt.addAll(_leftAlign);
    receipt.addAll(_printRow('Subtotal', _formatCurrency(transaction.subtotal), _lineWidth));

    if (transaction.discount > 0) {
      receipt.addAll(_printRow('Diskon', '-${_formatCurrency(transaction.discount)}', _lineWidth));
    }

    receipt.addAll(_printDottedLine());

    // === TOTAL (centered, large, bold) ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_largeFontOn);
    receipt.addAll(_stringToBytes('TOTAL'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_stringToBytes(_formatCurrency(transaction.totalAmount)));
    receipt.addAll(_lineFeed);
    receipt.addAll(_largeFontOff);
    receipt.addAll(_unbold);
    receipt.addAll(_printDottedLine());

    // === PAYMENT INFO (compact key-value) ===
    receipt.addAll(_leftAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('PEMBAYARAN'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_printDottedLine());

    receipt.addAll(_printRow('Metode', transaction.paymentMethod.displayName, _lineWidth));
    if (transaction.paymentMethod == PaymentMethod.cash) {
      receipt.addAll(_printRow('Dibayar', _formatCurrency(transaction.amountPaid), _lineWidth));
      receipt.addAll(_printRow('Kembali', _formatCurrency(transaction.change), _lineWidth));
    }
    receipt.addAll(_printDottedLine());

    // === CUSTOMER & THERAPIST INFO ===
    if (transaction.customerNames.isNotEmpty) {
      receipt.addAll(_bold);
      receipt.addAll(_stringToBytes('PELANGGAN'));
      receipt.addAll(_lineFeed);
      receipt.addAll(_unbold);

      // Extract and clean customer names
      final allCustomers = <String>[];
      for (final name in transaction.customerNames) {
        final extracted = _extractTherapistNames(name);
        allCustomers.addAll(extracted);
      }

      // Group and count
      final customerCount = <String, int>{};
      for (final name in allCustomers) {
        if (name.isNotEmpty) {
          customerCount[name] = (customerCount[name] ?? 0) + 1;
        }
      }

      final sortedEntries = customerCount.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));

      for (final entry in sortedEntries) {
        final line = '   ${entry.key}';
        receipt.addAll(_stringToBytes(_truncate(line, _lineWidth)));
        receipt.addAll(_lineFeed);
      }

      receipt.addAll(_printDottedLine());
    }

    if (transaction.terapisNames.isNotEmpty) {
      receipt.addAll(_bold);
      receipt.addAll(_stringToBytes('TERAPIS'));
      receipt.addAll(_lineFeed);
      receipt.addAll(_unbold);

      // Extract and clean therapist names
      final allTherapists = <String>[];
      for (final name in transaction.terapisNames) {
        final extracted = _extractTherapistNames(name);
        allTherapists.addAll(extracted);
      }

      // Group therapists by name and count
      final therapistCount = <String, int>{};
      for (final name in allTherapists) {
        final cleanName = name.trim();
        if (cleanName.isNotEmpty) {
          therapistCount[cleanName] = (therapistCount[cleanName] ?? 0) + 1;
        }
      }

      // Sort by count (descending) then by name
      final sortedEntries = therapistCount.entries.toList()
        ..sort((a, b) {
          final countCompare = b.value.compareTo(a.value);
          if (countCompare != 0) return countCompare;
          return a.key.compareTo(b.key);
        });

      for (final entry in sortedEntries) {
        final line = '   ${entry.key} ${entry.value}x';
        receipt.addAll(_stringToBytes(_truncate(line, _lineWidth)));
        receipt.addAll(_lineFeed);
      }

      receipt.addAll(_printDottedLine());
    }

    // Notes
    if (transaction.notes != null && transaction.notes!.isNotEmpty) {
      receipt.addAll(_bold);
      receipt.addAll(_stringToBytes('CATATAN'));
      receipt.addAll(_lineFeed);
      receipt.addAll(_unbold);
      final notes = _wrapText(transaction.notes!, _lineWidth - 2);
      for (final line in notes) {
        receipt.addAll(_stringToBytes('  $line'));
        receipt.addAll(_lineFeed);
      }
      receipt.addAll(_printDottedLine());
    }

    // === FOOTER ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('TERIMA KASIH!'));
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

  /// Helper untuk mengekstrak dan membersihkan daftar terapis dari berbagai format
  List<Map<String, dynamic>> _cleanTherapistList(List<Map<String, dynamic>> terapis) {
    final cleaned = <Map<String, dynamic>>[];
    final seenNames = <String>{};

    for (final t in terapis) {
      final rawName = (t['name'] as String?) ?? '';
      if (rawName.isEmpty) continue;

      // Jika nama mengandung koma, split
      if (rawName.contains(',')) {
        final parts = rawName.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
        for (final part in parts) {
          if (!seenNames.contains(part)) {
            seenNames.add(part);
            cleaned.add({'name': part});
          }
        }
      } else if (rawName.contains(' dan ')) {
        final parts = rawName.split(' dan ').map((e) => e.trim()).where((e) => e.isNotEmpty);
        for (final part in parts) {
          if (!seenNames.contains(part)) {
            seenNames.add(part);
            cleaned.add({'name': part});
          }
        }
      } else {
        if (!seenNames.contains(rawName)) {
          seenNames.add(rawName);
          cleaned.add({'name': rawName});
        }
      }
    }

    return cleaned;
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

    // === HEADER ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_largeFontOn);
    receipt.addAll(_stringToBytes('LAPORAN TUTUP KASIR'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_largeFontOff);
    receipt.addAll(_printDoubleLine());

    // Branch name
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes(_truncate(branchName, _lineWidth)));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_stringToBytes('DHBH POS'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_printDoubleLine());

    // === INFO ===
    receipt.addAll(_leftAlign);
    receipt.addAll(_printRow('Kasir', _truncate(cashierName, 20), _lineWidth));
    receipt.addAll(_printRow('Buka', _formatDateTime(waktuBuka), _lineWidth));
    receipt.addAll(_printRow('Tutup', _formatDateTime(waktuTutup), _lineWidth));
    receipt.addAll(_printDoubleLine());

    // === TERAPIS SUMMARY ===
    if (terapis.isNotEmpty) {
      receipt.addAll(_centerAlign);
      receipt.addAll(_bold);
      receipt.addAll(_stringToBytes('DAFTAR TERAPIS'));
      receipt.addAll(_lineFeed);
      receipt.addAll(_unbold);
      receipt.addAll(_leftAlign);
      receipt.addAll(_printDottedLine());

      // Clean and group therapists
      final cleanedTerapis = _cleanTherapistList(terapis);

      // Group therapists by name and count from original data
      final therapistCount = <String, int>{};
      for (final t in terapis) {
        final rawName = (t['name'] as String?) ?? '';
        if (rawName.isEmpty) continue;

        // Extract all names from this entry
        final names = _extractTherapistNames(rawName);
        for (final name in names) {
          if (name.isNotEmpty) {
            therapistCount[name] = (therapistCount[name] ?? 0) + 1;
          }
        }
      }

      // Sort by count (descending) then by name
      final sortedEntries = therapistCount.entries.toList()
        ..sort((a, b) {
          final countCompare = b.value.compareTo(a.value);
          if (countCompare != 0) return countCompare;
          return a.key.compareTo(b.key);
        });

      for (final entry in sortedEntries) {
        final line = '• ${entry.key} ${entry.value}x';
        receipt.addAll(_stringToBytes(_truncate(line, _lineWidth)));
        receipt.addAll(_lineFeed);
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
      // Group products by name
      final productSummary = <String, Map<String, dynamic>>{};
      for (final product in productsSold) {
        final name = (product['name'] as String? ?? '');
        final qty = product['qty'] as int? ?? 0;
        final price = product['total'] as int? ?? 0;

        if (name.isNotEmpty) {
          if (productSummary.containsKey(name)) {
            productSummary[name]!['qty'] = (productSummary[name]!['qty'] as int) + qty;
            productSummary[name]!['total'] = (productSummary[name]!['total'] as int) + price;
          } else {
            productSummary[name] = {
              'qty': qty,
              'total': price,
            };
          }
        }
      }

      // Sort by total (descending)
      final sortedProducts = productSummary.entries.toList()
        ..sort((a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));

      for (final entry in sortedProducts) {
        final name = entry.key;
        final qty = entry.value['qty'] as int;
        final price = entry.value['total'] as int;

        receipt.addAll(_stringToBytes(_truncate(name, _lineWidth)));
        receipt.addAll(_lineFeed);
        receipt.addAll(_rightAlign);
        receipt.addAll(_stringToBytes('${qty}x  ${_formatCurrency(price)}'));
        receipt.addAll(_lineFeed);
        receipt.addAll(_leftAlign);
      }
    }
    receipt.addAll(_printDottedLine());

    // === TOTAL PRODUK ===
    receipt.addAll(_bold);
    receipt.addAll(_printRow('Total Penjualan', _formatCurrency(totalPenerimaan), _lineWidth));
    receipt.addAll(_unbold);
    receipt.addAll(_printDoubleLine());

    // === MODAL AWAL ===
    receipt.addAll(_bold);
    receipt.addAll(_printRow('MODAL AWAL', _formatCurrency(modalAwal), _lineWidth));
    receipt.addAll(_unbold);
    receipt.addAll(_printDoubleLine());

    // === PENERIMAAN PER METODE ===
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
      // Group payments by method
      final paymentSummary = <String, int>{};
      for (final payment in payments) {
        final method = payment['method'] as String? ?? '';
        final amount = payment['amount'] as int? ?? 0;
        if (method.isNotEmpty) {
          paymentSummary[method] = (paymentSummary[method] ?? 0) + amount;
        }
      }

      // Sort by amount (descending)
      final sortedPayments = paymentSummary.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final entry in sortedPayments) {
        receipt.addAll(_printRow(entry.key, _formatCurrency(entry.value), _lineWidth));
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
    receipt.addAll(_printDottedLine());

    // === SALDO AKHIR ===
    receipt.addAll(_leftAlign);
    receipt.addAll(_bold);
    receipt.addAll(_printRow('SALDO AKHIR', _formatCurrency(modalAwal + totalPenerimaan), _lineWidth));
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
    receipt.addAll(_printDottedLine());
    receipt.addAll(_printRow('Transaksi Selesai', '$totalTransaksiSelesai', _lineWidth));
    receipt.addAll(_printRow('Transaksi Hold', '$totalTransaksiHold', _lineWidth));
    receipt.addAll(_printRow('Total Item', '$totalQty', _lineWidth));
    receipt.addAll(_printDottedLine());

    // === FOOTER ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('Terima Kasih'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
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
    required List<Map<String, dynamic>> productsSold,
  }) {
    final receipt = <int>[];

    receipt.addAll(_initPrinter);
    receipt.addAll(_lineFeed);

    // === HEADER ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_largeFontOn);
    receipt.addAll(_stringToBytes('RINGKASAN HARIAN'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_largeFontOff);
    receipt.addAll(_printDoubleLine());

    // Branch name
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes(_truncate(branchName, _lineWidth)));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_stringToBytes('DHBH POS'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_printDoubleLine());

    // === INFO ===
    receipt.addAll(_leftAlign);
    receipt.addAll(_printRow('Kasir', _truncate(cashierName, 20), _lineWidth));
    receipt.addAll(_printRow('Tanggal', _formatDateTime(tanggal), _lineWidth));
    receipt.addAll(_printDoubleLine());

    // === TERAPIS SUMMARY ===
    if (terapis.isNotEmpty) {
      receipt.addAll(_centerAlign);
      receipt.addAll(_bold);
      receipt.addAll(_stringToBytes('DAFTAR TERAPIS'));
      receipt.addAll(_lineFeed);
      receipt.addAll(_unbold);
      receipt.addAll(_leftAlign);
      receipt.addAll(_printDottedLine());

      // Group therapists by name and count
      final therapistCount = <String, int>{};
      for (final t in terapis) {
        final rawName = (t['name'] as String?) ?? '';
        if (rawName.isEmpty) continue;

        // Extract all names from this entry
        final names = _extractTherapistNames(rawName);
        for (final name in names) {
          if (name.isNotEmpty) {
            therapistCount[name] = (therapistCount[name] ?? 0) + 1;
          }
        }
      }

      // Sort by count (descending) then by name
      final sortedEntries = therapistCount.entries.toList()
        ..sort((a, b) {
          final countCompare = b.value.compareTo(a.value);
          if (countCompare != 0) return countCompare;
          return a.key.compareTo(b.key);
        });

      for (final entry in sortedEntries) {
        final line = '• ${entry.key} ${entry.value}x';
        receipt.addAll(_stringToBytes(_truncate(line, _lineWidth)));
        receipt.addAll(_lineFeed);
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
      // Group products by name
      final productSummary = <String, Map<String, dynamic>>{};
      for (final product in productsSold) {
        final name = (product['name'] as String? ?? '');
        final qty = product['qty'] as int? ?? 0;
        final price = product['total'] as int? ?? 0;

        if (name.isNotEmpty) {
          if (productSummary.containsKey(name)) {
            productSummary[name]!['qty'] = (productSummary[name]!['qty'] as int) + qty;
            productSummary[name]!['total'] = (productSummary[name]!['total'] as int) + price;
          } else {
            productSummary[name] = {
              'qty': qty,
              'total': price,
            };
          }
        }
      }

      // Sort by total (descending)
      final sortedProducts = productSummary.entries.toList()
        ..sort((a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));

      for (final entry in sortedProducts) {
        final name = entry.key;
        final qty = entry.value['qty'] as int;
        final price = entry.value['total'] as int;

        receipt.addAll(_stringToBytes(_truncate(name, _lineWidth)));
        receipt.addAll(_lineFeed);
        receipt.addAll(_rightAlign);
        receipt.addAll(_stringToBytes('${qty}x  ${_formatCurrency(price)}'));
        receipt.addAll(_lineFeed);
        receipt.addAll(_leftAlign);
      }
    }
    receipt.addAll(_printDottedLine());

    // === TOTAL PRODUK ===
    receipt.addAll(_bold);
    receipt.addAll(_printRow('Total Penjualan', _formatCurrency(totalRevenue), _lineWidth));
    receipt.addAll(_unbold);
    receipt.addAll(_printDoubleLine());

    // === TOTALS ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('TOTAL HARI INI'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_leftAlign);
    receipt.addAll(_printDottedLine());
    receipt.addAll(_printRow('Jumlah Transaksi', '$totalTransaksi', _lineWidth));
    receipt.addAll(_printRow('Total Revenue', _formatCurrency(totalRevenue), _lineWidth));
    receipt.addAll(_printDoubleLine());

    // === PENERIMAAN PER METODE ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('METODE PEMBAYARAN'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
    receipt.addAll(_leftAlign);
    receipt.addAll(_printDottedLine());
    receipt.addAll(_printRow('Cash', _formatCurrency(cash), _lineWidth));
    receipt.addAll(_printRow('Transfer', _formatCurrency(transfer), _lineWidth));
    receipt.addAll(_printRow('QRIS', _formatCurrency(qris), _lineWidth));
    if (refund > 0) {
      receipt.addAll(_printRow('Refund', '-${_formatCurrency(refund)}', _lineWidth));
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
    receipt.addAll(_printDottedLine());

    // === FOOTER ===
    receipt.addAll(_centerAlign);
    receipt.addAll(_bold);
    receipt.addAll(_stringToBytes('Terima Kasih'));
    receipt.addAll(_lineFeed);
    receipt.addAll(_unbold);
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
    required List<Map<String, dynamic>> productsSold,
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
        productsSold: productsSold,
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

  /// Membuat baris dengan label di kiri dan value di kanan
  /// [lineWidth] menentukan lebar total baris (default: 32)
  List<int> _printRow(String label, String value, int lineWidth) {
    final row = _stringToBytes(_padRow('$label:', value, lineWidth));
    row.addAll(_lineFeed);
    return row;
  }

  /// Pad row: label di kiri, value di kanan dengan lebar tertentu
  /// Jika total panjang melebihi lineWidth, value dipotong dari kiri dengan "..."
  String _padRow(String left, String right, int lineWidth) {
    final available = lineWidth - left.length;
    if (available <= 0) {
      return left.substring(0, lineWidth);
    }
    String trimmedRight = right;
    if (right.length > available) {
      trimmedRight = '...${right.substring(right.length - available + 3)}';
    }
    final spaces = ' ' * (available - trimmedRight.length);
    return '$left$spaces$trimmedRight';
  }

  /// Print dotted line dengan panjang tertentu (default: 32)
  List<int> _printDottedLine({int length = _lineWidth}) {
    final line = _stringToBytes('-' * length);
    line.addAll(_lineFeed);
    return line;
  }

  /// Print double line dengan panjang tertentu (default: 32)
  List<int> _printDoubleLine({int length = _lineWidth}) {
    final line = _stringToBytes('=' * length);
    line.addAll(_lineFeed);
    return line;
  }

  /// Print custom line dengan karakter tertentu
  List<int> _printCustomLine({required String char, required int length, bool addNewLine = true}) {
    final line = _stringToBytes(char * length);
    if (addNewLine) {
      line.addAll(_lineFeed);
    }
    return line;
  }

  /// Truncate text ke maxChars dengan menambahkan "..." di akhir
  String _truncate(String text, int maxChars) {
    if (text.isEmpty) return '';
    if (text.length <= maxChars) return text;
    if (maxChars <= 3) return text.substring(0, maxChars);
    return '${text.substring(0, maxChars - 3)}...';
  }

  /// Wrap text menjadi beberapa baris dengan lebar tertentu
  List<String> _wrapText(String text, int maxChars) {
    if (text.isEmpty) return [];

    final lines = <String>[];
    String remaining = text.trim();

    while (remaining.isNotEmpty) {
      if (remaining.length <= maxChars) {
        lines.add(remaining);
        break;
      }

      // Cari spasi terakhir sebelum maxChars
      int breakPoint = remaining.lastIndexOf(' ', maxChars);
      if (breakPoint == -1) {
        breakPoint = maxChars;
      }

      lines.add(remaining.substring(0, breakPoint));
      remaining = remaining.substring(breakPoint).trim();
    }

    return lines;
  }

  /// Format string dengan padding center
  String _centerText(String text, int lineWidth) {
    if (text.length >= lineWidth) return text;
    final padding = (lineWidth - text.length) ~/ 2;
    return ' ' * padding + text + ' ' * (lineWidth - text.length - padding);
  }

  /// Format string dengan padding right
  String _rightText(String text, int lineWidth) {
    if (text.length >= lineWidth) return text;
    return ' ' * (lineWidth - text.length) + text;
  }

  /// Format string dengan padding left
  String _leftText(String text, int lineWidth) {
    if (text.length >= lineWidth) return text;
    return text + ' ' * (lineWidth - text.length);
  }

  /// Format date time ke dd/MM/yyyy HH:mm
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/'
        '${dateTime.month.toString().padLeft(2, '0')}/'
        '${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Format currency dengan pemisah titik ribuan
  String _formatCurrency(int amount) {
    if (amount < 0) {
      return '-${_formatCurrency(amount.abs())}';
    }

    final formatter = amount.toString();
    if (formatter.length <= 3) return 'Rp$formatter';

    final reversed = formatter.split('').reversed.toList();
    final chunks = <String>[];
    for (int i = 0; i < reversed.length; i += 3) {
      chunks.add(reversed.sublist(i, i + 3 < reversed.length ? i + 3 : reversed.length).reversed.join());
    }
    return 'Rp${chunks.reversed.join('.')}';
  }

  /// Format currency dengan padding (untuk right alignment)
  String _formatCurrencyPadded(int amount, int lineWidth) {
    final formatted = _formatCurrency(amount);
    return _rightText(formatted, lineWidth);
  }

  /// Create a divider line with custom character
  String _createDivider({String char = '-', int length = _lineWidth}) {
    return char * length;
  }

  /// Create a section header with padding
  String _createSectionHeader(String title, {String leftChar = ' ', String rightChar = ' '}) {
    final padding = (_lineWidth - title.length - 2) ~/ 2;
    final leftPadding = leftChar * padding;
    final rightPadding = rightChar * (padding);
    return '$leftPadding $title $rightPadding';
  }
}