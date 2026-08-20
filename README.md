# JobTrack

A native **iOS 17+ / macOS 14+** SwiftUI app to organize your job search:

1. **Store job offers** you spot on LinkedIn — imported *manually* (no scraping, see below)
2. **Store your CV(s)** as PDF with extracted text
3. **Generate tailored cover letters** with the Claude API
4. **Browse / filter / organize** saved offers

> ⚠️ **No LinkedIn scraping.** LinkedIn's Terms of Service forbid automated
> extraction and there is no public API for the personal feed. JobTrack never
> automates reading your LinkedIn feed. Instead it offers three fast *manual*
> import paths:
>
> - **Share Extension** — share a post/offer from Safari or the LinkedIn app straight into JobTrack
> - **Paste text / URL** — paste the raw offer text and let Claude parse it (title, company, location, description)
> - **Screenshot + OCR** — paste a screenshot and extract the text with the Vision framework

## Nouveautés

- **Fil** : traduction FR automatique et **analyse IA** de chaque offre (résumé,
  tags, score CV). Sources **France Travail** + **Adzuna** (alternative légale à
  LinkedIn/Indeed) avec filtre mots-clés (défaut : `nucléaire`).
- **Relances** : suivi des candidatures, détection « pas de réponse depuis
  N jours », **notifications** locales, e-mails de candidature/relance rédigés
  par Claude, envoi via **Gmail** ou ta messagerie, et détection des réponses.

### Configurer les clés (toutes gratuites, dans **Réglages**)

| Service | Où créer la clé | Ce qu'on stocke (Keychain) |
|---|---|---|
| **Anthropic** | console.anthropic.com | clé API |
| **France Travail** | francetravail.io (espace développeur, API « Offres d'emploi v2 ») | client id + secret |
| **Adzuna** | developer.adzuna.com | app_id + app_key |
| **Gmail** | console.cloud.google.com → identifiant OAuth **type iOS**, API Gmail activée, scopes `gmail.send` + `gmail.readonly` | client id + jetons OAuth |

Après avoir saisi les clés France Travail / Adzuna, **active la source** dans
**Fil → Sources**. Pour Gmail, **Réglages → Connecter Gmail**.

> Gmail via OAuth (PKCE) : aucun mot de passe stocké, seulement un jeton
> sécurisé dans le Keychain. L'app n'envoie jamais rien sans ton action.

## Feed tab ("Fil")

A refreshing in-app feed of job postings, sourced **only from public, legitimate
job boards** (RSS/Atom feeds and public JSON APIs such as Remotive and We Work
Remotely). This is the legal alternative to a "LinkedIn feed reader": it never
reads LinkedIn's personal feed (forbidden by their ToS, no public API), so LinkedIn
stays on the three manual import paths above.

- Pull-to-refresh, keyword filter
- One-tap **"Enregistrer dans mes offres"** → the posting enters your JobOffer
  pipeline (matching, cover-letter generation, statuses…)
- **Manage sources**: toggle the built-in feeds or add your own RSS/Atom URL
  (e.g. a company career page). Sources are stored in the App Group.

---

## Tech stack

| Concern            | Technology                                    |
|--------------------|-----------------------------------------------|
| UI                 | SwiftUI                                        |
| Persistence        | SwiftData (App Group–backed `ModelContainer`)  |
| AI                 | Anthropic Claude Messages API                  |
| OCR                | Vision framework                               |
| Secure storage     | Keychain (API key — never in `UserDefaults`)   |
| PDF read/export    | PDFKit                                          |

The Claude model used for API calls is **`claude-sonnet-4-6`** (configurable in
`Shared/Config/AppConfig.swift`).

---

## Architecture

Clean **Views / ViewModels / Services** separation. The Claude service is fully
isolated behind a protocol so it is testable and mockable.

```
JobTrack/
├── project.yml                     # XcodeGen spec → generates JobTrack.xcodeproj
├── README.md
├── SETUP.md                        # Step-by-step Xcode setup (capabilities, API key)
│
├── Shared/                         # Code shared by the app AND the Share Extension
│   ├── Config/
│   │   └── AppConfig.swift          # Bundle ids, App Group id, Claude model
│   ├── Models/
│   │   ├── JobOffer.swift           # @Model
│   │   ├── Resume.swift             # @Model
│   │   ├── CoverLetter.swift        # @Model
│   │   └── Enums.swift              # ApplicationStatus, LetterStatus, Tone…
│   ├── Persistence/
│   │   └── ModelContainer+Shared.swift  # App-Group-scoped SwiftData container
│   └── Services/
│       ├── Keychain/
│       │   └── KeychainService.swift
│       └── Claude/
│           ├── ClaudeAPIService.swift   # protocol + live implementation
│           ├── ClaudeModels.swift       # request/response DTOs
│           └── ClaudeError.swift
│
├── JobTrack/                       # Main app target
│   ├── App/
│   │   ├── JobTrackApp.swift
│   │   └── RootView.swift
│   ├── Features/
│   │   ├── Offers/
│   │   │   ├── OfferListView.swift
│   │   │   ├── OfferListViewModel.swift
│   │   │   ├── OfferDetailView.swift
│   │   │   ├── OfferDetailViewModel.swift
│   │   │   ├── AddOfferView.swift
│   │   │   └── AddOfferViewModel.swift
│   │   ├── CoverLetter/
│   │   │   ├── CoverLetterView.swift
│   │   │   └── CoverLetterViewModel.swift
│   │   ├── Resume/
│   │   │   ├── ResumeListView.swift
│   │   │   └── ResumeViewModel.swift
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       └── SettingsViewModel.swift
│   ├── Services/
│   │   ├── OCRService.swift          # Vision
│   │   ├── PDFService.swift          # PDFKit read + export
│   │   └── ImportInboxService.swift  # drains Share-Extension inbox
│   ├── Components/
│   │   ├── StatusBadge.swift
│   │   └── TagChips.swift
│   └── Resources/
│       ├── Info.plist
│       ├── JobTrack.entitlements
│       └── Assets.xcassets/
│
└── ShareExtension/                 # Share Extension target
    ├── ShareViewController.swift
    ├── Info.plist
    └── ShareExtension.entitlements
```

### Data model

**JobOffer** — `id`, `title`, `company`, `location`, `descriptionText`,
`sourceURL`, `dateAdded`, `status` (à traiter / candidature envoyée / entretien /
refus / accepté), `notes`, `tags`, `matchScore?`, `rawImportText?`,
`needsParsing`, plus a `coverLetters` relationship.

**Resume** — `id`, `name`, `pdfData`, `extractedText`, `dateUpdated`, `isDefault`.
Multiple versions supported (généraliste / spécialisé).

**CoverLetter** — `id`, `content`, `dateGenerated`, `status`
(brouillon / finalisée / envoyée), `tone`, back-reference to its `JobOffer`.

---

## Build order (how this was built)

1. **CRUD offers + CV storage** (no AI) — a working, testable base
2. **Claude parsing** of pasted offer text
3. **Cover-letter generation**
4. **Share Extension** (added last — the most involved Xcode setup)

---

## Getting started

You need macOS with **Xcode 16+** (the project format emitted by the current
XcodeGen requires it). See **[SETUP.md](SETUP.md)** for the full
walkthrough (generating the project, capabilities, App Groups, and where to paste
your Anthropic API key).

```bash
brew install xcodegen        # one-time
cd JobTrack
xcodegen generate            # creates JobTrack.xcodeproj
open JobTrack.xcodeproj
```

Then in the app: **Settings → API key** and paste your Anthropic key (stored in
the Keychain). Get a key at <https://console.anthropic.com>.
