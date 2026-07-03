import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'state.dart';

/// Tiny in-app i18n. Each key maps to [en, pl, uk]. Use `context.t('key')`,
/// or `context.t('key', {'n': 3})` for `{n}`-style placeholders.
const List<String> kLangs = ['en', 'pl', 'uk'];
const Map<String, String> kLangNames = {
  'en': 'English',
  'pl': 'Polski',
  'uk': 'Українська',
};

class L10n {
  static int _idx(String lang) {
    final i = kLangs.indexOf(lang);
    return i < 0 ? 0 : i;
  }

  static String tr(String lang, String key, [Map<String, Object>? args]) {
    final entry = _m[key];
    var s = entry == null ? key : entry[_idx(lang)];
    if (args != null) {
      args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    }
    return s;
  }

  static const Map<String, List<String>> _m = {
    // nav
    'nav_today': ['Today', 'Dziś', 'Сьогодні'],
    'nav_tasks': ['Quests', 'Zadania', 'Завдання'],
    'nav_rooms': ['Rooms', 'Pokoje', 'Кімнати'],
    'nav_family': ['Family', 'Rodzina', 'Сім\'я'],
    'nav_cal': ['Calendar', 'Kalendarz', 'Календар'],
    'nav_goals': ['Goals', 'Cele', 'Цілі'],
    'nav_more': ['More', 'Więcej', 'Більше'],

    // gamification / quests
    'quests': ['Quests', 'Zadania', 'Завдання'],
    'quest_board': ['Quest board', 'Tablica zadań', 'Дошка завдань'],
    'quest_board_sub': [
      'pick a quest, earn xp & coins',
      'wybierz zadanie, zdobywaj xp i monety',
      'обери завдання, заробляй xp і монети'
    ],
    'todays_quests': ['Today\'s quests', 'Dzisiejsze zadania', 'Сьогоднішні завдання'],
    'level_label': ['Level {lvl} · {name}', 'Poziom {lvl} · {name}', 'Рівень {lvl} · {name}'],
    'xp_to_next': ['{xp} xp to level {lvl}', '{xp} xp do poziomu {lvl}', '{xp} xp до рівня {lvl}'],
    'daily_goal': ['Daily goal', 'Cel dzienny', 'Денна ціль'],
    'day_streak': ['day streak', 'dni z rzędu', 'днів поспіль'],
    'coins_lc': ['coins', 'monety', 'монети'],
    'see_all': ['see all', 'zobacz wszystkie', 'усі'],
    'shortcuts': ['shortcuts', 'skróty', 'швидкі дії'],
    'sc_rewards': ['rewards', 'nagrody', 'нагороди'],
    'q_all': ['all', 'wszystkie', 'усі'],
    'q_quick': ['quick', 'szybkie', 'швидкі'],
    'q_epic': ['epic', 'epickie', 'епічні'],
    'claimed_xp': ['claimed +{n} xp 🎉', 'zdobyto +{n} xp 🎉', 'отримано +{n} xp 🎉'],
    'go': ['go', 'start', 'вперед'],
    'xp': ['xp', 'xp', 'xp'],

    // common
    'cancel': ['Cancel', 'Anuluj', 'Скасувати'],
    'delete': ['Delete', 'Usuń', 'Видалити'],
    'add': ['Add', 'Dodaj', 'Додати'],
    'save': ['Save', 'Zapisz', 'Зберегти'],
    'logout': ['Log out', 'Wyloguj', 'Вийти'],
    'pts': ['pts', 'pkt', 'бал.'],
    'net_error': ['Network error', 'Błąd sieci', 'Помилка мережі'],
    'pending': ['pending', 'oczekuje', 'очікує'],
    'soon': ['soon', 'wkrótce', 'скоро'],

    // greetings + cleanliness
    'greet_morning': ['Good morning', 'Dzień dobry', 'Доброго ранку'],
    'greet_afternoon': ['Good afternoon', 'Dzień dobry', 'Доброго дня'],
    'greet_evening': ['Good evening', 'Dobry wieczór', 'Добрий вечір'],
    'clean_sparkling': ['The house is sparkling', 'Dom lśni czystością', 'Дім сяє чистотою'],
    'clean_good': ['Looking good', 'Całkiem nieźle', 'Виглядає добре'],
    'clean_love': ['Needs some love', 'Wymaga uwagi', 'Потребує уваги'],
    'clean_dirty': ['Time to clean up', 'Czas posprzątać', 'Час прибирати'],
    'avg_clean': ['Average cleanliness {n}%', 'Średnia czystość {n}%', 'Середня чистота {n}%'],
    'leader': ['Leader · {name}', 'Lider · {name}', 'Лідер · {name}'],

    // today
    'effort_today': ['Effort today', 'Wysiłek dziś', 'Зусилля сьогодні'],
    'effort_of': ['{n} / {t} pts', '{n} / {t} pkt', '{n} / {t} бал.'],
    'todo': ['To do', 'Do zrobienia', 'Зробити'],
    'done': ['Done', 'Zrobione', 'Готово'],
    'missed': ['Missed', 'Przepadło', 'Пропущено'],
    'todays_tasks': ['Today\'s tasks', 'Dzisiejsze zadania', 'Сьогоднішні завдання'],
    'n_total': ['{n} total', '{n} łącznie', '{n} всього'],
    'all_done_today': ['All done for today! 🎉', 'Wszystko zrobione na dziś! 🎉', 'Все зроблено на сьогодні! 🎉'],
    'pending_approvals': ['Pending approvals', 'Oczekujące zatwierdzenia', 'Очікують підтвердження'],
    'wants_done': ['{name} wants to mark this done', '{name} chce oznaczyć to jako zrobione', '{name} хоче позначити це як виконане'],
    'approved': ['Approved', 'Zatwierdzono', 'Підтверджено'],
    'rejected': ['Rejected', 'Odrzucono', 'Відхилено'],
    'nice_pts': ['Nice! +{n} pts', 'Brawo! +{n} pkt', 'Чудово! +{n} бал.'],
    'sent_approval': ['Sent for approval ✋', 'Wysłano do zatwierdzenia ✋', 'Надіслано на підтвердження ✋'],

    // freq + diff
    'freq_daily': ['Daily', 'Codziennie', 'Щодня'],
    'freq_every2': ['Every 2 days', 'Co 2 dni', 'Кожні 2 дні'],
    'freq_weekly': ['Weekly', 'Co tydzień', 'Щотижня'],
    'freq_biweekly': ['Biweekly', 'Co 2 tyg.', 'Раз на 2 тижні'],
    'freq_monthly': ['Monthly', 'Co miesiąc', 'Щомісяця'],
    'freq_custom': ['Custom', 'Własne', 'Власне'],
    'diff_easy': ['Easy', 'Łatwe', 'Легке'],
    'diff_medium': ['Medium', 'Średnie', 'Середнє'],
    'diff_hard': ['Hard', 'Trudne', 'Важке'],

    // tasks
    'tasks_title': ['Tasks', 'Zadania', 'Завдання'],
    'tasks_sub': ['{n} total · {d} done today', '{n} łącznie · {d} dziś', '{n} всього · {d} сьогодні'],
    'seg_all': ['All', 'Wszystkie', 'Усі'],
    'seg_today': ['Today', 'Dziś', 'Сьогодні'],
    'seg_done': ['Done', 'Zrobione', 'Готові'],
    'no_tasks': ['No tasks here yet.', 'Brak zadań.', 'Поки немає завдань.'],
    'delete_task_q': ['Delete task?', 'Usunąć zadanie?', 'Видалити завдання?'],
    'will_be_removed': ['"{name}" will be removed.', '"{name}" zostanie usunięte.', '"{name}" буде видалено.'],
    'task_deleted': ['Task deleted', 'Zadanie usunięte', 'Завдання видалено'],
    'new_task': ['New task', 'Nowe zadanie', 'Нове завдання'],
    'task_label': ['Task', 'Zadanie', 'Завдання'],
    'task_hint': ['e.g. Wipe the counters', 'np. Przetrzyj blaty', 'напр. Протерти стільниці'],
    'room_label': ['Room', 'Pokój', 'Кімната'],
    'select_room': ['Select a room', 'Wybierz pokój', 'Виберіть кімнату'],
    'assign_to': ['Assign to', 'Przypisz do', 'Призначити'],
    'anyone': ['Anyone', 'Ktokolwiek', 'Будь-хто'],
    'repeats': ['Repeats', 'Powtarza się', 'Повторюється'],
    'difficulty': ['Difficulty', 'Trudność', 'Складність'],
    'needs_approval': ['Needs approval', 'Wymaga zatwierdzenia', 'Потребує підтвердження'],
    'one_time': ['One-time task', 'Zadanie jednorazowe', 'Одноразове завдання'],
    'add_task': ['Add task', 'Dodaj zadanie', 'Додати завдання'],
    'task_suggestions': ['Suggestions', 'Sugestie', 'Пропозиції'],
    'tap_suggestion': ['Tap a task to use it', 'Dotknij, aby użyć', 'Торкніться, щоб обрати'],
    'give_task_name': ['Give the task a name', 'Podaj nazwę zadania', 'Вкажіть назву завдання'],
    'add_room_first': ['Add a room first (Rooms tab)', 'Najpierw dodaj pokój (zakładka Pokoje)', 'Спершу додайте кімнату (вкладка Кімнати)'],
    'task_added': ['Task added', 'Zadanie dodane', 'Завдання додано'],

    // rooms
    'rooms_title': ['Rooms', 'Pokoje', 'Кімнати'],
    'n_rooms': ['{n} rooms', '{n} pokoi', '{n} кімнат'],
    'add_first_room': ['Add your first room', 'Dodaj pierwszy pokój', 'Додайте першу кімнату'],
    'never_cleaned': ['Never cleaned', 'Nigdy nie sprzątane', 'Ніколи не прибирали'],
    'cleaned_today': ['Cleaned today', 'Sprzątnięte dziś', 'Прибрано сьогодні'],
    'cleaned_yesterday': ['Cleaned yesterday', 'Sprzątnięte wczoraj', 'Прибрано вчора'],
    'cleaned_days': ['Cleaned {n} days ago', 'Sprzątnięte {n} dni temu', 'Прибрано {n} дн. тому'],
    'clean_badge': ['Clean!', 'Czysto!', 'Чисто!'],
    'needs_work': ['Needs work', 'Do sprzątania', 'Потрібно прибрати'],
    'n_task': ['{n} task', '{n} zadanie', '{n} завдання'],
    'n_tasks': ['{n} tasks', '{n} zadań', '{n} завдань'],
    'delete_room_q': ['Delete room?', 'Usunąć pokój?', 'Видалити кімнату?'],
    'room_will_remove': ['"{name}" and its tasks will be removed.', '"{name}" i jego zadania zostaną usunięte.', '"{name}" та його завдання буде видалено.'],
    'room_deleted': ['Room deleted', 'Pokój usunięty', 'Кімнату видалено'],
    'new_room': ['New room', 'Nowy pokój', 'Нова кімната'],
    'room_name_hint': ['Room name (e.g. Kitchen)', 'Nazwa pokoju (np. Kuchnia)', 'Назва кімнати (напр. Кухня)'],
    'add_room': ['Add room', 'Dodaj pokój', 'Додати кімнату'],
    'give_room_name': ['Give the room a name', 'Podaj nazwę pokoju', 'Вкажіть назву кімнати'],
    'room_added': ['Room added', 'Pokój dodany', 'Кімнату додано'],

    // family
    'family_title': ['Family', 'Rodzina', 'Сім\'я'],
    'leaderboard_title': ['Leaderboard', 'Ranking', 'Рейтинг'],
    'nav_lb': ['Ranking', 'Ranking', 'Рейтинг'],
    'manage_members': ['Manage household members', 'Zarządzaj domownikami', 'Керуйте учасниками'],
    'n_members': ['{n} members', '{n} domowników', '{n} учасників'],
    'period_week': ['This week', 'Ten tydzień', 'Цей тиждень'],
    'period_month': ['This month', 'Ten miesiąc', 'Цей місяць'],
    'period_all': ['All time', 'Cały czas', 'За весь час'],
    'lb_error': ['Could not load leaderboard', 'Nie można wczytać rankingu', 'Не вдалося завантажити рейтинг'],
    'creator_locked': ['Family creator — can\'t be changed or removed', 'Twórca rodziny — nie można zmienić ani usunąć', 'Засновник сім\'ї — не можна змінити чи видалити'],
    'make_member': ['Make member', 'Ustaw jako domownika', 'Зробити учасником'],
    'make_admin': ['Make admin', 'Ustaw jako administratora', 'Зробити адміністратором'],
    'remove_member': ['Remove member', 'Usuń domownika', 'Видалити учасника'],
    'role_updated': ['Role updated', 'Rola zaktualizowana', 'Роль оновлено'],
    'member_removed': ['Member removed', 'Domownik usunięty', 'Учасника видалено'],
    'member_added': ['Member added', 'Domownik dodany', 'Учасника додано'],
    'add_member': ['Add family member', 'Dodaj domownika', 'Додати учасника'],
    'member_name_hint': ['Name (e.g. Mom)', 'Imię (np. Mama)', 'Ім\'я (напр. Мама)'],
    'add_member_btn': ['Add member', 'Dodaj domownika', 'Додати учасника'],
    'enter_name': ['Enter a name', 'Podaj imię', 'Вкажіть ім\'я'],

    // calendar
    'calendar_title': ['Calendar', 'Kalendarz', 'Календар'],
    'cal_no_data': ['No data', 'Brak danych', 'Немає даних'],

    // goals
    'goals_title': ['Family goals', 'Cele rodziny', 'Сімейні цілі'],
    'your_coins': ['YOUR COINS', 'TWOJE MONETY', 'ВАШІ МОНЕТИ'],
    'add_first_goal': ['Add the first goal for your family!', 'Dodaj pierwszy cel dla rodziny!', 'Додайте першу ціль для сім\'ї!'],
    'no_goals': ['No goals yet', 'Brak celów', 'Поки немає цілей'],
    'redeem': ['Redeem', 'Wykorzystaj', 'Отримати'],
    'not_enough': ['Not enough', 'Za mało', 'Замало'],
    'mark_given': ['Mark given', 'Oznacz wydane', 'Позначити видане'],
    'redeemed_this': ['{name} redeemed this', '{name} wykorzystał(a) to', '{name} отримав(ла) це'],
    'marked_given': ['Marked as given', 'Oznaczono jako wydane', 'Позначено як видане'],
    'delete_goal_q': ['Delete goal?', 'Usunąć cel?', 'Видалити ціль?'],
    'goal_deleted': ['Goal deleted', 'Cel usunięty', 'Ціль видалено'],
    'new_goal': ['New goal', 'Nowy cel', 'Нова ціль'],
    'reward_hint': ['Reward name (e.g. Movie night)', 'Nazwa nagrody (np. Wieczór filmowy)', 'Назва нагороди (напр. Кіновечір)'],
    'desc_optional': ['Description (optional)', 'Opis (opcjonalnie)', 'Опис (необов\'язково)'],
    'price_coins': ['Price in coins', 'Cena w monetach', 'Ціна в монетах'],
    'add_goal': ['Add goal', 'Dodaj cel', 'Додати ціль'],
    'goal_templates': ['Quick templates', 'Szybkie szablony', 'Швидкі шаблони'],
    'enter_name_price': ['Enter a name and price', 'Podaj nazwę i cenę', 'Вкажіть назву та ціну'],
    'goal_added': ['Goal added', 'Cel dodany', 'Ціль додано'],
    'redeemed': ['Redeemed', 'Wykorzystano', 'Отримано'],

    // badges
    'badges_title': ['Badges', 'Odznaki', 'Нагороди'],
    'earned': ['Earned', 'Zdobyte', 'Отримано'],
    'all': ['All', 'Wszyscy', 'Усі'],
    'cat_first_steps': ['First steps', 'Pierwsze kroki', 'Перші кроки'],
    'cat_day_streaks': ['Day streaks', 'Serie dni', 'Серії днів'],
    'cat_special': ['Special', 'Specjalne', 'Особливі'],

    // badge names + descriptions (key: b_<key>_n / b_<key>_d)
    'b_first_step_n': ['First Step', 'Pierwszy Krok', 'Перший крок'],
    'b_first_step_d': ['Complete your first task', 'Wykonaj pierwsze zadanie', 'Виконай перше завдання'],
    'b_tasks_10_n': ['Hardworking', 'Pracowity', 'Працьовитий'],
    'b_tasks_10_d': ['Complete 10 tasks', 'Wykonaj 10 zadań', 'Виконай 10 завдань'],
    'b_tasks_50_n': ['Superhero', 'Superbohater', 'Супергерой'],
    'b_tasks_50_d': ['Complete 50 tasks', 'Wykonaj 50 zadań', 'Виконай 50 завдань'],
    'b_tasks_100_n': ['Legend', 'Legenda', 'Легенда'],
    'b_tasks_100_d': ['Complete 100 tasks', 'Wykonaj 100 zadań', 'Виконай 100 завдань'],
    'b_streak_3_n': ['3-Day Streak', 'Seria 3 dni', 'Серія 3 дні'],
    'b_streak_3_d': ['3 days in a row', '3 dni z rzędu', '3 дні поспіль'],
    'b_streak_7_n': ['Week Streak', 'Seria tygodnia', 'Серія тижня'],
    'b_streak_7_d': ['7 days in a row', '7 dni z rzędu', '7 днів поспіль'],
    'b_streak_30_n': ['Unbreakable', 'Niezniszczalny', 'Незламний'],
    'b_streak_30_d': ['30 days in a row', '30 dni z rzędu', '30 днів поспіль'],
    'b_daily_5_n': ['Lightning', 'Błyskawica', 'Блискавка'],
    'b_daily_5_d': ['5 tasks in one day', '5 zadań w jeden dzień', '5 завдань за день'],
    'b_perfect_room_n': ['Perfectionist', 'Perfekcjonista', 'Перфекціоніст'],
    'b_perfect_room_d': ['Get a room to 100%', 'Doprowadź pokój do 100%', 'Доведи кімнату до 100%'],
    'b_hard_worker_n': ['Tough', 'Twardziel', 'Міцний горішок'],
    'b_hard_worker_d': ['Complete 5 hard tasks', 'Wykonaj 5 trudnych zadań', 'Виконай 5 важких завдань'],
    'b_week_champ_n': ['Cleaner of the Week', 'Sprzątacz Tygodnia', 'Прибиральник тижня'],
    'b_week_champ_d': ['Most points this week', 'Najwięcej punktów w tygodniu', 'Найбільше балів за тиждень'],
    'b_month_champ_n': ['Master of the Month', 'Mistrz Miesiąca', 'Майстер місяця'],
    'b_month_champ_d': ['Most points this month', 'Najwięcej punktów w miesiącu', 'Найбільше балів за місяць'],
    'b_early_bird_n': ['Early Bird', 'Ranny Ptaszek', 'Рання пташка'],
    'b_early_bird_d': ['A task before 9:00', 'Zadanie przed 9:00', 'Завдання до 9:00'],
    'b_night_owl_n': ['Night Owl', 'Nocna Sowa', 'Нічна сова'],
    'b_night_owl_d': ['A task after 22:00', 'Zadanie po 22:00', 'Завдання після 22:00'],

    // profile
    'profile_title': ['Profile', 'Profil', 'Профіль'],
    'progress_next': ['Progress to next level', 'Postęp do następnego poziomu', 'Прогрес до наступного рівня'],
    'pts_to_go': ['{n} pts to go', '{n} pkt do celu', 'ще {n} бал.'],
    'max_level': ['Max level', 'Maks. poziom', 'Макс. рівень'],
    'points': ['Points', 'Punkty', 'Бали'],
    'coins': ['Coins', 'Monety', 'Монети'],
    'streak': ['Streak', 'Seria', 'Серія'],
    'my_badges_n': ['My badges ({n})', 'Moje odznaki ({n})', 'Мої нагороди ({n})'],
    'no_badges': ['Complete your first task to earn a badge!', 'Wykonaj pierwsze zadanie, aby zdobyć odznakę!', 'Виконайте перше завдання, щоб отримати нагороду!'],
    'family_code': ['Family code', 'Kod rodziny', 'Код сім\'ї'],

    // more
    'more_title': ['More', 'Więcej', 'Більше'],
    'appearance': ['Appearance', 'Wygląd', 'Вигляд'],
    'theme_light': ['Light', 'Jasny', 'Світла'],
    'theme_dark': ['Dark', 'Ciemny', 'Темна'],
    'theme_system': ['System default', 'Systemowy', 'Системна'],
    'language': ['Language', 'Język', 'Мова'],
    'ai_assistant': ['AI assistant', 'Asystent AI', 'AI-помічник'],
    'goals_nav': ['Family goals', 'Cele rodziny', 'Сімейні цілі'],
    'share_code': ['Share so others can join your family', 'Udostępnij, aby inni mogli dołączyć', 'Поділіться, щоб інші приєдналися'],
    'code_copied': ['Code copied', 'Skopiowano kod', 'Код скопійовано'],
    'edit_family_name': ['Edit family name', 'Zmień nazwę rodziny', 'Змінити назву сім\'ї'],
    'name_saved': ['Saved', 'Zapisano', 'Збережено'],

    // auth
    'welcome_back': ['Welcome back', 'Witaj ponownie', 'З поверненням'],
    'start_family': ['Start a new family', 'Załóż nową rodzinę', 'Створити нову сім\'ю'],
    'join_family': ['Join your family', 'Dołącz do rodziny', 'Приєднатися до сім\'ї'],
    'login': ['Log in', 'Zaloguj', 'Увійти'],
    'create': ['Create', 'Utwórz', 'Створити'],
    'join': ['Join', 'Dołącz', 'Приєднатись'],
    'create_account': ['Create account', 'Utwórz konto', 'Створити акаунт'],
    'family_code_hint': ['Family code (6 chars)', 'Kod rodziny (6 znaków)', 'Код сім\'ї (6 символів)'],
    'lookup_family': ['Look up family', 'Znajdź rodzinę', 'Знайти сім\'ю'],
    'who_are_you': ['{name} — who are you?', '{name} — kim jesteś?', '{name} — хто ви?'],
    'your_name': ['Your name', 'Twoje imię', 'Ваше ім\'я'],
    'family_name': ['Family name', 'Nazwa rodziny', 'Назва сім\'ї'],
    'username': ['Username', 'Nazwa użytkownika', 'Ім\'я користувача'],
    'password': ['Password', 'Hasło', 'Пароль'],
    'enter_user_pass': ['Enter a username and password.', 'Podaj nazwę użytkownika i hasło.', 'Введіть ім\'я користувача та пароль.'],
    'enter_code6': ['Enter the 6-character family code.', 'Podaj 6-znakowy kod rodziny.', 'Введіть 6-значний код сім\'ї.'],
    'pick_who': ['Look up the family and pick who you are.', 'Znajdź rodzinę i wybierz, kim jesteś.', 'Знайдіть сім\'ю та виберіть, хто ви.'],
    'net_retry': ['Network error. Try again.', 'Błąd sieci. Spróbuj ponownie.', 'Помилка мережі. Спробуйте ще.'],
    'email': ['Email address', 'Adres email', 'Адреса email'],
    'enter_email': ['Enter a valid email address.', 'Podaj poprawny adres email.', 'Введіть дійсну адресу email.'],
    'gdpr_required': ['You must accept the privacy policy.', 'Musisz zaakceptować politykę prywatności.', 'Ви повинні прийняти політику конфіденційності.'],
    'gdpr_accept': ['I accept the ', 'Akceptuję ', 'Я приймаю '],
    'privacy_policy': ['privacy policy', 'politykę prywatności', 'політику конфіденційності'],
    'forgot_password': ['Forgot password?', 'Zapomniałem hasła', 'Забули пароль?'],
    'rfid_hint': ['You can also tap your RFID card', 'Możesz też zeskanować kartę RFID', 'Ви також можете прикласти картку RFID'],
    'forgot_desc': ['Enter your registration email. We\'ll send a verification code.', 'Podaj email z rejestracji. Wyślemy kod weryfikacyjny.', 'Введіть email з реєстрації. Надішлемо код.'],
    'enter_code_desc': ['Enter the 6-digit code from your email:', 'Wpisz 6-cyfrowy kod z emaila:', 'Введіть 6-значний код з email:'],
    'check_spam': ['📁 Check your spam/junk folder if you don\'t see it.', '📁 Nie widzisz? Sprawdź folder spam/śmietnik.', '📁 Не бачите? Перевірте папку спам.'],
    'send_code': ['Send code', 'Wyślij kod', 'Надіслати код'],
    'new_password': ['New password', 'Nowe hasło', 'Новий пароль'],
    'pass_changed': ['Password changed! You can now log in.', 'Hasło zmienione! Możesz się zalogować.', 'Пароль змінено! Тепер можна увійти.'],

    // assistant
    'assistant_title': ['AI assistant', 'Asystent AI', 'AI-помічник'],
    'assistant_hint': [
      'Tap the mic and say what you did or want to do.\nE.g. "I cleaned the kitchen".',
      'Dotknij mikrofonu i powiedz, co zrobiłeś lub chcesz zrobić.\nNp. "Posprzątałem kuchnię".',
      'Торкніться мікрофона і скажіть, що зробили або хочете зробити.\nНапр. "Я прибрав кухню".'
    ],
    'tap_to_speak': ['Tap to speak', 'Dotknij, aby mówić', 'Торкніться, щоб говорити'],
    'listening': ['Listening…', 'Słucham…', 'Слухаю…'],
    'type_command': ['Or type a command', 'Lub wpisz polecenie', 'Або введіть команду'],
    'send': ['Send', 'Wyślij', 'Надіслати'],
    'assistant_lang': ['Speaking language', 'Język mówienia', 'Мова розмови'],
    'didnt_understand': ['I didn\'t understand. Try "I cleaned the kitchen".', 'Nie zrozumiałem. Spróbuj "Posprzątałem kuchnię".', 'Я не зрозумів. Спробуйте "Я прибрав кухню".'],
    'voice_added': ['Added a task ✅', 'Dodano zadanie ✅', 'Додано завдання ✅'],
    'voice_completed': ['Marked as done ✅', 'Oznaczono jako zrobione ✅', 'Позначено як виконане ✅'],
    'mic_denied': ['Microphone permission denied', 'Brak dostępu do mikrofonu', 'Немає доступу до мікрофона'],
    'mic_unavailable': ['Speech recognition unavailable on this device', 'Rozpoznawanie mowy niedostępne', 'Розпізнавання мовлення недоступне'],
    'no_speech': ['No speech detected — check your microphone', 'Nie wykryto mowy — sprawdź mikrofon', 'Мовлення не виявлено — перевірте мікрофон'],
  };
}

extension L10nContext on BuildContext {
  String t(String key, [Map<String, Object>? args]) {
    // Use read (not watch): the root MaterialApp rebuilds the whole tree on
    // language change, so widgets re-translate anyway. watch here would crash
    // when t() is called from event handlers (e.g. dialogs/onPressed).
    final lang = read<AppState>().lang;
    return L10n.tr(lang, key, args);
  }
}
