import 'package:flutter/material.dart';

/// Responsive breakpoint constants and helper functions.
const double kMobileBreakpoint = 600;
const double kTabletBreakpoint = 900;

bool isMobile(BuildContext context) =>
    MediaQuery.of(context).size.width < kMobileBreakpoint;

bool isTablet(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  return w >= kMobileBreakpoint && w < kTabletBreakpoint;
}

bool isDesktop(BuildContext context) =>
    MediaQuery.of(context).size.width >= kTabletBreakpoint;

/// Returns horizontal padding based on screen width.
double responsivePadding(BuildContext context) {
  if (isMobile(context)) return 12;
  if (isTablet(context)) return 16;
  return 20;
}

/// Returns a dialog width constrained to screen.
double dialogWidth(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  if (w < kMobileBreakpoint) return w - 32; // near full-width on phone
  return (w * 0.85).clamp(400, 700);
}

/// Returns a dialog height constrained to screen.
double dialogHeight(BuildContext context) {
  final h = MediaQuery.of(context).size.height;
  if (h < 700) return h - 80;
  return (h * 0.85).clamp(400, 800);
}
