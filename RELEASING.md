# Випуск LingoPop

Цей документ для мейнтейнера. Інструкції для кінцевого користувача та документація публічного репо живуть у `public-repo/` і публікуються скриптом `scripts/sync-public-repo.sh`.

## Вміст публічного репо

Все що з'являється в публічному репо живе у `public-repo/` цього приватного репо:

```
public-repo/
├── README.md                       # Сторінка продукту на github.com/slucheninov/lingopop
├── LICENSE                         # Ліцензія на розповсюдження бінарників
├── PRIVACY.md                      # Політика конфіденційності
├── CHANGELOG.md                    # Історія версій (ведеться вручну)
├── docs/
│   └── screenshots/                # PNG-скріншоти з README
│       └── README.md               # Інструкції що сюди класти
└── .github/
    └── ISSUE_TEMPLATE/
        ├── bug_report.yml          # Шаблон баг-репорту
        ├── feature_request.yml
        └── config.yml              # Вимикає порожні issues, додає посилання
```

Джерело правди — тут, у приватному репо. Публічне репо — downstream:
- **Бінарні артефакти** (.dmg, .zip) — публікує release workflow при пуші тегу.
- **Документація** (README, CHANGELOG, шаблони) — публікує `scripts/sync-public-repo.sh` при ручному запуску.

Скріншоти, додані напряму в публічне репо через веб-інтерфейс, sync-скрипт зберігає — він не видаляє `.png/.jpg/.jpeg/.gif` файли яких немає в `public-repo/docs/screenshots/`.

## Архітектура

```
┌──────────────────────────┐       push tag v0.2.2        ┌──────────────────────────┐
│   PRIVATE repo (source)  │ ──────────────────────────►  │  GitHub Actions          │
│                          │                              │  macos-14 runner         │
│   .github/workflows/     │                              │  • xcodegen + xcodebuild │
│   release.yml            │                              │  • universal arm64+x86_64│
└──────────────────────────┘                              │  • ad-hoc codesign       │
                                                          │  • build .dmg + .zip     │
                                                          └────────────┬─────────────┘
                                                                       │ gh release create
                                                                       ▼
                                                          ┌──────────────────────────┐
                                                          │  PUBLIC repo (releases)  │
                                                          │  Release v0.2.2          │
                                                          │  • LingoPop-...dmg       │
                                                          │  • LingoPop-...zip       │
                                                          └──────────────────────────┘
```

## Одноразове налаштування GitHub

### 1. Створити публічне репо

На GitHub створити нове публічне репо (наприклад `slucheninov/lingopop`). Вихідний код туди не йде — тільки релізи та документація продукту.

Потім запушити вміст `public-repo/`:

```bash
./scripts/sync-public-repo.sh "Initial public repo content"
```

Повторювати при кожній зміні README / CHANGELOG / шаблонів issues / тощо.

### 2. Створити Personal Access Token

Workflow потребує токен що може писати релізи в **публічне** репо з **приватного**. Використовувати **fine-grained PAT**.

- Перейти на [github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new)
- **Token name:** `LingoPop release publisher`
- **Expiration:** 1 рік (потрібно буде оновлювати)
- **Resource owner:** ваш акаунт
- **Repository access** → **Only select repositories** → вибрати тільки **публічне** репо
- **Permissions** → **Repository permissions**:
  - **Contents** → **Read and write**
  - **Metadata** → Read-only (додається автоматично)
- Згенерувати. Скопіювати токен (`github_pat_...`) — показується тільки раз.

### 3. Додати секрет і змінну в приватне репо

У **приватному** репо:

- **Settings → Secrets and variables → Actions → Secrets → New repository secret**
  - Name: `PUBLIC_REPO_TOKEN`
  - Value: PAT з кроку 2

- **Settings → Secrets and variables → Actions → Variables → New repository variable**
  - Name: `PUBLIC_REPO`
  - Value: `owner/repo` публічного репо, наприклад `slucheninov/lingopop`

⚠️ Переконатися що `PUBLIC_REPO` вказує на **публічне** репо, а не приватне. Якщо вказати приватне — PAT (обмежений тільки публічним репо) отримає HTTP 404 на `gh release create`.

### 4. Запушити workflow

Переконатися що `.github/workflows/release.yml` закомічений і запушений у приватне репо. Налаштування завершено.

---

## Випуск нової версії

Повний чеклист для випуску, наприклад `0.2.2`:

### 1. Переконатися що гілка чиста

```bash
git pull
git status   # має бути clean
```

### 2. Оновити версію в project.yml

У `project.yml` змінити `MARKETING_VERSION`:

```yaml
MARKETING_VERSION: "0.2.2"
```

