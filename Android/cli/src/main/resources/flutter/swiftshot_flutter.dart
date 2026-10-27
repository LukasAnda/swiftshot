// Swiftshot's Flutter renderer, run by `flutter test` from files Swiftshot generates: every
// @Preview built the way Flutter's widget previewer builds it, on each device, in each language,
// appearance and text scale, captured to PNG. One process renders one language (its fonts).
// ignore_for_file: avoid_print, implementation_imports

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_test/flutter_test.dart';

/// An annotated declaration: its annotations (evaluated; the non-preview ones are ignored) and
/// the preview function, constructor or static method as a tear-off.
class Entry {
  const Entry(this.script, this.line, this.function, this.annotations, this.target);
  final String script;
  final int line;
  final String function;
  final List<Object?> annotations;
  final Object target;
}

class _Device {
  _Device(Map<String, dynamic> j)
      : name = j['name'] as String,
        platform = j['platform'] == 'ios' ? TargetPlatform.iOS : TargetPlatform.android,
        size = Size((j['width'] as num).toDouble(), (j['height'] as num).toDouble()),
        ratio = (j['ratio'] as num).toDouble(),
        insets = [for (final v in j['insets'] as List) (v as num).toDouble()];
  final String name;
  final TargetPlatform platform;
  final Size size;
  final double ratio;
  final List<double> insets; // top, right, bottom, left (logical)
}

class _Shot {
  _Shot(this.entry, this.preview, this.name, this.device, this.locale, this.brightness, this.scale, this.file);
  final Entry entry;
  final Preview preview;
  final String name;
  final _Device device;
  final Locale locale;
  final Brightness brightness;
  final double scale;
  final String file;
}

/// The previews of [entries] (each annotation that is a [Preview] or [MultiPreview], transformed).
List<(Entry, Preview)> previewsOf(List<Entry> entries) => [
      for (final e in entries)
        for (final a in e.annotations)
          if (a is Preview) (e, a.transform()) else if (a is MultiPreview) for (final p in a.transform()) (e, p),
    ];

Locale _locale(String tag) {
  final parts = tag.replaceAll('_', '-').split('-');
  String? script;
  String? country;
  for (final p in parts.skip(1)) {
    if (p.length == 4) {
      script = p;
    } else {
      country = p;
    }
  }
  return Locale.fromSubtags(languageCode: parts[0], scriptCode: script, countryCode: country);
}

String _tag(Locale l) => l.toLanguageTag();

final _fontFiles = <String, ByteData>{};

/// [family] from [files], each file read once however many families use it.
Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    if (!File(f).existsSync()) continue;
    loader.addFont(Future.value(_fontFiles.putIfAbsent(f, () => ByteData.sublistView(File(f).readAsBytesSync()))));
  }
  await loader.load();
}

/// The app's own fonts (pubspec `fonts:`, packages' fonts such as CupertinoIcons), from the
/// FontManifest `flutter test` bundles.
Future<void> _appFonts() async {
  final String manifest;
  try {
    manifest = await rootBundle.loadString('FontManifest.json');
  } on Object {
    return;
  }
  for (final family in json.decode(manifest) as List) {
    final loader = FontLoader((family as Map)['family'] as String);
    for (final font in family['fonts'] as List) {
      loader.addFont(rootBundle.load((font as Map)['asset'] as String));
    }
    await loader.load();
  }
}

bool _matches(String name, List<String> globs) => globs.isEmpty ||
    globs.any((g) => RegExp('^${RegExp.escape(g).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$').hasMatch(name));

String _clean(String s) => s.replaceAll('/', '-').replaceAll(':', '-');

