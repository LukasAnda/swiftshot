import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

import '../ui/habits_root.dart';
import 'preview_support.dart';

/*
 * Previews that set the locale through the previewer's `localizations` instead of the frame:
 * the frame then follows the ambient locale, here Arabic, so the whole app lays out right to
 * left.
 */

@Preview(name: 'Root (Arabic)', group: 'Locales', localizations: arabicLocalizations, wrapper: screenWrapper)
Widget rootArabicPreview() => const HabitsRoot();
