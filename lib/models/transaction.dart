import 'cart_item.dart';

enum TransactionStatus { completed, pending, cancelled, refunded }

enum PaymentMethod { cash, transfer, qris }

enum PrintStatus { printed, unprinted, failed, pending }

extension PrintStatusExtension on PrintStatus {
  String get displayName {
    switch (this) {
      case PrintStatus.printed:
        return 'Printed';
      case PrintStatus.unprinted:
        return 'Unprinted';
      case PrintStatus.failed:
        return 'Failed';
      case PrintStatus.pending:
        return 'Pending';
    }
  }
}

extension PaymentMethodExtension on PaymentMethod {
  String get displayName {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.transfer:
        return 'Transfer';
      case PaymentMethod.qris:
        return 'QRIS';
    }
  }
}

extension TransactionStatusExtension on TransactionStatus {
  String get displayName {
    switch (this) {
      case TransactionStatus.completed:
        return 'Completed';
      case TransactionStatus.pending:
        return 'Pending';
      case TransactionStatus.cancelled:
        return 'Cancelled';
      case TransactionStatus.refunded:
        return 'Refunded';
    }
  }
}

class Transaction {
  final String id;
  final int? orderNo;
  final String cashierId;
  final List<CartItem> items;
  final int totalAmount;
  final int amountPaid;
  final int change;
  final PaymentMethod paymentMethod;
  final String cashierName;

  /// Discount amount (Rupiah) applied to this transaction. [totalAmount] is
  /// the GRAND TOTAL after discount; [subtotal] = totalAmount + discount.
  final int discount;

  /// Multiple customers per transaction (dynamic).
  final List<String> customerNames;

  /// Multiple terapis per transaction (dynamic) — ids parallel to [terapisNames].
  final List<String> terapisIds;
  final List<String> terapisNames;

  final String? notes;
  final int? branchId;
  final String? branchName;
  final DateTime createdAt;
  final TransactionStatus status;
  final PrintStatus printStatus;

  Transaction({
    required this.id,
    this.orderNo,
    required this.cashierId,
    required this.items,
    required this.totalAmount,
    required this.amountPaid,
    required this.change,
    required this.paymentMethod,
    required this.cashierName,
    this.discount = 0,
    List<String>? customerNames,
    List<String>? terapisIds,
    List<String>? terapisNames,
    String? customerName,
    String? terapisId,
    String? terapisName,
    this.notes,
    this.branchId,
    this.branchName,
    required this.createdAt,
    this.status = TransactionStatus.completed,
    this.printStatus = PrintStatus.unprinted,
  })  : customerNames = (customerNames != null && customerNames.isNotEmpty)
            ? customerNames
            : (customerName != null && customerName.trim().isNotEmpty
                ? [customerName.trim()]
                : const <String>[]),
        terapisIds = (terapisIds != null && terapisIds.isNotEmpty)
            ? terapisIds
            : (terapisId != null && terapisId.isNotEmpty
                ? <String>[terapisId]
                : const <String>[]),
        terapisNames = (terapisNames != null && terapisNames.isNotEmpty)
            ? terapisNames
            : (terapisName != null && terapisName.trim().isNotEmpty
                ? [terapisName.trim()]
                : const <String>[]);

  /// Backward-compatible convenience getters (all names joined).
  String? get customerName => customerNames.isEmpty ? null : customerNames.join(', ');
  String? get terapisId => terapisIds.isEmpty ? null : terapisIds.first;
  String? get terapisName => terapisNames.isEmpty ? null : terapisNames.join(', ');

  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);

  /// Total before discount (sum of items).
  int get subtotal => totalAmount + discount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'order_no': orderNo,
        'cashier_id': cashierId,
        'items': items.map((e) => e.toJson()).toList(),
        'total_amount': totalAmount,
        'discount': discount,
        'amount_paid': amountPaid,
        'change': change,
        'payment_method': paymentMethod.name,
        'cashier_name': cashierName,
        'customer_name': customerName,
        'customers': customerNames,
        'terapis_id': terapisId,
        'terapis_name': terapisName,
        'terapis': [
          for (var i = 0; i < terapisNames.length; i++)
            {
              'id': i < terapisIds.length ? terapisIds[i] : '',
              'name': terapisNames[i],
            },
        ],
        'notes': notes,
        'branch_id': branchId,
        'branch_name': branchName,
        'created_at': createdAt.toIso8601String(),
        'status': status.name,
        'print_status': printStatus.name,
      };
}
