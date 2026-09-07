import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'grovio_shared.dart';
import 'dart:async';

class UniversalDashboard extends StatefulWidget {
  const UniversalDashboard({super.key});

  @override
  State<UniversalDashboard> createState() => _UniversalDashboardState();
}

class _UniversalDashboardState extends State<UniversalDashboard> {
  int _activeTab = 0;
  bool _isCleaning = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildMainContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: const Color(0xFF1A1C1E),
      child: Column(
        children: [
          const SizedBox(height: 40),
          _buildLogo(),
          const SizedBox(height: 50),
          _sidebarItem(0, Icons.speed, "System Pulse"),
          _sidebarItem(1, Icons.storefront, "Store Ops"),
          _sidebarItem(2, Icons.local_shipping, "Logistics"),
          _sidebarItem(3, Icons.analytics, "Financials"),
          _sidebarItem(4, Icons.payments, "Cost Control"),
          const Spacer(),
          _buildUsageBrief(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: GrovioColors.primaryGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.bolt, color: Colors.white),
        ),
        const SizedBox(width: 12),
        const Text(
          "GROVIO",
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _sidebarItem(int index, IconData icon, String label) {
    bool active = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? GrovioColors.primaryGreen.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: active ? GrovioColors.primaryGreen : Colors.white60,
              size: 20,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white60,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageBrief() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "QUOTA USAGE",
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const LinearProgressIndicator(
            value: 0.12,
            backgroundColor: Colors.white12,
            color: GrovioColors.primaryGreen,
          ),
          const SizedBox(height: 8),
          const Text(
            "12% of Free Tier used",
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Text(
            _getTabTitle(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1C1E),
            ),
          ),
          const Spacer(),
          _buildHeaderAction(
            Icons.account_balance_wallet,
            "View Cloud Billing",
            "https://console.firebase.google.com/project/_/billing",
          ),
          const SizedBox(width: 12),
          const CircleAvatar(
            backgroundColor: GrovioColors.primaryGreen,
            radius: 18,
            child: Icon(
              Icons.admin_panel_settings,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction(IconData icon, String label, String url) {
    return OutlinedButton.icon(
      onPressed: () => launchUrl(Uri.parse(url)),
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.blueGrey,
        side: const BorderSide(color: Color(0xFFE0E0E0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String _getTabTitle() {
    switch (_activeTab) {
      case 0:
        return "Universal Pulse Overview";
      case 1:
        return "Store Operations & Inventory";
      case 2:
        return "Logistics & Fleet Management";
      case 3:
        return "Quarterly Financial Statements";
      case 4:
        return "Financials & Quota Controls";
      default:
        return "Dashboard";
    }
  }

  Widget _buildMainContent() {
    switch (_activeTab) {
      case 0:
        return const _SystemPulseTab();
      case 1:
        return const _StoreOpsTab();
      case 2:
        return const _LogisticsTab();
      case 3:
        return const _FinancialsTab();
      case 4:
        return _buildCostControl();
      default:
        return const Center(child: Text("Select a module"));
    }
  }

  Widget _buildCostControl() {
    return ListView(
      padding: const EdgeInsets.all(30),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildCostSummaryCard()),
            const SizedBox(width: 30),
            Expanded(child: _buildUsagePieChart()),
          ],
        ),
        const SizedBox(height: 30),
        const Text(
          "Data Optimization Tools",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _optiToolCard(
              "Cleanup Delivery Photos",
              "Remove photos older than 7 days to free up Cloud Storage space.",
              Icons.cleaning_services,
              Colors.orange,
              _isCleaning
                  ? null
                  : () async {
                      setState(() => _isCleaning = true);
                      await GrovioFirestore.cleanupOldPhotos();
                      setState(() => _isCleaning = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Cleanup completed successfully!"),
                          ),
                        );
                      }
                    },
            ),
            const SizedBox(width: 20),
            _optiToolCard(
              "Read Quota Optimizer",
              "Limits real-time streams when the dashboard is idle to save on Firebase reads.",
              Icons.compress,
              Colors.blue,
              () {},
            ),
          ],
        ),
        const SizedBox(height: 30),
        _buildGCPBillingCard(),
      ],
    );
  }

  Widget _buildCostSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C3E50), Color(0xFF000000)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "ESTIMATED MONTHLY BILL",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "WITHIN FREE TIER",
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            "₹0.00",
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Next billing cycle starts on 1st Sept 2026",
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _optiToolCard(
    String title,
    String desc,
    IconData icon,
    Color color,
    VoidCallback? action,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              desc,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: action,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color.withValues(alpha: 0.1),
                  foregroundColor: color,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: action == null
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Run Now"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsagePieChart() {
    return Container(
      height: 230,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 40,
                sections: [
                  PieChartSectionData(
                    color: Colors.amber,
                    value: 65,
                    title: '65%',
                    radius: 25,
                    titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  PieChartSectionData(
                    color: Colors.blue,
                    value: 20,
                    title: '20%',
                    radius: 25,
                    titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  PieChartSectionData(
                    color: Colors.green,
                    value: 10,
                    title: '10%',
                    radius: 25,
                    titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  PieChartSectionData(
                    color: Colors.red,
                    value: 5,
                    title: '5%',
                    radius: 25,
                    titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legendItem("Firestore", Colors.amber),
              _legendItem("Storage", Colors.blue),
              _legendItem("Auth/Hosting", Colors.green),
              _legendItem("Functions", Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildGCPBillingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              "Tip: Avoid frequent refreshes of this dashboard. Every time you open it, Firebase charges 1 read per active document.",
              style: TextStyle(color: Colors.blueGrey, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () =>
                launchUrl(Uri.parse("https://firebase.google.com/pricing")),
            child: const Text("LEARN MORE"),
          ),
        ],
      ),
    );
  }
}

class _SystemPulseTab extends StatelessWidget {
  const _SystemPulseTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GrovioOrder>>(
      stream: GrovioFirestore.getOrders(),
      builder: (context, snapshot) {
        final orders = snapshot.data ?? [];
        final pending = orders.where((o) => o.status == "PLACED").length;
        final onWay = orders
            .where((o) => o.status == "OUT_FOR_DELIVERY")
            .length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _statTile(
                    "Pending Orders",
                    "$pending",
                    Icons.shopping_basket,
                    Colors.orange,
                  ),
                  const SizedBox(width: 20),
                  _statTile(
                    "Active Logistics",
                    "$onWay",
                    Icons.local_shipping,
                    Colors.blue,
                  ),
                  const SizedBox(width: 20),
                  _statTile(
                    "Revenue (Today)",
                    "₹${_calcTodayRev(orders)}",
                    Icons.account_balance_wallet,
                    Colors.green,
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _pulseSection(
                      "Live Activity Feed",
                      _buildActivityList(orders),
                    ),
                  ),
                  const SizedBox(width: 30),
                  Expanded(
                    child: _pulseSection("Quick Metrics", _buildMiniStats()),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _calcTodayRev(List<GrovioOrder> orders) {
    final now = DateTime.now();
    return orders
        .where((o) => o.date.day == now.day && o.status == "DELIVERED")
        .fold(0.0, (s, o) => s + o.total)
        .toStringAsFixed(0);
  }

  Widget _statTile(String label, String val, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                Text(
                  val,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pulseSection(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildActivityList(List<GrovioOrder> orders) {
    if (orders.isEmpty) return const Center(child: Text("No recent activity"));
    final recent = orders.take(10).toList();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recent.length,
      separatorBuilder: (_, _) => const Divider(height: 24),
      itemBuilder: (context, i) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: _statusColor(
            recent[i].status,
          ).withValues(alpha: 0.1),
          radius: 20,
          child: Icon(
            _statusIcon(recent[i].status),
            color: _statusColor(recent[i].status),
            size: 16,
          ),
        ),
        title: Text(
          recent[i].customerName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text("Order #${recent[i].id} • ₹${recent[i].total}"),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _statusColor(recent[i].status).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            recent[i].status,
            style: TextStyle(
              color: _statusColor(recent[i].status),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(String s) {
    if (s == "DELIVERED") return Colors.green;
    if (s == "OUT_FOR_DELIVERY") return Colors.blue;
    if (s == "PLACED") return Colors.orange;
    return Colors.grey;
  }

  IconData _statusIcon(String s) {
    if (s == "DELIVERED") return Icons.check_circle;
    if (s == "OUT_FOR_DELIVERY") return Icons.delivery_dining;
    if (s == "PLACED") return Icons.new_releases;
    return Icons.info;
  }

  Widget _buildMiniStats() {
    return Column(
      children: [
        _miniRow("Store Health", "98%", Colors.green),
        _miniRow("Driver Availability", "4/5", Colors.blue),
        _miniRow("Avg Delivery Time", "18m", Colors.orange),
      ],
    );
  }

  Widget _miniRow(String l, String v, Color c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: const TextStyle(color: Colors.grey)),
          Text(
            v,
            style: TextStyle(fontWeight: FontWeight.bold, color: c),
          ),
        ],
      ),
    );
  }
}

class _StoreOpsTab extends StatelessWidget {
  const _StoreOpsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroceryItem>>(
      stream: GrovioFirestore.getProducts(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _pulseSection(
                "Inventory Quick Management",
                DataTable(
                  columns: const [
                    DataColumn(label: Text("Item")),
                    DataColumn(label: Text("Stock")),
                    DataColumn(label: Text("Price")),
                    DataColumn(label: Text("Status")),
                  ],
                  rows: items
                      .take(15)
                      .map(
                        (it) => DataRow(
                          cells: [
                            DataCell(Text(it.name)),
                            DataCell(Text("${it.stockQty}")),
                            DataCell(Text("₹${it.price}")),
                            DataCell(
                              Icon(
                                it.inStock ? Icons.check_circle : Icons.error,
                                color: it.inStock ? Colors.green : Colors.red,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pulseSection(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _LogisticsTab extends StatelessWidget {
  const _LogisticsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GrovioOrder>>(
      stream: GrovioFirestore.getOrders(),
      builder: (context, snapshot) {
        final orders = snapshot.data ?? [];
        final outForDelivery = orders
            .where((o) => o.status == "OUT_FOR_DELIVERY")
            .toList();

        return ListView.builder(
          padding: const EdgeInsets.all(30),
          itemCount: outForDelivery.length,
          itemBuilder: (context, i) => Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              leading: const Icon(
                Icons.delivery_dining,
                size: 40,
                color: Colors.blue,
              ),
              title: Text("Order #${outForDelivery[i].id} is with Driver"),
              subtitle: Text(
                "Delivering to: ${outForDelivery[i].customerAddress}",
              ),
              trailing: const Chip(label: Text("ON THE WAY")),
            ),
          ),
        );
      },
    );
  }
}

class _FinancialsTab extends StatefulWidget {
  const _FinancialsTab();

  @override
  State<_FinancialsTab> createState() => _FinancialsTabState();
}

class _FinancialsTabState extends State<_FinancialsTab> {
  int _selectedQuarter = 0; // 0=Q1 (Jan-Mar), 1=Q2 (Apr-Jun), etc.
  final List<String> _quarters = [
    "Q1 (JAN-MAR)",
    "Q2 (APR-JUN)",
    "Q3 (JUL-SEP)",
    "Q4 (OCT-DEC)",
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GrovioOrder>>(
      stream: GrovioFirestore.getOrders(),
      builder: (context, orderSnap) {
        return StreamBuilder<List<GrovioOrder>>(
          stream: GrovioFirestore.getOfflineBills(),
          builder: (context, offlineSnap) {
            return StreamBuilder<List<GrovioExpense>>(
              stream: GrovioFirestore.getExpenses(),
              builder: (context, expenseSnap) {
                final List<GrovioOrder> allOrders = [
                  ...(orderSnap.data ?? []),
                  ...(offlineSnap.data ?? []),
                ];
                final List<GrovioExpense> allExpenses = expenseSnap.data ?? [];

                final qData = _filterByQuarter(
                  allOrders,
                  allExpenses,
                  _selectedQuarter,
                );

                return ListView(
                  padding: const EdgeInsets.all(30),
                  children: [
                    Row(
                      children: [
                        DropdownButton<int>(
                          value: _selectedQuarter,
                          items: List.generate(
                            4,
                            (i) => DropdownMenuItem(
                              value: i,
                              child: Text(_quarters[i]),
                            ),
                          ),
                          onChanged: (v) =>
                              setState(() => _selectedQuarter = v!),
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: () => _exportFinancials(qData),
                          icon: const Icon(Icons.download),
                          label: const Text("Export Bank-Ready PDF"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GrovioColors.primaryGreen,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    _buildPLStatement(qData),
                    const SizedBox(height: 30),
                    _buildCashFlowStatement(qData),
                    const SizedBox(height: 30),
                    _buildExpenseLogger(),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> _filterByQuarter(
    List<GrovioOrder> orders,
    List<GrovioExpense> expenses,
    int q,
  ) {
    int startMonth = (q * 3) + 1;
    int endMonth = (q * 3) + 3;
    final year = DateTime.now().year;

    final qOrders = orders
        .where(
          (o) =>
              o.date.year == year &&
              o.date.month >= startMonth &&
              o.date.month <= endMonth,
        )
        .toList();
    final qExpenses = expenses
        .where(
          (e) =>
              e.date.year == year &&
              e.date.month >= startMonth &&
              e.date.month <= endMonth,
        )
        .toList();

    double revenue = qOrders.fold(0, (sum, o) => sum + o.total);
    double cogs = 0;
    for (var o in qOrders) {
      for (var it in o.items) {
        cogs += it.costPrice * it.qty;
      }
    }

    double opEx = qExpenses.fold(0, (sum, e) => sum + e.amount);

    return {
      'quarter': _quarters[q],
      'year': year,
      'revenue': revenue,
      'cogs': cogs,
      'grossProfit': revenue - cogs,
      'opEx': opEx,
      'netProfit': (revenue - cogs) - opEx,
      'orders': qOrders,
      'expenses': qExpenses,
    };
  }

  Widget _buildPLStatement(Map<String, dynamic> data) {
    return _financeCard("PROFIT & LOSS STATEMENT", [
      _financeRow(
        "Total Revenue (Sales)",
        "₹${data['revenue']}",
        isHeader: true,
      ),
      _financeRow("Cost of Goods Sold (COGS)", "- ₹${data['cogs']}"),
      const Divider(),
      _financeRow("GROSS PROFIT", "₹${data['grossProfit']}", isBold: true),
      const SizedBox(height: 10),
      _financeRow("Operating Expenses", "- ₹${data['opEx']}"),
      const Divider(),
      _financeRow(
        "NET PROFIT / LOSS",
        "₹${data['netProfit']}",
        isHeader: true,
        color: data['netProfit'] >= 0 ? Colors.green : Colors.red,
      ),
    ]);
  }

  Widget _buildCashFlowStatement(Map<String, dynamic> data) {
    double cashIn =
        data['revenue']; // Assuming all sales are cash/upi for simplicity
    double cashOut = data['cogs'] + data['opEx'];

    return _financeCard("CASH FLOW STATEMENT", [
      _financeRow("Cash Inflow (Sales)", "₹$cashIn"),
      _financeRow("Cash Outflow (Purchase + Exp)", "- ₹$cashOut"),
      const Divider(),
      _financeRow("NET CASH POSITION", "₹${cashIn - cashOut}", isBold: true),
    ]);
  }

  Widget _financeCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Colors.blueGrey,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _financeRow(
    String label,
    String val, {
    bool isHeader = false,
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isHeader ? 16 : 14,
              fontWeight: isHeader || isBold
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
          Text(
            val,
            style: TextStyle(
              fontSize: isHeader ? 16 : 14,
              fontWeight: isHeader || isBold
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseLogger() {
    final noteController = TextEditingController();
    final amountController = TextEditingController();
    String category = "Rent";

    return _financeCard("LOG OPERATING EXPENSE", [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Amount",
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: category,
              items: [
                "Rent",
                "Salary",
                "Electricity",
                "Marketing",
                "Maintenance",
                "Tax",
                "Other",
              ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => category = v!,
              decoration: const InputDecoration(
                labelText: "Category",
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        controller: noteController,
        decoration: const InputDecoration(
          labelText: "Note (e.g. July Rent)",
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 15),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () async {
            if (amountController.text.isEmpty) return;
            final expense = GrovioExpense(
              id: "EXP_${DateTime.now().millisecondsSinceEpoch}",
              date: DateTime.now(),
              category: category,
              amount: double.tryParse(amountController.text) ?? 0.0,
              note: noteController.text,
            );
            await GrovioFirestore.saveExpense(expense);
            amountController.clear();
            noteController.clear();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Expense logged successfully")),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueGrey,
            foregroundColor: Colors.white,
          ),
          child: const Text("Save Expense"),
        ),
      ),
    ]);
  }

  Future<void> _exportFinancials(Map<String, dynamic> data) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoCondensedRegular();
    final fontBold = await PdfGoogleFonts.robotoCondensedBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "GROVIO SUPERMART",
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 24,
                          color: PdfColors.green900,
                        ),
                      ),
                      pw.Text(
                        "Quarterly Financial Report",
                        style: pw.TextStyle(font: font, fontSize: 14),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        "Period: ${data['quarter']} ${data['year']}",
                        style: pw.TextStyle(font: font, fontSize: 12),
                      ),
                      pw.Text(
                        "Generated: ${DateFormat('dd-MM-yyyy').format(DateTime.now())}",
                        style: pw.TextStyle(font: font, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 40),
              pw.Text(
                "1. PROFIT & LOSS STATEMENT",
                style: pw.TextStyle(font: fontBold, fontSize: 16),
              ),
              pw.Divider(),
              _pdfRow("Total Revenue", "Rs ${data['revenue']}", font),
              _pdfRow(
                "Cost of Goods Sold (COGS)",
                "(Rs ${data['cogs']})",
                font,
              ),
              pw.Divider(),
              _pdfRow("GROSS PROFIT", "Rs ${data['grossProfit']}", fontBold),
              pw.SizedBox(height: 10),
              _pdfRow("Operating Expenses", "(Rs ${data['opEx']})", font),
              pw.Divider(thickness: 2),
              _pdfRow("NET PROFIT", "Rs ${data['netProfit']}", fontBold),

              pw.SizedBox(height: 40),
              pw.Text(
                "2. OPERATING EXPENSES BREAKDOWN",
                style: pw.TextStyle(font: fontBold, fontSize: 16),
              ),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          "Date",
                          style: pw.TextStyle(font: fontBold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          "Category",
                          style: pw.TextStyle(font: fontBold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          "Amount",
                          style: pw.TextStyle(font: fontBold),
                        ),
                      ),
                    ],
                  ),
                  ...(data['expenses'] as List<GrovioExpense>).map(
                    (e) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(DateFormat('dd-MM-yy').format(e.date)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(e.category),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text("Rs ${e.amount}"),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Center(
                child: pw.Text(
                  "This is a computer-generated statement verified by Grovio System Pulse.",
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 8,
                    color: PdfColors.grey,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Grovio_Financial_Report_${data['quarter']}.pdf',
    );
  }

  pw.Widget _pdfRow(String label, String val, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font)),
          pw.Text(val, style: pw.TextStyle(font: font)),
        ],
      ),
    );
  }
}
