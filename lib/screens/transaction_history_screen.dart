import 'package:flutter/material.dart';
import '../data/app_data.dart'
    show
        BarberTransaction,
        BarberTransactionTypeExtension,
        TransactionTypeExtension,
        WalletTransaction;
import '../data/user_data_provider.dart';

/// Full list of the signed-in user's wallet or earnings transactions.
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final _userDataProvider = UserDataProvider();

  @override
  void initState() {
    super.initState();
    _userDataProvider.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _userDataProvider.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  bool get _isBarber => _userDataProvider.userRole?.name == 'barber';

  @override
  Widget build(BuildContext context) {
    final barberTx = _userDataProvider.barberTransactions;
    final customerTx = _userDataProvider.customerTransactions;
    final isEmpty = _isBarber ? barberTx.isEmpty : customerTx.isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A1A)),
        title: const Text(
          'Transaction History',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: isEmpty
          ? Center(
              child: Text(
                'No transactions yet',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _isBarber ? barberTx.length : customerTx.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (_isBarber) return _barberTile(barberTx[index]);
                return _customerTile(customerTx[index]);
              },
            ),
    );
  }

  Widget _customerTile(WalletTransaction tx) {
    return _tile(
      title: tx.type.displayName,
      subtitle: tx.description.isEmpty ? tx.formattedDate : tx.description,
      trailing: tx.formattedAmount,
      date: tx.formattedDate,
      credit: tx.type.isCredit,
    );
  }

  Widget _barberTile(BarberTransaction tx) {
    return _tile(
      title: tx.type.displayName,
      subtitle: tx.description.isEmpty ? tx.formattedDate : tx.description,
      trailing: tx.formattedAmount,
      date: tx.formattedDate,
      credit: tx.type.isCredit,
    );
  }

  Widget _tile({
    required String title,
    required String subtitle,
    required String trailing,
    required String date,
    required bool credit,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: (credit ? const Color(0xFF00AA5B) : Colors.red)
                .withValues(alpha: 0.12),
            child: Icon(
              credit ? Icons.arrow_downward : Icons.arrow_upward,
              color: credit ? const Color(0xFF00AA5B) : Colors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trailing,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: credit ? const Color(0xFF00AA5B) : const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                date,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
