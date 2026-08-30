import 'package:cloud_functions/cloud_functions.dart';

/// Calls the `enhanceMemoryText` Cloud Function for a few AI-suggested
/// rewrites of a memory's text — grammar/phrasing improvements only.
///
/// Explicit and opt-in per PRODUCT_SPEC.md §15: the parent presses a button
/// and picks a suggestion (or dismisses them); nothing is ever applied
/// automatically, and the prompt enforced server-side never invents facts
/// or changes meaning.
class AiTextEnhancementService {
  final _functions = FirebaseFunctions.instance;

  Future<List<String>> enhance(String text) async {
    final callable = _functions.httpsCallable('enhanceMemoryText');

    final result = await callable.call<Map<String, dynamic>>({'text': text});

    return (result.data['suggestions'] as List<dynamic>).cast<String>();
  }
}
