import 'package:flutter/material.dart';
import '../../models/barber_service.dart';
import '../../services/barber_services_service.dart';
import '../../services/auth_service.dart';
import 'add_edit_service_screen.dart';

/// ServiceManagementScreen — Full CRUD for barber services.
///
/// Shows all services (default, custom, combo) grouped by type.
/// Supports: add, edit, enable/disable, delete.
/// Seeds default services on first visit.
class ServiceManagementScreen extends StatefulWidget {
  const ServiceManagementScreen({super.key});

  @override
  State<ServiceManagementScreen> createState() => _ServiceManagementScreenState();
}

class _ServiceManagementScreenState extends State<ServiceManagementScreen> {
  final _svcService = BarberServicesService();
  final _authService = AuthService();
  bool _seeded = false;

  String get _barberId => _authService.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _seedDefaults();
  }

  Future<void> _seedDefaults() async {
    if (_barberId.isEmpty) return;
    await _svcService.seedDefaultsIfEmpty(_barberId);
    if (mounted) setState(() => _seeded = true);
  }

  // ─────────────────────── Actions ───────────────────────

  void _openAddService() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditServiceScreen(barberId: _barberId),
      ),
    );
  }

  void _openEditService(BarberService service, List<BarberService> allServices) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditServiceScreen(
          barberId: _barberId,
          existingService: service,
          allServices: allServices,
        ),
      ),
    );
  }

  Future<void> _toggleService(BarberService service) async {
    await _svcService.toggleEnabled(service.id, !service.isEnabled);
  }

  Future<void> _deleteService(BarberService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Service?'),
        content: Text(
          'Are you sure you want to permanently delete "${service.name}"?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _svcService.deleteService(service.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${service.emoji} "${service.name}" deleted'),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    }
  }

  // ─────────────────────── UI ───────────────────────

  @override
  Widget build(BuildContext context) {
    if (_barberId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'My Services',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
        ),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: _openAddService,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<List<BarberService>>(
        stream: _svcService.streamServices(_barberId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load services.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting && !_seeded) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF1A1A1A)),
            );
          }

          final services = snapshot.data ?? [];

          if (services.isEmpty) {
            return _buildEmptyState();
          }

          // Group by type for clean display
          final defaults = services.where((s) => s.type == ServiceType.defaultService).toList();
          final customs = services.where((s) => s.type == ServiceType.custom).toList();
          final combos = services.where((s) => s.type == ServiceType.combo).toList();

          return RefreshIndicator(
            color: const Color(0xFF1A1A1A),
            onRefresh: () async {
              // Stream auto-refreshes; this is just for pull-to-refresh UX
              await Future.delayed(const Duration(milliseconds: 300));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                // Summary card
                _buildSummaryCard(services),
                const SizedBox(height: 20),

                if (defaults.isNotEmpty) ...[
                  _buildSectionHeader('💈  Default Services', defaults.length),
                  const SizedBox(height: 8),
                  ...defaults.map((s) => _buildServiceCard(s, services)),
                  const SizedBox(height: 20),
                ],

                if (customs.isNotEmpty) ...[
                  _buildSectionHeader('🎨  Custom Services', customs.length),
                  const SizedBox(height: 8),
                  ...customs.map((s) => _buildServiceCard(s, services)),
                  const SizedBox(height: 20),
                ],

                if (combos.isNotEmpty) ...[
                  _buildSectionHeader('📦  Combo Deals', combos.length),
                  const SizedBox(height: 8),
                  ...combos.map((s) => _buildServiceCard(s, services)),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddService,
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Service', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Text('✂️', style: TextStyle(fontSize: 36)),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Services Yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your services and set your prices.\nCustomers will see these when booking.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[600], height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openAddService,
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Service'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(List<BarberService> services) {
    final active = services.where((s) => s.isEnabled).length;
    final disabled = services.length - active;
    final combos = services.where((s) => s.isCombo).length;
    final minPrice = services.isEmpty
        ? 0
        : services.where((s) => s.isEnabled).fold<int>(
            999999, (min, s) => s.pricePKR < min ? s.pricePKR : min);
    final maxPrice = services.isEmpty
        ? 0
        : services.where((s) => s.isEnabled).fold<int>(
            0, (max, s) => s.pricePKR > max ? s.pricePKR : max);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          _buildStat('$active', 'Active', Colors.green[700]!),
          _buildStatDivider(),
          _buildStat('$disabled', 'Disabled', Colors.orange[700]!),
          _buildStatDivider(),
          _buildStat('$combos', 'Combos', Colors.blue[700]!),
          _buildStatDivider(),
          _buildStat(
            services.isEmpty ? '—' : 'Rs.$minPrice–$maxPrice',
            'Price Range',
            const Color(0xFF1A1A1A),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: value.length > 8 ? 11 : 16,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 30, color: Colors.grey[200]);
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceCard(BarberService service, List<BarberService> allServices) {
    final isDisabled = !service.isEnabled;

    return Opacity(
      opacity: isDisabled ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDisabled ? Colors.orange[200]! : Colors.grey[200]!,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openEditService(service, allServices),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Emoji avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _emojiBackgroundColor(service),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(service.emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Name + meta
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                service.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A1A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isDisabled) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.orange[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'OFF',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.orange[800],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              service.formattedDuration,
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            ),
                            if (service.category != null) ...[
                              Text(' · ', style: TextStyle(color: Colors.grey[400])),
                              Text(
                                service.category!,
                                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                              ),
                            ],
                            if (service.isCombo) ...[
                              Text(' · ', style: TextStyle(color: Colors.grey[400])),
                              Text(
                                '${service.comboServiceNames.length} services',
                                style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                              ),
                            ],
                          ],
                        ),
                        // Show included services for combos
                        if (service.isCombo && service.comboServiceNames.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            service.comboServiceNames.join(' + '),
                            style: TextStyle(fontSize: 11, color: Colors.grey[400], fontStyle: FontStyle.italic),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Price
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rs.${service.pricePKR}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        service.typeLabel,
                        style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),

                  // 3-dot menu
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      switch (action) {
                        case 'edit':
                          _openEditService(service, allServices);
                          break;
                        case 'toggle':
                          _toggleService(service);
                          break;
                        case 'delete':
                          _deleteService(service);
                          break;
                      }
                    },
                    icon: Icon(Icons.more_vert, color: Colors.grey[400], size: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Row(
                          children: [
                            Icon(
                              service.isEnabled ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(service.isEnabled ? 'Disable' : 'Enable'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _emojiBackgroundColor(BarberService service) {
    switch (service.type) {
      case ServiceType.defaultService:
        return const Color(0xFFF5F0FF);
      case ServiceType.custom:
        return const Color(0xFFF0F7FF);
      case ServiceType.combo:
        return const Color(0xFFFFF8E7);
    }
  }
}
