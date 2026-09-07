import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- BRAND IDENTITY ---
class GrovioColors {
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color secondaryOrange = Color(0xFFFF9800);
  static const Color backgroundWhite = Colors.white;
}

// --- CONFIGURATION ---
class GrovioConfig {
  static const String storeUpiId = "70684879@axl";
  static const String storeName = "Abhishek Singh";
}

// --- DATA MODEL ---
class GroceryItem {
  final String id;
  final Map<String, String> names;
  final String category;
  final double price;
  final double mrp;
  final String unit;
  final String imageUrl;
  final String barcode;
  final String description;
  bool inStock;
  int stockQty;

  GroceryItem({
    required this.id,
    required this.names,
    required this.category,
    required this.price,
    required this.mrp,
    required this.unit,
    required this.imageUrl,
    required this.barcode,
    this.description = "",
    this.inStock = true,
    this.stockQty = 0,
  });

  String get name => names[GrovioStrings.lang] ?? names["en"] ?? "Item";
  int get discountPercent =>
      mrp > 0 ? (((mrp - price) / mrp) * 100).round() : 0;

  Map<String, dynamic> toMap() => {
    'id': id,
    'names': names,
    'category': category,
    'price': price,
    'mrp': mrp,
    'unit': unit,
    'imageUrl': imageUrl,
    'barcode': barcode,
    'description': description,
    'inStock': inStock,
    'stockQty': stockQty,
  };

  factory GroceryItem.fromMap(Map<String, dynamic> map) => GroceryItem(
    id: map['id'] ?? "",
    names: Map<String, String>.from(map['names'] ?? {"en": "Item"}),
    category: map['category'] ?? "",
    price: (map['price'] ?? 0).toDouble(),
    mrp: (map['mrp'] ?? 0).toDouble(),
    unit: map['unit'] ?? "",
    imageUrl: map['imageUrl'] ?? "",
    barcode: map['barcode'] ?? "",
    description: map['description'] ?? "",
    inStock: map['inStock'] ?? true,
    stockQty: map['stockQty'] ?? 0,
  );
}