Це потрібно щоб дев-збірки (`./build.sh`) та вкладка About у застосунку показували правильну версію. CI бере версію з тегу, але `project.yml` має бути синхронізований.

### 3. Оновити CHANGELOG

У `public-repo/CHANGELOG.md` додати запис вгорі:

```markdown
## v0.2.2 — 2026-05-17

- Що змінилось
- Що полагодили
```

### 4. Закомітити і запушити

```bash
git add project.yml public-repo/CHANGELOG.md
git commit -m "Release v0.2.2"
git push
```

### 5. Поставити тег → запускає CI

```bash
git tag v0.2.2
git push origin v0.2.2
```

CI (`.github/workflows/release.yml`) зробить все інше:
1. Встановить Xcode + xcodegen на macos-14 раннері
2. Запустить `./scripts/release.sh 0.2.2` → `dist/LingoPop-0.2.2-mac-universal.{dmg,zip}`
3. Згенерує release notes з git log з попереднього тегу
4. Створить реліз у публічному репо через `gh release create v0.2.2`

Через ~5 хвилин реліз з'явиться в публічному репо.

### 6. Синхронізувати документацію (якщо змінювались README / скріншоти)

```bash
./scripts/sync-public-repo.sh "Update docs for v0.2.2"
```

Скрипт клонує публічне репо, синхронізує `public-repo/` в нього (зберігаючи скріншоти), комітить і пушить.

---

## Локальний dry run

Перед пушем тегу можна перевірити що CI збере:

```bash
./scripts/release.sh 0.2.2
# перевірити dist/LingoPop-0.2.2-mac-universal.{dmg,zip}
```

Локальна збірка використовує сертифікат `LingoPop Dev` якщо він є в кейчейні; CI підписує ad-hoc. Поведінка для користувачів однакова.

## Ручний запуск без тегу

Можна запустити збірку вручну з GitHub UI:

**Actions → Release → Run workflow** → ввести версію → Run.

Створює справжній реліз у публічному репо — використовувати обережно.

## Версіонування

Версія живе в одному місці: `MARKETING_VERSION` у `project.yml`.

- `./build.sh` → бере з `project.yml` (About у застосунку показує цю версію)
- `./scripts/release.sh` без аргументу → читає з `project.yml` через awk
- `./scripts/release.sh 0.2.2` → перекриває аргументом (CI використовує тег)
- `Info.plist` → `CFBundleShortVersionString = $(MARKETING_VERSION)` (змінна збірки, не рядок)

Якщо тег `v0.2.2` вже існує — потрібно спочатку видалити реліз у публічному репо, бо `gh release create` відмовляється перезаписувати. Простіше використати новий тег.

## Підписання коду — поточний стан

Членства в Apple Developer Program немає, тому:

- CI підписує ad-hoc (`codesign --sign -`). Застосунок **не нотаризований**.
- macOS Gatekeeper при першому запуску покаже попередження. Користувач має натиснути правою кнопкою → **Open** один раз, після чого Gatekeeper запам'ятає рішення.
- README у публічному репо це документує.

Якщо з'явиться Apple Developer ID ($99/рік):
1. Експортувати Developer ID Application сертифікат як p12
2. Додати `MACOS_CERT_P12_BASE64` + `MACOS_CERT_PASSWORD` у секрети репо
3. Оновити workflow — імпорт сертифікату в тимчасовий кейчейн + підпис ним
4. Додати крок нотаризації (`xcrun notarytool submit`) — потрібні Apple ID + app-specific password

## Усунення проблем

- **"PUBLIC_REPO is not set"** — пропустили крок 3. Додати змінну.
- **"PUBLIC_REPO_TOKEN is not set"** — те саме, додати секрет.
- **`gh release create` повертає "HTTP 403"** — PAT не має `Contents: Read and write` на публічному репо, або він прострочений. Перегенерувати.
- **`gh release create` повертає "HTTP 404: Not Found .../releases"** — PAT не бачить репо. Причини: `PUBLIC_REPO` вказує не на те репо (часто приватне замість публічного), публічне репо не існує, або PAT обмежений іншим репо. Перевірити URL публічного репо в браузері і що список "Only select repositories" в PAT містить саме його.
- **`gh release create` повертає "release already exists"** — цей тег вже використовувався. Видалити існуючий реліз у публічному репо або використати новий тег.
- **Збірка на раннері падає з помилками codesign** — зазвичай крок `xattr -cr` у `release.sh` щось пропустив. Дивитись лог workflow.
- **`lipo -archs` показує тільки одну архітектуру** — застряг `ONLY_ACTIVE_ARCH`. Скрипт примусово ставить `NO`, але якщо кастомізувати — переконатись що залишається.
