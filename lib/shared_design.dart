// shared_design.dart
// Place at: lib/screens/register/shared_design.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
// Mirrors the palette used across home.dart / alerts.dart / book.dart / check.dart
// so the auth flow (login, register, OTP) reads as part of the same app.
const Color kCrimson     = Color(0xFFDC2626);
const Color kCrimsonDark = Color(0xFF750000);
const Color kSurface     = Colors.white;
const Color kInputFill   = Color(0xFFF9FAFB);
const Color kBorder      = Color(0xFFD1D5DB);
const Color kTextPrimary = Color(0xFF111827);
const Color kTextMuted   = Color(0xFF6B7280);

const List<Color> kHeaderGradient = [kCrimsonDark, Color(0xFFFF4E4E)];

// ─── Full-bleed gradient background for auth screens ──────────────────────────
// Wraps a screen's content so the crimson gradient fills the whole Scaffold
// (matching the hero-header gradient used elsewhere), while RegisterCard's
// opaque white surface covers everything below the header.
class GradientScreen extends StatelessWidget {
  final Widget child;
  const GradientScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: kHeaderGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(child: child),
      );
}

// ─── Circular icon button for gradient headers (back / feed shortcuts) ───────
class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white.withOpacity(0.16),
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white30, width: 1.2),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}

// ─── Step progress indicator ──────────────────────────────────────────────────
class StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const StepIndicator(
      {super.key, required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (i) {
        final active  = i + 1 <= currentStep;
        final current = i + 1 == currentStep;
        return Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: current ? 28 : 10,
            height: 10,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white.withOpacity(0.35),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          if (i < totalSteps - 1)
            Container(
              width: 24,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: active
                  ? Colors.white.withOpacity(0.55)
                  : Colors.white.withOpacity(0.2),
            ),
        ]);
      }),
    );
  }
}

// ─── Shared header ────────────────────────────────────────────────────────────
class RegisterHeader extends StatelessWidget {
  final int step;
  final String subtitle;
  const RegisterHeader(
      {super.key, required this.step, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, h * 0.06, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.bloodtype_rounded, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text('eDonate',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
            ],
          ),
          const SizedBox(height: 16),
          StepIndicator(currentStep: step, totalSteps: 3),
          const SizedBox(height: 12),
          Text(subtitle,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.75), fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Card wrapper ─────────────────────────────────────────────────────────────
class RegisterCard extends StatelessWidget {
  final Widget child;
  const RegisterCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: child,
      );
}

// ─── Field label ─────────────────────────────────────────────────────────────
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: kTextPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      );
}

// ─── Text field ───────────────────────────────────────────────────────────────
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final bool readOnly;
  final TextInputType keyboardType;
  final IconData? prefixIcon;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final VoidCallback? onTap;

  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.readOnly = false,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
    this.suffix,
    this.inputFormatters,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        readOnly: readOnly,
        inputFormatters: inputFormatters,
        onTap: onTap,
        style: const TextStyle(color: kTextPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(color: kTextMuted.withOpacity(0.6), fontSize: 14),
          filled: true,
          fillColor: kInputFill,
          prefixIcon: prefixIcon != null
              ? Icon(prefixIcon, color: kTextMuted, size: 18)
              : null,
          suffixIcon: suffix,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kCrimson, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      );
}

// ─── Dropdown ─────────────────────────────────────────────────────────────────
class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?)? onChanged;

  const AppDropdown({
    super.key,
    required this.value,
    required this.hint,
    required this.items,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded,
            color: kTextMuted, size: 20),
        decoration: InputDecoration(
          filled: true,
          fillColor: kInputFill,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kCrimson, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        hint: Text(hint,
            style: TextStyle(
                color: kTextMuted.withOpacity(0.6), fontSize: 14)),
        style: const TextStyle(color: kTextPrimary, fontSize: 14),
        items: items,
        onChanged: onChanged,
      );
}

// ─── Primary button ───────────────────────────────────────────────────────────
class PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  const PrimaryButton(
      {super.key,
      required this.label,
      this.loading = false,
      required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kCrimson,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: loading ? null : onTap,
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
              : Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      );
}

// ─── Outline button ───────────────────────────────────────────────────────────
class OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const OutlineBtn({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: kCrimson,
            side: const BorderSide(color: kCrimson, width: 1.5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onTap,
          child: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      );
}

// ─── Section title ────────────────────────────────────────────────────────────
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
                color: kCrimson, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  color: kTextMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
        ],
      );
}