// --- FIRESTORE SERVICE ---
class GrovioFirestore {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // Store Methods
  static Stream<List<GroceryItem>> getProducts() {
    return _db
        .collection('products')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => GroceryItem.fromMap(doc.data())).toList(),
        );
  }

  static Future<void> updateStock(String id, bool inStock) {
    return _db.collection('products').doc(id).update({'inStock': inStock});
  }

  static Future<void> updateQuantity(String id, int newQty) {
    return _db.collection('products').doc(id).update({
      'stockQty': newQty,
      'inStock': newQty > 0,
    });
  }

  static Future<void> decrementStock(List<OrderItem> items) async {
    for (var item in items) {
      final docRef = _db.collection('products').doc(item.itemId);
      try {
        await _db.runTransaction((transaction) async {
          DocumentSnapshot snapshot = await transaction.get(docRef);
          if (snapshot.exists) {
            int currentStock =
                (snapshot.data() as Map<String, dynamic>)['stockQty'] ?? 0;
            int newQty = currentStock - item.qty;
            transaction.update(docRef, {
              'stockQty': newQty < 0 ? 0 : newQty,
              'inStock': newQty > 0,
            });
          }
        });
      } catch (e) {
        debugPrint("Error decrementing stock for ${item.itemId}: $e");
      }
    }
  }

  static Future<void> placeCustomProduct(GroceryItem item) {
    return _db.collection('products').doc(item.id).set(item.toMap());
  }

  static Future<void> deleteProduct(String id) {
    return _db.collection('products').doc(id).delete();
  }

  static Future<void> deleteAllProducts() async {
    var snapshots = await _db.collection('products').get();
    for (var doc in snapshots.docs) {
      await doc.reference.delete();
    }
  }

  static Future<void> placeOrder(GrovioOrder order) {
    return _db.collection('orders').doc(order.id).set(order.toMap());
  }

  static Stream<List<GrovioOrder>> getOrders({String? customerPhone}) {
    Query query = _db.collection('orders');
    if (customerPhone != null) {
      query = query.where('customerPhone', isEqualTo: customerPhone);
    }
    return query.snapshots().map(
      (snap) => snap.docs
          .map((doc) => GrovioOrder.fromMap(doc.data() as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<void> updateOrderStatus(String id, String status) {
    return _db.collection('orders').doc(id).update({'status': status});
  }

  static Future<void> markAsDelivered(
    String id,
    String photoUrl, {
    String? actualPaymentMode,
    bool isSettled = false,
  }) {
    return _db.collection('orders').doc(id).update({
      'status': 'DELIVERED',
      'deliveryPhotoUrl': photoUrl,
      'deliveredAt': DateTime.now().toIso8601String(),
      'actualPaymentMode': actualPaymentMode,
      'isSettled': isSettled,
    });
  }

  static Future<void> settleOrder(String id) {
    return _db.collection('orders').doc(id).update({'isSettled': true});
  }

  static Future<void> deleteOrder(String id) {
    return _db.collection('orders').doc(id).delete();
  }

  static Future<void> cleanupOldPhotos() async {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final query = await _db
        .collection('orders')
        .where('status', isEqualTo: 'DELIVERED')
        .get();

    for (var doc in query.docs) {
      final data = doc.data();
      if (data['deliveredAt'] != null && data['deliveryPhotoUrl'] != null) {
        DateTime deliveredAt = DateTime.parse(data['deliveredAt']);
        if (deliveredAt.isBefore(sevenDaysAgo)) {
          await doc.reference.update({'deliveryPhotoUrl': null});
        }
      }
    }
  }

  static Future<void> saveOfflineBill(GrovioOrder order) {
    return _db.collection('offline_bills').doc(order.id).set(order.toMap());
  }

  static Stream<List<GrovioOrder>> getOfflineBills() {
    return _db
        .collection('offline_bills')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => GrovioOrder.fromMap(doc.data())).toList(),
        );
  }

  static Future<void> suggestProduct(String name) async {
    final cleanName = name.trim().toLowerCase();
    if (cleanName.isEmpty) return;
    final docRef = _db.collection('demands').doc(cleanName);

    return _db.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        transaction.set(docRef, {
          'name': name.trim(),
          'count': 1,
          'lastRequested': DateTime.now().toIso8601String(),
        });
      } else {
        int newCount = (snapshot.data() as Map<String, dynamic>)['count'] + 1;
        transaction.update(docRef, {
          'count': newCount,
          'lastRequested': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  static Stream<List<Map<String, dynamic>>> getDemands() {
    return _db
        .collection('demands')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()).toList());
  }
}

// --- ORDER MODEL ---
class GrovioOrder {
  final String id;
  final DateTime date;
  final List<OrderItem> items;
  final double total;
  final double totalSavings;
  final String status;
  final String paymentMethod;
  final String? actualPaymentMode;
  final String otp;
  final bool isSettled;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final double? lat;
  final double? lng;
  final String? deliveryPhotoUrl;
  final DateTime? deliveredAt;

  GrovioOrder({
    required this.id,
    required this.date,
    required this.items,
    required this.total,
    required this.status,
    required this.paymentMethod,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    this.totalSavings = 0,
    this.actualPaymentMode,
    this.otp = "",
    this.isSettled = false,
    this.lat,
    this.lng,
    this.deliveryPhotoUrl,
    this.deliveredAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date.toIso8601String(),
    'items': items.map((i) => i.toMap()).toList(),
    'total': total,
    'totalSavings': totalSavings,
    'status': status,
    'paymentMethod': paymentMethod,
    'actualPaymentMode': actualPaymentMode,
    'otp': otp,
    'isSettled': isSettled,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'customerAddress': customerAddress,
    'lat': lat,
    'lng': lng,
    'deliveryPhotoUrl': deliveryPhotoUrl,
    'deliveredAt': deliveredAt?.toIso8601String(),
  };

  factory GrovioOrder.fromMap(Map<String, dynamic> map) => GrovioOrder(
    id: map['id'] ?? "",
    date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()),
    items: (map['items'] as List? ?? [])
        .map((i) => OrderItem.fromMap(Map<String, dynamic>.from(i)))
        .toList(),
    total: (map['total'] ?? 0).toDouble(),
    totalSavings: (map['totalSavings'] ?? 0).toDouble(),
    status: map['status'] ?? "PLACED",
    paymentMethod: map['paymentMethod'] ?? "COD",
    actualPaymentMode: map['actualPaymentMode'],
    otp: map['otp'] ?? "",
    isSettled: map['isSettled'] ?? false,
    customerName: map['customerName'] ?? "",
    customerPhone: map['customerPhone'] ?? "",
    customerAddress: map['customerAddress'] ?? "",
    lat: map['lat']?.toDouble(),
    lng: map['lng']?.toDouble(),
    deliveryPhotoUrl: map['deliveryPhotoUrl'],
    deliveredAt: map['deliveredAt'] != null
        ? DateTime.parse(map['deliveredAt'])
        : null,
  );
}

class OrderItem {
  final String itemId;
  final String name;
  final String unit;
  final int qty;
  final double price;
  final double mrp;

  OrderItem({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.qty,
    required this.price,
    this.mrp = 0,
  });
  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'name': name,
    'unit': unit,
    'qty': qty,
    'price': price,
    'mrp': mrp,
  };
  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
    itemId: map['itemId'] ?? "",
    name: map['name'] ?? "",
    unit: map['unit'] ?? "",
    qty: map['qty'] ?? 0,
    price: (map['price'] ?? 0).toDouble(),
    mrp: (map['mrp'] ?? 0).toDouble(),
  );
}

