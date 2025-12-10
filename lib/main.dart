import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LedControlPage(),
    );
  }
}

class LedControlPage extends StatefulWidget {
  const LedControlPage({super.key});
  @override
  State<LedControlPage> createState() => _LedControlPageState();
}

class _LedControlPageState extends State<LedControlPage> {
  String _brokerIp = "";
  late MqttServerClient _client;
  bool isConnected = false;
  bool ledState = false; // trạng thái bật/tắt đèn
  double lightIntensity = 0.5; // Cường độ ánh sáng (0.0 đến 1.0)

  // ====================================================
  // LOGIC VỊ TRÍ & KÍCH THƯỚC ĐÈN (Cần thay đổi ở đây để tùy chỉnh)
  // ====================================================

  // Kích thước/Vị trí của đèn treo (lamp.png)
  final double lampWidth = 180; // Kích thước đèn (pixels)
  final double lampTop = -0;  // Vị trí trục Y (Âm để kéo dây lên sát mép trên)
  final double lampRight = 20; // Vị trí trục X (Âm để dịch ra ngoài mép phải)

  // Kích thước của bóng đèn (light.png)
  final double lightHeight = 50; 

  // Vị trí của bóng đèn (light.png) TÍNH TƯƠNG ĐỐI VỚI lamp.png
  // GIẢ ĐỊNH: Nếu lampTop = -50, lightTopOffset = 250 => Đèn treo ở ~200px từ đỉnh màn hình
  final double lightTopOffset = 250; 
  final double lightRightOffset = 41; 

  // Vị trí của ánh sáng mờ (BoxShadow) TÍNH TƯƠNG ĐỐI VỚI lamp.png
  final double glowTopOffset = 180; 
  final double glowRightOffset = 20; 
  final double glowSize = 200; 

  // Chiều cao dự kiến của khu vực đèn treo (để tính vị trí bắt đầu của điều khiển)
  // Đây là chiều cao cố định của khối điều khiển khi có Slider.
  final double controlAreaFixedHeight = 280; 

  // ====================================================
  // LOGIC MQTT & DATA (Giữ nguyên)
  // ====================================================
  @override
  void initState() {
    super.initState();
    _loadBrokerIp();
  }
  
  Future<void> _loadBrokerIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString("broker_ip");

