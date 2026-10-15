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
│                          │                              │  macos-15 runner         │
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

Основний шлях — єдиний оркестратор:

```bash
./scripts/publish-release.sh patch --note "Fixed fallback handling for provider errors"
./scripts/publish-release.sh minor \
  --note "Added a new translation workflow" \
  --note "Improved popup accessibility" \
  --message "Release v0.4.0"
./scripts/publish-release.sh 0.4.1 --notes-file /path/to/release-notes.md
```

Він перевіряє чистий `main`, синхронність з `origin/main` та відсутність дубльованого тегу/релізу, збільшує `MARKETING_VERSION` і `CURRENT_PROJECT_VERSION`, додає секцію нової версії до `public-repo/CHANGELOG.md`, запускає `./build.sh`, атомарно комітить `project.yml` разом із changelog і пушить приватний `main`. Далі він запускає `scripts/sync-public-repo.sh`, який синхронізує changelog та іншу документацію у публічний репо, створює annotated-тег у приватному репо, чекає саме на запущений цим тегом workflow `Release` і перевіряє публічні `.dmg`, `.zip` та їх `SHA256SUMS`.

Release notes обов'язкові для нового випуску й ніколи не генеруються автоматично:

- `--note TEXT` додає один пункт списку; опцію можна повторювати.
- `--notes-file PATH` вставляє вміст Markdown-файлу як тіло секції. Файл не повинен містити ATX-заголовок рівня `##` (включно з порожнім `##`), бо заголовок версії створює оркестратор. Setext-заголовки (`Title` + `---`) дозволені як частина тіла.
- `--note` та `--notes-file` взаємовиключні.

Перед справжнім випуском можна подивитися план без запису файлів і без мережевих запитів:

```bash
./scripts/publish-release.sh patch --note "Describe the release" --dry-run
```

Dry-run працює і з dirty worktree, але явно покаже це як blocker для справжнього запуску. Remote-теги, GitHub release та актуальність `origin/main` у dry-run навмисно не перевіряються, щоб він залишався no-network. Для Git read-команд встановлюється `GIT_OPTIONAL_LOCKS=0`, тому dry-run також не оновлює optional Git metadata на кшталт index refresh.

`--skip-build` — ризикований явний override. Скрипт виділяє його попередженням; використовувати лише коли цей самий source commit уже перевірений:

```bash
./scripts/publish-release.sh 0.4.1 --skip-build --note "Describe the release"
```

Dry-run перевіряє release notes та показує запланований заголовок changelog, але не змінює `project.yml` або `public-repo/CHANGELOG.md`.

### Продовження після часткового збою

Remote Git/GitHub state є джерелом правди. Якщо запуск уже створив version commit, але зупинився на push, public sync, tag, CI або перевірці assets, повторити команду з **точною** версією:

```bash
./scripts/publish-release.sh 0.4.1
```

Для resume release notes повторно передавати не потрібно: секція вже є в release-коміті. Resume підтримується лише коли `HEAD` — валідний release-коміт, який змінив тільки `project.yml` і `public-repo/CHANGELOG.md`, збільшив build number рівно на 1, додав рівно одну секцію цільової версії, а `origin/main` вказує на цей commit або його прямого parent. Наявні local/remote tag приймаються лише якщо вони вказують на цей exact commit; тег ніколи не пересувається і force-push не використовується. Якщо публічний release вже існує, скрипт знаходить відповідний tag-triggered run і повторно перевіряє assets/checksums.

CI (`.github/workflows/release.yml`) після push тегу:
1. Встановлює Xcode + xcodegen на macos-15 runner (Xcode 16.4; actions закріплені по commit SHA; `xcodegen` ставиться через brew без піну версії).
2. Запускає `./scripts/release.sh <version>`.
3. Генерує release notes (секція `## v<version>` з `public-repo/CHANGELOG.md`, без приватних commit-повідомлень) та `SHA256SUMS`.
4. Створює release у публічному репо.

Локальна перевірка YAML або локальна збірка не вважається підтвердженням CI: оркестратор завершується успішно лише після `conclusion=success` exact workflow run та перевірки завантажених артефактів.

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

Створює справжній реліз у публічному репо — використовувати обережно. Запуск дозволений лише з гілки за замовчуванням (workflow падає на іншій гілці).

## Версіонування

Версія і build number живуть у `project.yml`: `MARKETING_VERSION` має SemVer `X.Y.Z`, а числовий `CURRENT_PROJECT_VERSION` збільшується на 1 для кожного випуску.

- `./build.sh` → бере з `project.yml` (About у застосунку показує цю версію)
- `./scripts/release.sh` без аргументу → читає з `project.yml` через awk
- `./scripts/release.sh 0.2.2` → перекриває аргументом (CI використовує тег)
- `Info.plist` → `CFBundleShortVersionString = $(MARKETING_VERSION)` (змінна збірки, не рядок)

Теги релізів незмінні. Якщо тег уже вказує не на очікуваний release-коміт, потрібно випустити нову версію; скрипт не видаляє та не пересуває теги.

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
