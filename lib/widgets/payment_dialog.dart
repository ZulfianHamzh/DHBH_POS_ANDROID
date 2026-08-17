import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transaction.dart';
import '../models/customer.dart';
import '../providers/pos_provider.dart';
import '../screens/customer_screen.dart';
import '../utils/app_theme.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_form_field.dart';

enum _DiscountType { percent, nominal }

class PaymentDialog extends ConsumerStatefulWidget {
  final int totalAmount;
  final VoidCallback? onDismiss;
  final List<String>? initialCustomerNames;
  final int? branchId;

  const PaymentDialog({
    super.key,
    required this.totalAmount,
    this.onDismiss,
    this.initialCustomerNames,
    this.branchId,
  });

  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
  PaymentMethod _selectedMethod = PaymentMethod.cash;
  final _amountController = TextEditingController();
  final List<TextEditingController> _customerControllers = [];
  final List<Map<String, dynamic>> _selectedTerapis = [];
  final _noteController = TextEditingController();
  final _discountController = TextEditingController();
  _DiscountType _discountType = _DiscountType.nominal;
  final _formKey = GlobalKey<FormState>();
  int _change = 0;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final initials = (widget.initialCustomerNames ?? const <String>[])
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (initials.isEmpty) {
      _customerControllers.add(TextEditingController());
    } else {
      for (final name in initials) {
        _customerControllers.add(TextEditingController(text: name));
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    for (final c in _customerControllers) {
      c.dispose();
    }
    _discountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Discount amount (Rupiah) from the current type + input, clamped to total.
  int _discountAmount() {
    final input =
        int.tryParse(_discountController.text.replaceAll('.', '')) ?? 0;
    if (input <= 0) return 0;
    final amount = _discountType == _DiscountType.percent
        ? (widget.totalAmount * input / 100).round()
        : input;
    return amount.clamp(0, widget.totalAmount);
  }

  int get _grandTotal => widget.totalAmount - _discountAmount();

  void _calculateChange() {
    final paid = int.tryParse(_amountController.text.replaceAll('.', '')) ?? 0;
    setState(() {
      _change = paid - _grandTotal;
    });
  }

  void _addCustomerField() {
    setState(() {
      _customerControllers.add(TextEditingController());
    });
  }

  void _removeCustomerField(int index) {
    setState(() {
      _customerControllers.removeAt(index).dispose();
    });
  }

  Future<void> _pilihPelanggan(int index) async {
    final customer = await Navigator.push<Customer>(
      context,
      MaterialPageRoute(builder: (_) => const CustomerScreen(isPicker: true)),
    );
    if (customer != null) {
      _customerControllers[index].text = customer.name;
    }
  }

  Future<void> _addTerapis() async {
    final branchId = widget.branchId;
    if (branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cabang kasir tidak diketahui')),
      );
      return;
    }
    final supabase = ref.read(supabaseServiceProvider);
    final therapists = await supabase.fetchTherapists(branchId);
    if (!mounted) return;
    if (therapists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada terapis di cabang ini')),
      );
      return;
    }
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TherapistPickerDialog(therapists: therapists),
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedTerapis.add({
          'id': selected['id'] as String,
          'name': selected['full_name'] as String,
        });
      });
    }
  }

  void _removeTerapis(int index) {
    setState(() {
      _selectedTerapis.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Pembayaran', style: AppTypography.headingBold),
                    GestureDetector(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        widget.onDismiss?.call();
                        Navigator.pop(context);
                      },
                      child: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Total: Rp ${_formatPrice(widget.totalAmount)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Metode Pembayaran',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: PaymentMethod.values.map((method) {
                    final isSelected = _selectedMethod == method;
                    return ChoiceChip(
                      label: Text(method.displayName),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedMethod = method);
                      },
                      selectedColor: AppColors.primaryGreen,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // ── Diskon (persen / nominal) ──
                const Text(
                  'Diskon',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Persen (%)',
                          style: TextStyle(fontSize: 12)),
                      selected: _discountType == _DiscountType.percent,
                      onSelected: (_) => setState(() {
                        _discountType = _DiscountType.percent;
                        _calculateChange();
                      }),
                      selectedColor: AppColors.primaryGreen,
                      labelStyle: TextStyle(
                        color: _discountType == _DiscountType.percent
                            ? Colors.white
                            : Colors.black,
                        fontSize: 12,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Nominal (Rp)',
                          style: TextStyle(fontSize: 12)),
                      selected: _discountType == _DiscountType.nominal,
                      onSelected: (_) => setState(() {
                        _discountType = _DiscountType.nominal;
                        _calculateChange();
                      }),
                      selectedColor: AppColors.primaryGreen,
                      labelStyle: TextStyle(
                        color: _discountType == _DiscountType.nominal
                            ? Colors.white
                            : Colors.black,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AppFormField(
                  label: 'Nilai Diskon',
                  controller: _discountController,
                  hint: _discountType == _DiscountType.percent
                      ? 'Contoh: 10'
                      : 'Masukkan nominal diskon',
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsInputFormatter()],
                  onChanged: (_) => _calculateChange(),
                ),
                if (_discountAmount() > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Total Setelah Diskon: Rp ${_formatPrice(_grandTotal)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ],
                if (_selectedMethod == PaymentMethod.cash) ...[
                  const SizedBox(height: 12),
                  AppFormField(
                    label: 'Jumlah Dibayar',
                    controller: _amountController,
                    hint: 'Masukkan jumlah',
                    keyboardType: TextInputType.number,
                    inputFormatters: const [ThousandsInputFormatter()],
                    onChanged: (_) => _calculateChange(),
                  ),
                  if (_change >= 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Kembalian: Rp ${_formatPrice(_change)}',
                        style: TextStyle(
                          color: _change >= 0
                              ? AppColors.primaryGreen
                              : AppColors.error,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                // ── Pelanggan (dynamic) ──
                for (var i = 0; i < _customerControllers.length; i++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppFormField(
                          label: i == 0
                              ? 'Nama Pelanggan'
                              : 'Nama Pelanggan ${i + 1}',
                          controller: _customerControllers[i],
                          hint: 'Masukkan nama pelanggan',
                          suffix: TextButton.icon(
                            onPressed: () => _pilihPelanggan(i),
                            icon: const Icon(Icons.person_search, size: 16),
                            label: const Text('Pilih',
                                style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Nama pelanggan wajib diisi';
                            }
                            return null;
                          },
                        ),
                      ),
                      if (_customerControllers.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 22, left: 4),
                          child: InkWell(
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              _removeCustomerField(i);
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.remove_circle_outline,
                                size: 20,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                TextButton.icon(
                  onPressed: _addCustomerField,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Tambah Pelanggan',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(height: 12),
                // ── Terapis (dynamic) ──
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Terapis',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_selectedTerapis.isEmpty)
                      Text(
                        'Belum ada terapis dipilih',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500]),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _selectedTerapis.length; i++)
                            Chip(
                              avatar: const Icon(
                                Icons.healing,
                                size: 16,
                                color: AppColors.primaryGreen,
                              ),
                              label: Text(
                                _selectedTerapis[i]['name'] as String,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onDeleted: () => _removeTerapis(i),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              backgroundColor: AppColors.primaryGreen
                                  .withValues(alpha: 0.08),
                              side: BorderSide(
                                color: AppColors.primaryGreen
                                    .withValues(alpha: 0.2),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _addTerapis,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Tambah Terapis',
                          style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // ── Note ──
                AppFormField(
                  label: 'Note',
                  controller: _noteController,
                  hint: 'Tips: Rp 50.000',
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                AppActionButton(
                  label: 'Bayar',
                  isLoading: _submitted,
                  onPressed: _submitted
                      ? null
                      : () {
                          if (!_formKey.currentState!.validate()) return;
                          setState(() => _submitted = true);
                          final paid =
                              int.tryParse(
                                _amountController.text.replaceAll('.', ''),
                              ) ??
                              _grandTotal;
                          if (_selectedMethod == PaymentMethod.cash &&
                              paid < _grandTotal) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Jumlah pembayaran tidak mencukupi',
                                ),
                              ),
                            );
                            setState(() => _submitted = false);
                            return;
                          }
                          final discount = _discountAmount();
                          final customerNames = _customerControllers
                              .map((c) => c.text.trim())
                              .where((s) => s.isNotEmpty)
                              .toList();
                          final terapisNames = _selectedTerapis
                              .map((t) => t['name'] as String)
                              .toList();
                          final terapisIds = _selectedTerapis
                              .map((t) => t['id'] as String)
                              .toList();
                          final note = _noteController.text.trim();
                          Navigator.pop(context, {
                            'amountPaid': _selectedMethod == PaymentMethod.cash
                                ? paid
                                : _grandTotal,
                            'paymentMethod': _selectedMethod,
                            'discount': discount,
                            'customerNames': customerNames,
                            'terapisIds': terapisIds,
                            'terapisNames': terapisNames,
                            'customerName': customerNames.join(', '),
                            'terapisId': terapisIds.isEmpty
                                ? null
                                : terapisIds.first,
                            'terapisName': terapisNames.join(', '),
                            'notes': note.isEmpty ? null : note,
                          });
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatPrice(int price) {
    return price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}.',
    );
  }
}

/// Dialog untuk memilih terapis (dari daftar yang sudah difilter per cabang).
class _TherapistPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> therapists;

  const _TherapistPickerDialog({required this.therapists});

  @override
  State<_TherapistPickerDialog> createState() => _TherapistPickerDialogState();
}

class _TherapistPickerDialogState extends State<_TherapistPickerDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.toLowerCase();
    if (q.isEmpty) return widget.therapists;
    return widget.therapists
        .where((t) =>
            ((t['full_name'] as String?) ?? '').toLowerCase().contains(q) ||
            ((t['username'] as String?) ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih Terapis',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkBlue,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Cari terapis...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Tidak ada terapis',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final t = _filtered[index];
                          return ListTile(
                            dense: true,
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.healing,
                                size: 18,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            title: Text(
                              (t['full_name'] as String?) ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              (t['username'] as String?) ?? '',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                            ),
                            onTap: () => Navigator.pop(context, t),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
