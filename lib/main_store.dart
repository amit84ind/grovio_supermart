import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:screenshot/screenshot.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'grovio_shared.dart';
import 'admin_uploader.dart';

// --- NOTIFICATION SETUP ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await GrovioConfig.initFirebase();
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
  } catch (e) {
    debugPrint("Firebase init failed: $e");
  }
  runApp(const GrovioStoreApp());
}

class GrovioStoreApp extends StatelessWidget {
  const GrovioStoreApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grovio Store',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: GrovioColors.primaryGreen,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: GrovioColors.primaryGreen),
      ),
      home: const StoreDashboard(),
    );
  }
}

class StoreDashboard extends StatefulWidget {
  const StoreDashboard({super.key});
  @override
  State<StoreDashboard> createState() => _StoreDashboardState();
}

class _StoreDashboardState extends State<StoreDashboard>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const OrdersManagerPage(),
    const InventoryManagerPage(),
    const BillingPage(),
    const StoreInsightsPage(),
    const StoreFeedbackPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GrovioFirestore.cleanupOldPhotos();
    _setupNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    debugPrint("Memory Pressure: Cleared Image Cache (Store App)");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      // Memory Optimization: Clear image cache when app goes to background
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      debugPrint("Memory: Image cache cleared (Background)");
    }
  }

  void _setupNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.subscribeToTopic('store_orders');
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'High Importance Notifications',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/launcher_icon',
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "GROVIO STORE",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: GrovioColors.primaryGreen,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BulkUploaderPage()),
            ),
            icon: const Icon(
              Icons.cloud_upload_outlined,
              color: GrovioColors.primaryGreen,
            ),
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            label: "Orders",
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: "Inventory",
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: "Quick Bill",
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            label: "Earnings",
          ),
          NavigationDestination(
            icon: Icon(Icons.rate_review_outlined),
            label: "Feedback",
          ),
        ],
      ),
    );
  }
}

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});
  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  final ScreenshotController screenshotController = ScreenshotController();
  List<BluetoothInfo> _devices = [];
  BluetoothInfo? _selectedDevice;
  bool _connected = false;
  bool _isPaid = false;
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  List<OrderItem> billItems = [];
  double total = 0;

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  void _initBluetooth() async {
    try {
      // Request permissions
      if (Platform.isAndroid) {
        await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
        ].request();
      }

      bool isPermissionGranted =
          await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!isPermissionGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Bluetooth permissions denied")),
          );
        }
        return;
      }

      bool bluetoothEnabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!bluetoothEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please enable Bluetooth")),
          );
        }
        return;
      }

      final List<BluetoothInfo> listVotes =
          await PrintBluetoothThermal.pairedBluetooths;
      setState(() {
        _devices = listVotes;
      });

      if (listVotes.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No paired printers found. Pair in settings first."),
          ),
        );
      }
    } catch (e) {
      debugPrint("Bluetooth Init Error: $e");
    }
  }

  void _connect() async {
    if (_selectedDevice != null) {
      setState(() => _connected = false);
      final bool result = await PrintBluetoothThermal.connect(
        macPrinterAddress: _selectedDevice!.macAdress,
      );
      setState(() {
        _connected = result;
      });
      if (!result && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to connect printer.")),
        );
      }
    }
  }

  void _addItem(GroceryItem item) {
    setState(() {
      _isPaid = false;
      int idx = billItems.indexWhere((it) => it.itemId == item.id);
      if (idx != -1) {
        billItems[idx] = OrderItem(
          itemId: item.id,
          name: item.name,
          unit: item.unit,
          qty: billItems[idx].qty + 1,
          price: item.price,
          mrp: item.mrp,
          costPrice: item.costPrice,
        );
      } else {
        billItems.add(
          OrderItem(
            itemId: item.id,
            name: item.name,
            unit: item.unit,
            qty: 1,
            price: item.price,
            mrp: item.mrp,
            costPrice: item.costPrice,
          ),
        );
      }
      total += item.price;
    });
  }

  void _scanBarcode() {
    final MobileScannerController controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Scan Barcode",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => controller.toggleTorch(),
                    icon: ValueListenableBuilder<MobileScannerState>(
                      valueListenable: controller,
                      builder: (context, state, child) {
                        return Icon(
                          state.torchState == TorchState.on
                              ? Icons.flash_on
                              : Icons.flash_off,
                          color: GrovioColors.primaryGreen,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  MobileScanner(
                    controller: controller,
                    onDetect: (capture) {
                      final barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        final code = barcodes.first.rawValue;
                        if (code != null) {
                          controller.dispose();
                          Navigator.pop(context);
                          _handleScannedCode(code);
                        }
                      }
                    },
                  ),
                  // Overlay to help focus
                  Center(
                    child: Container(
                      width: 250,
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        "Keep barcode inside the box\nUse flash for better result",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).then((_) => controller.dispose());
  }

  void _handleScannedCode(String code) async {
    final item = await GrovioFirestore.getProductByBarcode(code);
    if (item != null) {
      _addItem(item);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Product not found!")));
      }
    }
  }

  void _showItemPicker() {
    String localSearch = "";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setPickerState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                onChanged: (v) => setPickerState(() => localSearch = v),
                decoration: InputDecoration(
                  hintText: "Search items...",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: StreamBuilder<List<GroceryItem>>(
                  stream: GrovioFirestore.getProducts(limit: 1000),
                  builder: (context, snapshot) {
                    var items = snapshot.data ?? [];
                    if (localSearch.isNotEmpty) {
                      items = items
                          .where(
                            (it) => it.name.toLowerCase().contains(
                              localSearch.toLowerCase(),
                            ),
                          )
                          .toList();
                    }
                    return ListView.builder(
                      itemCount: items.length,
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      itemBuilder: (context, i) => ListTile(
                        leading: Image.network(
                          items[i].imageUrl,
                          width: 40,
                          cacheWidth: 100,
                          errorBuilder: (_, __, ___) => const Icon(Icons.image),
                        ),
                        title: Text(items[i].name),
                        subtitle: Text("Rs ${items[i].price}"),
                        onTap: () {
                          _addItem(items[i]);
                          Navigator.pop(context);
                        },
                      ),
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

  void _confirmPayment() {
    if (billItems.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Verify Payment"),
        content: Text("Received Rs $total?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("NO"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _isPaid = true);
              Navigator.pop(ctx);
            },
            child: const Text("YES"),
          ),
        ],
      ),
    );
  }

  double _calculateTotalSavings() {
    double s = 0;
    for (var it in billItems) {
      if (it.mrp > it.price) s += (it.mrp - it.price) * it.qty;
    }
    return s;
  }

  void _resetBilling() {
    setState(() {
      billItems.clear();
      total = 0;
      _isPaid = false;
      _customerNameController.clear();
      _customerPhoneController.clear();
    });
  }

  Future<void> _sendBillToWhatsApp(GrovioOrder order) async {
    String msg =
        "*GROVIO SUPERMART INVOICE*\n--------------------------\nOrder ID: ${order.id}\nDate: ${order.date.toString().substring(0, 16)}\nCustomer: ${order.customerName}\n--------------------------\n";
    for (var it in order.items) {
      msg += "• ${it.name} x${it.qty} = Rs ${it.price * it.qty}\n";
    }
    msg += "--------------------------\n*TOTAL: Rs ${order.total}*\n";
    if (order.totalSavings > 0) {
      msg += "*YOU SAVED: Rs ${order.totalSavings.toStringAsFixed(0)}*\n";
    }
    msg += "\nThank You! - Grovio SuperMart Amethi";
    String phone = order.customerPhone.replaceAll(RegExp(r'\D'), '');
    if (phone.length == 10) phone = "91$phone";
    if (phone.isEmpty || phone == "91") return;
    final url = "https://wa.me/$phone?text=${Uri.encodeComponent(msg)}";
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _sharePdf(GrovioOrder order) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          58 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 5 * PdfPageFormat.mm,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  "GROVIO SUPERMART",
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                "Date: ${order.date.toString().substring(0, 16)}",
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                "Order: ${order.id}",
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                "Cust: ${order.customerName}",
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Divider(thickness: 0.5),
              ...order.items.map(
                (it) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        "${it.name} x${it.qty}",
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ),
                    pw.Text(
                      "Rs ${it.price * it.qty}",
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "TOTAL",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  pw.Text(
                    "Rs ${order.total}",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              if (order.totalSavings > 0)
                pw.Text(
                  "SAVED: Rs ${order.totalSavings.toStringAsFixed(0)}",
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                    color: PdfColors.green,
                  ),
                ),
              pw.SizedBox(height: 20),
              pw.Center(
                child: pw.Text(
                  "Visit Again!",
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          );
        },
      ),
    );
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Grovio_Bill_${order.id}.pdf',
    );
  }

  void _printReceipt() async {
    if (!_isPaid) return;
    final offOrder = GrovioOrder(
      id: "OFF_${DateTime.now().millisecondsSinceEpoch % 100000}",
      date: DateTime.now(),
      items: List.from(billItems),
      total: total,
      totalSavings: _calculateTotalSavings(),
      status: "DELIVERED",
      paymentMethod: "Cash",
      customerName: _customerNameController.text.isEmpty
          ? "Guest"
          : _customerNameController.text,
      customerPhone: _customerPhoneController.text.isEmpty
          ? "N/A"
          : _customerPhoneController.text,
      customerAddress: "Store",
    );
    await GrovioFirestore.saveOfflineBill(offOrder);
    await GrovioFirestore.decrementStock(offOrder.items);
    try {
      await GrovioPrinter.printInvoice(offOrder);
      _resetBilling();
    } catch (e) {
      if (!await PrintBluetoothThermal.connectionStatus) {
        await _sendBillToWhatsApp(offOrder);
        _resetBilling();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<BluetoothInfo>(
                      isExpanded: true,
                      hint: Text(_devices.isEmpty
                          ? "No Printer Found (Refresh)"
                          : "Select Printer"),
                      value: _selectedDevice,
                      items: _devices
                          .map(
                            (e) =>
                                DropdownMenuItem(value: e, child: Text(e.name)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedDevice = v),
                    ),
                  ),
                  IconButton(
                    onPressed: _initBluetooth,
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: "Refresh Printers",
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _connected
                        ? () async {
                            await PrintBluetoothThermal.disconnect;
                            setState(() => _connected = false);
                          }
                        : _connect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _connected ? Colors.red : Colors.blue,
                    ),
                    child: Text(
                      _connected ? "Off" : "Connect",
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customerNameController,
                      decoration: const InputDecoration(
                        hintText: "Customer Name",
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _customerPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: "Phone Number",
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _scanBarcode,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text("SCAN"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showItemPicker,
                      icon: const Icon(Icons.search),
                      label: const Text("MANUAL"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: billItems.length,
            itemBuilder: (context, i) {
              final item = billItems[i];
              return ListTile(
                title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text("Rs ${item.price} / ${item.unit}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.orange),
                      onPressed: () {
                        setState(() {
                          if (item.qty > 1) {
                            total -= item.price;
                            billItems[i] = OrderItem(
                              itemId: item.itemId,
                              name: item.name,
                              unit: item.unit,
                              qty: item.qty - 1,
                              price: item.price,
                              mrp: item.mrp,
                              costPrice: item.costPrice,
                            );
                          } else {
                            total -= item.price;
                            billItems.removeAt(i);
                          }
                        });
                      },
                    ),
                    Text("${item.qty}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                      onPressed: () {
                        setState(() {
                          total += item.price;
                          billItems[i] = OrderItem(
                            itemId: item.itemId,
                            name: item.name,
                            unit: item.unit,
                            qty: item.qty + 1,
                            price: item.price,
                            mrp: item.mrp,
                            costPrice: item.costPrice,
                          );
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: Text(
                        "₹${(item.price * item.qty).toStringAsFixed(1)}",
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "TOTAL AMOUNT",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Rs ${total.toStringAsFixed(1)}",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: GrovioColors.primaryGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              if (!_isPaid)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _confirmPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                    ),
                    child: Text("CONFIRM PAYMENT (Rs $total)"),
                  ),
                )
              else
                Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        if (billItems.isEmpty) return;
                        final order = GrovioOrder(
                          id: "OFF_${DateTime.now().millisecondsSinceEpoch % 100000}",
                          date: DateTime.now(),
                          items: List.from(billItems),
                          total: total,
                          totalSavings: _calculateTotalSavings(),
                          status: "DELIVERED",
                          paymentMethod: "WhatsApp",
                          customerName: _customerNameController.text.isEmpty
                              ? "Guest"
                              : _customerNameController.text,
                          customerPhone: _customerPhoneController.text.isEmpty
                              ? "N/A"
                              : _customerPhoneController.text,
                          customerAddress: "Store",
                        );
                        await GrovioFirestore.saveOfflineBill(order);
                        await GrovioFirestore.decrementStock(order.items);
                        await _sendBillToWhatsApp(order);
                        _resetBilling();
                      },
                      icon: const Icon(Icons.chat, color: Colors.green),
                    ),
                    IconButton(
                      onPressed: () async {
                        if (billItems.isEmpty) return;
                        final order = GrovioOrder(
                          id: "OFF_${DateTime.now().millisecondsSinceEpoch % 100000}",
                          date: DateTime.now(),
                          items: List.from(billItems),
                          total: total,
                          totalSavings: _calculateTotalSavings(),
                          status: "DELIVERED",
                          paymentMethod: "PDF",
                          customerName: _customerNameController.text.isEmpty
                              ? "Guest"
                              : _customerNameController.text,
                          customerPhone: _customerPhoneController.text.isEmpty
                              ? "N/A"
                              : _customerPhoneController.text,
                          customerAddress: "Store",
                        );
                        await GrovioFirestore.saveOfflineBill(order);
                        await GrovioFirestore.decrementStock(order.items);
                        await _sharePdf(order);
                        _resetBilling();
                      },
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _printReceipt,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GrovioColors.primaryGreen,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("PRINT & SAVE"),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class OrdersManagerPage extends StatelessWidget {
  const OrdersManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            labelColor: GrovioColors.primaryGreen,
            indicatorColor: GrovioColors.primaryGreen,
            tabs: [
              Tab(text: "NEW"),
              Tab(text: "ACTIVE"),
              Tab(text: "PAST"),
            ],
          ),
          Expanded(
            child: StreamBuilder<List<GrovioOrder>>(
              stream: GrovioFirestore.getOrders(),
              builder: (context, snapshot) {
                final allOrders = snapshot.data ?? [];
                allOrders.sort((a, b) => b.date.compareTo(a.date));
                return TabBarView(
                  children: [
                    _buildOrderList(
                      allOrders.where((o) => o.status == "PLACED").toList(),
                    ),
                    _buildOrderList(
                      allOrders
                          .where(
                            (o) => [
                              "ACCEPTED",
                              "PACKING",
                              "OUT_FOR_DELIVERY",
                              "READY",
                            ].contains(o.status),
                          )
                          .toList(),
                    ),
                    _buildOrderList(
                      allOrders.where((o) => o.status == "DELIVERED").toList(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderList(List<GrovioOrder> orders) {
    if (orders.isEmpty) return const Center(child: Text("No orders found"));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      itemBuilder: (context, index) => _OrderActionCard(order: orders[index]),
    );
  }
}

class _OrderActionCard extends StatelessWidget {
  final GrovioOrder order;
  const _OrderActionCard({required this.order});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          "ORDER #${order.id}",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Builder(
                          builder: (context) {
                            final pm = order.paymentMethod.toUpperCase();
                            final isCash = pm.contains("CASH") ||
                                pm.contains("COD") ||
                                order.paymentMethod == "Cash on Delivery";
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isCash
                                    ? Colors.green.shade50
                                    : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isCash
                                      ? Colors.green.shade200
                                      : Colors.blue.shade200,
                                ),
                              ),
                              child: Text(
                                isCash ? "💵 CASH ON DELIVERY" : "💳 UPI",
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isCash
                                      ? Colors.green.shade900
                                      : Colors.blue.shade900,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    Text(
                      "${order.date.day}/${order.date.month} ${order.date.hour}:${order.date.minute.toString().padLeft(2, '0')}",
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                _statusBadge(order.status),
              ],
            ),
            const Divider(height: 24),
            ...order.items.map(
              (it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "• ${it.name}${it.unit.isNotEmpty ? ' (${it.unit})' : ''}",
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      "x${it.qty} = ₹${it.price * it.qty}",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "${order.customerName} | ${order.customerPhone}",
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const Divider(height: 32),
            _buildStatusTracker(order.status),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  "₹${order.total}",
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: GrovioColors.primaryGreen,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () async {
                    try {
                      await GrovioPrinter.printInvoice(order);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  },
                  icon: const Icon(Icons.print, color: Colors.blue),
                ),
                const SizedBox(width: 8),
                if (order.status == "DELIVERED" && !order.isSettled)
                  ElevatedButton.icon(
                    onPressed: () => GrovioFirestore.settleOrder(order.id),
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text("SETTLE CASH"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  )
                else
                  _buildNextActionButton(order),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTracker(String status) {
    int step = 0;
    if (status == "ACCEPTED") {
      step = 1;
    } else if (status == "PACKING") {
      step = 2;
    } else if (status == "READY" || status == "OUT_FOR_DELIVERY") {
      step = 3;
    } else if (status == "DELIVERED") {
      step = 4;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _statusStep(Icons.assignment_turned_in, "Placed", step >= 0),
        _statusStep(Icons.inventory_2, "Packed", step >= 2),
        _statusStep(Icons.delivery_dining, "On Way", step >= 3),
        _statusStep(Icons.check_circle, "Done", step >= 4),
      ],
    );
  }

  Widget _statusStep(IconData icon, String label, bool active) => Column(
    children: [
      Icon(
        icon,
        color: active ? GrovioColors.primaryGreen : Colors.grey.shade300,
        size: 18,
      ),
      Text(
        label,
        style: TextStyle(
          fontSize: 8,
          color: active ? Colors.black : Colors.grey,
        ),
      ),
    ],
  );
  Widget _statusBadge(String s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.blue.withAlpha(20),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      s.replaceAll("_", " "),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: Colors.blue,
      ),
    ),
  );
  Widget _buildNextActionButton(GrovioOrder order) {
    String label = "";
    String next = "";
    Color col = GrovioColors.primaryGreen;
    switch (order.status) {
      case "PLACED":
        label = "ACCEPT";
        next = "ACCEPTED";
        break;
      case "ACCEPTED":
        label = "PACK";
        next = "PACKING";
        break;
      case "PACKING":
        label = "READY";
        next = "READY";
        col = GrovioColors.secondaryOrange;
        break;
      case "READY":
        label = "OUT";
        next = "OUT_FOR_DELIVERY";
        col = Colors.blue;
        break;
      case "OUT_FOR_DELIVERY":
        label = "DONE";
        next = "DELIVERED";
        col = Colors.black;
        break;
      default:
        return const Icon(Icons.check_circle, color: Colors.green);
    }
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: col,
        foregroundColor: Colors.white,
      ),
      onPressed: () {
        GrovioFirestore.updateOrderStatus(order.id, next);
        if (order.status == "PLACED") {
          GrovioFirestore.decrementStock(order.items);
        }
      },
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class InventoryManagerPage extends StatefulWidget {
  const InventoryManagerPage({super.key});
  @override
  State<InventoryManagerPage> createState() => _InventoryManagerPageState();
}

class _InventoryManagerPageState extends State<InventoryManagerPage> {
  String searchQuery = "";
  String selectedCategory = "cat_all";

  void _showAddProductDialog(
    BuildContext context, {
    String? prefilledBarcode,
    GroceryItem? existingItem,
  }) {
    final name = TextEditingController(text: existingItem?.names["en"]);
    final price = TextEditingController(text: existingItem?.price.toString());
    final mrp = TextEditingController(text: existingItem?.mrp.toString());
    final cost = TextEditingController(
      text: existingItem?.costPrice.toString(),
    );
    final unit = TextEditingController(text: existingItem?.unit);
    final barcode = TextEditingController(
      text: prefilledBarcode ?? existingItem?.barcode,
    );
    final qty = TextEditingController(
      text: existingItem?.stockQty.toString() ?? "10",
    );
    final imgUrl = TextEditingController(text: existingItem?.imageUrl);
    final desc = TextEditingController(text: existingItem?.description);
    String selectedCat = existingItem?.category ?? GrovioDatabase.categories[1];
    File? pickedImage;
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  existingItem == null ? "Add Product" : "Edit Product",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    final img = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                    );
                    if (img != null) {
                      setModalState(() => pickedImage = File(img.path));
                    }
                  },
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: pickedImage != null
                        ? Image.file(pickedImage!, fit: BoxFit.cover)
                        : (existingItem != null
                              ? Image.network(
                                  existingItem.imageUrl,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(Icons.add_a_photo)),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: barcode,
                  decoration: InputDecoration(
                    labelText: "Barcode",
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () {
                        final MobileScannerController scannerController =
                            MobileScannerController(
                              detectionSpeed: DetectionSpeed.noDuplicates,
                            );
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (context) => SizedBox(
                            height: MediaQuery.of(context).size.height * 0.7,
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        "Scan Barcode",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed:
                                            () =>
                                                scannerController.toggleTorch(),
                                        icon: ValueListenableBuilder<
                                          MobileScannerState
                                        >(
                                          valueListenable: scannerController,
                                          builder: (context, state, child) {
                                            return Icon(
                                              state.torchState == TorchState.on
                                                  ? Icons.flash_on
                                                  : Icons.flash_off,
                                              color: GrovioColors.primaryGreen,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Stack(
                                    children: [
                                      MobileScanner(
                                        controller: scannerController,
                                        onDetect: (capture) {
                                          final barcodes = capture.barcodes;
                                          if (barcodes.isNotEmpty) {
                                            final code = barcodes.first.rawValue;
                                            if (code != null) {
                                              barcode.text = code;
                                              scannerController.dispose();
                                              Navigator.pop(context);
                                            }
                                          }
                                        },
                                      ),
                                      Center(
                                        child: Container(
                                          width: 250,
                                          height: 150,
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                      const Positioned(
                                        bottom: 20,
                                        left: 0,
                                        right: 0,
                                        child: Center(
                                          child: Text(
                                            "Keep barcode inside the box\nUse flash for better result",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white,
                                              backgroundColor: Colors.black54,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).then((_) => scannerController.dispose());
                      },
                    ),
                  ),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: "Name"),
                ),
                TextField(
                  controller: imgUrl,
                  decoration: const InputDecoration(labelText: "Image URL"),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedCat,
                  items: GrovioDatabase.categories
                      .skip(1)
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(GrovioStrings.get(c)),
                          ))
                      .toList(),
                  selectedItemBuilder: (context) {
                    return GrovioDatabase.categories.skip(1).map((c) {
                      return Text(GrovioStrings.get(c));
                    }).toList();
                  },
                  onChanged: (v) => selectedCat = v!,
                  decoration: const InputDecoration(labelText: "Category"),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: price,
                        decoration: const InputDecoration(labelText: "Price"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: mrp,
                        decoration: const InputDecoration(labelText: "MRP"),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: unit,
                        decoration: const InputDecoration(labelText: "Unit"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: qty,
                        decoration: const InputDecoration(labelText: "Stock"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (isUploading)
                  const CircularProgressIndicator()
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        setModalState(() => isUploading = true);
                        String finalUrl = imgUrl.text;
                        if (pickedImage != null) {
                          final ref = FirebaseStorage.instance.ref().child(
                            'products/${DateTime.now().millisecondsSinceEpoch}.jpg',
                          );
                          await ref.putFile(pickedImage!);
                          finalUrl = await ref.getDownloadURL();
                        }
                        final item = GroceryItem(
                          id:
                              existingItem?.id ??
                              "custom_${DateTime.now().millisecondsSinceEpoch}",
                          names: {"en": name.text, "hi": name.text},
                          category: selectedCat,
                          price: double.tryParse(price.text) ?? 0,
                          mrp: double.tryParse(mrp.text) ?? 0,
                          costPrice: double.tryParse(cost.text) ?? 0,
                          unit: unit.text,
                          barcode: barcode.text,
                          description: desc.text,
                          stockQty: int.tryParse(qty.text) ?? 0,
                          imageUrl: finalUrl,
                        );
                        await GrovioFirestore.placeCustomProduct(item);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text("SAVE"),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => searchQuery = v),
                      decoration: const InputDecoration(
                        hintText: "Search items...",
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _showAddProductDialog(context),
                    icon: const Icon(
                      Icons.add_box,
                      color: GrovioColors.primaryGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: GrovioDatabase.categories
                            .map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    GrovioStrings.get(c),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  selected: selectedCategory == c,
                                  onSelected: (v) =>
                                      setState(() => selectedCategory = c),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  StreamBuilder<List<GroceryItem>>(
                    stream: GrovioFirestore.getProducts(category: "cat_all", limit: 2000),
                    builder: (context, snap) {
                      final count = snap.data?.length ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: GrovioColors.primaryGreen.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "Total: $count",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: GrovioColors.primaryGreen,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<GroceryItem>>(
            stream: GrovioFirestore.getProducts(
              category: selectedCategory,
              limit: 1000, // Increased to show everything
            ),
            builder: (context, snapshot) {
              var items = snapshot.data ?? [];
              if (searchQuery.isNotEmpty) {
                items = items
                    .where(
                      (it) => it.name.toLowerCase().contains(
                        searchQuery.toLowerCase(),
                      ),
                    )
                    .toList();
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    leading: Image.network(
                      item.imageUrl,
                      width: 40,
                      cacheWidth: 100,
                    ),
                    title: Text(item.name),
                    subtitle: Text("Stock: ${item.stockQty}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showAddProductDialog(
                            context,
                            existingItem: item,
                          ),
                        ),
                        Switch(
                          value: item.inStock,
                          onChanged: (v) =>
                              GrovioFirestore.updateStock(item.id, v),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class StoreInsightsPage extends StatelessWidget {
  const StoreInsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Earnings & Insights"),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<GrovioOrder>>(
        stream: GrovioFirestore.getOrders(),
        builder: (context, onlineSnap) {
          return StreamBuilder<List<GrovioOrder>>(
            stream: GrovioFirestore.getOfflineBills(),
            builder: (context, offlineSnap) {
              return StreamBuilder<List<GrovioExpense>>(
                stream: GrovioFirestore.getExpenses(),
                builder: (context, expenseSnap) {
                  final online = onlineSnap.data ?? [];
                  final offline = offlineSnap.data ?? [];
                  final expenses = expenseSnap.data ?? [];

                  final delivered =
                      online.where((o) => o.status == "DELIVERED").toList();
                  final allTransactions = [...delivered, ...offline];

                  double totalRev = allTransactions.fold(
                    0.0,
                    (sum, o) => sum + o.total,
                  );
                  double todayRev = allTransactions
                      .where((o) => _isToday(o.date))
                      .fold(0.0, (sum, o) => sum + o.total);

                  double totalExp = expenses.fold(
                    0.0,
                    (sum, e) => sum + e.amount,
                  );

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildEarningsHeader(totalRev, todayRev, totalRev - totalExp),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _detailStatCard(
                              "Online Revenue",
                              "₹${delivered.fold(0.0, (sum, o) => sum + o.total).toStringAsFixed(1)}",
                              Icons.cloud_done_outlined,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _detailStatCard(
                              "Offline Revenue",
                              "₹${offline.fold(0.0, (sum, o) => sum + o.total).toStringAsFixed(1)}",
                              Icons.storefront_outlined,
                              Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildUsageBrief(),
                      const SizedBox(height: 20),
                      _buildGCPBillingCard(),
                      const SizedBox(height: 20),
                      const Text(
                        "QUOTA USAGE",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildUsagePieChart(),
                      const SizedBox(height: 20),
                      _buildQuickActions(context),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Widget _buildEarningsHeader(double total, double today, double profit) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [GrovioColors.primaryGreen, Color(0xFF1B5E20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: GrovioColors.primaryGreen.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            "TOTAL REVENUE",
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            "₹${total.toStringAsFixed(2)}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(color: Colors.white24, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _headerStat("Today", "₹${today.toStringAsFixed(2)}"),
              _headerStat("Net Position", "₹${profit.toStringAsFixed(2)}"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _detailStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageBrief() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "FIRESTORE READS (QUOTA)",
                style: TextStyle(color: Colors.grey, fontSize: 10),
              ),
              Text(
                "12% Used",
                style: TextStyle(color: Colors.orange.shade700, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const LinearProgressIndicator(
            value: 0.12,
            backgroundColor: Color(0xFFF0F0F0),
            color: Colors.orange,
          ),
          const SizedBox(height: 8),
          const Text(
            "Usage is high due to real-time streams.",
            style: TextStyle(color: Colors.grey, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _buildGCPBillingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "GOOGLE CLOUD BILL",
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              const Icon(Icons.account_balance, color: Colors.white24, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "₹0.00",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            "Current Plan: Spark (Free Tier)",
            style: TextStyle(color: Colors.greenAccent, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildUsagePieChart() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 30,
                sections: [
                  PieChartSectionData(
                    color: Colors.amber,
                    value: 65,
                    title: '',
                    radius: 15,
                  ),
                  PieChartSectionData(
                    color: Colors.blue,
                    value: 20,
                    title: '',
                    radius: 15,
                  ),
                  PieChartSectionData(
                    color: Colors.green,
                    value: 15,
                    title: '',
                    radius: 15,
                  ),
                ],
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legendItem("Firestore", Colors.amber),
              _legendItem("Storage", Colors.blue),
              _legendItem("Auth", Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String l, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(l, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
      ],
    ),
  );

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            context,
            "OFFLINE HISTORY",
            Icons.history,
            Colors.blue,
            const OfflineRecordsPage(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            context,
            "DEMAND REPORT",
            Icons.trending_up,
            Colors.orange,
            const DemandReportPage(),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(
    BuildContext context,
    String t,
    IconData i,
    Color c,
    Widget p,
  ) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => p)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(i, color: c),
            const SizedBox(height: 8),
            Text(
              t,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class DemandReportPage extends StatelessWidget {
  const DemandReportPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Demands")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: GrovioFirestore.getDemands(),
        builder: (context, snapshot) {
          final demands = snapshot.data ?? [];
          return ListView.builder(
            itemCount: demands.length,
            itemBuilder: (context, index) => ListTile(
              title: Text(demands[index]['name']),
              trailing: Text("${demands[index]['count']} requests"),
            ),
          );
        },
      ),
    );
  }
}

class OfflineRecordsPage extends StatelessWidget {
  const OfflineRecordsPage({super.key});

  void _showOfflineOrderDetails(BuildContext context, GrovioOrder order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "BILL #${order.id}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      "💵 PAID (OFFLINE)",
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                order.customerName.isEmpty ? "Walk-in Customer" : order.customerName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              if (order.customerPhone.isNotEmpty)
                Text(
                  order.customerPhone,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              Text(
                order.date.toString().substring(0, 16),
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
              const Divider(height: 24),
              const Text(
                "ITEMS PURCHASED:",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: order.items.length,
                  itemBuilder: (context, i) {
                    final item = order.items[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              "• ${item.name}${item.unit.isNotEmpty ? ' (${item.unit})' : ''}",
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            "₹${item.price} x ${item.qty} = ₹${(item.price * item.qty).toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 24),
              if (order.totalSavings > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Total Savings:",
                        style: TextStyle(color: Colors.green),
                      ),
                      Text(
                        "₹${order.totalSavings.toStringAsFixed(2)}",
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "TOTAL AMOUNT:",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    "₹${order.total.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: GrovioColors.primaryGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await GrovioPrinter.printInvoice(order);
                    } catch (e) {
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  },
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text("PRINT RECEIPT"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: GrovioColors.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Offline Records"),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<GrovioOrder>>(
        stream: GrovioFirestore.getOfflineBills(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final bills = snapshot.data ?? [];
          if (bills.isEmpty) {
            return const Center(child: Text("No offline records found"));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bills.length,
            itemBuilder: (context, index) {
              final b = bills[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  onTap: () => _showOfflineOrderDetails(context, b),
                  leading: CircleAvatar(
                    backgroundColor:
                        GrovioColors.primaryGreen.withAlpha(20),
                    child: const Icon(
                      Icons.receipt_long,
                      color: GrovioColors.primaryGreen,
                    ),
                  ),
                  title: Text(
                    b.customerName.isEmpty ? "Walk-in Customer" : b.customerName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.date.toString().substring(0, 16)),
                      Text(
                        "${b.items.length} item(s) • Tap to view details",
                        style: const TextStyle(
                          color: GrovioColors.primaryGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "₹${b.total.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: GrovioColors.primaryGreen,
                          fontSize: 16,
                        ),
                      ),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class GrovioPrinter {
  static Future<void> printInvoice(GrovioOrder order) async {
    if (!await PrintBluetoothThermal.connectionStatus) {
      throw Exception("Printer not connected");
    }
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];
    bytes += gen.text(
      "GROVIO SUPERMART",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += gen.text("Order: #${order.id}");
    bytes += gen.text("Cust: ${order.customerName}");
    bytes += gen.text("--------------------------------");
    for (var it in order.items) {
      bytes += gen.text("${it.name} x${it.qty} : ${it.price * it.qty}");
    }
    bytes += gen.text("--------------------------------");
    bytes += gen.text(
      "TOTAL: RS ${order.total}",
      styles: const PosStyles(bold: true),
    );
    if (order.totalSavings > 0) {
      bytes += gen.text(
        "TOTAL SAVED: RS ${order.totalSavings}",
        styles: const PosStyles(bold: true),
      );
    }
    bytes += gen.text("--------------------------------");
    bytes += gen.text(
      "THANK YOU FOR VISITING!",
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += gen.feed(2);
    bytes += gen.cut();
    await PrintBluetoothThermal.writeBytes(bytes);
  }
}

class StoreFeedbackPage extends StatelessWidget {
  const StoreFeedbackPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: GrovioFirestore.getFeedbacks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final feedbacks = snapshot.data ?? [];
        if (feedbacks.isEmpty) {
          return const Center(child: Text("No feedback received yet"));
        }
        return ListView.builder(
          itemCount: feedbacks.length,
          itemBuilder: (context, index) {
            final f = feedbacks[index];
            final rating = (f['rating'] ?? 0).toDouble();
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          f['customerName'] ?? "Unknown",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              i < rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(f['feedback'] ?? ""),
                    if (f['reply'] != null)
                      Text(
                        "Reply: ${f['reply']}",
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      )
                    else
                      TextButton(
                        onPressed: () => _showReplyDialog(context, f['id']),
                        child: const Text("REPLY"),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showReplyDialog(BuildContext context, String feedbackId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reply"),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () async {
              await GrovioFirestore.replyToFeedback(
                feedbackId,
                controller.text.trim(),
              );
              if (!context.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("Reply sent!")));
            },
            child: const Text("SEND"),
          ),
        ],
      ),
    );
  }
}