    if (savedIp == null) {
      _openIpDialog(firstOpen: true);
    } else {
      _brokerIp = savedIp;
      _connectMQTT();
    }
  }

  Future<void> _saveBrokerIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("broker_ip", ip);

    setState(() => _brokerIp = ip);
    _connectMQTT();
  }

  Future<void> _openIpDialog({bool firstOpen = false}) async {
    final controller = TextEditingController(text: _brokerIp);

    showDialog(
      context: context,
      barrierDismissible: !firstOpen,
      builder: (context) => AlertDialog(
        title: const Text("Nhập IP Broker MQTT"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "VD: 192.168.1.100",
          ),
        ),
        actions: [
          if (!firstOpen)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Hủy"),
            ),
          ElevatedButton(
            onPressed: () {
              final ip = controller.text.trim();
              if (ip.isNotEmpty) {
                _saveBrokerIp(ip);
                Navigator.pop(context);
              }
            },
            child: const Text("Lưu"),
          ),
        ],
      ),
    );
  }

  Future<void> _connectMQTT() async {
    if (isConnected || (_client.connectionStatus?.state == MqttConnectionState.connecting)) return;
    
    _client = MqttServerClient(_brokerIp, "flutter_client_${DateTime.now().millisecondsSinceEpoch}");

    _client.port = 1883;
    _client.keepAlivePeriod = 20;
    _client.logging(on: false);

    _client.onConnected = () => setState(() => isConnected = true);
    _client.onDisconnected = () => setState(() => isConnected = false);
    _client.onSubscribed = (topic) => print('Subscribed to $topic');
    _client.onSubscribeFail = (topic) => print('Failed to subscribe to $topic');
    
    try {
      await _client.connect();
    } catch (e) {
      print('MQTT connection failed: $e');
      _client.disconnect();
    }
    setState(() {});
  }

  void _publishLed(bool turnOn) {
    if (!isConnected) {
      _connectMQTT();
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(turnOn ? "1" : "0");

    _client.publishMessage(
      "/test/led",
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  void _publishIntensity(double intensity) {
    if (!isConnected) {
      _connectMQTT();
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(intensity.toStringAsFixed(2));

    _client.publishMessage(
      "/test/intensity",
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  //====================================================
  // GIAO DIỆN CHÍNH (Sử dụng Stack toàn màn hình)
  //====================================================
  @override
  Widget build(BuildContext context) {
    final double headerHeight = MediaQuery.of(context).padding.top + 50; 

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 28, 54, 46), 
      body: Stack(
        children: [
          // 1. Phần Điều Khiển (Lớp dưới, căn DƯỚI CÙNG với chiều cao cố định)
          Positioned(
            bottom: 0, 
            left: 0,
            right: 0,
            height: controlAreaFixedHeight, // Chiều cao cố định đủ chỗ cho Slider
            child: LightControlView(
              ledState: ledState,
              lightIntensity: lightIntensity,
              onToggle: (val) {
                setState(() {
                  ledState = val;
                  if (val && lightIntensity == 0.0) {
                      lightIntensity = 0.5; 
                  } else if (!val) {
                      lightIntensity = 0.0; 
                  }
                });
                _publishLed(val);
              },
              onIntensityChange: (val) {
                setState(() {
                  lightIntensity = val;
                  if (val > 0.0 && !ledState) {
                    ledState = true;
                    _publishLed(true);
                  } else if (val == 0.0 && ledState) {
                    ledState = false;
                    _publishLed(false);
                  }
                });
                _publishIntensity(val);
              },
              isConnected: isConnected,
              brokerIp: _brokerIp,
            ),
          ),

          // 2. Header Controls (Icon, Kitchen, Settings) (Lớp giữa, căn trên cùng)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _HeaderControls(
              onOpenIpDialog: _openIpDialog,
            ),
          ),
          
          // 3. Phần Đèn (Fixed ở trên, ĐÈ LÊN tất cả, sử dụng các biến tùy chỉnh)
          // Để đèn không bị che bởi khối điều khiển, ta đặt nó cao hơn
          _LightDisplay(
            ledState: ledState,
            lightIntensity: lightIntensity,
            lampTop: lampTop,
            lampRight: lampRight,
            lampWidth: lampWidth,
            lightHeight: lightHeight,
            lightTopOffset: lightTopOffset,
            lightRightOffset: lightRightOffset,
            glowTopOffset: glowTopOffset,
            glowRightOffset: glowRightOffset,
            glowSize: glowSize,
          ),
        ],
      ),
    );
  }
}

// ====================================================
// WIDGET TIÊU ĐỀ/ĐIỀU KHIỂN (HEADER)
// ====================================================
class _HeaderControls extends StatelessWidget {
  final VoidCallback onOpenIpDialog;

  const _HeaderControls({required this.onOpenIpDialog});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10, // Padding cho Status Bar
        left: 20, // Padding trái
        right: 20, // Padding phải
        bottom: 10,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () {},
                padding: EdgeInsets.zero, // Bỏ padding mặc định của IconButton
                constraints: const BoxConstraints(), // Bỏ constraints mặc định
              ),
              const Text(
                "Kitchen",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: onOpenIpDialog,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ====================================================
// WIDGET CHỈ HIỂN THỊ ĐÈN
// ====================================================
class _LightDisplay extends StatelessWidget {
  final bool ledState;
  final double lightIntensity;
  // Tham số tùy chỉnh
  final double lampTop;
  final double lampRight;
  final double lampWidth;
  final double lightHeight;
  final double lightTopOffset;
  final double lightRightOffset;
  final double glowTopOffset;
  final double glowRightOffset;
  final double glowSize;

  const _LightDisplay({
    required this.ledState,
    required this.lightIntensity,
    required this.lampTop,
    required this.lampRight,
    required this.lampWidth,
    required this.lightHeight,
    required this.lightTopOffset,
    required this.lightRightOffset,
    required this.glowTopOffset,
    required this.glowRightOffset,
    required this.glowSize,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = ledState ? 0.3 + (lightIntensity * 0.7) : 0.0;
    
    return Stack(
      children: [
        // 1. Hiệu ứng ánh sáng mờ (Lớp dưới)
        if (ledState)
          Positioned(
            top: glowTopOffset, 
            right: glowRightOffset,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: glowSize,
                height: glowSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.5 * lightIntensity),
                      blurRadius: 100 * lightIntensity, 
                      spreadRadius: 20 * lightIntensity, 
                    ),
                  ],
                ),
              ),
            ),
          ),
        
        // 2. Bóng đèn (light.png) (Lớp giữa)
        if (ledState)
          Positioned(
            top: lightTopOffset, 
            right: lightRightOffset, 
            child: Opacity(
              opacity: opacity,
              child: Image.asset(
                'assets/light.png',
                height: lightHeight,
              ),
            ),
          ),

        // 3. Đèn treo (lamp.png) (Lớp trên cùng)
        Positioned(
          top: lampTop,
          right: lampRight,
          child: Image.asset(
            'assets/lamp.png',
            width: lampWidth, 
          ),
        ),
      ],
    );
  }
}

