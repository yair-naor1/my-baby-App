import 'package:flutter/material.dart';

/// Lets code outside the widget tree (notification tap handling) push routes
/// without a [BuildContext] of its own.
final navigatorKey = GlobalKey<NavigatorState>();
