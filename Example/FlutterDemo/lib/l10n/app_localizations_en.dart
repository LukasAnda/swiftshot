// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Habits';

  @override
  String get healthConnect => 'Health Connect';

  @override
  String get backupSync => 'Backup & sync';

  @override
  String get tabToday => 'Today';

  @override
  String get tabStats => 'Stats';

  @override
  String get tabHistory => 'History';

  @override
  String get tabSettings => 'Settings';

  @override
  String get statistics => 'Statistics';

  @override
  String get habitWater => 'Drink water';

  @override
  String get habitRun => 'Morning run';

  @override
  String get habitRead => 'Read 20 pages';

  @override
  String get habitMeditate => 'Meditate';

  @override
  String get habitJournal => 'Journal';

  @override
  String get detailWater => '3 of 8 glasses';

  @override
  String get detailRun => '5.2 km';

  @override
  String get detailRead => '8 of 20 pages';

  @override
  String get detailMeditate => '10 minutes';

  @override
  String get detailJournal => 'Not yet today';

  @override
  String get greeting => 'Good morning, Mara';

  @override
  String get summaryBody =>
      'Three habits left today. You’re on a 31-day run streak.';

  @override
  String get filterAll => 'All';

  @override
  String get filterMorning => 'Morning';

  @override
  String get filterEvening => 'Evening';

  @override
  String get newHabit => 'New habit';

  @override
  String get upNext => 'Up next';

  @override
  String get remindersOn => 'Reminders on';

  @override
  String get noteNextGlass => 'Next glass';

  @override
  String get notePagesToGo => '12 pages to go';

  @override
  String get noteThreeLines => 'Three lines are enough';

  @override
  String get insightTitle => 'Mornings work for you';

  @override
  String get insightBody =>
      'You finish 94% of the habits you plan before 9:00, and 61% of those after 20:00. Try moving Journal to the morning.';

  @override
  String get nextMilestone => 'Next milestone';

  @override
  String get milestoneTitle => '50-day run streak';

  @override
  String get completionRate => 'Completion rate';

  @override
  String vsLastWeek(String delta) {
    return '$delta vs last week';
  }

  @override
  String get last7Days => 'Last 7 days';

  @override
  String get last30Days => 'Last 30 days';

  @override
  String get range => 'Range';

  @override
  String get rangeWeek => 'Week';

  @override
  String get rangeMonth => 'Month';

  @override
  String get rangeYear => 'Year';

  @override
  String get currentStreak => 'Current streak';

  @override
  String get bestStreak => 'Best streak';

  @override
  String get checkIns => 'Check-ins';

  @override
  String get consistency => 'Consistency';

  @override
  String get less => 'Less';

  @override
  String get more => 'More';

  @override
  String get byHabit => 'By habit';

  @override
  String get highlights => 'Highlights';

  @override
  String get bestDay => 'Best day';

  @override
  String get bestDayValue => 'Wednesday · 96%';

  @override
  String get bestTime => 'Best time';

  @override
  String get bestTimeValue => 'Before 9:00';

  @override
  String get mostConsistent => 'Most consistent';

  @override
  String get needsAttention => 'Needs attention';

  @override
  String get needsAttentionValue => 'Journal · 47%';

  @override
  String get perfectDay => 'Perfect day';

  @override
  String get inProgress => 'In progress';

  @override
  String get allHabitsCompleted => 'All habits completed';

  @override
  String nOf5Habits(int count) {
    return '$count of 5 habits';
  }

  @override
  String nOfMDone(int done, int total) {
    return '$done of $total done';
  }

  @override
  String ofTotal(int total) {
    return 'of $total';
  }

  @override
  String get sectionReminders => 'Reminders';

  @override
  String get sectionGeneral => 'General';

  @override
  String get sectionData => 'Data';

  @override
  String get sectionAbout => 'About';

  @override
  String get dailyReminder => 'Daily reminder';

  @override
  String get reminderTime => 'Reminder time';

  @override
  String get sounds => 'Sounds';

  @override
  String get weekStartsOn => 'Week starts on';

  @override
  String get monday => 'Monday';

  @override
  String get sunday => 'Sunday';

  @override
  String get appearance => 'Appearance';

  @override
  String get appearanceSystem => 'System';

  @override
  String get exportHistory => 'Export history';

  @override
  String get rateHabits => 'Rate Habits';

  @override
  String get privacy => 'Privacy';

  @override
  String get version => 'Version';

  @override
  String get dataFooter => 'Your data stays on your devices.';

  @override
  String get planSince => 'Habits Plus · since 2024';

  @override
  String get welcomeTitle => 'A steady rhythm for the things that matter.';

  @override
  String get welcomeBody =>
      'Check in once a day, keep your streaks honest and see your week take shape.';

  @override
  String get getStarted => 'Get started';

  @override
  String get haveAccount => 'I already have an account';

  @override
  String get personalBest => 'Personal best';

  @override
  String get daysInARow => 'days in a row';

  @override
  String get name => 'Name';

  @override
  String get icon => 'Icon';

  @override
  String get repeat => 'Repeat';

  @override
  String get everyDay => 'Every day';

  @override
  String get remindMe => 'Remind me';

  @override
  String get time => 'Time';

  @override
  String get add => 'Add';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get deleteTitle => 'Delete “Drink water”?';

  @override
  String get deleteBody =>
      'Your 12-day streak and its history will be removed.';

  @override
  String get shareStreak => 'Share your streak';

  @override
  String days(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return '$_temp0';
  }

  @override
  String nCheckIns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count check-ins',
      one: '$count check-in',
    );
    return '$_temp0';
  }

  @override
  String daysToGo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days to go',
      one: '$count day to go',
    );
    return '$_temp0';
  }

  @override
  String dayStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-day streak',
      one: '$count-day streak',
    );
    return '$_temp0';
  }

  @override
  String lastNWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Last $count weeks',
      one: 'Last week',
    );
    return '$_temp0';
  }
}
