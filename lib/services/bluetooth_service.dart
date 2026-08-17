import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import 'bluetooth_service.dart' as fbp hide BluetoothService;

class BluetoothPrinterDevice {
  final String name;
  final String address;
  final bool isConnected;

  BluetoothPrinterDevice({
    required this.name,
    required this.address,
    this.isConnected = false,
  });
}

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();

  factory BluetoothService() {
    return _instance;
  }

  BluetoothService._internal();

  fbp.BluetoothDevice? _connectedDeviceInternal;
  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _adapterStateSubscription;
  Timer? _reconnectTimer;
  
  bool _isEnabled = false;
  bool _isConnected = false;
  fbp.BluetoothPrinterDevice? _connectedDevice;
  final List<fbp.BluetoothPrinterDevice> _pairedDevices = [];
  final _statusController = StreamController<bool>.broadcast();
  final _devicesController = StreamController<List<fbp.BluetoothPrinterDevice>>.broadcast();

  // Auto-connect MAC addresses for DHBH printers
  static const List<String> _autoConnectAddresses = [
    '66:12:3F:23:EF:92',
    '66:22:0E:80:81:CC',
  ];

  Stream<bool> get statusStream => _statusController.stream;
  Stream<List<fbp.BluetoothPrinterDevice>> get devicesStream => _devicesController.stream;
  
  bool get isConnected => _isConnected;
  bool get isEnabled => _isEnabled;
  fbp.BluetoothPrinterDevice? get connectedDevice => _connectedDevice;
  List<fbp.BluetoothPrinterDevice> get pairedDevices => List.unmodifiable(_pairedDevices);

  /// Whether Bluetooth thermal printing is supported on this platform.
  /// `flutter_blue_plus` supports Android only.
  /// NOT Windows desktop. On unsupported platforms the service becomes a
  /// safe no-op so the rest of the app keeps working normally.
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  /// Initialize Bluetooth service with auto-connect to known printers
  Future<void> initialize() async {
    if (!isSupported) {
      debugPrint('[Bluetooth] ⚠️ Bluetooth printing is not supported on this platform');
      _isEnabled = false;
      _isConnected = false;
      _statusController.add(false);
      return;
    }

    try {
      // Listen to adapter state changes
      fbp.FlutterBluePlus.adapterState.listen((fbp.BluetoothAdapterState state) {
        _isEnabled = state == fbp.BluetoothAdapterState.on;
        debugPrint('[Bluetooth] Adapter state: ${_isEnabled ? 'ON' : 'OFF'}');
        
        // Auto-reconnect when Bluetooth is turned back on
        if (_isEnabled && !_isConnected) {
          debugPrint('[Bluetooth] Bluetooth enabled, attempting auto-connect...');
          _tryAutoConnect();
        }
        
        _statusController.add(_isConnected);
      });
      
      // Get initial adapter state
      _isEnabled = await fbp.FlutterBluePlus.adapterState.first == fbp.BluetoothAdapterState.on;
      debugPrint('[Bluetooth] Initialized: enabled=$_isEnabled');
      
      // Emit initial state
      _statusController.add(false);
      
      // Get paired devices and attempt auto-connect
      await getPairedDevices();
      await _tryAutoConnect();
    } catch (e) {
      debugPrint('[Bluetooth] Init error: $e');
      _statusController.add(false);
    }
  }

  /// Try to auto-connect to known printer MAC addresses
  Future<void> _tryAutoConnect() async {
    if (_isConnected) {
      debugPrint('[Bluetooth] Already connected, skipping auto-connect');
      return;
    }

    debugPrint('[Bluetooth] Attempting auto-connect to known printers...');
    
    for (final address in _autoConnectAddresses) {
      debugPrint('[Bluetooth] Checking device: $address');
      
      // Check if this device is in paired devices
      final pairedDevice = _pairedDevices.firstWhere(
        (d) => d.address.toUpperCase() == address.toUpperCase(),
        orElse: () => fbp.BluetoothPrinterDevice(name: '', address: ''),
      );
      
      if (pairedDevice.address.isNotEmpty) {
        debugPrint('[Bluetooth] Found paired device: ${pairedDevice.name} ($address)');
        final success = await connect(address);
        if (success) {
          debugPrint('[Bluetooth] ✓ Auto-connected to ${pairedDevice.name}');
          return;
        }
      } else {
        debugPrint('[Bluetooth] Device $address not found in paired devices');
      }
    }
    
    debugPrint('[Bluetooth] Auto-connect failed - no known printers available');
  }

  /// Get paired devices
  Future<void> getPairedDevices() async {
    if (!isSupported) {
      debugPrint('[Bluetooth] Bluetooth printing is not supported on this platform');
      return;
    }

    try {
      if (!_isEnabled) {
        debugPrint('[Bluetooth] Bluetooth not enabled');
        return;
      }

      // Get bonded/paired devices from system
      final devices = await fbp.FlutterBluePlus.bondedDevices;
      _pairedDevices.clear();
      for (var device in devices) {
        _pairedDevices.add(fbp.BluetoothPrinterDevice(
          name: device.platformName ?? 'Unknown Device',
          address: device.remoteId.str,
        ));
      }
      
      _devicesController.add(_pairedDevices);
      debugPrint('[Bluetooth] Found ${_pairedDevices.length} paired devices');
    } catch (e) {
      debugPrint('[Bluetooth] Error getting paired devices: $e');
    }
  }

  /// Connect to device by MAC address
  Future<bool> connect(String deviceAddress) async {
    if (!isSupported) {
      debugPrint('[Bluetooth] Bluetooth printing is not supported on this platform');
      return false;
    }

    try {
      if (_isConnected) {
        await disconnect();
      }

      debugPrint('[Bluetooth] Connecting to $deviceAddress...');
      
      // Find the device from bonded devices
      final devices = await fbp.FlutterBluePlus.bondedDevices;
      final device = devices.firstWhere(
        (d) => d.remoteId.str.toUpperCase() == deviceAddress.toUpperCase(),
        orElse: () => throw Exception('Device not found: $deviceAddress'),
      );
      
      // Connect to the device
      await device.connect();
      _connectedDeviceInternal = device;
      
      // Listen for connection state changes
      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == fbp.BluetoothConnectionState.disconnected) {
          debugPrint('[Bluetooth] Device disconnected');
          _isConnected = false;
          _connectedDevice = null;
          _statusController.add(false);
        }
      });
      
      _isConnected = true;
      _connectedDevice = _pairedDevices.firstWhere(
        (d) => d.address.toUpperCase() == deviceAddress.toUpperCase(),
        orElse: () => fbp.BluetoothPrinterDevice(
          name: device.platformName ?? 'Unknown Device',
          address: deviceAddress,
        ),
      );

      debugPrint('[Bluetooth] ✓ Connected to ${_connectedDevice?.name}');
      _statusController.add(true);

      return true;
    } catch (e) {
      debugPrint('[Bluetooth] Connection error: $e');
      _isConnected = false;
      _statusController.add(false);
      return false;
    }
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    try {
      if (_connectedDeviceInternal != null) {
        await _connectedDeviceInternal!.disconnect();
        _connectedDeviceInternal = null;
      }
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;
      _isConnected = false;
      _connectedDevice = null;
      debugPrint('[Bluetooth] Disconnected');
      _statusController.add(false);
    } catch (e) {
      debugPrint('[Bluetooth] Disconnect error: $e');
    }
  }

  /// Send data to connected device via SPP/RFCOMM
  Future<bool> sendData(List<int> data) async {
    try {
      if (!isSupported || !_isConnected || _connectedDeviceInternal == null) {
        debugPrint('[Bluetooth] Not connected');
        return false;
      }

      // Write to the SPP service characteristic
      // Standard SPP service UUID: 00001101-0000-1000-8000-00805F9B34FB
      final sppServiceUuid = fbp.Guid('00001101-0000-1000-8000-00805F9B34FB');
      
      // Discover services first if needed
      List<fbp.BluetoothService> services;
      try {
        services = await _connectedDeviceInternal!.discoverServices();
      } catch (e) {
        debugPrint('[Bluetooth] Service discovery error: $e');
        return false;
      }
      
      // Find SPP service and write characteristic
      for (var service in services) {
        if (service.remoteId == sppServiceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
              await characteristic.write(Uint8List.fromList(data));
              debugPrint('[Bluetooth] Data sent: ${data.length} bytes');
              return true;
            }
          }
        }
      }
      
      debugPrint('[Bluetooth] SPP service not found');
      return false;
    } catch (e) {
      debugPrint('[Bluetooth] Send error: $e');
      return false;
    }
  }

  /// Enable Bluetooth adapter
  Future<void> enableBluetooth() async {
    if (!isSupported) {
      debugPrint('[Bluetooth] Bluetooth printing is not supported on this platform');
      return;
    }

    try {
      await fbp.FlutterBluePlus.turnOn();
      debugPrint('[Bluetooth] ✓ Bluetooth enabled');
    } catch (e) {
      debugPrint('[Bluetooth] Enable error: $e');
    }
  }

  /// Cleanup
  void dispose() {
    _reconnectTimer?.cancel();
    _adapterStateSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _statusController.close();
    _devicesController.close();
    disconnect();
  }
}
