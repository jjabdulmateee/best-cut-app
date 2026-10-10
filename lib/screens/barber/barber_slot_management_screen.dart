import 'package:flutter/material.dart';
import '../../data/user_data_provider.dart';

class BarberSlotManagementScreen extends StatefulWidget {
  const BarberSlotManagementScreen({super.key});

  @override
  State<BarberSlotManagementScreen> createState() => _BarberSlotManagementScreenState();
}

class _BarberSlotManagementScreenState extends State<BarberSlotManagementScreen> {
  final UserDataProvider _userData = UserDataProvider();
  DateTime _selectedDate = DateTime.now();
  late int _startHour;
  late int _endHour;
  late int _slotDuration;

  /// Closed clock times ("HH:mm") per day. Kept locally so a toggle stays
  /// put while the Firestore write is in flight, and survives leaving
  /// the screen because it is reloaded from `slots/{uid}_{date}`.
  final Map<String, Set<String>> _closedTimes = {};
  final Set<String> _loadedDates = {};

  static const _durations = [15, 30, 45, 60];

  @override
  void initState() {
    super.initState();
    _startHour = _userData.workStartHour.clamp(6, 17).toInt();
    _endHour = _userData.workEndHour.clamp(12, 23).toInt();
    if (_endHour <= _startHour) _endHour = (_startHour + 1).clamp(12, 23).toInt();
    _slotDuration = _durations.contains(_userData.slotDurationMinutes)
        ? _userData.slotDurationMinutes
        : 30;
    _loadClosedTimes(_dateKey(_selectedDate));
  }

