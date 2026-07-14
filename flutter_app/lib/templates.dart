/// Predefined task suggestions and goal templates, per language.
/// Mirrors _TASK_SUGG and _GOAL_TPL in templates/index.html.
library;

class TaskSuggestion {
  final String name;
  final String diff; // easy | medium | hard
  const TaskSuggestion(this.name, this.diff);
}

class GoalTemplate {
  final String emoji;
  final String name;
  final int price;
  final String description;
  const GoalTemplate(this.emoji, this.name, this.price, this.description);
}

const Map<String, List<TaskSuggestion>> _taskSugg = {
  'pl': [
    TaskSuggestion('Odkurzanie', 'medium'), TaskSuggestion('Mycie podłóg', 'hard'),
    TaskSuggestion('Wycieranie kurzu', 'easy'), TaskSuggestion('Mycie okien', 'hard'),
    TaskSuggestion('Zmywanie naczyń', 'easy'), TaskSuggestion('Czyszczenie zlewu', 'easy'),
    TaskSuggestion('Mycie toalety', 'medium'), TaskSuggestion('Czyszczenie wanny', 'hard'),
    TaskSuggestion('Zmiana pościeli', 'medium'), TaskSuggestion('Pranie', 'medium'),
    TaskSuggestion('Prasowanie', 'medium'), TaskSuggestion('Wyrzucenie śmieci', 'easy'),
    TaskSuggestion('Mycie lodówki', 'hard'), TaskSuggestion('Czyszczenie kuchenki', 'medium'),
    TaskSuggestion('Wycieranie luster', 'easy'), TaskSuggestion('Czyszczenie mikrofalówki', 'easy'),
    TaskSuggestion('Mycie kafelek', 'hard'), TaskSuggestion('Odkurzanie kanapy', 'medium'),
    TaskSuggestion('Porządkowanie szaf', 'hard'), TaskSuggestion('Mycie drzwi', 'medium'),
    TaskSuggestion('Wyprowadzanie psa', 'easy'), TaskSuggestion('Karmienie psa', 'easy'),
    TaskSuggestion('Karmienie kota', 'easy'), TaskSuggestion('Czyszczenie kuwety', 'medium'),
    TaskSuggestion('Czesanie zwierzaka', 'easy'), TaskSuggestion('Mycie miski zwierzaka', 'easy'),
    TaskSuggestion('Sprzątanie po zwierzaku', 'medium'), TaskSuggestion('Kąpiel psa', 'hard'),
  ],
  'en': [
    TaskSuggestion('Vacuuming', 'medium'), TaskSuggestion('Mopping floors', 'hard'),
    TaskSuggestion('Dusting', 'easy'), TaskSuggestion('Washing windows', 'hard'),
    TaskSuggestion('Doing dishes', 'easy'), TaskSuggestion('Cleaning the sink', 'easy'),
    TaskSuggestion('Cleaning the toilet', 'medium'), TaskSuggestion('Cleaning the bathtub', 'hard'),
    TaskSuggestion('Changing bedsheets', 'medium'), TaskSuggestion('Laundry', 'medium'),
    TaskSuggestion('Ironing', 'medium'), TaskSuggestion('Taking out trash', 'easy'),
    TaskSuggestion('Cleaning the fridge', 'hard'), TaskSuggestion('Cleaning the stove', 'medium'),
    TaskSuggestion('Wiping mirrors', 'easy'), TaskSuggestion('Cleaning the microwave', 'easy'),
    TaskSuggestion('Scrubbing tiles', 'hard'), TaskSuggestion('Vacuuming the sofa', 'medium'),
    TaskSuggestion('Organizing wardrobes', 'hard'), TaskSuggestion('Wiping doors', 'medium'),
    TaskSuggestion('Walking the dog', 'easy'), TaskSuggestion('Feeding the dog', 'easy'),
    TaskSuggestion('Feeding the cat', 'easy'), TaskSuggestion('Cleaning the litter box', 'medium'),
    TaskSuggestion('Brushing the pet', 'easy'), TaskSuggestion('Washing the pet bowl', 'easy'),
    TaskSuggestion('Cleaning up after the pet', 'medium'), TaskSuggestion('Bathing the dog', 'hard'),
  ],
  'uk': [
    TaskSuggestion('Пилосос', 'medium'), TaskSuggestion('Миття підлог', 'hard'),
    TaskSuggestion('Витирання пилу', 'easy'), TaskSuggestion('Миття вікон', 'hard'),
    TaskSuggestion('Миття посуду', 'easy'), TaskSuggestion('Чищення раковини', 'easy'),
    TaskSuggestion('Миття туалету', 'medium'), TaskSuggestion('Чищення ванни', 'hard'),
    TaskSuggestion('Зміна постільної білизни', 'medium'), TaskSuggestion('Прання', 'medium'),
    TaskSuggestion('Прасування', 'medium'), TaskSuggestion('Винесення сміття', 'easy'),
    TaskSuggestion('Миття холодильника', 'hard'), TaskSuggestion('Чищення плити', 'medium'),
    TaskSuggestion('Протирання дзеркал', 'easy'), TaskSuggestion('Чищення мікрохвильовки', 'easy'),
    TaskSuggestion('Чищення кахелю', 'hard'), TaskSuggestion('Пилосос дивану', 'medium'),
    TaskSuggestion('Упорядкування шаф', 'hard'), TaskSuggestion('Протирання дверей', 'medium'),
    TaskSuggestion('Вигул собаки', 'easy'), TaskSuggestion('Годування собаки', 'easy'),
    TaskSuggestion('Годування кота', 'easy'), TaskSuggestion('Чищення лотка', 'medium'),
    TaskSuggestion('Розчісування тварини', 'easy'), TaskSuggestion('Миття миски тварини', 'easy'),
    TaskSuggestion('Прибирання після тварини', 'medium'), TaskSuggestion('Купання собаки', 'hard'),
  ],
};

