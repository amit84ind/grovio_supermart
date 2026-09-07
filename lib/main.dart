import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:credential_manager/credential_manager.dart';
import 'grovio_shared.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Optimization for Low RAM devices
  PaintingBinding.instance.imageCache.maximumSize = 100; // Limit images in memory
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50MB max
  
  try {
    await GrovioConfig.initFirebase();
    debugPrint("Firebase initialized successfully");
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }
  runApp(const GrovioCustomerApp());
}

class CartManager {
  static Map<String, int> cartItems = {};
  static int get totalItems => cartItems.values.fold(0, (sum, q) => sum + q);
  static double totalAmount(List<GroceryItem> products) {
    double total = 0;
    // Create a map for O(1) lookup
    final productMap = {for (var p in products) p.id: p};
    cartItems.forEach((id, qty) {
      final item = productMap[id];
      if (item != null) {
        total += item.price * qty;
      }
    });
    return total;
  }
}

class UserAddress {
  final String address;
  final double lat;
  final double lng;
  final String label;

  UserAddress({
    required this.address,
    required this.lat,
    required this.lng,
    this.label = "Home",
  });

  Map<String, dynamic> toMap() => {
    'address': address,
    'lat': lat,
    'lng': lng,
    'label': label,
  };
  factory UserAddress.fromMap(Map<String, dynamic> map) => UserAddress(
    address: map['address'] ?? "",
    lat: map['lat'] ?? 0.0,
    lng: map['lng'] ?? 0.0,
    label: map['label'] ?? "Home",
  );
}

class AddressManager {
  static List<UserAddress> addresses = [];
  static int selectedIndex = 0;

  static UserAddress? get currentAddress =>
      addresses.isNotEmpty ? addresses[selectedIndex] : null;

  static Future<void> loadAddresses() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('user_addresses');
    if (data != null) {
      Iterable l = json.decode(data);
      addresses = List<UserAddress>.from(
        l.map((model) => UserAddress.fromMap(model)),
      );
    } else {
      String? oldAddress = prefs.getString('address');
      double? oldLat = prefs.getDouble('lat');
      double? oldLng = prefs.getDouble('lng');
      if (oldAddress != null && oldLat != null && oldLng != null) {
        addresses = [
          UserAddress(address: oldAddress, lat: oldLat, lng: oldLng),
        ];
        await saveAddresses();
      }
    }
    selectedIndex = prefs.getInt('selected_address_index') ?? 0;
    if (selectedIndex >= addresses.length) selectedIndex = 0;
  }

  static Future<void> saveAddresses() async {
    final prefs = await SharedPreferences.getInstance();
    String encoded = json.encode(addresses.map((a) => a.toMap()).toList());
    await prefs.setString('user_addresses', encoded);
    await prefs.setInt('selected_address_index', selectedIndex);
  }
}

class GrovioCustomerApp extends StatefulWidget {
  const GrovioCustomerApp({super.key});
  @override
  State<GrovioCustomerApp> createState() => _GrovioCustomerAppState();
}

