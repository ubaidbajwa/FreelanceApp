# FreelanceApp — Frontend (Flutter)

Global freelancing app. Backend (ASP.NET Core) is in `../backend`.

## Stack
- Flutter, Riverpod 3 (`Notifier`/`NotifierProvider` — **do NOT use `StateProvider`**, it's legacy in Riverpod 3)
- go_router (all routes in `lib/core/router/app_router.dart`)
- dio + flutter_secure_storage (network layer not built yet)

## Design System — "Luxury Premium" theme
Use ONLY this palette on all new screens. Minimal colors = premium feel.

| Token | Hex | Usage |
|---|---|---|
| bg | `#FAFAF8` | soft ivory background (light screens) |
| navy | `#0A1633` | primary text, buttons, icons |
| gold | `#C0A062` | accent: overline labels, active dots, thin borders |
| splash gradient | `#000428 → #004E92` | splash only (dark) |
| splash accent | `#00C9FF` cyan / `#92FE9D` mint | splash logo only |

Style rules:
- Letterspaced UPPERCASE gold overline labels (12px, w700, letterSpacing ~3.5)
- Big navy titles (32–36px, w800, tight height ~1.12)
- Muted body text: navy at 55% alpha
- Buttons: navy fill, `StadiumBorder` pills or circles; gold never used as button fill
- Thin gold borders (1.2px, ~45% alpha) instead of heavy colored containers
- Cards: white, radius 16, subtle navy shadow (6% alpha)
- Note: splash accent (cyan) differs from app accent (gold) — pending decision; prefer navy+gold for everything new.

## App Flow (built so far)
`/splash` (animated) → `/role-selection` (new user) or `/home` / `/profile-step1` (logged in)

Removed (2026-07): 3-slide onboarding and `/setup` (country+language) screens — deleted along with their routes and country/language providers. Country/language constants in `core/constants/` are kept for future phone verification + KYC.

Next planned steps: phone verification (dial code from country) → KYC (National ID vs Passport choice based on country).

## Key files
- `lib/core/constants/country_config.dart` — ~195 countries: name, ISO, dialCode, optional `nationalId` (NationalIdDoc). Flag emoji auto-generated from ISO code. `kycDocuments` getter returns KYC doc choices (Passport always; National ID if country has one, e.g. PK=CNIC, IN=Aadhaar, AE=Emirates ID; US/GB/CA = passport only).
- `lib/core/constants/languages.dart` — ~58 languages (name, nativeName, ISO 639-1 code), independent of country.
- `lib/features/onboarding/providers/onboarding_providers.dart` — `selectedRoleProvider` (role-selection + signup read this).

## Conventions
- Screens live in `lib/features/<feature>/presentation/screens/`
- Selection state goes in feature `providers/` folder, global config data in `core/constants/`
- Comments in the codebase are Roman Urdu + English (owner is learning Flutter, coming from C#/ASP.NET)
- After changes run `flutter analyze` (must be 0 issues) and `flutter test`
