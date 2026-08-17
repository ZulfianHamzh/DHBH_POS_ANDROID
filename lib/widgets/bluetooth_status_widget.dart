import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/windows_bluetooth_printer_provider.dart';
import '../providers/windows_printer_provider.dart';
import '../services/bluetooth_service.dart';
import '../services/windows_bluetooth_printer_service.dart';
import '../utils/responsive_utils.dart';
import '../utils/app_theme.dart';
import 'bluetooth_connection_dialog.dart';

class BluetoothStatusWidget extends ConsumerWidget {
  final VoidCallback? onTap;

  const BluetoothStatusWidget({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Windows desktop now supports Bluetooth thermal printers via
    // flutter_thermal_printer_windows — show that connection status first.
    if (WindowsBluetoothPrinterService.isSupported) {
      return _buildWindowsBluetoothStatus(context, ref);
    }

    // Other platforms without Bluetooth use the default system printer.
    if (!BluetoothService.isSupported) {
      return _buildWindowsPrinterStatus(context, ref);
    }

    final statusAsync = ref.watch(bluetoothStatusProvider);
    return statusAsync.when(
      data: (isConnected) => _buildStatusChip(
        context,
        isConnected,
        isConnected ? 'Printer' : 'No Printer',
        isConnected
            ? 'Printer connected. Tap to disconnect/reconnect'
            : 'Tap to connect printer',
      ),
      loading: () => Padding(
        padding: EdgeInsets.symmetric(horizontal: ResponsiveUtils.spaceSmall),
        child: SizedBox(
          width: ResponsiveUtils.iconSmall,
          height: ResponsiveUtils.iconSmall,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryGreen,
          ),
        ),
      ),
      error: (error, stack) => Tooltip(
        message: 'Bluetooth error',
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveUtils.spaceSmall,
            vertical: ResponsiveUtils.spaceXSmall,
          ),
          child: Icon(
            Icons.bluetooth_disabled,
            color: Colors.orange,
            size: ResponsiveUtils.iconSmall,
          ),
        ),
      ),
    );
  }

  /// Status indicator for the Bluetooth thermal printer on Windows desktop.
  Widget _buildWindowsBluetoothStatus(BuildContext context, WidgetRef ref) {
    final btAsync = ref.watch(windowsBluetoothStatusProvider);
    return btAsync.when(
      data: (connected) => _buildStatusChip(
        context,
        connected,
        connected ? 'Printer' : 'No Printer',
        connected
            ? 'Bluetooth printer connected. Tap for options'
            : 'Tap to connect Bluetooth printer',
      ),
      loading: () => Padding(
        padding: EdgeInsets.symmetric(horizontal: ResponsiveUtils.spaceSmall),
        child: SizedBox(
          width: ResponsiveUtils.iconSmall,
          height: ResponsiveUtils.iconSmall,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryGreen,
          ),
        ),
      ),
      error: (error, stack) => _buildStatusChip(
        context,
        false,
        'No Printer',
        'Bluetooth printer unavailable',
      ),
    );
  }

  /// Status indicator for the default Windows printer (used on desktop).
  Widget _buildWindowsPrinterStatus(BuildContext context, WidgetRef ref) {
    final printerAsync = ref.watch(windowsPrinterReadyProvider);
    return printerAsync.when(
      data: (ready) => _buildStatusChip(
        context,
        ready,
        ready ? 'Printer' : 'No Printer',
        ready
            ? 'Windows printer ready. Tap for options'
            : 'No default Windows printer detected',
      ),
      loading: () => Padding(
        padding: EdgeInsets.symmetric(horizontal: ResponsiveUtils.spaceSmall),
        child: SizedBox(
          width: ResponsiveUtils.iconSmall,
          height: ResponsiveUtils.iconSmall,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryGreen,
          ),
        ),
      ),
      error: (error, stack) => _buildStatusChip(
        context,
        false,
        'No Printer',
        'Printer unavailable',
      ),
    );
  }

  /// Shared printer status chip (green when available, red otherwise).
  Widget _buildStatusChip(
    BuildContext context,
    bool active,
    String label,
    String tooltip,
  ) {
    return GestureDetector(
      onTap: () {
        onTap?.call();
        showDialog(
          context: context,
          builder: (context) => const BluetoothConnectionDialog(),
        );
      },
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveUtils.spaceSmall,
            vertical: ResponsiveUtils.spaceXSmall,
          ),
          decoration: BoxDecoration(
            color: active ? Colors.green.shade50 : Colors.red.shade50,
            border: Border.all(
              color: active ? AppColors.primaryGreen : Colors.red,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(ResponsiveUtils.radiusSmall),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.print,
                color: active ? AppColors.primaryGreen : Colors.red,
                size: ResponsiveUtils.iconSmall,
              ),
              SizedBox(width: ResponsiveUtils.spaceXSmall),
              Text(
                label,
                style: TextStyle(
                  fontSize: ResponsiveUtils.fontSmall,
                  color: active ? AppColors.primaryGreen : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
