import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/barber_service.dart';
import '../../services/barber_services_service.dart';

/// AddEditServiceScreen — Create or edit a custom / combo / default service.
///
/// Modes:
///  • **Add custom**  — form with name, price, duration, category, emoji
///  • **Add combo**   — pick 2+ existing services, set one bundle price
///  • **Edit**        — pre-populated form for any existing service
class AddEditServiceScreen extends StatefulWidget {
  final String barberId;
  final BarberService? existingService;

  /// All of the barber's services (needed for combo picker).
  /// Only required when creating/editing a combo.
  final List<BarberService>? allServices;

  const AddEditServiceScreen({
    super.key,
    required this.barberId,
    this.existingService,
    this.allServices,
  });

  @override
  State<AddEditServiceScreen> createState() => _AddEditServiceScreenState();
}

class _AddEditServiceScreenState extends State<AddEditServiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _svcService = BarberServicesService();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _categoryCtrl;

  bool _isCombo = false;
  String _selectedEmoji = '✂️';
  final Set<String> _selectedComboIds = {};
  bool _saving = false;

  bool get _isEditing => widget.existingService != null;

  // Available emojis for quick pick
  static const _emojis = ['✂️', '🧔', '💈', '💇', '🪒', '🧴', '💆', '🎨', '🧖', '👑', '⭐', '🔥'];

  // Suggested categories
  static const _categories = ['Hair', 'Face', 'Grooming', 'Spa', 'Kids', 'Other'];

  @override
  void initState() {
    super.initState();
    final svc = widget.existingService;

    _nameCtrl = TextEditingController(text: svc?.name ?? '');
    _priceCtrl = TextEditingController(text: svc != null ? '${svc.pricePKR}' : '');
    _durationCtrl = TextEditingController(text: svc != null ? '${svc.durationMinutes}' : '30');
    _categoryCtrl = TextEditingController(text: svc?.category ?? '');
    _selectedEmoji = svc?.emoji ?? '✂️';
    _isCombo = svc?.isCombo ?? false;

    if (svc != null && svc.isCombo) {
      _selectedComboIds.addAll(svc.comboServiceIds);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _durationCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────── Save ───────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isCombo && _selectedComboIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 2 services for a combo'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final name = _nameCtrl.text.trim();
      final price = int.parse(_priceCtrl.text.trim());
      final duration = int.tryParse(_durationCtrl.text.trim()) ?? 30;
      final category = _categoryCtrl.text.trim().isEmpty ? null : _categoryCtrl.text.trim();

      // Build combo metadata
      List<String> comboIds = [];
      List<String> comboNames = [];
      if (_isCombo) {
        final allSvcs = widget.allServices ?? [];
        comboIds = _selectedComboIds.toList();
        comboNames = allSvcs
            .where((s) => _selectedComboIds.contains(s.id))
            .map((s) => s.name)
            .toList();
      }

      if (_isEditing) {
        // UPDATE existing service
        await _svcService.updateService(widget.existingService!.id, {
          'name': name,
          'pricePKR': price,
          'durationMinutes': duration,
          'category': category,
          'emoji': _selectedEmoji,
          'type': _isCombo ? ServiceType.combo.name : widget.existingService!.type.name,
          'comboServiceIds': comboIds,
          'comboServiceNames': comboNames,
        });
      } else {
        // CREATE new service
        final newService = BarberService(
          id: '',
          barberId: widget.barberId,
          name: name,
          pricePKR: price,
          type: _isCombo ? ServiceType.combo : ServiceType.custom,
          category: category,
          emoji: _selectedEmoji,
          durationMinutes: duration,
          comboServiceIds: comboIds,
          comboServiceNames: comboNames,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await _svcService.addService(newService);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? '$_selectedEmoji Service updated!' : '$_selectedEmoji Service added!'),
            backgroundColor: const Color(0xFF00AA5B),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving service: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─────────────────────── UI ───────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? 'Edit Service' : 'New Service',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A1A1A)),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Service type toggle ──
            _buildTypeToggle(),
            const SizedBox(height: 20),

            // ── Emoji picker ──
            _buildEmojiPicker(),
            const SizedBox(height: 20),

            // ── Name field ──
            _buildTextField(
              controller: _nameCtrl,
              label: 'Service Name',
              hint: _isCombo ? 'e.g. Full Grooming Package' : 'e.g. Hair Color',
              icon: Icons.label_outline,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter a service name';
                return null;
              },
            ),
            const SizedBox(height: 14),

            // ── Price + Duration row ──
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _priceCtrl,
                    label: 'Price (PKR)',
                    hint: '500',
                    icon: Icons.attach_money,
                    keyboardType: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter price';
                      if (int.tryParse(v.trim()) == null) return 'Invalid';
                      if (int.parse(v.trim()) <= 0) return 'Must be > 0';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _durationCtrl,
                    label: 'Duration (min)',
                    hint: '30',
                    icon: Icons.timer_outlined,
                    keyboardType: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter duration';
                      if (int.tryParse(v.trim()) == null) return 'Invalid';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Category chips ──
            _buildCategorySection(),
            const SizedBox(height: 20),

            // ── Combo picker ──
            if (_isCombo) ...[
              _buildComboPicker(),
              const SizedBox(height: 20),
            ],

            // ── Save button ──
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _isEditing ? 'Update Service' : 'Create Service',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Service type toggle: Custom vs Combo ──
  Widget _buildTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildToggleButton(
            label: '🎨 Custom Service',
            isSelected: !_isCombo,
            onTap: () => setState(() => _isCombo = false),
          ),
          _buildToggleButton(
            label: '📦 Combo Deal',
            isSelected: _isCombo,
            onTap: () => setState(() => _isCombo = true),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  // ── Emoji picker grid ──
  Widget _buildEmojiPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Icon',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _emojis.map((emoji) {
            final isSelected = _selectedEmoji == emoji;
            return GestureDetector(
              onTap: () => setState(() => _selectedEmoji = emoji),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected ? null : Border.all(color: Colors.grey[300]!),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Category quick-select ──
  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Category (optional)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categories.map((cat) {
            final isSelected = _categoryCtrl.text == cat;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _categoryCtrl.text = isSelected ? '' : cat;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1A1A1A) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey[300]!,
                  ),
                ),
                child: Text(
                  cat,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.grey[700],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Combo service multi-select ──
  Widget _buildComboPicker() {
    final available = (widget.allServices ?? [])
        .where((s) => !s.isCombo) // Don't allow combo-of-combos
        .where((s) => s.id != widget.existingService?.id) // Don't include self
        .toList();

    if (available.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Add at least 2 individual services first, then create a combo from them.',
                style: TextStyle(fontSize: 13, color: Colors.blue[700]),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Select Services to Bundle',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
            ),
            const Spacer(),
            Text(
              '${_selectedComboIds.length} selected',
              style: TextStyle(
                fontSize: 12,
                color: _selectedComboIds.length >= 2 ? Colors.green[700] : Colors.orange[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...available.map((svc) {
          final isSelected = _selectedComboIds.contains(svc.id);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selectedComboIds.remove(svc.id);
                } else {
                  _selectedComboIds.add(svc.id);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF0FFF0) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.green[400]! : Colors.grey[200]!,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: Text(svc.emoji, style: const TextStyle(fontSize: 18))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          svc.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Rs.${svc.pricePKR} · ${svc.formattedDuration}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected ? Colors.green[600] : Colors.grey[300],
                    size: 24,
                  ),
                ],
              ),
            ),
          );
        }),
        if (_selectedComboIds.length >= 2)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  'Set a unique combo price above (usually a discount)',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Reusable text field ──
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      validator: validator,
      style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1A1A1A), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red[400]!),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
