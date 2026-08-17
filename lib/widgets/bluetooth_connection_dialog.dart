import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_thermal_printer_windows/flutter_thermal_printer_windows.dart'
as tp;
import '../services/bluetooth_service.dart';
import '../services/windows_bluetooth_printer_service.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/windows_bluetooth_printer_provider.dart';
import '../utils/responsive_utils.dart';
import '../utils/app_theme.dart';

class BluetoothConnectionDialog extends ConsumerStatefulWidget {
  const BluetoothConnectionDialog({super.key});

  @override
  ConsumerState<BluetoothConnectionDialog> createState() =>
      _BluetoothConnectionDialogState();
}

class _BluetoothConnectionDialogState
    extends ConsumerState<BluetoothConnectionDialog> {
  BluetoothPrinterDevice? _selectedDevice;
  bool _isConnecting = false;
  bool _scanning = false;
  List<tp.BluetoothPrinter> _scanResults = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bluetooth = ref.read(bluetoothServiceProvider);
      bluetooth.getPairedDevices();
    });
  }

  /// Windows desktop: manage the Bluetooth thermal printer
  /// (scan, pair, connect, test print).
  Widget _buildWindowsBluetoothSection(BuildContext context) {
    final service = ref.watch(windowsBluetoothPrinterServiceProvider);
    final connected = service.connectedPrinter;
    final pairedAsync = ref.watch(windowsBluetoothPairedDevicesProvider);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection status
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected != null ? Colors.green : Colors.red,
                ),
              ),
              SizedBox(width: ResponsiveUtils.spaceSmall),
              Expanded(
                child: Text(
                  connected != null
                      ? 'Bluetooth: ${connected.name}'
                      : 'Bluetooth: not connected',
                  style: TextStyle(
                    fontSize: ResponsiveUtils.fontNormal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveUtils.spaceSmall),
          const Divider(),
          SizedBox(height: ResponsiveUtils.spaceSmall),
          Text(
            'Bluetooth Thermal Printer',
            style: TextStyle(
              fontSize: ResponsiveUtils.fontNormal,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Scan, pair, lalu hubungkan printer thermal via Bluetooth.',
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSmall,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: ResponsiveUtils.spaceSmall),
          ElevatedButton.icon(
            onPressed: connected != null
                ? () => _printWindowsTest(service)
                : null,
            icon: const Icon(Icons.print, size: 16),
            label: const Text('Print test receipt'),
          ),
          SizedBox(height: ResponsiveUtils.spaceSmall),
          OutlinedButton.icon(
            onPressed: () => _scanWindowsPrinters(service),
            icon: const Icon(Icons.bluetooth_searching, size: 16),
            label: Text(_scanning ? 'Scanning...' : 'Scan for printers'),
          ),
          if (_scanResults.isNotEmpty) ...[
            SizedBox(height: ResponsiveUtils.spaceSmall),
            const Text(
              'Scan Results:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ..._scanResults.map((d) => _buildWindowsDeviceTile(service, d)),
          ],
          SizedBox(height: ResponsiveUtils.spaceSmall),
          Text(
            'Paired Devices:',
            style: TextStyle(
              fontSize: ResponsiveUtils.fontNormal,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveUtils.spaceXSmall),
          pairedAsync.when(
            data: (devices) => devices.isEmpty
                ? Padding(
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveUtils.spaceSmall,
              ),
              child: Text(
                'No paired Bluetooth printers found',
                style: TextStyle(
                  fontSize: ResponsiveUtils.fontSmall,
                  color: Colors.grey,
                ),
              ),
            )
                : Column(
              mainAxisSize: MainAxisSize.min,
              children: devices
                  .map((d) => _buildWindowsDeviceTile(service, d))
                  .toList(),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, s) => Padding(
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveUtils.spaceSmall,
              ),
              child: Text(
                'Error: $e',
                style: TextStyle(
                  fontSize: ResponsiveUtils.fontSmall,
                  color: Colors.red,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowsDeviceTile(
      WindowsBluetoothPrinterService service,
      tp.BluetoothPrinter device,
      ) {
    final isConnected = service.connectedPrinter?.id == device.id;
    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveUtils.spaceXSmall),
      elevation: 1,
      child: ListTile(
        dense: true,
        leading: const Icon(
          Icons.print,
          color: AppColors.primaryGreen,
          size: 20,
        ),
        title: Text(
          device.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${_cleanDeviceMac(device)}${device.isPaired ? ' • paired' : ''}',
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
        trailing: isConnected
            ? TextButton(
          onPressed: () async {
            await service.disconnect();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Printer terputus')),
              );
            }
          },
          child: const Text('Disconnect'),
        )
            : TextButton(
          onPressed: () => _connectWindowsDevice(service, device),
          child: const Text('Connect'),
        ),
      ),
    );
  }

  /// Extracts a clean MAC address from a Windows Bluetooth id such as
  /// "Bluetooth#Bluetooth04:7f:0e:7f:06:97-66:12:3f:23:ef:92#RFCOMM...".
  String _cleanDeviceMac(tp.BluetoothPrinter device) {
    final raw = device.macAddress.isNotEmpty ? device.macAddress : device.id;
    final rfcomm = raw.indexOf('#RFCOMM');
    final end = rfcomm < 0 ? raw.length : rfcomm;
    final dash = raw.lastIndexOf('-', end);
    if (dash >= 0) {
      final mac = raw.substring(dash + 1, end);
      if (mac.length >= 12) return mac;
    }
    return raw;
  }

  Future<void> _connectWindowsDevice(
      WindowsBluetoothPrinterService service,
      tp.BluetoothPrinter device,
      ) async {
    setState(() => _isConnecting = true);
    var ok = await service.connect(device);
    if (!ok && !device.isPaired) {
      ok = await service.pair(device);
      if (ok) ok = await service.connect(device);
    }
    if (mounted) {
      setState(() => _isConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Terhubung ke ${device.name}' : 'Gagal terhubung ke ${device.name}',
          ),
          backgroundColor: ok ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _scanWindowsPrinters(
      WindowsBluetoothPrinterService service,
      ) async {
    setState(() => _scanning = true);
    final results = await service.scanForPrinters(
      timeout: const Duration(seconds: 15),
    );
    if (mounted) {
      setState(() {
        _scanResults = results;
        _scanning = false;
      });
    }
  }

  Future<void> _printWindowsTest(
      WindowsBluetoothPrinterService service,
      ) async {
    final ok = await service.printTestReceipt();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Struk uji berhasil dicetak' : 'Cetak gagal - periksa printer',
          ),
          backgroundColor: ok ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveUtils.init(context);
    final devicesAsync = ref.watch(bluetoothDevicesProvider);
    final bluetooth = ref.watch(bluetoothServiceProvider);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ResponsiveUtils.radiusMedium),
      ),
      child: Padding(
        padding: ResponsiveUtils.paddingNormal,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Center(
              child: Text(
                'Connect Thermal Printer',
                style: TextStyle(
                  fontSize: ResponsiveUtils.fontLarge,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(height: ResponsiveUtils.spaceNormal),

            // Status indicator
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bluetooth.isEnabled ? Colors.green : Colors.red,
                  ),
                ),
                SizedBox(width: ResponsiveUtils.spaceSmall),
                Text(
                  bluetooth.isEnabled ? 'Bluetooth: ON' : 'Bluetooth: OFF',
                  style: TextStyle(fontSize: ResponsiveUtils.fontNormal),
                ),
              ],
            ),
            SizedBox(height: ResponsiveUtils.spaceSmall),
            const Divider(),
            SizedBox(height: ResponsiveUtils.spaceSmall),

            // Devices list header
            Text(
              'Available Devices:',
              style: TextStyle(
                fontSize: ResponsiveUtils.fontNormal,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveUtils.spaceSmall),

            // Flexible device list
            Flexible(
              child: devicesAsync.when(
                data: (devices) {
                  // Windows desktop: Bluetooth thermal printer management.
                  if (WindowsBluetoothPrinterService.isSupported) {
                    return _buildWindowsBluetoothSection(context);
                  }

                  if (devices.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: ResponsiveUtils.spaceNormal,
                      ),
                      child: Center(
                        child: Text(
                          'No paired Bluetooth devices found',
                          style: TextStyle(
                            fontSize: ResponsiveUtils.fontSmall,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    padding: EdgeInsets.zero,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      final isThisConnected = bluetooth.isConnected &&
                          bluetooth.connectedDevice?.address.toUpperCase() ==
                              device.address.toUpperCase();

                      return Card(
                        margin: EdgeInsets.only(
                          bottom: ResponsiveUtils.spaceXSmall,
                        ),
                        elevation: 1,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedDevice = device;
                            });
                          },
                          borderRadius: BorderRadius.circular(
                            ResponsiveUtils.radiusSmall,
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveUtils.spaceNormal,
                              vertical: ResponsiveUtils.spaceSmall,
                            ),
                            child: Row(
                              children: [
                                if (isThisConnected)
                                  const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(Icons.check_circle,
                                        color: Colors.green, size: 20),
                                  )
                                else
                                  Radio<BluetoothPrinterDevice>(
                                    value: device,
                                    groupValue: _selectedDevice,
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedDevice = value;
                                      });
                                    },
                                  ),
                                SizedBox(width: ResponsiveUtils.spaceSmall),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device.name,
                                        style: TextStyle(
                                          fontSize: ResponsiveUtils.fontNormal,
                                          fontWeight: isThisConnected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isThisConnected
                                              ? Colors.green.shade700
                                              : Colors.black87,
                                        ),
                                      ),
                                      SizedBox(
                                        height: ResponsiveUtils.spaceXSmall,
                                      ),
                                      Text(
                                        isThisConnected
                                            ? '${device.address} • Connected'
                                            : device.address,
                                        style: TextStyle(
                                          fontSize: ResponsiveUtils.fontSmall,
                                          color: isThisConnected
                                              ? Colors.green
                                              : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isThisConnected)
                                  TextButton(
                                    onPressed: () async {
                                      await bluetooth.disconnect();
                                      setState(() {});
                                    },
                                    child: const Text('Disconnect',
                                        style: TextStyle(color: Colors.red)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: ResponsiveUtils.spaceNormal,
                  ),
                  child: const Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: ResponsiveUtils.spaceNormal,
                  ),
                  child: Center(
                    child: Text(
                      'Error: $error',
                      style: TextStyle(
                        fontSize: ResponsiveUtils.fontSmall,
                        color: Colors.red,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: ResponsiveUtils.spaceNormal),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(fontSize: ResponsiveUtils.fontNormal),
                  ),
                ),
                if (!WindowsBluetoothPrinterService.isSupported) ...[
                  SizedBox(width: ResponsiveUtils.spaceSmall),
                  if (bluetooth.isConnected)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: _isConnecting
                          ? null
                          : () async {
                        setState(() => _isConnecting = true);
                        await bluetooth.disconnect();
                        setState(() => _isConnecting = false);
                      },
                      child: const Text(
                        'Disconnect Printer',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  else
                    ElevatedButton(
                      onPressed: _isConnecting || _selectedDevice == null
                          ? null
                          : _handleConnect,
                      child: _isConnecting
                          ? SizedBox(
                        height: ResponsiveUtils.iconNormal,
                        width: ResponsiveUtils.iconNormal,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : Text(
                        'Connect',
                        style: TextStyle(
                            fontSize: ResponsiveUtils.fontNormal),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleConnect() async {
    if (_selectedDevice == null) return;

    setState(() => _isConnecting = true);

    final bluetooth = ref.read(bluetoothServiceProvider);
    final success = await bluetooth.connect(_selectedDevice!.address);

    if (mounted) {
      setState(() => _isConnecting = false);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Connected to ${_selectedDevice!.name}',
              style: TextStyle(fontSize: ResponsiveUtils.fontNormal),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to connect to ${_selectedDevice!.name}',
              style: TextStyle(fontSize: ResponsiveUtils.fontNormal),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}