/// Every shot for this process's language, in a fixed order.
List<_Shot> _plan(List<Entry> entries, Map<String, dynamic> job) {
  final devices = [for (final d in job['devices'] as List) _Device(d as Map<String, dynamic>)];
  final language = job['language'] as String;
  final appearances = [for (final a in job['appearances'] as List) a == 'dark' ? Brightness.dark : Brightness.light];
  final scales = [for (final s in job['fontScales'] as List) (s as num).toDouble()];
  final filter = [for (final p in job['previews'] as List) p as String];
  final output = job['output'] as String;
  final names = <String, int>{};
  final shots = <_Shot>[];
  for (final (entry, preview) in previewsOf(entries)) {
    final name = preview.name ?? entry.function;
    if (!_matches(name, filter)) continue;
    // A preview's own locale, brightness and text scale win over the run's.
    // A pinned locale renders once: in its own language's process, else in the first one's.
    final own = preview.localizations?.call().locale;
    if (own != null) {
      final languages = job['languages'] as List;
      if (language != (languages.contains(_tag(own)) ? _tag(own) : languages.first)) continue;
    }
    final locale = own ?? _locale(language);
    final brightnesses = preview.brightness != null ? [preview.brightness!] : appearances;
    final textScales = preview.textScaleFactor != null ? [preview.textScaleFactor!] : scales;
    for (final device in devices) {
      for (final b in brightnesses) {
        for (final s in textScales) {
          var base = '${_clean(device.name)}-${_clean(name)}';
          if (preview.brightness == null && (brightnesses.length > 1 || b == Brightness.dark)) base += b == Brightness.dark ? '-dark' : '-light';
          if (preview.textScaleFactor == null && (textScales.length > 1 || s != 1.0)) base += '-x${s.toString().replaceAll(RegExp(r'\.0$'), '')}';
          final dir = '$output/${_tag(locale)}';
          final n = names.update('$dir/$base', (v) => v + 1, ifAbsent: () => 1);
          shots.add(_Shot(entry, preview, name, device, locale, b, s, '$dir/$base${n > 1 ? ' $n' : ''}.png'));
        }
      }
    }
  }
  return shots;
}

Widget _content(Entry e, Preview p) {
  Widget build() {
    final t = e.target;
    final Object built = t is Widget Function() ? t() : (t as Function)();
    if (built is Widget) return built;
    if (built is WidgetBuilder) return Builder(builder: built);
    throw StateError('${e.function} returns ${built.runtimeType}, not a Widget or WidgetBuilder');
  }

  final wrapper = p.wrapper;
  return Builder(builder: (_) => wrapper == null ? build() : wrapper(build()));
}

/// The previewer's layers around a preview, inside out: wrapper, theme, size, media query
/// (brightness, text scale, size), localizations — in a MaterialApp as the previewer's own.
Widget _tree(_Shot s, GlobalKey key) {
  final p = s.preview;
  final content = _content(s.entry, p);
  final theme = p.theme?.call();
  final themed = theme == null
      ? content
      : Builder(builder: (context) {
          final (material, cupertino) = theme.themeForBrightness(MediaQuery.platformBrightnessOf(context));
          Widget r = content;
          if (material != null) r = Theme(data: material, child: r);
          if (cupertino != null) r = CupertinoTheme(data: cupertino, child: r);
          return r;
        });
  final size = p.size;
  final component = size != null;
  final sized = !component
      ? themed
      : SizedBox(width: size.width == double.infinity ? null : size.width, height: size.height == double.infinity ? null : size.height, child: themed);
  final queried = Builder(builder: (context) {
    var data = MediaQuery.of(context).copyWith(platformBrightness: s.brightness, textScaler: TextScaler.linear(s.scale));
    if (size != null) data = data.copyWith(size: Size(size.width.isFinite ? size.width : data.size.width, size.height.isFinite ? size.height : data.size.height));
    return MediaQuery(data: data, child: sized);
  });
  final l10n = p.localizations?.call();
  final localized = l10n == null
      ? queried
      : Localizations(locale: s.locale, delegates: [...?l10n.localizationsDelegates, ...kDefaultLocalizations()], child: queried);
  // Components are captured at their own size; screens fill the device.
  final home = component
      ? Align(alignment: AlignmentDirectional.topStart, child: RepaintBoundary(key: key, child: Material(type: MaterialType.canvas, child: localized)))
      : Material(child: localized);
  // Without flutter_localizations Material speaks English only: the language's text direction
  // still applies (previews with their own MaterialApp read the platform locale).
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(),
    darkTheme: ThemeData.dark(),
    themeMode: s.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    locale: kHasGlobalLocalizations ? s.locale : const Locale('en', 'US'),
    supportedLocales: [kHasGlobalLocalizations ? s.locale : const Locale('en', 'US')],
    localizationsDelegates: kDefaultLocalizations(),
    home: kHasGlobalLocalizations ? home : Directionality(textDirection: _rtl.contains(s.locale.languageCode) ? TextDirection.rtl : TextDirection.ltr, child: home),
  );
  return component ? app : RepaintBoundary(key: key, child: app);
}

