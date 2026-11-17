// Ключ передаётся при сборке: --dart-define=YT_API_KEY=...
const String kApiKey = String.fromEnvironment('YT_API_KEY');

// Адрес каталога, который наполняет Telegram-бот (подставляется при сборке).
const String kCatalogUrl = String.fromEnvironment('CATALOG_URL');

// Категории: id -> название.
const Map<String, String> kCats = {
  'cartoons': 'Мультики',
  'english': 'Английский',
  'learn': 'Обучение',
  'music': 'Музыка',
};

class Seed {
  final String name;
  final String handle; // без @
  final String lang; // ru / en
  final String cat; // cartoons / english / learn / music
  const Seed(this.name, this.handle, this.lang, this.cat);
}

// Стартовый белый список. Каналы, которые не найдутся, будут помечены
// в родительском режиме — их можно заменить или добавить свои.
const List<Seed> kSeeds = [
  Seed('Маша и Медведь', 'mashabearrussian', 'ru', 'cartoons'),
  Seed('Фиксики', 'fixiki', 'ru', 'cartoons'),
  Seed('Смешарики', 'TVSmeshariki', 'ru', 'cartoons'),
  Seed('Лунтик', 'luntik', 'ru', 'cartoons'),
  Seed('Союзмультфильм', 'soyuzmultfilm', 'ru', 'cartoons'),
  Seed('Bluey', 'Bluey', 'en', 'cartoons'),
  Seed('Peppa Pig', 'peppapig', 'en', 'cartoons'),
  Seed('Pocoyo', 'Pocoyo', 'en', 'cartoons'),
  Seed('Super Simple Songs', 'SuperSimpleSongs', 'en', 'english'),
  Seed('Alphablocks', 'Alphablocks', 'en', 'english'),
  Seed('Ms Rachel', 'msrachelforlittlelearners', 'en', 'english'),
  Seed('Sesame Street', 'sesamestreet', 'en', 'learn'),
  Seed('Numberblocks', 'Numberblocks', 'en', 'learn'),
  Seed('StoryBots', 'StoryBots', 'en', 'learn'),
  Seed('Cocomelon', 'cocomelon', 'en', 'music'),
  Seed('Little Baby Bum', 'LittleBabyBum', 'en', 'music'),
  Seed('Pinkfong', 'pinkfong', 'en', 'music'),
  Seed('Mother Goose Club', 'MotherGooseClub', 'en', 'music'),
];

// Видео скрывается, если в НАЗВАНИИ есть любая из этих подстрок (без учёта регистра).
const List<String> kStopWords = [
  // русские
  'страшил', 'страшн', 'ужас', 'монстр', 'хоррор', 'кошмар', 'убий', 'кровав', 'кровь', 'крови',
  'зомби', 'призрак', 'привидени', 'скелет', 'вампир', 'маньяк', 'демон',
  'проклят', 'чудовищ', 'мрачн', 'жутк', 'пугающ', 'пугаю', 'хэллоуин',
  'хеллоуин', 'хагги', 'хаги ваги', 'киси миси', 'поппи плейтайм', 'монстр',
  'злой клоун', 'мертвец', 'мёртвый', 'гроб', 'кладбищ', 'ведьм', 'оборотень',
  // английские
  'horror', 'scary', 'spooky', 'creepy', 'monster', 'nightmare', 'haunted',
  'ghost', 'zombie', 'killer', 'blood', 'gore', 'skibidi', 'huggy',
  'poppy playtime', 'siren head', 'backrooms', 'fnaf', 'five nights',
  'slender', 'scream', 'evil', 'demon', 'vampire', 'skeleton', 'halloween',
  'witch', 'werewolf', 'graveyard', 'dead', 'death', 'curse',
];
