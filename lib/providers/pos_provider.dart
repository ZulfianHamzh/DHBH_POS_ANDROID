import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';
import '../models/held_order.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../models/user.dart';
import '../services/supabase_service.dart';
import '../services/thermal_printer_service.dart';
import '../services/bluetooth_service.dart';
import '../services/windows_printer_service.dart';
import '../services/windows_bluetooth_printer_service.dart';
import '../repository/auth_repository.dart';
import '../repository/product_repository.dart';
import '../repository/transaction_repository.dart';
import '../repository/held_order_repository.dart';
import '../utils/wib_time.dart';

const _all = '';

class PosProvider extends StateNotifier<PosState> {
  final SupabaseService _supabase;
  final AuthRepository _authRepo;
  final ProductRepository _productRepo;
  final TransactionRepository _transactionRepo;
  final HeldOrderRepository _heldOrderRepo;

  PosProvider(
    this._supabase, {
    required AuthRepository authRepo,
    required ProductRepository productRepo,
    required TransactionRepository transactionRepo,
    required HeldOrderRepository heldOrderRepo,
  })  : _authRepo = authRepo,
        _productRepo = productRepo,
        _transactionRepo = transactionRepo,
        _heldOrderRepo = heldOrderRepo,
        super(PosState());

  // ─── AUTH ───────────────────────────────────────────────────────

  Future<String?> login(String email, String password) async {
    debugPrint('[DHBH Provider] login: email=$email');
    state = state.copyWith(isLoading: true);
    try {
      final user = await _authRepo.login(email, password).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          debugPrint('[DHBH Provider] login TIMEOUT after 12 seconds');
          throw TimeoutException('Login timeout: Server tidak merespons dalam waktu yang ditentukan');
        },
      );
      
      if (user == null) {
        debugPrint('[DHBH Provider] login FAILED: user null');
        state = state.copyWith(isLoading: false);
        return 'Email atau password salah';
      }
      
      debugPrint('[DHBH Provider] login SUCCESS: ${user.name} (${user.role.name})');
      state = state.copyWith(currentUser: user, isLoading: false);
      
      // Log activity
      try {
        await _supabase.logActivity(user.id, 'login', details: {'email': email});
      } catch (_) {}

      // Auto-load products, transactions, and held orders for this session.
      // Called from the provider (not the widget) so it always runs after
      // login, even if the LoginScreen is disposed during the UI swap.
      await loadProducts();

      // Auto-connect the Windows Bluetooth thermal printer (best-effort,
      // non-blocking): enables Bluetooth first, then connects to the printer
      // with the known MAC address.
      if (WindowsBluetoothPrinterService.isSupported) {
        WindowsBluetoothPrinterService().autoConnect();
      }

