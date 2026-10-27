import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_sk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('ja'),
    Locale('sk'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Habits'**
  String get appName;

  /// No description provided for @healthConnect.
  ///
  /// In en, this message translates to:
  /// **'Health Connect'**
  String get healthConnect;

  /// No description provided for @backupSync.
  ///
  /// In en, this message translates to:
  /// **'Backup & sync'**
  String get backupSync;

  /// No description provided for @tabToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get tabToday;

  /// No description provided for @tabStats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get tabStats;

  /// No description provided for @tabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get tabHistory;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @habitWater.
  ///
  /// In en, this message translates to:
  /// **'Drink water'**
  String get habitWater;

  /// No description provided for @habitRun.
  ///
  /// In en, this message translates to:
  /// **'Morning run'**
  String get habitRun;

  /// No description provided for @habitRead.
  ///
  /// In en, this message translates to:
  /// **'Read 20 pages'**
  String get habitRead;

  /// No description provided for @habitMeditate.
  ///
  /// In en, this message translates to:
  /// **'Meditate'**
  String get habitMeditate;

  /// No description provided for @habitJournal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get habitJournal;

  /// No description provided for @detailWater.
  ///
  /// In en, this message translates to:
  /// **'3 of 8 glasses'**
  String get detailWater;

  /// No description provided for @detailRun.
  ///
  /// In en, this message translates to:
  /// **'5.2 km'**
  String get detailRun;

  /// No description provided for @detailRead.
  ///
  /// In en, this message translates to:
  /// **'8 of 20 pages'**
  String get detailRead;

  /// No description provided for @detailMeditate.
  ///
  /// In en, this message translates to:
  /// **'10 minutes'**
  String get detailMeditate;

  /// No description provided for @detailJournal.
  ///
  /// In en, this message translates to:
  /// **'Not yet today'**
  String get detailJournal;

  /// No description provided for @greeting.
  ///
  /// In en, this message translates to:
  /// **'Good morning, Mara'**
  String get greeting;

  /// No description provided for @summaryBody.
  ///
  /// In en, this message translates to:
  /// **'Three habits left today. You’re on a 31-day run streak.'**
  String get summaryBody;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterMorning.
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get filterMorning;

  /// No description provided for @filterEvening.
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get filterEvening;

  /// No description provided for @newHabit.
  ///
  /// In en, this message translates to:
  /// **'New habit'**
  String get newHabit;

  /// No description provided for @upNext.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get upNext;

  /// No description provided for @remindersOn.
  ///
  /// In en, this message translates to:
  /// **'Reminders on'**
  String get remindersOn;

  /// No description provided for @noteNextGlass.
  ///
  /// In en, this message translates to:
  /// **'Next glass'**
  String get noteNextGlass;

  /// No description provided for @notePagesToGo.
  ///
  /// In en, this message translates to:
  /// **'12 pages to go'**
  String get notePagesToGo;

  /// No description provided for @noteThreeLines.
  ///
  /// In en, this message translates to:
  /// **'Three lines are enough'**
  String get noteThreeLines;

  /// No description provided for @insightTitle.
  ///
  /// In en, this message translates to:
  /// **'Mornings work for you'**
  String get insightTitle;

  /// No description provided for @insightBody.
  ///
  /// In en, this message translates to:
  /// **'You finish 94% of the habits you plan before 9:00, and 61% of those after 20:00. Try moving Journal to the morning.'**
  String get insightBody;

  /// No description provided for @nextMilestone.
  ///
  /// In en, this message translates to:
  /// **'Next milestone'**
  String get nextMilestone;

  /// No description provided for @milestoneTitle.
  ///
  /// In en, this message translates to:
  /// **'50-day run streak'**
  String get milestoneTitle;

  /// No description provided for @completionRate.
  ///
  /// In en, this message translates to:
  /// **'Completion rate'**
  String get completionRate;

  /// No description provided for @vsLastWeek.
  ///
  /// In en, this message translates to:
  /// **'{delta} vs last week'**
  String vsLastWeek(String delta);

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get last7Days;

  /// No description provided for @last30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get last30Days;

  /// No description provided for @range.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get range;

  /// No description provided for @rangeWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get rangeWeek;

  /// No description provided for @rangeMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get rangeMonth;

  /// No description provided for @rangeYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get rangeYear;

  /// No description provided for @currentStreak.
  ///
  /// In en, this message translates to:
  /// **'Current streak'**
  String get currentStreak;

  /// No description provided for @bestStreak.
  ///
  /// In en, this message translates to:
  /// **'Best streak'**
  String get bestStreak;

  /// No description provided for @checkIns.
  ///
  /// In en, this message translates to:
  /// **'Check-ins'**
  String get checkIns;

  /// No description provided for @consistency.
  ///
  /// In en, this message translates to:
  /// **'Consistency'**
  String get consistency;

  /// No description provided for @less.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get less;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @byHabit.
  ///
  /// In en, this message translates to:
  /// **'By habit'**
  String get byHabit;

  /// No description provided for @highlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get highlights;

  /// No description provided for @bestDay.
  ///
  /// In en, this message translates to:
  /// **'Best day'**
  String get bestDay;

  /// No description provided for @bestDayValue.
  ///
  /// In en, this message translates to:
  /// **'Wednesday · 96%'**
  String get bestDayValue;

  /// No description provided for @bestTime.
  ///
  /// In en, this message translates to:
  /// **'Best time'**
  String get bestTime;

  /// No description provided for @bestTimeValue.
  ///
  /// In en, this message translates to:
  /// **'Before 9:00'**
  String get bestTimeValue;

  /// No description provided for @mostConsistent.
  ///
  /// In en, this message translates to:
  /// **'Most consistent'**
  String get mostConsistent;

  /// No description provided for @needsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get needsAttention;

  /// No description provided for @needsAttentionValue.
  ///
  /// In en, this message translates to:
  /// **'Journal · 47%'**
  String get needsAttentionValue;

  /// No description provided for @perfectDay.
  ///
  /// In en, this message translates to:
  /// **'Perfect day'**
  String get perfectDay;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get inProgress;

  /// No description provided for @allHabitsCompleted.
  ///
  /// In en, this message translates to:
  /// **'All habits completed'**
  String get allHabitsCompleted;

  /// No description provided for @nOf5Habits.
  ///
  /// In en, this message translates to:
  /// **'{count} of 5 habits'**
  String nOf5Habits(int count);

  /// No description provided for @nOfMDone.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} done'**
  String nOfMDone(int done, int total);

  /// No description provided for @ofTotal.
  ///
  /// In en, this message translates to:
  /// **'of {total}'**
  String ofTotal(int total);

  /// No description provided for @sectionReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get sectionReminders;

  /// No description provided for @sectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get sectionGeneral;

  /// No description provided for @sectionData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get sectionData;

  /// No description provided for @sectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get sectionAbout;

  /// No description provided for @dailyReminder.
  ///
  /// In en, this message translates to:
  /// **'Daily reminder'**
  String get dailyReminder;

  /// No description provided for @reminderTime.
  ///
  /// In en, this message translates to:
  /// **'Reminder time'**
  String get reminderTime;

  /// No description provided for @sounds.
  ///
  /// In en, this message translates to:
  /// **'Sounds'**
  String get sounds;

  /// No description provided for @weekStartsOn.
  ///
  /// In en, this message translates to:
  /// **'Week starts on'**
  String get weekStartsOn;

  /// No description provided for @monday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get monday;

  /// No description provided for @sunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get sunday;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @appearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get appearanceSystem;

  /// No description provided for @exportHistory.
  ///
  /// In en, this message translates to:
  /// **'Export history'**
  String get exportHistory;

  /// No description provided for @rateHabits.
  ///
  /// In en, this message translates to:
  /// **'Rate Habits'**
  String get rateHabits;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @dataFooter.
  ///
  /// In en, this message translates to:
  /// **'Your data stays on your devices.'**
  String get dataFooter;

  /// No description provided for @planSince.
  ///
  /// In en, this message translates to:
  /// **'Habits Plus · since 2024'**
  String get planSince;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'A steady rhythm for the things that matter.'**
  String get welcomeTitle;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Check in once a day, keep your streaks honest and see your week take shape.'**
  String get welcomeBody;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @haveAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get haveAccount;

  /// No description provided for @personalBest.
  ///
  /// In en, this message translates to:
  /// **'Personal best'**
  String get personalBest;

  /// No description provided for @daysInARow.
  ///
  /// In en, this message translates to:
  /// **'days in a row'**
  String get daysInARow;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @icon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get icon;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// No description provided for @everyDay.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get everyDay;

  /// No description provided for @remindMe.
  ///
  /// In en, this message translates to:
  /// **'Remind me'**
  String get remindMe;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “Drink water”?'**
  String get deleteTitle;

  /// No description provided for @deleteBody.
  ///
  /// In en, this message translates to:
  /// **'Your 12-day streak and its history will be removed.'**
  String get deleteBody;

  /// No description provided for @shareStreak.
  ///
  /// In en, this message translates to:
  /// **'Share your streak'**
  String get shareStreak;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} day} other{{count} days}}'**
  String days(int count);

  /// No description provided for @nCheckIns.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} check-in} other{{count} check-ins}}'**
  String nCheckIns(int count);

  /// No description provided for @daysToGo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} day to go} other{{count} days to go}}'**
  String daysToGo(int count);

  /// No description provided for @dayStreak.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count}-day streak} other{{count}-day streak}}'**
  String dayStreak(int count);

  /// No description provided for @lastNWeeks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Last week} other{Last {count} weeks}}'**
  String lastNWeeks(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'de', 'en', 'ja', 'sk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'sk':
      return AppLocalizationsSk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
