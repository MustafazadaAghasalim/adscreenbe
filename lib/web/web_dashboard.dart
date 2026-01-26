import 'package:flutter/material.dart';
import 'views/tablet_map.dart';
import 'views/ad_uploader.dart';
import '../ui/admin_moderation_screen.dart';

class WebDashboard extends StatefulWidget {
  const WebDashboard({super.key});

  @override
  State<WebDashboard> createState() => _WebDashboardState();
}

class _WebDashboardState extends State<WebDashboard> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    TabletMapView(),
    AdUploaderView(),
    AdminModerationScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adscreen Admin'),
        backgroundColor: Colors.black,
      ),
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: Colors.grey[900],
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.tablet_android),
                selectedIcon: Icon(Icons.tablet_android, color: Colors.blueAccent),
                label: Text('Tablets'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.cloud_upload),
                selectedIcon: Icon(Icons.cloud_upload, color: Colors.blueAccent),
                label: Text('Ad Uploader'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.admin_panel_settings),
                selectedIcon: Icon(Icons.admin_panel_settings, color: Colors.redAccent),
                label: Text('Moderation'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
    );
  }
}
