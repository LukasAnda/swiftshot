// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'Habits';

  @override
  String get healthConnect => 'ヘルスコネクト';

  @override
  String get backupSync => 'バックアップと同期';

  @override
  String get tabToday => '今日';

  @override
  String get tabStats => '統計';

  @override
  String get tabHistory => '履歴';

  @override
  String get tabSettings => '設定';

  @override
  String get statistics => '統計';

  @override
  String get habitWater => '水を飲む';

  @override
  String get habitRun => '朝のランニング';

  @override
  String get habitRead => '20ページ読む';

  @override
  String get habitMeditate => '瞑想';

  @override
  String get habitJournal => '日記';

  @override
  String get detailWater => '8杯中3杯';

  @override
  String get detailRun => '5.2 km';

  @override
  String get detailRead => '20ページ中8ページ';

  @override
  String get detailMeditate => '10分';

  @override
  String get detailJournal => '今日はまだ';

  @override
  String get greeting => 'おはようございます、Maraさん';

  @override
  String get summaryBody => '今日の残りはあと3つ。ランニングは31日連続です。';

  @override
  String get filterAll => 'すべて';

  @override
  String get filterMorning => '朝';

  @override
  String get filterEvening => '夜';

  @override
  String get newHabit => '新しい習慣';

  @override
  String get upNext => 'このあと';

  @override
  String get remindersOn => 'リマインダーオン';

  @override
  String get noteNextGlass => '次の1杯';

  @override
  String get notePagesToGo => '残り12ページ';

  @override
  String get noteThreeLines => '3行で十分';

  @override
  String get insightTitle => '朝が得意なタイプです';

  @override
  String get insightBody =>
      '9:00前に予定した習慣は94%、20:00以降は61%達成しています。日記を朝に移してみましょう。';

  @override
  String get nextMilestone => '次のマイルストーン';

  @override
  String get milestoneTitle => 'ランニング50日連続';

  @override
  String get completionRate => '達成率';

  @override
  String vsLastWeek(String delta) {
    return '先週比 $delta';
  }

  @override
  String get last7Days => '過去7日間';

  @override
  String get last30Days => '過去30日間';

  @override
  String get range => '期間';

  @override
  String get rangeWeek => '週';

  @override
  String get rangeMonth => '月';

  @override
  String get rangeYear => '年';

  @override
  String get currentStreak => '現在の連続記録';

  @override
  String get bestStreak => '最長記録';

  @override
  String get checkIns => 'チェックイン';

  @override
  String get consistency => '継続度';

  @override
  String get less => '少';

  @override
  String get more => '多';

  @override
  String get byHabit => '習慣別';

  @override
  String get highlights => 'ハイライト';

  @override
  String get bestDay => 'ベストな曜日';

  @override
  String get bestDayValue => '水曜日 · 96%';

  @override
  String get bestTime => 'ベストな時間';

  @override
  String get bestTimeValue => '9:00前';

  @override
  String get mostConsistent => '最も継続';

  @override
  String get needsAttention => '要注意';

  @override
  String get needsAttentionValue => '日記 · 47%';

  @override
  String get perfectDay => 'パーフェクトな日';

  @override
  String get inProgress => '進行中';

  @override
  String get allHabitsCompleted => 'すべての習慣を達成';

  @override
  String nOf5Habits(int count) {
    return '5件中$count件';
  }

  @override
  String nOfMDone(int done, int total) {
    return '$total件中$done件完了';
  }

  @override
  String ofTotal(int total) {
    return '/ $total';
  }

  @override
  String get sectionReminders => 'リマインダー';

  @override
  String get sectionGeneral => '一般';

  @override
  String get sectionData => 'データ';

  @override
  String get sectionAbout => '情報';

  @override
  String get dailyReminder => '毎日のリマインダー';

  @override
  String get reminderTime => 'リマインダーの時刻';

  @override
  String get sounds => 'サウンド';

  @override
  String get weekStartsOn => '週の始まり';

  @override
  String get monday => '月曜日';

  @override
  String get sunday => '日曜日';

  @override
  String get appearance => '外観';

  @override
  String get appearanceSystem => 'システム';

  @override
  String get exportHistory => '履歴を書き出す';

  @override
  String get rateHabits => 'Habitsを評価';

  @override
  String get privacy => 'プライバシー';

  @override
  String get version => 'バージョン';

  @override
  String get dataFooter => 'データはお使いのデバイスにのみ保存されます。';

  @override
  String get planSince => 'Habits Plus · 2024年から';

  @override
  String get welcomeTitle => '大切なことに、続けられるリズムを。';

  @override
  String get welcomeBody => '1日1回チェックするだけ。連続記録を積み重ね、1週間の形が見えてきます。';

  @override
  String get getStarted => 'はじめる';

  @override
  String get haveAccount => 'アカウントをお持ちの方';

  @override
  String get personalBest => '自己ベスト';

  @override
  String get daysInARow => '日連続';

  @override
  String get name => '名前';

  @override
  String get icon => 'アイコン';

  @override
  String get repeat => '繰り返し';

  @override
  String get everyDay => '毎日';

  @override
  String get remindMe => 'リマインド';

  @override
  String get time => '時刻';

  @override
  String get add => '追加';

  @override
  String get cancel => 'キャンセル';

  @override
  String get delete => '削除';

  @override
  String get deleteTitle => '「水を飲む」を削除しますか？';

  @override
  String get deleteBody => '12日連続の記録と履歴が削除されます。';

  @override
  String get shareStreak => '連続記録を共有';

  @override
  String days(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count日間',
    );
    return '$_temp0';
  }

  @override
  String nCheckIns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'チェックイン$count回',
    );
    return '$_temp0';
  }

  @override
  String daysToGo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'あと$count日',
    );
    return '$_temp0';
  }

  @override
  String dayStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count日連続',
    );
    return '$_temp0';
  }

  @override
  String lastNWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '過去$count週間',
    );
    return '$_temp0';
  }
}
