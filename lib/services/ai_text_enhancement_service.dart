import 'package:cloud_functions/cloud_functions.dart';

/// One AI-suggested rewrite in a particular [style] ("natural", "warm", or
/// "playful" — see functions/index.js's RESPONSE_SCHEMA).
class TextSuggestion {
  TextSuggestion({required this.style, required this.text});

  final String style;
  final String text;
}

/// Calls the `enhanceMemoryText` Cloud Function for a few AI-suggested
/// rewrites of a memory's text — grammar/phrasing improvements only.
///
/// Explicit and opt-in per PRODUCT_SPEC.md §15: the parent presses a button
/// and picks a suggestion (or dismisses them); nothing is ever applied
/// automatically, and the prompt enforced server-side never invents facts
/// or changes meaning.
class AiTextEnhancementService {
  final _functions = FirebaseFunctions.instance;

  Future<List<TextSuggestion>> enhance(String text) async {
    final callable = _functions.httpsCallable('enhanceMemoryText');

    final result = await callable.call<Map<String, dynamic>>({'text': text});

    final options = (result.data['options'] as List<dynamic>)
        .cast<Map<Object?, Object?>>();

    return options
        .map(
          (option) => TextSuggestion(
            style: option['style'] as String,
            text: option['text'] as String,
          ),
        )
        .toList();
  }
}