const Map<String, List<GoalTemplate>> _goalTpl = {
  'pl': [
    GoalTemplate('🏎️', 'Gokarty', 150, 'Wypad na tory gokartowe!'),
    GoalTemplate('🎬', 'Kino', 80, 'Wieczór filmowy w kinie'),
    GoalTemplate('🍕', 'Pizza na wynos', 50, 'Zamawiamy ulubioną pizzę'),
    GoalTemplate('🍽️', 'Kolacja w restauracji', 120, 'Wspólna kolacja na mieście'),
    GoalTemplate('🎳', 'Kręgle', 90, 'Wieczór na kręgielni'),
    GoalTemplate('🏊', 'Aquapark', 200, 'Cały dzień w aquaparku'),
    GoalTemplate('🎲', 'Gra planszowa', 30, 'Wieczór z grą planszową'),
    GoalTemplate('🔐', 'Escape room', 200, 'Ucieczka z pokoju zagadek'),
    GoalTemplate('🎮', 'Nowa gra', 120, 'Nowa gra do wspólnego grania'),
    GoalTemplate('🍦', 'Lody', 25, 'Wypad na ulubione lody'),
    GoalTemplate('🚗', 'Wycieczka', 300, 'Weekendowy wypad samochodem'),
    GoalTemplate('📺', 'Netflix weekend', 20, 'Maraton seriali przez cały weekend'),
    GoalTemplate('🎡', 'Park rozrywki', 250, 'Dzień w parku rozrywki'),
    GoalTemplate('🧁', 'Ciastka z cukierni', 35, 'Pyszne ciastka z ulubionej cukierni'),
    GoalTemplate('🎯', 'Paintball', 180, 'Bitwa paintballowa z drużyną'),
  ],
  'en': [
    GoalTemplate('🏎️', 'Go-karting', 150, 'Trip to the go-kart track!'),
    GoalTemplate('🎬', 'Cinema', 80, 'Movie night at the cinema'),
    GoalTemplate('🍕', 'Pizza night', 50, 'Order our favourite pizza'),
    GoalTemplate('🍽️', 'Restaurant dinner', 120, 'Family dinner out'),
    GoalTemplate('🎳', 'Bowling', 90, 'Evening at the bowling alley'),
    GoalTemplate('🏊', 'Water park', 200, 'Full day at the water park'),
    GoalTemplate('🎲', 'Board game night', 30, 'Evening with a board game'),
    GoalTemplate('🔐', 'Escape room', 200, 'Escape from the puzzle room'),
    GoalTemplate('🎮', 'New game', 120, 'A new game to play together'),
    GoalTemplate('🍦', 'Ice cream', 25, 'Trip for favourite ice cream'),
    GoalTemplate('🚗', 'Road trip', 300, 'Weekend trip by car'),
    GoalTemplate('📺', 'Netflix weekend', 20, 'Series marathon all weekend'),
    GoalTemplate('🎡', 'Amusement park', 250, 'Day at the amusement park'),
    GoalTemplate('🧁', 'Bakery treats', 35, 'Delicious cakes from the bakery'),
    GoalTemplate('🎯', 'Paintball', 180, 'Paintball battle with the team'),
  ],
  'uk': [
    GoalTemplate('🏎️', 'Картинг', 150, 'Поїздка на картодром!'),
    GoalTemplate('🎬', 'Кіно', 80, 'Кіновечір у кінотеатрі'),
    GoalTemplate('🍕', 'Піца додому', 50, 'Замовляємо улюблену піцу'),
    GoalTemplate('🍽️', 'Вечеря в ресторані', 120, 'Спільна вечеря в місті'),
    GoalTemplate('🎳', 'Боулінг', 90, 'Вечір у боулінг-клубі'),
    GoalTemplate('🏊', 'Аквапарк', 200, 'Цілий день в аквапарку'),
    GoalTemplate('🎲', 'Настільна гра', 30, 'Вечір з настільною грою'),
    GoalTemplate('🔐', 'Квест-кімната', 200, 'Вихід з кімнати загадок'),
    GoalTemplate('🎮', 'Нова гра', 120, 'Нова гра для спільного грання'),
    GoalTemplate('🍦', 'Морозиво', 25, 'Поїздка за улюбленим морозивом'),
    GoalTemplate('🚗', 'Поїздка', 300, 'Виїзд на вихідні'),
    GoalTemplate('📺', 'Netflix-вихідні', 20, 'Марафон серіалів на вихідних'),
    GoalTemplate('🎡', 'Парк розваг', 250, 'День у парку розваг'),
    GoalTemplate('🧁', 'Тістечка з кондитерської', 35, 'Смачні тістечка з улюбленої кондитерської'),
    GoalTemplate('🎯', 'Пейнтбол', 180, 'Пейнтбольна битва з командою'),
  ],
};

List<TaskSuggestion> taskSuggestions(String lang) =>
    _taskSugg[lang] ?? _taskSugg['en']!;
List<GoalTemplate> goalTemplates(String lang) =>
    _goalTpl[lang] ?? _goalTpl['en']!;
