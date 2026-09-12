import 'package:flutter/material.dart';

import '../controllers/playground_controller.dart';

const Size phoneLogicalSize = Size(390, 844);

class DevicePreviewFrame extends StatelessWidget {
  const DevicePreviewFrame({
    super.key,
    required this.controller,
    required this.child,
  });

  final PlaygroundController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const ValueKey('device-preview-logical-size'),
        width: phoneLogicalSize.width,
        height: phoneLogicalSize.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: Colors.black87, width: 8),
            boxShadow: const [
              BoxShadow(blurRadius: 24, color: Colors.black26),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: phoneLogicalSize,
                        padding: EdgeInsets.zero,
                        viewPadding: EdgeInsets.zero,
                        viewInsets: EdgeInsets.zero,
                      ),
                      child: Theme(
                        data: controller.darkPreview
                            ? ThemeData.dark(useMaterial3: true)
                            : ThemeData.light(useMaterial3: true),
                        child: Material(
                          color: controller.darkPreview
                              ? const Color(0xff121212)
                              : Colors.white,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Center(
                      child: Container(
                        width: 120,
                        height: 5,
                        decoration: BoxDecoration(
                          color: controller.darkPreview
                              ? Colors.white54
                              : Colors.black45,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