      return null;
    } on TimeoutException catch (e) {
      debugPrint('[DHBH Provider] login TIMEOUT: ${e.toString()}');
      state = state.copyWith(isLoading: false);
      return e.toString();
    } catch (e) {
      debugPrint('[DHBH Provider] login ERROR: $e');
      state = state.copyWith(isLoading: false);
      return 'Gagal login: ${e.toString()}';
    }
  }

  Future<void> logout() async {
    debugPrint('[DHBH Provider] logout');
    await _supabase.signOut();
    state = PosState();
    debugPrint('[DHBH Provider] logout DONE');
  }

  Future<void> checkSession() async {
    // Auto logout on restart — no session persist
    debugPrint('[DHBH Provider] checkSession: skipped (auto-logout on restart)');
    state = PosState();
  }

  // ─── SEARCH & FILTER ────────────────────────────────────────────

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSelectedCategory(String category) {
    state = state.copyWith(selectedCategory: category);
  }

  void setMenuSelectedCategory(String category) {
    state = state.copyWith(menuSelectedCategory: category);
  }

  List<Product> filteredProducts(bool showInactive, {bool forMenu = false}) {
    var products = showInactive
        ? state.products
        : state.products.where((p) => p.isActive).toList();
    final category = forMenu ? state.menuSelectedCategory : state.selectedCategory;
    if (category.isNotEmpty) {
      products = products.where((p) => p.category == category).toList();
    }
    if (state.searchQuery.isNotEmpty) {
      final query = state.searchQuery.toLowerCase();
      products = products.where((p) => p.name.toLowerCase().contains(query)).toList();
    }
    return products;
  }

  List<String> get categories {
    return state.products
        .map((p) => p.category)
        .toSet()
        .where((c) => c.isNotEmpty)
        .toList()
      ..sort();
  }

  // ─── PRODUCTS ───────────────────────────────────────────────────

  Future<void> loadProducts() async {
    debugPrint('[DHBH Provider] ════════════════ loadProducts ════════════════');
    state = state.copyWith(isLoading: true);
    
    try {
      // Load products directly from Supabase
      final products = await _productRepo.getProducts();
      debugPrint('[DHBH Provider] Products loaded: ${products.length}');
      
      // Load transactions directly from Supabase
      List<Transaction> transactions = [];
      try {
        transactions = await _transactionRepo.getTransactions(
          branchId: state.currentUser?.branchId,
        );
        debugPrint('[DHBH Provider] Transactions loaded: ${transactions.length}');
      } catch (e) {
        debugPrint('[DHBH Provider] Transactions load error: $e');
      }
      
      // Load held orders from Supabase
      List<HeldOrder> heldOrders = [];
      try {
        final cashierId = state.currentUser?.id ?? '';
        if (cashierId.isNotEmpty) {
          heldOrders = await _heldOrderRepo.getHeldOrders(cashierId: cashierId);
          debugPrint('[DHBH Provider] HeldOrders loaded: ${heldOrders.length}');
        }
      } catch (e) {
        debugPrint('[DHBH Provider] HeldOrders load error: $e');
      }
      
      state = state.copyWith(
        products: products,
        transactions: transactions,
        heldOrders: heldOrders,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[DHBH Provider] loadProducts ERROR: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  // ─── CART ───────────────────────────────────────────────────────

  void addToCart(Product product, {bool isHomeVisit = false}) {
    final branchId = state.currentUser?.branchId;
    final existingIndex = state.cartItems.indexWhere(
      (item) => item.product.id == product.id && item.isHomeVisit == isHomeVisit,
    );
    final updatedCart = [...state.cartItems];
    if (existingIndex >= 0) {
      updatedCart[existingIndex] = CartItem(
        product: updatedCart[existingIndex].product,
        quantity: updatedCart[existingIndex].quantity + 1,
        notes: updatedCart[existingIndex].notes,
        isHomeVisit: updatedCart[existingIndex].isHomeVisit,
        branchId: branchId,
      );
    } else {
      updatedCart.add(CartItem(product: product, isHomeVisit: isHomeVisit, branchId: branchId));
    }
    state = state.copyWith(cartItems: updatedCart);
  }

  void removeFromCart(int index) {
    final updatedCart = [...state.cartItems]..removeAt(index);
    state = state.copyWith(cartItems: updatedCart);
  }

  void updateCartItemQuantity(int index, int quantity) {
    if (quantity <= 0) {
      removeFromCart(index);
      return;
    }
    final updatedCart = [...state.cartItems];
    updatedCart[index] = CartItem(
      product: updatedCart[index].product,
      quantity: quantity,
      notes: updatedCart[index].notes,
      isHomeVisit: updatedCart[index].isHomeVisit,
      branchId: updatedCart[index].branchId,
    );
    state = state.copyWith(cartItems: updatedCart);
  }

  void updateCartItemNotes(int index, String? notes) {
    final updatedCart = [...state.cartItems];
    updatedCart[index] = CartItem(
      product: updatedCart[index].product,
      quantity: updatedCart[index].quantity,
      notes: notes,
      isHomeVisit: updatedCart[index].isHomeVisit,
      branchId: updatedCart[index].branchId,
    );
    state = state.copyWith(cartItems: updatedCart);
  }

  int get cartTotal => state.cartItems.fold(0, (sum, item) => sum + item.totalPrice);
  int get cartItemCount => state.cartItems.fold(0, (sum, item) => sum + item.quantity);

  // ─── TRANSACTIONS ───────────────────────────────────────────────

  Future<void> completeTransaction({
    required int amountPaid,
    required PaymentMethod paymentMethod,
    int discount = 0,
    List<String>? customerNames,
    List<String>? terapisIds,
    List<String>? terapisNames,
    String? notes,
  }) async {
    if (state.currentUser == null) {
      debugPrint('[DHBH Provider] completeTransaction SKIP: no user');
      return;
    }
    final grandTotal = (cartTotal - discount) < 0 ? 0 : cartTotal - discount;
    debugPrint('[DHBH Provider] completeTransaction: total=$cartTotal, discount=$discount, grandTotal=$grandTotal, method=${paymentMethod.name}');
    
    // Save transaction directly to Supabase via repository
    final transaction = await _transactionRepo.saveTransaction(
      cashierId: state.currentUser!.id,
      branchId: state.currentUser!.branchId,
      items: List.from(state.cartItems),
      totalAmount: grandTotal,
      discount: discount,
      amountPaid: amountPaid,
      change: amountPaid - grandTotal,
      paymentMethod: paymentMethod,
      cashierName: state.currentUser!.name,
      customerNames: customerNames,
      terapisIds: terapisIds,
      terapisNames: terapisNames,
      notes: notes,
      branchName: state.currentUser?.branchName,
    );
    
    // Add to local state
    state = state.copyWith(
      cartItems: [],
      pendingCustomerNames: const [],
      transactions: [...state.transactions, transaction],
    );
    debugPrint('[DHBH Provider] cart cleared, ${state.transactions.length} total transactions');
    
    // Auto-print receipt if printer is connected
    _tryAutoPrint(transaction);
  }

  Future<void> _tryAutoPrint(Transaction transaction) async {
    try {
      // Windows desktop: prefer a connected Bluetooth thermal printer; fall
      // back to the default Windows printer (PDF) otherwise.
      if (WindowsBluetoothPrinterService.isSupported) {
        final btPrinter = WindowsBluetoothPrinterService();
        final winPrinter = WindowsPrinterService();
        final printerReady =
            btPrinter.isConnected || await winPrinter.isPrinterReady;
        if (!printerReady) {
          debugPrint('[DHBH Provider] auto-print SKIP: no Windows printer ready');
          return;
        }
      } else if (!BluetoothService().isConnected) {
        debugPrint('[DHBH Provider] auto-print SKIP: printer not connected');
        return;
      }
      // Delegate to printTransaction() so the actual printing happens AND the
      // print_status is persisted to the DB + local state (printed/failed).
      debugPrint('[DHBH Provider] auto-print: printing receipt...');
      await printTransaction(transaction);
    } catch (e) {
      debugPrint('[DHBH Provider] auto-print ERROR: $e');
    }
  }

  // ─── HELD ORDERS ───────────────────────────────────────────────

  Future<void> holdCurrentOrder({String? notes, List<String>? customerNames, String? customerName}) async {
    if (state.cartItems.isEmpty) return;
    debugPrint('[DHBH Provider] holdCurrentOrder: ${state.cartItems.length} items');

    final held = await _heldOrderRepo.saveHeldOrder(
      cashierId: state.currentUser?.id ?? '',
      branchId: state.currentUser?.branchId,
      items: List.from(state.cartItems),
      notes: notes,
      customerNames: customerNames,
      customerName: customerName,
    );

    state = state.copyWith(
      cartItems: [],
      heldOrders: [held, ...state.heldOrders],
    );
  }

  Future<void> retrieveHeldOrder(int index) async {
    final order = state.heldOrders[index];
    debugPrint('[DHBH Provider] retrieveHeldOrder: id=${order.id}, customer=${order.customerName}');

    state = state.copyWith(
      cartItems: List.from(order.items),
      pendingCustomerNames: order.customerNames,
    );

    final updatedOrders = [...state.heldOrders]..removeAt(index);
    state = state.copyWith(heldOrders: updatedOrders);

    if (order.id > 0) {
      await _heldOrderRepo.retrieveHeldOrder(order.id);
    }
  }

  Future<void> deleteHeldOrder(int index) async {
    final order = state.heldOrders[index];
    final updatedOrders = [...state.heldOrders]..removeAt(index);
    state = state.copyWith(heldOrders: updatedOrders);

    if (order.id > 0) {
      await _heldOrderRepo.deleteHeldOrder(order.id);
    }
  }

  Future<void> loadHeldOrders() async {
    if (state.currentUser == null) return;
    debugPrint('[DHBH Provider] loadHeldOrders');
    try {
      final orders = await _heldOrderRepo.getHeldOrders(cashierId: state.currentUser!.id);
      state = state.copyWith(heldOrders: orders);
      debugPrint('[DHBH Provider] held orders: ${orders.length}');
    } catch (e) {
      debugPrint('[DHBH Provider] held orders error: $e');
    }
  }

  // ─── PRODUCT CRUD (Admin) ──────────────────────────────────────

  Future<void> addProduct(Product product) async {
    debugPrint('[DHBH Provider] addProduct: ${product.name}');
    try {
      final saved = await _productRepo.addProduct(product);
      debugPrint('[DHBH Provider] addProduct SUCCESS: id=${saved.id}');
      // Reload from local SQLite to ensure consistency
      final refreshed = await _productRepo.getProducts();
      state = state.copyWith(products: refreshed);
      debugPrint('[DHBH Provider] addProduct: SQLite now has ${refreshed.length} products');
    } catch (e) {
      debugPrint('[DHBH Provider] addProduct ERROR: $e — falling back');
      final maxId = state.products.fold(0, (max, p) => p.id > max ? p.id : max);
      final newProduct = product.copyWith(id: maxId + 1);
      state = state.copyWith(products: [...state.products, newProduct]);
    }
  }

  Future<void> updateProduct(Product updatedProduct) async {
    debugPrint('[DHBH Provider] updateProduct: id=${updatedProduct.id}, name=${updatedProduct.name}');
    try {
      await _productRepo.updateProduct(updatedProduct);
      debugPrint('[DHBH Provider] updateProduct SUCCESS');
    } catch (e) {
      debugPrint('[DHBH Provider] updateProduct ERROR: $e');
    }
    // Reload from local SQLite to ensure consistency
    try {
      final refreshed = await _productRepo.getProducts();
      state = state.copyWith(products: refreshed);
      debugPrint('[DHBH Provider] updateProduct: SQLite now has ${refreshed.length} products');
    } catch (e) {
      debugPrint('[DHBH Provider] updateProduct reload error: $e');
      final updatedList = state.products.map((p) =>
        p.id == updatedProduct.id ? updatedProduct : p,
      ).toList();
      state = state.copyWith(products: updatedList);
    }
  }

  Future<void> deleteProduct(int productId) async {
    debugPrint('[DHBH Provider] deleteProduct: id=$productId');
    try {
      await _productRepo.deleteProduct(productId);
      debugPrint('[DHBH Provider] deleteProduct SUCCESS');
    } catch (e) {
      debugPrint('[DHBH Provider] deleteProduct ERROR: $e');
    }
    // Reload from local SQLite
    try {
      final refreshed = await _productRepo.getProducts();
      state = state.copyWith(products: refreshed);
    } catch (e) {
      debugPrint('[DHBH Provider] deleteProduct reload error: $e');
      final updatedList = state.products.where((p) => p.id != productId).toList();
      state = state.copyWith(products: updatedList);
    }
  }

  // ─── TODAY STATS ────────────────────────────────────────────────

  int get todayTransactionCount {
    // createdAt from DB is UTC -> convert to WIB before comparing with WIB "today".
    // Filtered per branch (user's branch) so each cabang sees its own count.
    final today = DateTime.now();
    final branchId = state.currentUser?.branchId;
    return state.transactions.where((t) {
      final wib = t.createdAt.toUtc().add(WibTime.offset);
      return wib.year == today.year &&
        wib.month == today.month &&
        wib.day == today.day &&
        (branchId == null || t.branchId == branchId) &&
        t.status == TransactionStatus.completed;
    }).length;
  }

  int get todayRevenue {
    final today = DateTime.now();
    final branchId = state.currentUser?.branchId;
    return state.transactions.where((t) {
      final wib = t.createdAt.toUtc().add(WibTime.offset);
      return wib.year == today.year &&
        wib.month == today.month &&
        wib.day == today.day &&
        (branchId == null || t.branchId == branchId) &&
        t.status == TransactionStatus.completed;
    }).fold(0, (sum, t) => sum + t.totalAmount);
  }

  // ─── THERMAL PRINTER ────────────────────────────────────────────

  Future<bool> printTransaction(Transaction transaction) async {
    debugPrint('[DHBH Provider] printTransaction: id=${transaction.id}, orderNo=${transaction.orderNo}');
    bool printSuccess = false;
    try {
      // Windows desktop: prefer a connected Bluetooth thermal printer; fall
      // back to the default Windows printer (PDF) otherwise. Only fall back
      // when a Windows printer is actually ready — otherwise report failure
      // instead of silently "succeeding" with no printer.
      if (WindowsBluetoothPrinterService.isSupported) {
        final btPrinter = WindowsBluetoothPrinterService();
        if (btPrinter.isConnected) {
          printSuccess = await btPrinter.printTransaction(transaction);
        } else if (await WindowsPrinterService().isPrinterReady) {
          printSuccess =
              await WindowsPrinterService().printTransaction(transaction);
        } else {
          debugPrint('[DHBH Provider] printTransaction SKIP: no printer ready');
        }
      } else if (WindowsPrinterService.isAvailable) {
        printSuccess =
            await WindowsPrinterService().printTransaction(transaction);
      } else {
        final printer = ThermalPrinterService();
        printSuccess = await printer.printTransaction(transaction);
      }
    } catch (e) {
      debugPrint('[DHBH Provider] printTransaction print error: $e');
    }
    
    // Always try to update status in DB (don't let DB failure affect print result)
    if (transaction.orderNo != null) {
      try {
        await _supabase.updatePrintStatus(
          transaction.orderNo!,
          printSuccess ? PrintStatus.printed.name : PrintStatus.failed.name,
        );
      } catch (e) {
        debugPrint('[DHBH Provider] printTransaction DB update error: $e');
      }
    } else {
      debugPrint('[DHBH Provider] printTransaction SKIP DB update: no orderNo (offline)');
    }
    
    // Update local state regardless
    final updatedTrans = state.transactions.map((t) {
      if (t.id == transaction.id) {
        return Transaction(
          id: t.id,
          orderNo: t.orderNo,
          cashierId: t.cashierId,
          items: t.items,
          totalAmount: t.totalAmount,
          discount: t.discount,
          amountPaid: t.amountPaid,
          change: t.change,
          paymentMethod: t.paymentMethod,
          cashierName: t.cashierName,
          customerNames: t.customerNames,
          terapisIds: t.terapisIds,
          terapisNames: t.terapisNames,
          notes: t.notes,
          branchId: t.branchId,
          createdAt: t.createdAt,
          status: t.status,
          printStatus: printSuccess ? PrintStatus.printed : PrintStatus.failed,
        );
      }
      return t;
    }).toList();
    state = state.copyWith(transactions: updatedTrans);
    
    debugPrint('[DHBH Provider] printTransaction ${printSuccess ? "SUCCESS" : "FAILED"}');
    return printSuccess;
  }

  Future<void> printUnprintedTransactions() async {
    debugPrint('[DHBH Provider] printUnprintedTransactions');
    final unprintedTrans = state.transactions
        .where((t) => t.printStatus == PrintStatus.unprinted)
        .toList();
    
    if (unprintedTrans.isEmpty) {
      debugPrint('[DHBH Provider] No unprinted transactions');
      return;
    }

    final printer = ThermalPrinterService();
    int successCount = 0;
    
    for (final transaction in unprintedTrans) {
      final success = await printer.printTransaction(transaction);
      if (success && transaction.orderNo != null) {
        successCount++;
        await _supabase.updatePrintStatus(transaction.orderNo!, PrintStatus.printed.name);
      }
    }

    debugPrint('[DHBH Provider] printUnprintedTransactions: $successCount/${unprintedTrans.length} printed');
    
    // Refresh transactions
    await loadProducts();
  }
}

class PosState {
  final AppUser? currentUser;
  final List<Product> products;
  final List<CartItem> cartItems;
  final List<Transaction> transactions;
  final List<HeldOrder> heldOrders;
  final List<String> pendingCustomerNames;
  final String searchQuery;
  final String selectedCategory;
  final String menuSelectedCategory;
  final bool isLoading;

  PosState({
    this.currentUser,
    this.products = const [],
    this.cartItems = const [],
    this.transactions = const [],
    this.heldOrders = const [],
    this.pendingCustomerNames = const [],
    this.searchQuery = '',
    this.selectedCategory = _all,
    this.menuSelectedCategory = _all,
    this.isLoading = false,
  });

  PosState copyWith({
    AppUser? currentUser,
    List<Product>? products,
    List<CartItem>? cartItems,
    List<Transaction>? transactions,
    List<HeldOrder>? heldOrders,
    List<String>? pendingCustomerNames,
    String? searchQuery,
    String? selectedCategory,
    String? menuSelectedCategory,
    bool? isLoading,
  }) {
    return PosState(
      currentUser: currentUser ?? this.currentUser,
      products: products ?? this.products,
      cartItems: cartItems ?? this.cartItems,
      transactions: transactions ?? this.transactions,
      heldOrders: heldOrders ?? this.heldOrders,
      pendingCustomerNames: pendingCustomerNames ?? this.pendingCustomerNames,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      menuSelectedCategory: menuSelectedCategory ?? this.menuSelectedCategory,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  try {
    final client = Supabase.instance.client;
    debugPrint('[DHBH Provider] SupabaseClient obtained successfully');
    return client;
  } catch (e) {
    debugPrint('[DHBH Provider] ⚠️ Error getting SupabaseClient: $e');
    rethrow;
  }
});

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService(ref.watch(supabaseClientProvider));
});

final posProvider = StateNotifierProvider<PosProvider, PosState>((ref) {
  final supabase = ref.watch(supabaseServiceProvider);
  return PosProvider(
    supabase,
    authRepo: AuthRepository(supabase),
    productRepo: ProductRepository(supabase),
    transactionRepo: TransactionRepository(supabase),
    heldOrderRepo: HeldOrderRepository(supabase),
  );
});
