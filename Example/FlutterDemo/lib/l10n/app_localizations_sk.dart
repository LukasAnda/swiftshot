// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Slovak (`sk`).
class AppLocalizationsSk extends AppLocalizations {
  AppLocalizationsSk([String locale = 'sk']) : super(locale);

  @override
  String get appName => 'Habits';

  @override
  String get healthConnect => 'Health Connect';

  @override
  String get backupSync => 'Záloha a synchronizácia';

  @override
  String get tabToday => 'Dnes';

  @override
  String get tabStats => 'Štatistiky';

  @override
  String get tabHistory => 'História';

  @override
  String get tabSettings => 'Nastavenia';

  @override
  String get statistics => 'Štatistiky';

  @override
  String get habitWater => 'Piť vodu';

  @override
  String get habitRun => 'Ranný beh';

  @override
  String get habitRead => 'Prečítať 20 strán';

  @override
  String get habitMeditate => 'Meditovať';

  @override
  String get habitJournal => 'Denník';

  @override
  String get detailWater => '3 z 8 pohárov';

  @override
  String get detailRun => '5,2 km';

  @override
  String get detailRead => '8 z 20 strán';

  @override
  String get detailMeditate => '10 minút';

  @override
  String get detailJournal => 'Dnes ešte nie';

  @override
  String get greeting => 'Dobré ráno, Mara';

  @override
  String get summaryBody => 'Dnes ešte tri návyky. Behávate už 31 dní v rade.';

  @override
  String get filterAll => 'Všetky';

  @override
  String get filterMorning => 'Ráno';

  @override
  String get filterEvening => 'Večer';

  @override
  String get newHabit => 'Nový návyk';

  @override
  String get upNext => 'Nasleduje';

  @override
  String get remindersOn => 'Pripomienky zapnuté';

  @override
  String get noteNextGlass => 'Ďalší pohár';

  @override
  String get notePagesToGo => 'Ešte 12 strán';

  @override
  String get noteThreeLines => 'Stačia tri riadky';

  @override
  String get insightTitle => 'Ránom sa vám darí';

  @override
  String get insightBody =>
      'Splníte 94 % návykov naplánovaných pred 9:00 a 61 % tých po 20:00. Skúste si denník presunúť na ráno.';

  @override
  String get nextMilestone => 'Ďalší míľnik';

  @override
  String get milestoneTitle => '50 dní behu v rade';

  @override
  String get completionRate => 'Miera plnenia';

  @override
  String vsLastWeek(String delta) {
    return '$delta oproti minulému týždňu';
  }

  @override
  String get last7Days => 'Posledných 7 dní';

  @override
  String get last30Days => 'Posledných 30 dní';

  @override
  String get range => 'Obdobie';

  @override
  String get rangeWeek => 'Týždeň';

  @override
  String get rangeMonth => 'Mesiac';

  @override
  String get rangeYear => 'Rok';

  @override
  String get currentStreak => 'Aktuálna séria';

  @override
  String get bestStreak => 'Najdlhšia séria';

  @override
  String get checkIns => 'Záznamy';

  @override
  String get consistency => 'Pravidelnosť';

  @override
  String get less => 'Menej';

  @override
  String get more => 'Viac';

  @override
  String get byHabit => 'Podľa návyku';

  @override
  String get highlights => 'Najlepšie';

  @override
  String get bestDay => 'Najlepší deň';

  @override
  String get bestDayValue => 'Streda · 96 %';

  @override
  String get bestTime => 'Najlepší čas';

  @override
  String get bestTimeValue => 'Pred 9:00';

  @override
  String get mostConsistent => 'Najpravidelnejší';

  @override
  String get needsAttention => 'Treba zlepšiť';

  @override
  String get needsAttentionValue => 'Denník · 47 %';

  @override
  String get perfectDay => 'Dokonalý deň';

  @override
  String get inProgress => 'Prebieha';

  @override
  String get allHabitsCompleted => 'Všetky návyky splnené';

  @override
  String nOf5Habits(int count) {
    return '$count z 5 návykov';
  }

  @override
  String nOfMDone(int done, int total) {
    return 'Splnené: $done z $total';
  }

  @override
  String ofTotal(int total) {
    return 'z $total';
  }

  @override
  String get sectionReminders => 'Pripomienky';

  @override
  String get sectionGeneral => 'Všeobecné';

  @override
  String get sectionData => 'Údaje';

  @override
  String get sectionAbout => 'O aplikácii';

  @override
  String get dailyReminder => 'Denná pripomienka';

  @override
  String get reminderTime => 'Čas pripomienky';

  @override
  String get sounds => 'Zvuky';

  @override
  String get weekStartsOn => 'Týždeň začína';

  @override
  String get monday => 'Pondelok';

  @override
  String get sunday => 'Nedeľa';

  @override
  String get appearance => 'Vzhľad';

  @override
  String get appearanceSystem => 'Systém';

  @override
  String get exportHistory => 'Exportovať históriu';

  @override
  String get rateHabits => 'Ohodnotiť Habits';

  @override
  String get privacy => 'Súkromie';

  @override
  String get version => 'Verzia';

  @override
  String get dataFooter => 'Vaše údaje zostávajú vo vašich zariadeniach.';

  @override
  String get planSince => 'Habits Plus · od roku 2024';

  @override
  String get welcomeTitle => 'Pokojný rytmus pre veci, na ktorých záleží.';

  @override
  String get welcomeBody =>
      'Raz denne si odškrtnite, držte svoje série poctivo a sledujte, ako sa váš týždeň formuje.';

  @override
  String get getStarted => 'Začať';

  @override
  String get haveAccount => 'Už mám účet';

  @override
  String get personalBest => 'Osobný rekord';

  @override
  String get daysInARow => 'dní v rade';

  @override
  String get name => 'Názov';

  @override
  String get icon => 'Ikona';

  @override
  String get repeat => 'Opakovať';

  @override
  String get everyDay => 'Každý deň';

  @override
  String get remindMe => 'Pripomenúť';

  @override
  String get time => 'Čas';

  @override
  String get add => 'Pridať';

  @override
  String get cancel => 'Zrušiť';

  @override
  String get delete => 'Vymazať';

  @override
  String get deleteTitle => 'Vymazať „Piť vodu“?';

  @override
  String get deleteBody =>
      'Vaša 12-dňová séria aj jej história budú odstránené.';

  @override
  String get shareStreak => 'Zdieľať sériu';

  @override
  String days(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dní',
      many: '$count dňa',
      few: '$count dni',
      one: '$count deň',
    );
    return '$_temp0';
  }

  @override
  String nCheckIns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count záznamov',
      many: '$count záznamu',
      few: '$count záznamy',
      one: '$count záznam',
    );
    return '$_temp0';
  }

  @override
  String daysToGo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ešte $count dní',
      many: 'Ešte $count dňa',
      few: 'Ešte $count dni',
      one: 'Ešte $count deň',
    );
    return '$_temp0';
  }

  @override
  String dayStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Séria: $count dní',
      many: 'Séria: $count dňa',
      few: 'Séria: $count dni',
      one: 'Séria: $count deň',
    );
    return '$_temp0';
  }

  @override
  String lastNWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Posledných $count týždňov',
      many: 'Posledných $count týždňa',
      few: 'Posledné $count týždne',
      one: 'Posledný $count týždeň',
    );
    return '$_temp0';
  }
}
