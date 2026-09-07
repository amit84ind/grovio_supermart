import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'grovio_shared.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await GrovioConfig.initFirebase();
  } catch (e) {
    debugPrint("Firebase init failed: $e");
  }
  runApp(const GrovioDriverApp());
}

class GrovioDriverApp extends StatelessWidget {
  const GrovioDriverApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grovio Delivery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1A237E),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const DriverDashboard(),
    );
  }
}

class DriverDashboard extends StatelessWidget {
  const DriverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        title: const Text(
          "DELIVERY PARTNER",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: const Color(0xFF1A237E),
        centerTitle: true,
        elevation: 4,
      ),
      body: StreamBuilder<List<GrovioOrder>>(
        stream: GrovioFirestore.getOrders(),
        builder: (context, snapshot) {
          final allOrders = snapshot.data ?? [];
          final activeDeliveries = allOrders
              .where(
                (o) => o.status == "READY" || o.status == "OUT_FOR_DELIVERY",
              )
              .toList();

          if (activeDeliveries.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.delivery_dining_outlined,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No orders to deliver right now",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: activeDeliveries.length,
            itemBuilder: (context, index) {
              final order = activeDeliveries[index];
              bool isOut = order.status == "OUT_FOR_DELIVERY";

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "ORDER #${order.id}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isOut
                                  ? Colors.blue.shade50
                                  : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              order.status,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isOut ? Colors.blue : Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_pin_circle,
                            color: Color(0xFF1A237E),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              order.customerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.phone, color: Colors.green),
                            onPressed: () => launchUrl(
                              Uri.parse("tel:${order.customerPhone}"),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 28),
                        child: Text(
                          order.customerAddress,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _navigate(
                                order.lat,
                                order.lng,
                                order.customerAddress,
                              ),
                              icon: const Icon(Icons.navigation, size: 18),
                              label: const Text(
                                "NAVIGATE",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  _handleDeliveryAction(context, order, isOut),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isOut
                                    ? Colors.green.shade700
                                    : const Color(0xFF1A237E),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                isOut ? "MARK DELIVERED" : "START DELIVERY",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
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

  void _handleDeliveryAction(
    BuildContext context,
    GrovioOrder order,
    bool isOut,
  ) async {
    if (!isOut) {
      GrovioFirestore.updateOrderStatus(order.id, "OUT_FOR_DELIVERY");
      return;
    }

    // Step 1: Verify OTP
    final TextEditingController otpController = TextEditingController();
    final bool? otpVerified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Verify Delivery OTP"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Ask customer for the 4-digit OTP shown in their app."),
            const SizedBox(height: 16),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: "Enter OTP",
                counterText: "",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () {
              if (otpController.text == order.otp) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("Incorrect OTP!")));
              }
            },
            child: const Text("VERIFY"),
          ),
        ],
      ),
    );

    if (otpVerified != true) return;
    if (!context.mounted) return;

    // Step 2: Capture Photo (Existing feature)
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 800,
      imageQuality: 50,
    );

    if (image == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Photo is required for delivery proof!"),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;

    // Step 3: Select Payment Mode (New)
    String? finalPaymentMode = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("How was payment received?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, "CASH"),
            child: const Text("CASH"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, "UPI QR"),
            child: const Text("UPI QR"),
          ),
        ],
      ),
    );

    if (finalPaymentMode == null) return;
    if (!context.mounted) return;

    // Step 4: Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Step 5: Upload to Storage
      final ref = FirebaseStorage.instance.ref().child(
        'delivery_proofs/${order.id}.jpg',
      );
      await ref.putFile(File(image.path));
      final photoUrl = await ref.getDownloadURL();

      // Step 6: Update Firestore
      bool isSettled = (finalPaymentMode == "UPI QR");
      await GrovioFirestore.markAsDelivered(
        order.id,
        photoUrl,
        actualPaymentMode: finalPaymentMode,
        isSettled: isSettled,
      );

      if (context.mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Order Delivered Successfully!")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _navigate(double? lat, double? lng, String address) async {
    Uri uri;
    if (lat != null && lng != null) {
      uri = Uri.parse("google.navigation:q=$lat,$lng");
    } else {
      uri = Uri.parse(
        "https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}",
      );
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        final webUri = Uri.parse(
          "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
        );
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("Could not launch maps: $e");
    }
  }
}
