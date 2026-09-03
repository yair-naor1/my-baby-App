import 'package:cloud_functions/cloud_functions.dart';

/// Calls the `enhanceMemoryText` Cloud Function for a single AI-assisted
/// rewrite of a memory's text — the parent picks exactly one action
/// (translate / a specific style / fix) rather than getting several
/// variants to sift through at once.
///
/// Explicit and opt-in per PRODUCT_SPEC.md §15: the parent picks the action
/// and then confirms the result before it replaces anything; nothing is
/// ever applied automatically, and the prompt enforced server-side never
/// invents facts or changes meaning.
class AiTextEnhancementService {
  final _functions = FirebaseFunctions.instance;

  /// [mode] is 'translate', 'fix', or 'style'. [style] is required (and
  /// only used) when [mode] is 'style' — see functions/index.js's
  /// STYLE_INSTRUCTIONS for the current set.
  ///
  /// [childGender] ('male'/'female'/null) is used server-side only to get
  /// Hebrew grammatical gender right — never surfaced in the output text
  /// unless the parent's own original text already mentioned it.
  Future<String> enhance(
    String text, {
    required String mode,
    String? style,
    String? childGender,
  }) async {
    final callable = _functions.httpsCallable('enhanceMemoryText');

    final result = await callable.call<Map<String, dynamic>>({
      'text': text,
      'mode': mode,
      'style': ?style,
      'childGender': ?childGender,
    });

    return result.data['text'] as String;
  }
}