  String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  String _timeKey(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Future<void> _loadClosedTimes(String dateKey) async {
    if (_loadedDates.contains(dateKey)) return;
    _loadedDates.add(dateKey);
    try {
      final closed = await _userData.getClosedTimes(dateKey);
      if (!mounted) return;
      setState(() {
        // A toggle that landed before this read wins.
        _closedTimes.putIfAbsent(dateKey, () => closed);
      });
    } catch (e) {
      _loadedDates.remove(dateKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load slots: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleSlot(_SlotData slot) async {
    final dateKey = _dateKey(_selectedDate);
    final current = Set<String>.from(_closedTimes[dateKey] ?? {});
    if (current.contains(slot.timeKey)) {
      current.remove(slot.timeKey);
    } else {
      current.add(slot.timeKey);
    }
    setState(() => _closedTimes[dateKey] = current);

    try {
      await _userData.setClosedTimes(dateKey, current);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final reverted = Set<String>.from(_closedTimes[dateKey] ?? {});
        if (reverted.contains(slot.timeKey)) {
          reverted.remove(slot.timeKey);
        } else {
          reverted.add(slot.timeKey);
        }
        _closedTimes[dateKey] = reverted;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update that slot: $e'), backgroundColor: Colors.red),
      );
    }
  }

  List<_SlotData> _generateSlots() {
    final slots = <_SlotData>[];
    final dateKey = _dateKey(_selectedDate);
    final closed = _closedTimes[dateKey] ?? {};

    for (int hour = _startHour; hour < _endHour; hour++) {
      for (int minute = 0; minute < 60; minute += _slotDuration) {
        if (hour + (minute + _slotDuration) / 60 > _endHour) break;

        final isPM = hour >= 12;
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        final timeStr = '$displayHour:${minute.toString().padLeft(2, '0')} ${isPM ? 'PM' : 'AM'}';
        final timeKey = _timeKey(hour, minute);

        final slotDateTime = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          hour,
          minute,
        );

        final isPast = slotDateTime.isBefore(DateTime.now());
        final isClosed = closed.contains(timeKey);

        slots.add(_SlotData(
          timeKey: timeKey,
          time: timeStr,
          isOpen: !isClosed && !isPast,
          isPast: isPast,
        ));
      }
    }

    return slots;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Manage Availability',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _showWorkingHoursDialog,
            child: const Text(
              'Settings',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDateSelector(),
          _buildWorkingHoursInfo(),
          Expanded(child: _buildSlotGrid()),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final dates = List.generate(7, (index) => DateTime.now().add(Duration(days: index)));
    final dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SizedBox(
        height: 80,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: dates.length,
          itemBuilder: (context, index) {
            final date = dates[index];
            final isSelected = date.day == _selectedDate.day && 
                               date.month == _selectedDate.month;
            final isToday = index == 0;
            
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedDate = date;
                });
                _loadClosedTimes(_dateKey(date));
              },
              child: Container(
                width: 60,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: isSelected ? null : Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayNames[date.weekday % 7],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? Colors.white70 : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    if (isToday)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white24 : const Color(0xFF4CAF50).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Today',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : const Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWorkingHoursInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF2196F3), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Working Hours',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  '${_formatHour(_startHour)} - ${_formatHour(_endHour)} · $_slotDuration min slots',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _showWorkingHoursDialog,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  String _formatHour(int hour) {
    final isPM = hour >= 12;
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:00 ${isPM ? 'PM' : 'AM'}';
  }

  Widget _buildSlotGrid() {
    final slots = _generateSlots();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Time Slots',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              Text(
                'Tap to toggle availability',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Legend
          Row(
            children: [
              _buildLegendItem('Open', const Color(0xFF4CAF50)),
              const SizedBox(width: 16),
              _buildLegendItem('Closed', Colors.grey[400]!),
              const SizedBox(width: 16),
              _buildLegendItem('Past', Colors.grey[300]!),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 2.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: slots.length,
              itemBuilder: (context, index) {
                final slot = slots[index];
                return _buildSlotTile(slot);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildSlotTile(_SlotData slot) {
    final color = slot.isPast 
        ? Colors.grey[300]!
        : slot.isOpen 
            ? const Color(0xFF4CAF50)
            : Colors.grey[400]!;
    
    return GestureDetector(
      onTap: slot.isPast ? null : () => _toggleSlot(slot),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color),
        ),
        child: Center(
          child: Text(
            slot.time,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: slot.isPast ? Colors.grey[500] : color,
            ),
          ),
        ),
      ),
    );
  }

  void _showWorkingHoursDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Working Hours',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Start Hour
                Row(
                  children: [
                    const Text(
                      'Start Time',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    DropdownButton<int>(
                      value: _startHour,
                      items: List.generate(12, (i) => i + 6).map((hour) {
                        return DropdownMenuItem(
                          value: hour,
                          child: Text(_formatHour(hour)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() {
                            _startHour = value;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // End Hour
                Row(
                  children: [
                    const Text(
                      'End Time',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    DropdownButton<int>(
                      value: _endHour,
                      items: List.generate(12, (i) => i + 12).map((hour) {
                        return DropdownMenuItem(
                          value: hour,
                          child: Text(_formatHour(hour)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() {
                            _endHour = value;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Slot Duration
                Row(
                  children: [
                    const Text(
                      'Slot Duration',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    DropdownButton<int>(
                      value: _slotDuration,
                      items: [15, 30, 45, 60].map((duration) {
                        return DropdownMenuItem(
                          value: duration,
                          child: Text('$duration min'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() {
                            _slotDuration = value;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(this.context);
                      try {
                        await _userData.updateWorkingHours(
                          '${_startHour.toString().padLeft(2, '0')}:00',
                          '${_endHour.toString().padLeft(2, '0')}:00',
                          slotDurationMinutes: _slotDuration,
                        );
                        if (!mounted) return;
                        setState(() {});
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Slot settings saved'),
                            backgroundColor: Color(0xFF00C853),
                          ),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Could not save slot settings: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SlotData {
  final String timeKey;
  final String time;
  final bool isOpen;
  final bool isPast;

  _SlotData({
    required this.timeKey,
    required this.time,
    required this.isOpen,
    required this.isPast,
  });
}

