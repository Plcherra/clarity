// TODO: Remove or replace secrets handling before releasing the app to production

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Values from the project root `.env` file (loaded in `main()`).
class Constants {
  static String get openAIKey =>
      dotenv.env['OPENAI_API_KEY']?.trim() ?? '';
}
