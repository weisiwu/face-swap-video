import 'package:flutter/widgets.dart';

bool isBackgroundLifecycleState(AppLifecycleState state) {
  return switch (state) {
    AppLifecycleState.paused ||
    AppLifecycleState.detached ||
    AppLifecycleState.hidden => true,
    AppLifecycleState.resumed || AppLifecycleState.inactive => false,
  };
}
