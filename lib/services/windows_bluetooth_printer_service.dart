import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_thermal_printer_windows/flutter_thermal_printer_windows.dart'
    as tp;
import '../utils/wib_time.dart';
import '../models/transaction.dart';

/// Bluetooth thermal printer service for **Windows desktop**, backed by the
/// `flutter_thermal_printer_windows` plugin.
///
/// Provides discovery (`scanForPrinters`), pairing, connection, and ESC/POS
/// printing via structured [tp.Receipt] objects (header/items/footer/settings).
/// On Windows this is the preferred thermal path — the older
/// [BluetoothService]/[ThermalPrinterService] (flutter_bluetooth_serial) does
/// not support Windows.
///
/// Singleton; safe no-op when called on a non-Windows platform.
class WindowsBluetoothPrinterService {
  static final WindowsBluetoothPrinterService _instance =
      WindowsBluetoothPrinterService._internal();

  factory WindowsBluetoothPrinterService() => _instance;

  WindowsBluetoothPrinterService._internal();

  static const String _tag = '[WinBT]';

  /// MAC address of the thermal printer to auto-connect on session start.
  static const String autoConnectMac = '66:12:3f:23:ef:92';

  final tp.ThermalPrinterWindows _api = tp.ThermalPrinterWindows.instance;
  final StreamController<bool> _statusController =
      StreamController<bool>.broadcast();

  tp.BluetoothPrinter? _connectedPrinter;

  /// Stream of connection status (true when a printer is connected).
  Stream<bool> get statusStream => _statusController.stream;

  /// The currently connected Bluetooth printer, if any.
  tp.BluetoothPrinter? get connectedPrinter => _connectedPrinter;

  /// Whether a printer is currently connected.
  bool get isConnected => _connectedPrinter != null;