const _rtl = {'ar', 'fa', 'he', 'ur', 'ps', 'yi', 'dv', 'ku', 'sd', 'ug'};

/// Whether [kDefaultLocalizations] are flutter_localizations' (every language).
bool kHasGlobalLocalizations = false;

/// Material, Cupertino and widgets localizations for every language (flutter_localizations when
/// the project has it, which also gives right-to-left layouts), set by the generated file.
List<LocalizationsDelegate<Object?>> Function() kDefaultLocalizations = () => const [
      DefaultMaterialLocalizations.delegate,
      DefaultCupertinoLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ];

/// Renders this process's shots: the job (a JSON file) says the language, devices, appearances,
/// text scales, output folder and fonts; one result line per shot goes to its results file.
void run(List<Entry> entries, String jobPath) {
  final job = json.decode(File(jobPath).readAsStringSync()) as Map<String, dynamic>;
  testWidgets('swiftshot ${job['language']}', (tester) async {
    // One line per shot, written straight away: a process that dies still says how far it got.
    final results = File(job['results'] as String)..writeAsStringSync('');
    void result(Map<String, Object?> line) => results.writeAsStringSync('${json.encode(line)}\n', mode: FileMode.append, flush: true);
    debugDisableShadows = false;
    try {
      await tester.runAsync(() async {
        for (final f in (job['fonts'] as Map).entries) {
          await _font(f.key as String, [for (final p in f.value as List) p as String]);
        }
        await _appFonts();
      });
      final settle = Duration(milliseconds: ((job['delay'] as num? ?? 0) * 1000).round());
      for (final s in _plan(entries, job)) {
        final t0 = DateTime.now();
        final key = GlobalKey();
        try {
          final d = s.device;
          tester.view.devicePixelRatio = d.ratio;
          tester.view.physicalSize = d.size * d.ratio;
          final pad = FakeViewPadding(top: d.insets[0] * d.ratio, right: d.insets[1] * d.ratio, bottom: d.insets[2] * d.ratio, left: d.insets[3] * d.ratio);
          tester.view.padding = pad;
          tester.view.viewPadding = pad;
          tester.platformDispatcher.localesTestValue = [s.locale];
          tester.platformDispatcher.localeTestValue = s.locale;
          tester.platformDispatcher.platformBrightnessTestValue = s.brightness;
          tester.platformDispatcher.textScaleFactorTestValue = s.scale;
          debugDefaultTargetPlatformOverride = d.platform;
          // From an empty tree: no state carries over from the previous shot.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(_tree(s, key));
          // End states: animations play out (a sheet's slide, a dialog's fade), endless ones
          // are cut at 10 s of their own clock.
          try {
            await tester.pumpAndSettle(const Duration(milliseconds: 16), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
          } on FlutterError {
            await tester.pump();
          }
          if (settle > Duration.zero) await tester.pump(settle);
          final error = tester.takeException();
          if (error != null && !'$error'.contains("This application's locale")) throw error;
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final png = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: d.ratio);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final size = '${image.width}x${image.height}';
            image.dispose();
            return (data!.buffer.asUint8List(), size);
          });
          File(s.file)
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(png!.$1);
          result({'ok': true, 'file': s.file, 'preview': s.name, 'device': d.name, 'language': _tag(s.locale),
            'appearance': s.brightness == Brightness.dark ? 'dark' : 'light', 'fontScale': s.scale, 'size': png.$2,
            'millis': DateTime.now().difference(t0).inMilliseconds, 'script': s.entry.script, 'line': s.entry.line});
        } on Object catch (e) {
          result({'ok': false, 'file': s.file, 'preview': s.name, 'device': s.device.name, 'language': _tag(s.locale),
            'error': e.toString().split('\n').first, 'script': s.entry.script, 'line': s.entry.line});
          await tester.pumpWidget(const SizedBox());
          tester.takeException();
        }
      }
    } finally {
      debugDisableShadows = true;
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
      tester.platformDispatcher.clearAllTestValues();
    }
  }, timeout: Timeout.none);
}
