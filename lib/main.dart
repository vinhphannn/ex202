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

  @override
  void initState() {
    super.initState();
    _loadBrokerIp();
  }

  //====================================================
  // LẤY IP BROKER TỪ BỘ NHỚ
  //====================================================
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

  //====================================================
  // LƯU IP BROKER
  //====================================================
  Future<void> _saveBrokerIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("broker_ip", ip);

    setState(() => _brokerIp = ip);

    _connectMQTT();
  }

  //====================================================
  // POPUP NHẬP IP
  //====================================================
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

  //====================================================
  // KẾT NỐI MQTT TRỰC TIẾP ĐẾN BROKER
  //====================================================
  Future<void> _connectMQTT() async {
    _client = MqttServerClient(_brokerIp, "flutter_client_${DateTime.now().millisecondsSinceEpoch}");

    _client.port = 1883;
    _client.keepAlivePeriod = 20;
    _client.logging(on: false);

    _client.onConnected = () => setState(() => isConnected = true);
    _client.onDisconnected = () => setState(() => isConnected = false);

    try {
      await _client.connect();
    } catch (e) {
      _client.disconnect();
    }
    setState(() {});
  }

  //====================================================
  // GỬI LỆNH BẬT/TẮT LED
  //====================================================
  void _publishLed(bool turnOn) {
    if (!isConnected) return;

    final builder = MqttClientPayloadBuilder();
    builder.addString(turnOn ? "1" : "0");

    // gửi vào topic /test/led
    _client.publishMessage(
      "/test/led",
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  //====================================================
  // GIAO DIỆN
  //====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Điều khiển LED MQTT"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _openIpDialog(),
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isConnected
                  ? "Đã kết nối: $_brokerIp"
                  : "Chưa kết nối broker",
              style: TextStyle(
                fontSize: 18,
                color: isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 40),

            // công tắc bật tắt LED
            Switch(
              value: ledState,
              onChanged: (val) {
                setState(() => ledState = val);
                _publishLed(val);
              },
            ),

            Text(
              ledState ? "Đang bật LED" : "Đang tắt LED",
              style: const TextStyle(fontSize: 20),
            )
          ],
        ),
      ),
    );
  }
}