  /// Whether Bluetooth thermal printing is available on this platform.
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  void _emitStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(isConnected);
    }
  }

  /// Returns already-paired Bluetooth thermal printers.
  Future<List<tp.BluetoothPrinter>> getPairedPrinters() async {
    if (!isSupported) return const [];
    try {
      final list = await _api.getPairedPrinters();
      debugPrint('$_tag getPairedPrinters: ${list.length} device(s)');
      for (final d in list) {
        debugPrint('$_tag   paired: name=${d.name} id=${d.id} mac=${d.macAddress} isPaired=${d.isPaired}');
      }
      return list;
    } catch (e) {
      debugPrint('$_tag getPairedPrinters error: $e');
      return const [];
    }
  }

  /// Scans for nearby Bluetooth thermal printers.
  Future<List<tp.BluetoothPrinter>> scanForPrinters({Duration? timeout}) async {
    if (!isSupported) return const [];
    try {
      final list = await _api.scanForPrinters(
        timeout: timeout ?? tp.ThermalPrinterWindows.defaultScanTimeout,
      );
      debugPrint('$_tag scanForPrinters: ${list.length} device(s)');
      for (final d in list) {
        debugPrint('$_tag   scan: name=${d.name} id=${d.id} mac=${d.macAddress} isPaired=${d.isPaired}');
      }
      return list;
    } catch (e) {
      debugPrint('$_tag scan error: $e');
      return const [];
    }
  }

  /// Pairs with [printer]. Returns true on success.
  Future<bool> pair(tp.BluetoothPrinter printer) async {
    if (!isSupported) return false;
    try {
      await _api.pairPrinter(printer);
      debugPrint('$_tag paired: ${printer.name}');
      return true;
    } catch (e) {
      debugPrint('$_tag pair error: $e');
      return false;
    }
  }

  /// Connects to [printer] and stores it as the active printer.
  Future<bool> connect(tp.BluetoothPrinter printer) async {
    if (!isSupported) return false;
    try {
      await _api.connect(printer);
      _connectedPrinter = printer;
      _emitStatus();
      debugPrint('$_tag connected: ${printer.name}');
      return true;
    } catch (e) {
      debugPrint('$_tag connect error: $e');
      _connectedPrinter = null;
      _emitStatus();
      return false;
    }
  }

  /// Disconnects the active printer (if any).
  Future<void> disconnect() async {
    if (!isSupported) return;
    final printer = _connectedPrinter;
    _connectedPrinter = null;
    _emitStatus();
    if (printer != null) {
      try {
        await _api.disconnect(printer);
        debugPrint('$_tag disconnected: ${printer.name}');
      } catch (e) {
        debugPrint('$_tag disconnect error: $e');
      }
    }
  }

  // ── BLUETOOTH RADIO ───────────────────────────────────────────

  /// Ensures the Windows Bluetooth radio is on; enables it if it is off.
  /// Returns true when Bluetooth is enabled (or was already enabled).
  Future<bool> ensureBluetoothEnabled() async {
    if (!isSupported) return false;
    try {
      final enabled = await _api.isBluetoothEnabled();
      if (enabled) return true;
      debugPrint('$_tag Bluetooth is OFF — enabling adapter...');
      final ok = await _api.enableBluetooth();
      debugPrint('$_tag enableBluetooth: $ok');
      return ok;
    } catch (e) {
      debugPrint('$_tag ensureBluetoothEnabled error: $e');
      return false;
    }
  }

  /// Whether the Windows Bluetooth radio is currently on.
  Future<bool> isBluetoothEnabled() async {
    if (!isSupported) return false;
    try {
      return await _api.isBluetoothEnabled();
    } catch (e) {
      debugPrint('$_tag isBluetoothEnabled error: $e');
      return false;
    }
  }

  /// Auto-connects to the thermal printer with [macAddress] (defaults to
  /// [autoConnectMac]). Ensures Bluetooth is on first, then searches paired
  /// printers (falling back to a scan), pairs if needed, and connects.
  /// Best-effort: never throws.
  Future<void> autoConnect({String? macAddress}) async {
    if (!isSupported || _connectedPrinter != null) return;
    final mac = (macAddress ?? autoConnectMac).trim().toLowerCase();
    if (mac.isEmpty) {
      debugPrint('$_tag autoConnect: empty MAC, skipping');
      return;
    }
    try {
      await ensureBluetoothEnabled();

      // The plugin exposes the device-id string as `macAddress`, e.g.
      // "Bluetooth#Bluetooth04:7f:0e:7f:06:97-66:12:3f:23:ef:92#RFCOMM:..."
      // (adapter MAC, then printer MAC). Match the target MAC as a substring —
      // it appears verbatim — rather than extracting the first regex match
      // (which would pick up the adapter's MAC).
      bool matchesMac(tp.BluetoothPrinter p) {
        final raw = p.macAddress.toLowerCase();
        if (raw == mac) return true;
        final clean = RegExp(r'[0-9a-f]{2}(?::[0-9a-f]{2}){5}')
            .allMatches(raw)
            .map((m) => m.group(0)!)
            .toList();
        return clean.contains(mac) || raw.contains(mac);
      }

      // 1) Look in already-paired printers.
      tp.BluetoothPrinter? target;
      for (final p in await getPairedPrinters()) {
        if (matchesMac(p)) {
          target = p;
          break;
        }
      }

      // 2) Fall back to a short scan.
      if (target == null) {
        for (final p in await scanForPrinters(
          timeout: const Duration(seconds: 8),
        )) {
          if (matchesMac(p)) {
            target = p;
            break;
          }
        }
      }

      if (target == null) {
        debugPrint('$_tag autoConnect: printer $mac not found');
        return;
      }

      if (!target.isPaired) {
        await pair(target);
      }
      final ok = await connect(target);
      debugPrint(
        '$_tag autoConnect → ${target.name} (${target.macAddress}): $ok',
      );
    } catch (e) {
      debugPrint('$_tag autoConnect error: $e');
    }
  }

  // ── PRINTING ───────────────────────────────────────────────────

  /// Runs [action]; if it fails because the Bluetooth SPP connection was
  /// aborted (common on thermal printers — the link drops after a job),
  /// reconnects to the remembered printer and retries once. This makes
  /// printing resilient so the user does not have to reconnect manually.
  Future<bool> _printWithReconnect(Future<bool> Function() action) async {
    if (_connectedPrinter == null) {
      debugPrint('$_tag _printWithReconnect: not connected');
      return false;
    }
    var ok = await action();
    if (!ok) {
      final printer = _connectedPrinter;
      debugPrint('$_tag print failed — reconnecting & retrying...');
      if (printer != null) {
        await disconnect();
        // Small pause so the OS fully releases the aborted socket before we
        // open a fresh SPP connection.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final reconnected = await connect(printer);
        if (reconnected) {
          debugPrint('$_tag reconnected, retrying print...');
          ok = await action();
        }
      }
    }
    return ok;
  }

  /// Prints a transaction receipt to the connected printer.
  Future<bool> printTransaction(Transaction t) async {
    if (!isSupported || _connectedPrinter == null) {
      debugPrint('$_tag printTransaction: not connected');
      return false;
    }
    return _printWithReconnect(() async {
      try {
        await _api.printReceipt(_connectedPrinter!, _buildReceipt(t));
        debugPrint('$_tag ✓ transaction receipt printed');
        return true;
      } catch (e) {
        debugPrint('$_tag printTransaction error: $e');
        return false;
      }
    });
  }

  /// Prints a closing report / daily summary to the connected printer.
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
    if (!isSupported || _connectedPrinter == null) {
      debugPrint('$_tag printClosingReport: not connected');
      return false;
    }
    return _printWithReconnect(() async {
      try {
        await _api.printReceipt(
          _connectedPrinter!,
          _buildClosingReportReceipt(
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
        debugPrint('$_tag ✓ closing report printed');
        return true;
      } catch (e) {
        debugPrint('$_tag printClosingReport error: $e');
        return false;
      }
    });
  }

  /// Prints the daily summary (ringkasan harian) to the connected printer.
  /// Distinct from the closing report: compact totals without product detail.
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
    if (!isSupported || _connectedPrinter == null) {
      debugPrint('$_tag printDailySummary: not connected');
      return false;
    }
    return _printWithReconnect(() async {
      try {
        await _api.printReceipt(
          _connectedPrinter!,
          _buildDailySummaryReceipt(
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
        debugPrint('$_tag ✓ daily summary printed');
        return true;
      } catch (e) {
        debugPrint('$_tag printDailySummary error: $e');
        return false;
      }
    });
  }

  /// Prints a small sample receipt to verify the link.
  Future<bool> printTestReceipt() async {
    if (!isSupported || _connectedPrinter == null) {
      debugPrint('$_tag printTestReceipt: not connected');
      return false;
    }
    return _printWithReconnect(() async {
      try {
        await _api.printReceipt(
          _connectedPrinter!,
          tp.Receipt(
            header: tp.ReceiptHeader(
              text: 'DHBH POS\nStruk Uji / Test Receipt',
            ),
            items: [
              const tp.ReceiptItem(type: tp.ReceiptItemType.line),
              tp.ReceiptItem(
                type: tp.ReceiptItemType.text,
                text: 'Printer Bluetooth berfungsi!',
                style: const tp.TextStyle(bold: true),
              ),
              tp.ReceiptItem(
                type: tp.ReceiptItemType.text,
                text: 'Terima kasih',
                style: const tp.TextStyle(alignment: tp.TextAlignment.center),
              ),
            ],
            settings: const tp.ReceiptSettings(paperWidth: 58, autoCut: true),
          ),
        );
        debugPrint('$_tag ✓ test receipt printed');
        return true;
      } catch (e) {
        debugPrint('$_tag printTestReceipt error: $e');
        return false;
      }
    });
  }

  // ── RECEIPT BUILDERS ───────────────────────────────────────────

  // Explicit style on EVERY item is required: the plugin does not reset
  // bold/alignment/font between items, so a null style would inherit the
  // previous item's formatting.
  static const tp.TextStyle _s = tp.TextStyle();
  static const tp.TextStyle _sCenter = tp.TextStyle(
    alignment: tp.TextAlignment.center,
  );
  static const tp.TextStyle _sBold = tp.TextStyle(bold: true);
  static const tp.TextStyle _sBoldCenter = tp.TextStyle(
    bold: true,
    alignment: tp.TextAlignment.center,
  );
  static const tp.TextStyle _sLargeBoldCenter = tp.TextStyle(
    bold: true,
    fontSize: tp.FontSize.large,
    alignment: tp.TextAlignment.center,
  );

  tp.Receipt _buildReceipt(Transaction t) {
    final items = <tp.ReceiptItem>[
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'DHBH POS',
        style: _sLargeBoldCenter,
      ),
      if (t.branchName != null && t.branchName!.isNotEmpty)
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text: t.branchName!,
          style: _sCenter,
        ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Kasir: ${t.cashierName}',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Tgl: ${_formatDateTime(WibTime.toWib(t.createdAt))}',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'ID: #${t.orderNo ?? t.id}',
        style: _s,
      ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '-' * 32,
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Item',
        style: _sBold,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Qty',
        style: _sBold,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Harga',
        style: _sBold,
      ),
      for (final item in t.items) ...[
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text: item.product.name.length > 20
              ? item.product.name.substring(0, 20)
              : item.product.name,
          style: _s,
        ),
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text:
              '  ${item.isHomeVisit ? '(Home Visit)' : '(Klinik)'} @${_formatCurrency(item.unitPrice)}',
          style: _s,
        ),
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text: 'x${item.quantity}    ${_formatCurrency(item.totalPrice)}',
          style: _s,
        ),
      ],
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '-' * 32,
        style: _s,
      ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      if (t.discount > 0) ...[
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text: 'Subtotal: ${_formatCurrency(t.subtotal)}',
          style: _s,
        ),
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text: 'Diskon: -${_formatCurrency(t.discount)}',
          style: _s,
        ),
      ],
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Total: ${_formatCurrency(t.totalAmount)}',
        style: _sBoldCenter,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Metode: ${t.paymentMethod.displayName}',
        style: _s,
      ),
      for (var i = 0; i < t.customerNames.length; i++)
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text: i == 0
              ? 'Pelanggan: ${t.customerNames[i]}'
              : '           ${t.customerNames[i]}',
          style: _s,
        ),
      for (var i = 0; i < t.terapisNames.length; i++)
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text: i == 0
              ? 'Terapis: ${t.terapisNames[i]}'
              : '          ${t.terapisNames[i]}',
          style: _s,
        ),
      if (t.notes != null && t.notes!.isNotEmpty)
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text: 'Note: ${t.notes}',
          style: _s,
        ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Terima kasih!',
        style: _sCenter,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Selamat datang kembali',
        style: _sCenter,
      ),
    ];
    return tp.Receipt(
      items: items,
      settings: const tp.ReceiptSettings(paperWidth: 58, autoCut: true),
    );
  }

  tp.Receipt _buildClosingReportReceipt({
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

    final items = <tp.ReceiptItem>[
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'LAPORAN TUTUP KASIR',
        style: _sLargeBoldCenter,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'PENJUALAN & TRANSAKSI DHBH',
        style: _sCenter,
      ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Cabang: $branchName',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Kasir: $cashierName',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Waktu Buka: ${_formatDateTime(waktuBuka)}',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Waktu Tutup: ${_formatDateTime(waktuTutup)}',
        style: _s,
      ),
      for (final t in terapis)
        if (((t['name'] as String?) ?? '').isNotEmpty)
          tp.ReceiptItem(
            type: tp.ReceiptItemType.text,
            text: 'Terapis: ${t['name']}',
            style: _s,
          ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'PRODUK TERJUAL',
        style: _sBold,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '${'Nama'.padRight(18)} Qty  Harga',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '${'-' * 18} ${'-' * 3} ${'-' * 8}',
        style: _s,
      ),
      for (final product in productsSold)
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text:
              '${(product['name'] as String? ?? '').padRight(18)} '
              '${(product['qty'] as int? ?? 0).toString().padLeft(3)} '
              '${_formatCurrency(product['total'] as int? ?? 0).padLeft(8)}',
          style: _s,
        ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '-' * 32,
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Total: ${_formatCurrency(totalPenerimaan)}',
        style: _sBold,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Modal Awal: ${_formatCurrency(modalAwal)}',
        style: _s,
      ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'PENERIMAAN',
        style: _sBold,
      ),
      for (final payment in payments)
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text:
              '${(payment['method'] as String? ?? '').padRight(12)}'
              '${_formatCurrency(payment['amount'] as int? ?? 0).padLeft(12)}',
          style: _s,
        ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '-' * 32,
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Total Penerimaan: ${_formatCurrency(totalPenerimaan)}',
        style: _sBold,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Saldo Akhir: ${_formatCurrency(modalAwal + totalPenerimaan)}',
        style: _sBold,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Transaksi Selesai: $totalTransaksiSelesai',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Transaksi Hold: $totalTransaksiHold',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Total Item Terjual: $totalQty',
        style: _s,
      ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '-' * 32,
        style: _sCenter,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Terima kasih',
        style: _sCenter,
      ),
    ];
    return tp.Receipt(
      items: items,
      settings: const tp.ReceiptSettings(paperWidth: 58, autoCut: true),
    );
  }

  tp.Receipt _buildDailySummaryReceipt({
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
    final items = <tp.ReceiptItem>[
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'RINGKASAN HARIAN',
        style: _sLargeBoldCenter,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'PENJUALAN & TRANSAKSI DHBH',
        style: _sCenter,
      ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Cabang: $branchName',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Kasir: $cashierName',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Tanggal: ${_formatDateTime(tanggal)}',
        style: _s,
      ),
      for (final t in terapis)
        if (((t['name'] as String?) ?? '').isNotEmpty)
          tp.ReceiptItem(
            type: tp.ReceiptItemType.text,
            text: 'Terapis: ${t['name']}',
            style: _s,
          ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Total Transaksi: $totalTransaksi',
        style: _sBold,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Total Revenue: ${_formatCurrency(totalRevenue)}',
        style: _sBold,
      ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'PENERIMAAN',
        style: _sBold,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '${'Cash'.padRight(12)}${_formatCurrency(cash).padLeft(12)}',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '${'Transfer'.padRight(12)}${_formatCurrency(transfer).padLeft(12)}',
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '${'QRIS'.padRight(12)}${_formatCurrency(qris).padLeft(12)}',
        style: _s,
      ),
      if (refund > 0)
        tp.ReceiptItem(
          type: tp.ReceiptItemType.text,
          text: '${'Refund'.padRight(12)}-${_formatCurrency(refund).padLeft(11)}',
          style: _s,
        ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '-' * 32,
        style: _s,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Total Penerimaan: ${_formatCurrency(totalRevenue)}',
        style: _sBold,
      ),
      const tp.ReceiptItem(type: tp.ReceiptItemType.spacer, style: _s),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: '-' * 32,
        style: _sCenter,
      ),
      tp.ReceiptItem(
        type: tp.ReceiptItemType.text,
        text: 'Terima kasih',
        style: _sCenter,
      ),
    ];
    return tp.Receipt(
      items: items,
      settings: const tp.ReceiptSettings(paperWidth: 58, autoCut: true),
    );
  }

  /// Format date time (dd/MM/yyyy HH:mm).
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Format currency (Rp1.000.000).
  String _formatCurrency(int amount) {
    final formatter = amount.toString();
    if (formatter.length <= 3) return 'Rp$formatter';

    final reversed = formatter.split('').reversed.toList();
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