// ====================================================
// WIDGET GIAO DIỆN ĐIỀU KHIỂN
// ====================================================
class LightControlView extends StatelessWidget {
  final bool ledState;
  final double lightIntensity;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onIntensityChange;
  final bool isConnected;
  final String brokerIp;

  const LightControlView({
    super.key,
    required this.ledState,
    required this.lightIntensity,
    required this.onToggle,
    required this.onIntensityChange,
    required this.isConnected,
    required this.brokerIp,
  });

  @override
  Widget build(BuildContext context) {
    // Để căn đều nội dung xuống dưới cùng và chiếm toàn bộ không gian được cấp
    return Align(
      alignment: Alignment.topCenter, // Căn trên cùng của khu vực được cấp (Positioned)
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40.0, 0, 40.0, 40.0), // Padding bên ngoài
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(), 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max, // Cho phép Column chiếm hết chiều cao của SingleChildScrollView
            children: [
              // Thông tin kết nối (CHỈ HIỂN THỊ KHI CHƯA KẾT NỐI)
              if (!isConnected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    "Chưa kết nối broker",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              
              // Text: Island Kitchen Bar...
              const Text(
                "Island Kitchen Bar\nLED Pendant Ceiling Light",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Công tắc ON/OFF
              Row(
                mainAxisAlignment: MainAxisAlignment.start, // Dạt trái
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: ledState,
                        onChanged: onToggle,
                        activeColor: const Color(0xFF6BBA9C),
                        inactiveTrackColor: Colors.white.withOpacity(0.3),
                        inactiveThumbColor: Colors.white,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, 
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ledState ? "ON" : "OFF",
                        style: TextStyle(
                          color: ledState ? Colors.white : Colors.white.withOpacity(0.5),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              // Thanh trượt điều chỉnh cường độ
              // Sử dụng Opacity + AnimatedOpacity để tránh nhảy khi ẩn/hiện, nhưng vẫn giữ chỗ.
              AnimatedOpacity(
                opacity: ledState ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 30),
                    // Text: Light Intensity
                    const Text(
                      "Light Intensity",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Slider
                    Row(
                      children: [
                        const Icon(Icons.lightbulb_outline, color: Colors.white54),
                        Expanded(
                          child: Slider(
                            value: lightIntensity,
                            min: 0.0,
                            max: 1.0,
                            divisions: 100,
                            onChanged: onIntensityChange,
                            activeColor: Colors.white,
                            inactiveColor: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        const Icon(Icons.lightbulb_sharp, color: Colors.white),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}