// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'Habits';

  @override
  String get healthConnect => 'Health Connect';

  @override
  String get backupSync => 'النسخ الاحتياطي والمزامنة';

  @override
  String get tabToday => 'اليوم';

  @override
  String get tabStats => 'الإحصاءات';

  @override
  String get tabHistory => 'السجل';

  @override
  String get tabSettings => 'الإعدادات';

  @override
  String get statistics => 'الإحصاءات';

  @override
  String get habitWater => 'شرب الماء';

  @override
  String get habitRun => 'الجري الصباحي';

  @override
  String get habitRead => 'قراءة 20 صفحة';

  @override
  String get habitMeditate => 'التأمل';

  @override
  String get habitJournal => 'اليوميات';

  @override
  String get detailWater => '3 من 8 أكواب';

  @override
  String get detailRun => '5.2 كم';

  @override
  String get detailRead => '8 من 20 صفحة';

  @override
  String get detailMeditate => '10 دقائق';

  @override
  String get detailJournal => 'لم يُنجز اليوم بعد';

  @override
  String get greeting => 'صباح الخير يا مارا';

  @override
  String get summaryBody =>
      'تبقّت ثلاث عادات اليوم. أنت تركض منذ 31 يومًا متتاليًا.';

  @override
  String get filterAll => 'الكل';

  @override
  String get filterMorning => 'صباحًا';

  @override
  String get filterEvening => 'مساءً';

  @override
  String get newHabit => 'عادة جديدة';

  @override
  String get upNext => 'التالي';

  @override
  String get remindersOn => 'التذكيرات مفعّلة';

  @override
  String get noteNextGlass => 'الكوب التالي';

  @override
  String get notePagesToGo => 'تبقّت 12 صفحة';

  @override
  String get noteThreeLines => 'ثلاثة أسطر تكفي';

  @override
  String get insightTitle => 'الصباح يناسبك';

  @override
  String get insightBody =>
      'تُنجز 94% من العادات المخطط لها قبل 9:00، و61% من تلك بعد 20:00. جرّب نقل اليوميات إلى الصباح.';

  @override
  String get nextMilestone => 'الإنجاز التالي';

  @override
  String get milestoneTitle => '50 يومًا من الجري المتواصل';

  @override
  String get completionRate => 'نسبة الإنجاز';

  @override
  String vsLastWeek(String delta) {
    return '$delta مقارنةً بالأسبوع الماضي';
  }

  @override
  String get last7Days => 'آخر 7 أيام';

  @override
  String get last30Days => 'آخر 30 يومًا';

  @override
  String get range => 'النطاق';

  @override
  String get rangeWeek => 'أسبوع';

  @override
  String get rangeMonth => 'شهر';

  @override
  String get rangeYear => 'سنة';

  @override
  String get currentStreak => 'السلسلة الحالية';

  @override
  String get bestStreak => 'أطول سلسلة';

  @override
  String get checkIns => 'تسجيلات';

  @override
  String get consistency => 'الانتظام';

  @override
  String get less => 'أقل';

  @override
  String get more => 'أكثر';

  @override
  String get byHabit => 'حسب العادة';

  @override
  String get highlights => 'أبرز النتائج';

  @override
  String get bestDay => 'أفضل يوم';

  @override
  String get bestDayValue => 'الأربعاء · 96%';

  @override
  String get bestTime => 'أفضل وقت';

  @override
  String get bestTimeValue => 'قبل 9:00';

  @override
  String get mostConsistent => 'الأكثر انتظامًا';

  @override
  String get needsAttention => 'يحتاج إلى اهتمام';

  @override
  String get needsAttentionValue => 'اليوميات · 47%';

  @override
  String get perfectDay => 'يوم مثالي';

  @override
  String get inProgress => 'قيد التقدم';

  @override
  String get allHabitsCompleted => 'اكتملت كل العادات';

  @override
  String nOf5Habits(int count) {
    return '$count من 5 عادات';
  }

  @override
  String nOfMDone(int done, int total) {
    return 'أُنجز $done من $total';
  }

  @override
  String ofTotal(int total) {
    return 'من $total';
  }

  @override
  String get sectionReminders => 'التذكيرات';

  @override
  String get sectionGeneral => 'عام';

  @override
  String get sectionData => 'البيانات';

  @override
  String get sectionAbout => 'حول';

  @override
  String get dailyReminder => 'تذكير يومي';

  @override
  String get reminderTime => 'وقت التذكير';

  @override
  String get sounds => 'الأصوات';

  @override
  String get weekStartsOn => 'يبدأ الأسبوع يوم';

  @override
  String get monday => 'الاثنين';

  @override
  String get sunday => 'الأحد';

  @override
  String get appearance => 'المظهر';

  @override
  String get appearanceSystem => 'النظام';

  @override
  String get exportHistory => 'تصدير السجل';

  @override
  String get rateHabits => 'قيّم Habits';

  @override
  String get privacy => 'الخصوصية';

  @override
  String get version => 'الإصدار';

  @override
  String get dataFooter => 'تبقى بياناتك على أجهزتك.';

  @override
  String get planSince => 'Habits Plus · منذ 2024';

  @override
  String get welcomeTitle => 'إيقاع ثابت للأشياء المهمة.';

  @override
  String get welcomeBody =>
      'سجّل مرة واحدة في اليوم، وحافظ على سلاسلك بصدق، وشاهد أسبوعك يتشكّل.';

  @override
  String get getStarted => 'ابدأ الآن';

  @override
  String get haveAccount => 'لديّ حساب بالفعل';

  @override
  String get personalBest => 'أفضل إنجاز';

  @override
  String get daysInARow => 'يومًا متتاليًا';

  @override
  String get name => 'الاسم';

  @override
  String get icon => 'الأيقونة';

  @override
  String get repeat => 'التكرار';

  @override
  String get everyDay => 'كل يوم';

  @override
  String get remindMe => 'ذكّرني';

  @override
  String get time => 'الوقت';

  @override
  String get add => 'إضافة';

  @override
  String get cancel => 'إلغاء';

  @override
  String get delete => 'حذف';

  @override
  String get deleteTitle => 'هل تريد حذف „شرب الماء“؟';

  @override
  String get deleteBody => 'ستُحذف سلسلتك البالغة 12 يومًا وسجلها.';

  @override
  String get shareStreak => 'شارك سلسلتك';

  @override
  String days(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم',
      many: '$count يومًا',
      few: '$count أيام',
      two: 'يومان',
      one: 'يوم واحد',
      zero: '$count يوم',
    );
    return '$_temp0';
  }

  @override
  String nCheckIns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تسجيل',
      many: '$count تسجيلًا',
      few: '$count تسجيلات',
      two: 'تسجيلان',
      one: 'تسجيل واحد',
      zero: '$count تسجيل',
    );
    return '$_temp0';
  }

  @override
  String daysToGo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تبقّى $count يوم',
      many: 'تبقّى $count يومًا',
      few: 'تبقّت $count أيام',
      two: 'تبقّى يومان',
      one: 'تبقّى يوم واحد',
      zero: 'تبقّى $count يوم',
    );
    return '$_temp0';
  }

  @override
  String dayStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'سلسلة $count يوم',
      many: 'سلسلة $count يومًا',
      few: 'سلسلة $count أيام',
      two: 'سلسلة يومين',
      one: 'سلسلة يوم واحد',
      zero: 'سلسلة $count يوم',
    );
    return '$_temp0';
  }

  @override
  String lastNWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'آخر $count أسبوع',
      many: 'آخر $count أسبوعًا',
      few: 'آخر $count أسابيع',
      two: 'آخر أسبوعين',
      one: 'آخر أسبوع',
      zero: 'آخر $count أسبوع',
    );
    return '$_temp0';
  }
}