class _GrovioCustomerAppState extends State<GrovioCustomerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLang();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    // CRITICAL for low-RAM devices
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    debugPrint("Memory Pressure: Cleared Image Cache");
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

  Future<void> _loadLang() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      GrovioStrings.lang = prefs.getString('lang') ?? 'en';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grovio SuperMart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        primaryColor: GrovioColors.primaryGreen,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutBack,
    );
    _controller.forward();
    _checkRegistration();
  }

  void _checkRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    bool isRegistered = prefs.getBool('registered') ?? false;

    // Device Migration / Zero-Tap Sign-In Logic
    if (!isRegistered) {
      try {
        final credentialManager = CredentialManager();
        final response = await credentialManager.getCredentials();
        if (response.passwordCredential != null &&
            response.passwordCredential!.password != null) {
          // If we found saved credentials, auto-login
          final parts = response.passwordCredential!.password!.split('|');
          if (parts.length >= 2) {
            await prefs.setString('name', parts[0]);
            await prefs.setString('phone', parts[1]);
            await prefs.setBool('registered', true);
            isRegistered = true;
            debugPrint("Zero-Tap: Restored user ${parts[0]}");
          }
        }
      } catch (e) {
        debugPrint("Zero-Tap: No credentials found or error: $e");
      }
    }

    await AddressManager.loadAddresses();
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) {
      if (!isRegistered) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RegistrationPage()),
        );
      } else if (AddressManager.addresses.length > 1) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AddressPickerPage()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CustomerHomePage()),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ScaleTransition(
          scale: _animation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: GrovioColors.primaryGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shopping_basket,
                  size: 80,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 30),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                    children: [
                      TextSpan(
                        text: "Grovio",
                        style: TextStyle(color: GrovioColors.primaryGreen),
                      ),
                      TextSpan(
                        text: " SuperMart",
                        style: TextStyle(color: GrovioColors.secondaryOrange),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "समय भी बचेगा, पैसा भी बचेगा –",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                "जब Grovio आपके घर पहुँचेगा",
                style: TextStyle(
                  color: GrovioColors.primaryGreen,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});
  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
  static const double shopLat = 26.490639;
  static const double shopLng = 81.805222;
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isLoadingLocation = false;
  double? _lat, _lng;

  void _changeLang(String l) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', l);
    setState(() {
      GrovioStrings.lang = l;
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      if (kIsWeb) {
        try {
          Position position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          );
          _lat = position.latitude;
          _lng = position.longitude;
          setState(() {
            _addressController.text =
                "Location (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})";
          });
        } catch (_) {
          _lat = RegistrationPage.shopLat;
          _lng = RegistrationPage.shopLng;
          setState(() {
            _addressController.text = "Grovio Store, Amethi";
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        _lat = position.latitude;
        _lng = position.longitude;
        try {
          List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );
          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            setState(() {
              _addressController.text =
                  "${place.name}, ${place.subLocality}, ${place.locality}, ${place.postalCode}";
            });
          }
        } catch (_) {
          setState(() {
            _addressController.text =
                "Location (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})";
          });
        }
      }
    } catch (e) {
      if (kIsWeb) {
        _lat = RegistrationPage.shopLat;
        _lng = RegistrationPage.shopLng;
        setState(() {
          _addressController.text = "Grovio Store, Amethi";
        });
      } else {
        _showError("Error getting location: $e");
      }
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Location Check"),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  void _submit() async {
    final navigator = Navigator.of(context);
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (name.isNotEmpty &&
        phone.length >= 10 &&
        _addressController.text.isNotEmpty) {
      if (_lat == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(GrovioStrings.get("use_location"))),
        );
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('name', name);
      await prefs.setString('phone', phone);
      AddressManager.addresses = [
        UserAddress(address: _addressController.text, lat: _lat!, lng: _lng!),
      ];
      AddressManager.selectedIndex = 0;
      await AddressManager.saveAddresses();
      await prefs.setBool('registered', true);

      // Device Migration: Save credentials to Google Password Manager / Restore API
      try {
        final credentialManager = CredentialManager();
        await credentialManager.savePasswordCredentials(
          PasswordCredential(username: name, password: "$name|$phone"),
        );
        debugPrint("Zero-Tap: Saved credentials for $name");
      } catch (e) {
        debugPrint("Zero-Tap: Failed to save: $e");
      }

      if (mounted) {
        navigator.pushReplacement(
          MaterialPageRoute(builder: (_) => const CustomerHomePage()),
        );
      }
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please fill all details")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(GrovioStrings.get("registration_title")),
        actions: [_langSelector()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            Text(
              GrovioStrings.get("welcome"),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: GrovioColors.primaryGreen,
              ),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: GrovioStrings.get("name"),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: GrovioStrings.get("phone"),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _addressController,
              readOnly: true,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: GrovioStrings.get("address"),
                border: const OutlineInputBorder(),
                hintText: "Click 'Use My Location' below",
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _getCurrentLocation,
              icon: _isLoadingLocation
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, size: 16),
              label: Text(GrovioStrings.get("use_location")),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _submit,
                child: Text(GrovioStrings.get("save_start")),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _langSelector() => PopupMenuButton<String>(
    icon: const Icon(Icons.language),
    onSelected: _changeLang,
    itemBuilder: (context) => [
      const PopupMenuItem(value: 'en', child: Text("English")),
      const PopupMenuItem(value: 'hi', child: Text("Hindi")),
    ],
  );
}

class AddressPickerPage extends StatefulWidget {
  const AddressPickerPage({super.key});
  @override
  State<AddressPickerPage> createState() => _AddressPickerPageState();
}

class _AddressPickerPageState extends State<AddressPickerPage> {
  void _changeLang(String l) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', l);
    setState(() {
      GrovioStrings.lang = l;
    });
  }

  Widget _langSelector() => PopupMenuButton<String>(
    icon: const Icon(Icons.language),
    onSelected: _changeLang,
    itemBuilder: (context) => [
      const PopupMenuItem(value: 'en', child: Text("English")),
      const PopupMenuItem(value: 'hi', child: Text("Hindi")),
    ],
  );
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          GrovioStrings.lang == 'hi' ? "अपना पता चुनें" : "Select Your Address",
        ),
        actions: [_langSelector()],
        backgroundColor: GrovioColors.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: AddressManager.addresses.length,
        itemBuilder: (context, index) {
          final addr = AddressManager.addresses[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.location_on,
                color: GrovioColors.primaryGreen,
              ),
              title: Text(
                addr.label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(addr.address),
              trailing: AddressManager.selectedIndex == index
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
              onTap: () async {
                final navigator = Navigator.of(context);
                setState(() {
                  AddressManager.selectedIndex = index;
                });
                await AddressManager.saveAddresses();
                if (!mounted) return;
                navigator.pushReplacement(
                  MaterialPageRoute(builder: (_) => const CustomerHomePage()),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});
  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  String selectedCategory = "cat_all";
  String searchQuery = "";
  String userName = "";
  String userAddress = "";
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    await AddressManager.loadAddresses();
    setState(() {
      userName = prefs.getString('name') ?? "Customer";
      userAddress = AddressManager.currentAddress?.address ?? "Select Address";
    });
  }

  void _changeLang(String l) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', l);
    setState(() {
      GrovioStrings.lang = l;
    });
  }

  Widget _langSelector() => PopupMenuButton<String>(
    icon: const Icon(Icons.language),
    onSelected: _changeLang,
    itemBuilder: (context) => [
      const PopupMenuItem(value: 'en', child: Text("English")),
      const PopupMenuItem(value: 'hi', child: Text("Hindi")),
    ],
  );
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroceryItem>>(
      stream: GrovioFirestore.getProducts(
        category: searchQuery.isEmpty ? selectedCategory : "cat_all",
        limit: 1000, // Increased to ensure all 100% items show
      ),
      builder: (context, snapshot) {
        final allProducts = snapshot.data ?? [];
        final products = allProducts.where((p) {
          bool matchesCategory = searchQuery.isNotEmpty ||
              selectedCategory == "cat_all" || 
              p.category == selectedCategory;
          bool matchesSearch = p.names.values.any((n) => n.toLowerCase().contains(searchQuery.toLowerCase())) ||
                               p.barcode.contains(searchQuery);
          return matchesCategory && matchesSearch;
        }).toList();
        return Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddressPickerPage()),
              ).then((_) => _loadData()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        "${GrovioStrings.get('home')}, $userName",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                  Text(
                    userAddress,
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            backgroundColor: GrovioColors.primaryGreen,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              _langSelector(),
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CheckoutPage(products: allProducts),
                      ),
                    ).then((_) => setState(() {})),
                    icon: const Icon(Icons.shopping_cart_outlined),
                  ),
                  if (CartManager.totalItems > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: GrovioColors.secondaryOrange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          "${CartManager.totalItems}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyProfilePage()),
                ).then((_) => _loadData()),
                icon: const Icon(Icons.person_outline),
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.white,
                child: TextField(
                  onChanged: (v) => setState(() => searchQuery = v),
                  decoration: InputDecoration(
                    hintText: GrovioStrings.get("search_hint"),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: GrovioColors.primaryGreen,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Container(
                height: 54,
                color: Colors.white,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: GrovioDatabase.categories
                      .map(
                        (cKey) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: ChoiceChip(
                            showCheckmark: false,
                            backgroundColor: Colors.grey.shade50,
                            selectedColor: GrovioColors.primaryGreen.withAlpha(
                              25,
                            ),
                            side: BorderSide(
                              color: selectedCategory == cKey
                                  ? GrovioColors.primaryGreen
                                  : Colors.grey.shade200,
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            label: Text(
                              GrovioStrings.get(cKey),
                              style: TextStyle(
                                color: selectedCategory == cKey
                                    ? GrovioColors.primaryGreen
                                    : Colors.black54,
                                fontSize: 12,
                                fontWeight: selectedCategory == cKey
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                            selected: selectedCategory == cKey,
                            onSelected: (v) =>
                                setState(() => selectedCategory = cKey),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              Expanded(
                child: products.isEmpty && searchQuery.isNotEmpty
                    ? _buildNoResultsSuggestion()
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 0.58,
                              crossAxisSpacing: 4,
                              mainAxisSpacing: 4,
                            ),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final item = products[index];
                          int qty = CartManager.cartItems[item.id] ?? 0;
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey.shade100,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(5),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      GestureDetector(
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ProductDetailPage(item: item),
                                          ),
                                        ),
                                        child: Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Hero(
                                              tag: item.id,
                                              child: grovioNetworkImage(
                                                imageUrl: item.imageUrl,
                                                fit: BoxFit.contain,
                                                width: double.infinity,
                                                memCacheWidth: 200,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (item.discountPercent > 0)
                                        Positioned(
                                          top: 0,
                                          left: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3,
                                            ),
                                            decoration: const BoxDecoration(
                                              color: Colors.green,
                                              borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(12),
                                                bottomRight: Radius.circular(8),
                                              ),
                                            ),
                                            child: Text(
                                              "${item.discountPercent}% OFF",
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 7,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (item.stockQty <= 0)
                                        Positioned.fill(
                                          child: Container(
                                            color: Colors.black.withAlpha(76),
                                            child: Center(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                color: Colors.red,
                                                child: const Text(
                                                  "OUT OF STOCK",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 8,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          height: 1.2,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            "₹${item.price}",
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                              color: GrovioColors.primaryGreen,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          if (item.mrp > item.price)
                                            Text(
                                              "₹${item.mrp}",
                                              style: const TextStyle(
                                                fontSize: 8,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                                color: Colors.grey,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      item.stockQty <= 0
                                          ? const SizedBox(
                                              height: 28,
                                              child: Center(
                                                child: Text(
                                                  "Out of Stock",
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: Colors.red,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            )
                                          : (qty == 0
                                                ? SizedBox(
                                                    width: double.infinity,
                                                    height: 28,
                                                    child: ElevatedButton(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.white,
                                                        foregroundColor:
                                                            GrovioColors
                                                                .primaryGreen,
                                                        side: const BorderSide(
                                                          color: GrovioColors
                                                              .primaryGreen,
                                                          width: 1,
                                                        ),
                                                        elevation: 0,
                                                        padding:
                                                            EdgeInsets.zero,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                        ),
                                                      ),
                                                      onPressed: () {
                                                        setState(
                                                          () =>
                                                              CartManager
                                                                      .cartItems[item
                                                                      .id] =
                                                                  1,
                                                        );
                                                      },
                                                      child: const Text(
                                                        "ADD",
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                : Container(
                                                    height: 28,
                                                    decoration: BoxDecoration(
                                                      color: GrovioColors
                                                          .primaryGreen,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        InkWell(
                                                          onTap: () => setState(
                                                            () {
                                                              if (qty > 1) {
                                                                CartManager
                                                                        .cartItems[item
                                                                        .id] =
                                                                    qty - 1;
                                                              } else {
                                                                CartManager
                                                                    .cartItems
                                                                    .remove(
                                                                      item.id,
                                                                    );
                                                              }
                                                            },
                                                          ),
                                                          child: const Padding(
                                                            padding:
                                                                EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                ),
                                                            child: Icon(
                                                              Icons.remove,
                                                              size: 14,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          "$qty",
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                        InkWell(
                                                          onTap: () => setState(() {
                                                            if (qty <
                                                                item.stockQty) {
                                                              CartManager
                                                                      .cartItems[item
                                                                      .id] =
                                                                  qty + 1;
                                                            } else {
                                                              ScaffoldMessenger.of(
                                                                context,
                                                              ).showSnackBar(
                                                                const SnackBar(
                                                                  content: Text(
                                                                    "No more stock available",
                                                                  ),
                                                                ),
                                                              );
                                                            }
                                                          }),
                                                          child: const Padding(
                                                            padding:
                                                                EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                ),
                                                            child: Icon(
                                                              Icons.add,
                                                              size: 14,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  )),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          bottomNavigationBar: CartManager.totalItems > 0
              ? _buildCartBar(allProducts)
              : null,
        );
      },
    );
  }

  Widget _buildNoResultsSuggestion() {
    bool isHi = GrovioStrings.lang == 'hi';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            isHi
                ? "आपकी खोज से मेल खाने वाला कोई आइटम नहीं मिला।"
                : "No items found matching your search.",
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isHi
                ? "क्या आपको अपनी ज़रूरत का सामान नहीं मिला?"
                : "DON'T SEE WHAT YOU NEED?",
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () async {
              await GrovioFirestore.suggestProduct(searchQuery);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isHi
                          ? "'$searchQuery' की मांग दर्ज कर ली गई है! हम इसे जल्द ही जोड़ने की कोशिश करेंगे।"
                          : "Demand for '$searchQuery' registered! We will try to add it soon.",
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.add_task),
            label: Text(
              isHi ? "'$searchQuery' का सुझाव दें" : "SUGGEST '$searchQuery'",
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: GrovioColors.primaryGreen,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartBar(List<GroceryItem> products) => Container(
    height: 60,
    color: GrovioColors.primaryGreen,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            "₹${CartManager.totalAmount(products)}",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CheckoutPage(products: products)),
          ).then((_) => setState(() {})),
          child: const Text("VIEW CART", style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

class ProductDetailPage extends StatelessWidget {
  final GroceryItem item;
  const ProductDetailPage({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Product Details",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.grey.shade50),
              child: Hero(
                tag: item.id,
                child: grovioNetworkImage(
                  imageUrl: item.imageUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: 600,
                  placeholder: const Center(
                    child: CircularProgressIndicator(
                      color: GrovioColors.primaryGreen,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.discountPercent > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "${item.discountPercent}% OFF",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.unit,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        "₹${item.price}",
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (item.mrp > item.price)
                        Text(
                          "MRP ₹${item.mrp}",
                          style: const TextStyle(
                            fontSize: 18,
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  const Divider(),
                  const SizedBox(height: 10),
                  const Text(
                    "Product Description",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.description.isNotEmpty
                        ? item.description
                        : _generateSmartDescription(item),
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GrovioColors.primaryGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "BACK TO SHOP",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _generateSmartDescription(GroceryItem item) {
    String name = item.name;
    bool isHi = GrovioStrings.lang == 'hi';
    switch (item.category) {
      case "cat_dairy_bread":
        return isHi
            ? "ताज़ा और पौष्टिक $name, आपके दैनिक ऊर्जा और स्वास्थ्य के लिए आवश्यक।"
            : "Fresh and nutritious $name, essential for your daily energy and health.";
      case "cat_munchies":
        return isHi
            ? "कुरकुरा और स्वादिष्ट $name, आपकी छोटी-मोटी भूख के लिए बेहतरीन स्नैक।"
            : "Crunchy and flavorful $name, the perfect snack for your cravings.";
      case "cat_cold_drinks":
        return isHi
            ? "ताज़गी देने वाला ठंडा $name, गर्मी को मात देने के लिए सबसे अच्छा।"
            : "Refreshing and chilled $name, best to beat the heat anytime.";
      case "cat_bakery":
        return isHi
            ? "मीठा और ओवन-फ्रेश $name, बेहतरीन स्वाद के लिए प्रीमियम सामग्री से बना।"
            : "Sweet and oven-fresh $name, made with premium ingredients for great taste.";
      case "cat_staples":
        return isHi
            ? "उच्च गुणवत्ता वाला $name, आपकी रसोई के लिए सावधानी से पैक किया गया।"
            : "High-quality $name, sorted and packed with care for your kitchen.";
      case "cat_pharma":
        return isHi
            ? "भरोसेमंद और सुरक्षित $name, आपके और आपके परिवार के स्वास्थ्य के लिए।"
            : "Trusted and safe $name, providing the care you and your family deserve.";
      case "cat_cleaning":
        return isHi
            ? "चमकदार घर और बेहतर स्वच्छता के लिए प्रभावी $name।"
            : "Effective $name for a sparkling clean home and better hygiene.";
      case "cat_personal":
        return isHi
            ? "सौम्य और प्रभावी $name, आपकी दैनिक देखभाल के लिए डिज़ाइन किया गया।"
            : "Gentle and effective $name, designed for your daily grooming and care.";
      case "cat_baby":
        return isHi
            ? "शुद्ध और सुरक्षित $name, विशेष रूप से आपके छोटे बच्चे के आराम के लिए।"
            : "Pure and safe $name, specially crafted for your little one's comfort.";
      case "cat_kitchen":
        return isHi
            ? "टिकाऊ और सुंदर $name, आपकी रसोई और डाइनिंग की जरूरतों के लिए।"
            : "Durable and stylish $name, perfect for your kitchen and dining needs.";
      case "cat_household":
        return isHi
            ? "बेहतरीन गुणवत्ता वाला $name, आपके घर के दैनिक कार्यों के लिए उपयोगी।"
            : "High-quality $name, essential for your daily household tasks.";
      default:
        return isHi
            ? "प्रीमियम गुणवत्ता वाला $name, आपकी दैनिक घरेलू जरूरतों को पूरा करने के लिए।"
            : "Premium quality $name, selected carefully to meet your daily household needs.";
    }
  }
}

class CheckoutPage extends StatefulWidget {
  final List<GroceryItem> products;
  const CheckoutPage({super.key, required this.products});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  String selectedPayment = "Cash on Delivery";
  void _processOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? "Guest";
    final phone = prefs.getString('phone') ?? "No Phone";
    final currentAddr = AddressManager.currentAddress;
    if (currentAddr == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select an address first")),
        );
      }
      return;
    }
    final totalAmount = CartManager.totalAmount(widget.products);
    double totalSavings = 0;
    List<OrderItem> orderItems = [];
    for (var e in CartManager.cartItems.entries) {
      final item = widget.products.firstWhere((i) => i.id == e.key);
      orderItems.add(
        OrderItem(
          itemId: item.id,
          name: item.name,
          unit: item.unit,
          qty: e.value,
          price: item.price,
          mrp: item.mrp,
          costPrice: item.costPrice,
        ),
      );
      if (item.mrp > item.price) {
        totalSavings += (item.mrp - item.price) * e.value;
      }
    }
    final newOrder = GrovioOrder(
      id: "GS${DateTime.now().millisecondsSinceEpoch % 10000}",
      date: DateTime.now(),
      items: orderItems,
      total: totalAmount,
      totalSavings: totalSavings,
      status: "PLACED",
      paymentMethod: selectedPayment,
      customerName: name,
      customerPhone: phone,
      customerAddress: currentAddr.address,
      lat: currentAddr.lat,
      lng: currentAddr.lng,
      otp: (Random().nextInt(9000) + 1000).toString(),
      isSettled: selectedPayment == "UPI",
    );
    try {
      await GrovioFirestore.placeOrder(newOrder);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TrackingPage(savings: totalSavings),
          ),
        );
      }
      CartManager.cartItems.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to place order: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(GrovioStrings.get("checkout"))),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: CartManager.cartItems.entries.map((e) {
                final item = widget.products.firstWhere((i) => i.id == e.key);
                return ListTile(
                  title: Text(item.name),
                  subtitle: Text("₹${item.price} x ${e.value}"),
                  trailing: Text("₹${item.price * e.value}"),
                );
              }).toList(),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.white,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.money, color: GrovioColors.primaryGreen),
                  title: Text(GrovioStrings.get("cash_on_delivery")),
                  trailing: const Icon(Icons.check_circle, color: GrovioColors.primaryGreen),
                ),
                const Divider(),
                if (CartManager.cartItems.entries.any((e) {
                  final item = widget.products.firstWhere((i) => i.id == e.key);
                  return item.mrp > item.price;
                }))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          GrovioStrings.get("total_savings"),
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            double savings = 0;
                            for (var e in CartManager.cartItems.entries) {
                              final item = widget.products.firstWhere(
                                (i) => i.id == e.key,
                              );
                              if (item.mrp > item.price) {
                                savings += (item.mrp - item.price) * e.value;
                              }
                            }
                            return Text(
                              "₹${savings.toStringAsFixed(0)}",
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total"),
                    Text(
                      "₹${CartManager.totalAmount(widget.products)}",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GrovioColors.primaryGreen,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _processOrder,
                    child: Text(GrovioStrings.get("place_order")),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TrackingPage extends StatelessWidget {
  final double savings;
  const TrackingPage({super.key, this.savings = 0});
  @override
  Widget build(BuildContext context) {
    bool isHi = GrovioStrings.lang == 'hi';
    return Scaffold(
      appBar: AppBar(title: Text(isHi ? "ऑर्डर सफलतापूर्वक" : "Order Placed")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle,
                size: 100,
                color: GrovioColors.primaryGreen,
              ),
              const SizedBox(height: 20),
              Text(
                isHi ? "सफल!" : "Success!",
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: GrovioColors.primaryGreen,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isHi
                    ? "आपका ऑर्डर तैयार किया जा रहा है।"
                    : "Your order is being prepared.",
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 30),
              if (savings > 0)
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.elasticOut,
                  tween: Tween(begin: 0.0, end: 1.0),
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: Opacity(
                      opacity: value.clamp(0.0, 1.0),
                      child: child,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.green.shade200,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.stars_rounded,
                              color: Colors.green,
                              size: 32,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "${GrovioStrings.get('you_saved')} ₹${savings.toStringAsFixed(0)}",
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.stars_rounded,
                              color: Colors.green,
                              size: 32,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isHi
                              ? "इस ऑर्डर पर आपकी शानदार बचत!"
                              : "Fantastic savings on this order!",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.popUntil(context, (route) => route.isFirst),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GrovioColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isHi ? "होम पर वापस जाएं" : "Back to Home",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});
  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  String name = "", phone = "";
  bool _isLoading = false;
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    await AddressManager.loadAddresses();
    setState(() {
      name = prefs.getString('name') ?? "";
      phone = prefs.getString('phone') ?? "";
    });
  }

  void _addNewAddress() async {
    final TextEditingController houseController = TextEditingController();
    final TextEditingController areaController = TextEditingController();
    final TextEditingController landmarkController = TextEditingController();
    String selectedLabel = "Home";
    bool? proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(GrovioStrings.get("add_new_address")),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: houseController,
                decoration: InputDecoration(
                  labelText: GrovioStrings.lang == 'hi'
                      ? "मकान नंबर / बिल्डिंग"
                      : "House No. / Building",
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: areaController,
                decoration: InputDecoration(
                  labelText: GrovioStrings.get("address"),
                  hintText: "e.g. Gauriganj, Amethi",
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: landmarkController,
                decoration: InputDecoration(
                  labelText: GrovioStrings.lang == 'hi'
                      ? "लैंडमार्क (वैकल्पिक)"
                      : "Landmark (Optional)",
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedLabel,
                items: ["Home", "Office", "Other"]
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) => selectedLabel = v!,
                decoration: InputDecoration(
                  labelText: GrovioStrings.get("label"),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(GrovioStrings.get("cancel")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: GrovioColors.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: Text(GrovioStrings.get("save")),
          ),
        ],
      ),
    );
    if (proceed != true || areaController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      double lat = RegistrationPage.shopLat;
      double lng = RegistrationPage.shopLng;
      String pincode = "";

      if (!kIsWeb) {
        try {
          String searchQuery = "${areaController.text}, Amethi, Uttar Pradesh";
          List<Location> locations = await Geocoding().locationFromAddress(searchQuery);
          if (locations.isNotEmpty) {
            lat = locations[0].latitude;
            lng = locations[0].longitude;
            List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(lat, lng);
            if (placemarks.isNotEmpty) pincode = placemarks[0].postalCode ?? "";
          }
        } catch (e) {
          debugPrint("Geocoding failed: $e");
        }
      }

      String fullAddress = "${houseController.text}, ${areaController.text}";
      if (landmarkController.text.isNotEmpty) {
        fullAddress += " (Near ${landmarkController.text})";
      }
      if (pincode.isNotEmpty) fullAddress += " - $pincode";
      AddressManager.addresses.add(
        UserAddress(
          address: fullAddress,
          lat: lat,
          lng: lng,
          label: selectedLabel,
        ),
      );
      await AddressManager.saveAddresses();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              GrovioStrings.lang == 'hi'
                  ? "पता सफलतापूर्वक जोड़ा गया"
                  : "Address added successfully",
            ),
          ),
        );
      }
    } catch (e) {
      _showError("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Alert"),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  void _showFeedbackDialog({String? orderId}) async {
    final TextEditingController feedbackController = TextEditingController();
    double selectedRating = 5;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(GrovioStrings.get("give_feedback")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(GrovioStrings.get("rating")),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (index) => IconButton(
                    icon: Icon(
                      index < selectedRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                    onPressed: () =>
                        setDialogState(() => selectedRating = index + 1.0),
                  ),
                ),
              ),
              TextField(
                controller: feedbackController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: GrovioStrings.get("feedback_hint"),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(GrovioStrings.get("cancel")),
            ),
            ElevatedButton(
              onPressed: () async {
                if (feedbackController.text.trim().isEmpty) return;
                final messenger = ScaffoldMessenger.of(context);
                await GrovioFirestore.saveFeedback(
                  customerPhone: phone,
                  customerName: name,
                  feedback: feedbackController.text.trim(),
                  rating: selectedRating,
                  orderId: orderId,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(GrovioStrings.get("feedback_success")),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: GrovioColors.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: Text(GrovioStrings.get("submit")),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(GrovioStrings.get("my_profile"))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: GrovioColors.primaryGreen,
            child: Icon(Icons.person, size: 40, color: Colors.white),
          ),
          ListTile(
            title: Text(name),
            subtitle: Text(phone),
            leading: const Icon(Icons.person),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              GrovioStrings.get("saved_addresses"),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...List.generate(AddressManager.addresses.length, (index) {
            final addr = AddressManager.addresses[index];
            return ListTile(
              leading: const Icon(Icons.location_on, color: Colors.grey),
              title: Text(addr.label),
              subtitle: Text(addr.address),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (AddressManager.selectedIndex == index)
                    const Icon(Icons.check_circle, color: Colors.green),
                  if (AddressManager.addresses.length > 1)
                    IconButton(
                      icon: const Icon(
                        Icons.delete,
                        color: Colors.red,
                        size: 20,
                      ),
                      onPressed: () async {
                        setState(() {
                          AddressManager.addresses.removeAt(index);
                          if (AddressManager.selectedIndex >=
                              AddressManager.addresses.length) {
                            AddressManager.selectedIndex = 0;
                          }
                        });
                        await AddressManager.saveAddresses();
                      },
                    ),
                ],
              ),
              onTap: () async {
                setState(() {
                  AddressManager.selectedIndex = index;
                });
                await AddressManager.saveAddresses();
              },
            );
          }),
          ListTile(
            leading: const Icon(Icons.add_location_alt, color: Colors.blue),
            title: Text(
              GrovioStrings.get("add_new_address"),
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: _isLoading ? null : _addNewAddress,
            trailing: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          const Divider(),
          ListTile(
            title: Text(GrovioStrings.get("give_feedback")),
            leading: const Icon(Icons.rate_review, color: Colors.orange),
            onTap: () => _showFeedbackDialog(),
          ),
          ListTile(
            title: Text(GrovioStrings.get("cust_care")),
            subtitle: const Text("+91 7068487936"),
            leading: const Icon(
              Icons.support_agent,
              color: GrovioColors.primaryGreen,
            ),
            onTap: () => launchUrl(Uri.parse("tel:+917068487936")),
          ),
          ListTile(
            title: Text(GrovioStrings.get("wa_support")),
            subtitle: const Text("Share photo of damaged items"),
            leading: const Icon(Icons.chat, color: Colors.green),
            onTap: () => launchUrl(Uri.parse("https://wa.me/917068487936")),
          ),
          ListTile(
            title: Text(GrovioStrings.get("my_orders")),
            leading: const Icon(Icons.receipt),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyOrdersPage()),
            ),
          ),
          ListTile(
            title: Text(GrovioStrings.get("logout")),
            leading: const Icon(Icons.logout, color: Colors.red),
            onTap: () async {
              final navigator = Navigator.of(context);
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!mounted) return;
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const GrovioCustomerApp()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}

class MyOrdersPage extends StatefulWidget {
  const MyOrdersPage({super.key});
  @override
  State<MyOrdersPage> createState() => _MyOrdersPageState();
}

class _MyOrdersPageState extends State<MyOrdersPage> {
  String? _phone;
  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _phone = prefs.getString('phone'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(GrovioStrings.get("my_orders"))),
      body: _phone == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<GrovioOrder>>(
              stream: GrovioFirestore.getOrders(customerPhone: _phone),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                final orders = snapshot.data ?? [];
                if (orders.isEmpty) {
                  return const Center(child: Text("No orders yet"));
                }
                orders.sort((a, b) => b.date.compareTo(a.date));
                return ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return Card(
                      margin: const EdgeInsets.all(10),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ExpansionTile(
                        title: Text(
                          "Order #${order.id}",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Total: ₹${order.total}"),
                                if (order.totalSavings > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.green.shade100,
                                      ),
                                    ),
                                    child: Text(
                                      "${GrovioStrings.get('you_saved')} ₹${order.totalSavings.toStringAsFixed(0)}",
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              DateFormat(
                                'dd MMM yyyy, hh:mm a',
                              ).format(order.date),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        trailing: _statusBadge(order.status),
                        children: [
                          const Divider(),
                          if (order.status == "OUT_FOR_DELIVERY")
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.orange.shade200,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.lock_outline,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    GrovioStrings.lang == 'hi'
                                        ? "डिलीवरी OTP: ${order.otp}"
                                        : "Delivery OTP: ${order.otp}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          _buildStatusTracker(order.status),
                          const Divider(),
                          if (order.totalSavings > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    GrovioStrings.get("total_savings"),
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "₹${order.totalSavings.toStringAsFixed(0)}",
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ...order.items.map(
                            (it) => ListTile(
                              dense: true,
                              title: Text("${it.name} x ${it.qty}"),
                              trailing: Text(
                                "₹${it.price * it.qty}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          if (order.status == "DELIVERED")
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _showOrderFeedbackDialog(context, order),
                                icon: const Icon(
                                  Icons.star,
                                  color: Colors.orange,
                                ),
                                label: Text(GrovioStrings.get("give_feedback")),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  void _showOrderFeedbackDialog(BuildContext context, GrovioOrder order) async {
    final TextEditingController feedbackController = TextEditingController();
    double selectedRating = 5;
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? "";
    final phone = prefs.getString('phone') ?? "";
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(GrovioStrings.get("give_feedback")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Rate Order #${order.id}"),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (index) => IconButton(
                    icon: Icon(
                      index < selectedRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                    onPressed: () =>
                        setDialogState(() => selectedRating = index + 1.0),
                  ),
                ),
              ),
              TextField(
                controller: feedbackController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: GrovioStrings.get("feedback_hint"),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(GrovioStrings.get("cancel")),
            ),
            ElevatedButton(
              onPressed: () async {
                if (feedbackController.text.trim().isEmpty) return;
                await GrovioFirestore.saveFeedback(
                  customerPhone: phone,
                  customerName: name,
                  feedback: feedbackController.text.trim(),
                  rating: selectedRating,
                  orderId: order.id,
                );
                if (!context.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(GrovioStrings.get("feedback_success")),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: GrovioColors.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: Text(GrovioStrings.get("submit")),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: GrovioColors.primaryGreen.withAlpha(20),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      status.replaceAll("_", " "),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: GrovioColors.primaryGreen,
      ),
    ),
  );
  Widget _buildStatusTracker(String status) {
    int currentStep = 0;
    if (status == "ACCEPTED") currentStep = 1;
    if (status == "PACKING") currentStep = 2;
    if (status == "READY" || status == "OUT_FOR_DELIVERY") currentStep = 3;
    if (status == "DELIVERED") currentStep = 4;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _statusStep(Icons.assignment_turned_in, "Placed", currentStep >= 0),
          _statusLine(currentStep >= 1),
          _statusStep(Icons.inventory_2, "Packed", currentStep >= 2),
          _statusLine(currentStep >= 3),
          _statusStep(Icons.delivery_dining, "On Way", currentStep >= 3),
          _statusLine(currentStep >= 4),
          _statusStep(Icons.check_circle, "Done", currentStep >= 4),
        ],
      ),
    );
  }

  Widget _statusStep(IconData icon, String label, bool isActive) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        color: isActive ? GrovioColors.primaryGreen : Colors.grey.shade300,
        size: 22,
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 8,
          color: isActive ? Colors.black : Colors.grey,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    ],
  );
  Widget _statusLine(bool isActive) => Expanded(
    child: Container(
      height: 2,
      color: isActive ? GrovioColors.primaryGreen : Colors.grey.shade300,
    ),
  );
}


class MyFeedbacksPage extends StatefulWidget {
  const MyFeedbacksPage({super.key});
  @override
  State<MyFeedbacksPage> createState() => _MyFeedbacksPageState();
}

class _MyFeedbacksPageState extends State<MyFeedbacksPage> {
  String? _phone;
  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _phone = prefs.getString('phone'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          GrovioStrings.lang == 'hi' ? "मेरी प्रतिक्रियाएँ" : "My Feedbacks",
        ),
      ),
      body: _phone == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: GrovioFirestore.getFeedbacks(customerPhone: _phone),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                final feedbacks = snapshot.data ?? [];
                if (feedbacks.isEmpty) {
                  return const Center(child: Text("No feedback given yet"));
                }
                return ListView.builder(
                  itemCount: feedbacks.length,
                  itemBuilder: (context, index) {
                    final f = feedbacks[index];
                    final rating = (f['rating'] ?? 0).toDouble();
                    final reply = f['reply'];
                    return Card(
                      margin: const EdgeInsets.all(10),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  DateFormat(
                                    'dd MMM yyyy',
                                  ).format(DateTime.parse(f['date'])),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                Row(
                                  children: List.generate(
                                    5,
                                    (i) => Icon(
                                      i < rating
                                          ? Icons.star
                                          : Icons.star_border,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (f['orderId'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  "Order: #${f['orderId']}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const Divider(),
                            Text(
                              f['feedback'],
                              style: const TextStyle(fontSize: 14),
                            ),
                            if (reply != null)
                              Container(
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      GrovioStrings.lang == 'hi'
                                          ? "स्टोर का जवाब:"
                                          : "Store Reply:",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: GrovioColors.primaryGreen,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      reply,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
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