class GrovioStrings {
  static String lang = "en";
  static final Map<String, Map<String, String>> _data = {
    "en": {
      "app_name": "Grovio SuperMart",
      "home": "Home",
      "search_hint": "Search...",
      "my_profile": "My Profile",
      "my_orders": "My Orders",
      "logout": "Logout",
      "home_delivery": "Home Delivery",
      "add": "ADD",
      "view_cart": "VIEW CART",
      "checkout": "Checkout",
      "place_order": "PLACE ORDER",
      "cash_on_delivery": "Cash on Delivery",
      "upi_payment": "UPI Payment",
      "order_success": "Order Placed!",
      "estimated_delivery": "Delivery: Today Evening",
      "use_location": "Use My Location",
      "save_start": "SAVE & START",
      "registration_title": "Registration",
      "welcome": "Welcome!",
      "name": "Name",
      "phone": "Mobile",
      "address": "Address",
      "saved_addresses": "Saved Addresses",
      "add_new_address": "Add New Address",
      "cust_care": "Customer Care",
      "wa_support": "WhatsApp Support",
      "label": "Label",
      "save_address": "Save Address",
      "cancel": "Cancel",
      "save": "Save",
      "edit_order_title": "Edit Order?",
      "you_saved": "You saved",
      "total_savings": "Total Savings",
      "cat_all": "All",
      "cat_dairy_bread": "Dairy & Bread",
      "cat_cold_drinks": "Cold Drinks & Juices",
      "cat_munchies": "Snacks & Munchies",
      "cat_dry_fruits": "Dry Fruits",
      "cat_breakfast": "Breakfast & Instant Food",
      "cat_bakery": "Sweet, Bakery & Biscuits",
      "cat_beverages": "Tea, Coffee & Milk Drinks",
      "cat_staples": "Atta, Rice & Dal",
      "cat_masala": "Masala, Oil & More",
      "cat_sauces": "Sauces & Spreads",
      "cat_baby": "Baby Care",
      "cat_pharma": "Pharma & Wellness",
      "cat_cleaning": "Cleaning Essentials",
      "cat_personal": "Personal Care",
      "cat_feminine": "Feminine",
      "cat_kitchen": "Drinkware, Kitchen & Dining",
      "cat_household": "Household",
    },
    "hi": {
      "app_name": "ग्रोवियो सुपरमार्ट",
      "home": "होम",
      "search_hint": "खोजें...",
      "my_profile": "प्रोफाइल",
      "my_orders": "मेरे ऑर्डर",
      "logout": "लॉगआउट",
      "home_delivery": "होम डिलीवरी",
      "add": "जोड़ें",
      "view_cart": "कार्ट देखें",
      "checkout": "चेकआउट",
      "place_order": "ऑर्डर दें",
      "cash_on_delivery": "कैश ऑन डिलीवरी",
      "upi_payment": "UPI भुगतान",
      "order_success": "ऑर्डर हो गया!",
      "estimated_delivery": "डिलीवरी: आज शाम",
      "use_location": "लोकेशन का उपयोग करें",
      "save_start": "सहेजें",
      "registration_title": "पंजीकरण",
      "welcome": "स्वागत है!",
      "name": "नाम",
      "phone": "मोबाइल",
      "address": "पता",
      "saved_addresses": "सेव किए गए पते",
      "add_new_address": "नया पता जोड़ें",
      "cust_care": "ग्राहक सेवा",
      "wa_support": "वॉट्सऐप सहायता",
      "label": "नाम (जैसे घर/ऑफिस)",
      "save_address": "पता सहेजें",
      "cancel": "रद्द करें",
      "save": "सहेजें",
      "edit_order_title": "ऑर्डर बदलें?",
      "you_saved": "आपने बचाए",
      "total_savings": "कुल बचत",
      "cat_all": "सभी",
      "cat_dairy_bread": "डेयरी और ब्रेड",
      "cat_cold_drinks": "कोल्ड ड्रिंक्स और जूस",
      "cat_munchies": "स्नैक्स और नमकीन",
      "cat_dry_fruits": "ड्राय फ्रूट्स",
      "cat_breakfast": "नाश्ता और इंस्टेंट फूड",
      "cat_bakery": "मिठाई और बेकरी",
      "cat_beverages": "चाय और कॉफी",
      "cat_staples": "आटा, चावल और दाल",
      "cat_masala": "मसाले और तेल",
      "cat_sauces": "सॉस और जैम",
      "cat_baby": "बच्चों का सामान",
      "cat_pharma": "दवा और स्वास्थ्य",
      "cat_cleaning": "सफाई का सामान",
      "cat_personal": "पर्सनल केयर",
      "cat_feminine": "महिलाएं",
      "cat_kitchen": "किचन और डाइनिंग",
      "cat_household": "घरेलू सामान",
    },
  };
  static String get(String key) => _data[lang]?[key] ?? key;
}

class GrovioDatabase {
  static final List<String> categories = [
    "cat_all",
    "cat_dairy_bread",
    "cat_cold_drinks",
    "cat_munchies",
    "cat_dry_fruits",
    "cat_breakfast",
    "cat_bakery",
    "cat_beverages",
    "cat_staples",
    "cat_masala",
    "cat_sauces",
    "cat_baby",
    "cat_pharma",
    "cat_cleaning",
    "cat_personal",
    "cat_feminine",
    "cat_kitchen",
    "cat_household",
  ];
  static final List<GroceryItem> allItems = [];
}
