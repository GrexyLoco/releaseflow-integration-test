# ReleaseFlow: Branching, SemVer & CI/CD Konzept

## Inhaltsverzeichnis

1. [Begriffe und Definitionen](#begriffe)
2. [Übersicht](#uebersicht)
3. [Branch-Strategie](#branch-strategie)
4. [Semantic Versioning](#semantic-versioning)
5. [Release-Phasen](#release-phasen)
6. [Draft Intent System](#draft-intent)
7. [Guardrails](#guardrails)
8. [Alpha-Releases](#alpha-releases)
9. [Beta-Releases](#beta-releases)
10. [Stable Releases](#stable-releases)
11. [Backflow-Mechanismus](#backflow)
12. [Smart Tags](#smart-tags)
13. [Architektur und Tooling](#architektur)
14. [Versionsaktualisierung in Projektdateien](#version-update)

---

<a id="begriffe"></a>

## 1) Begriffe und Definitionen

- **ReleaseFlow**: Automatisiertes Release-Orchestrierungssystem für GitHub Actions
- **Draft Intent**: GitHub Draft Release, der als Entwicklungsziel dient
- **Guardrails (G1-G5)**: Validierungsregeln, die Prozessverletzungen verhindern
- **Backflow**: Automatisches Zurückführen von Stable-Changes in Development-Branches
- **Smart Tags**: Bewegliche Major/Minor-Tags (z.B. `v1`, `v1.2`) für einfache Versionierung
- **Alpha Release**: Pre-Release in Development-Phase (`vX.Y.Z-alpha.N`)
- **Beta Release**: Pre-Release in Release-Candidate-Phase (`vX.Y.Z-beta.N`)
- **Stable Release**: Finale Production-Version (`vX.Y.Z`)
- **Feature Freeze**: Zustand, in dem nur noch Bugfixes erlaubt sind
- **[skip ci]**: Commit-Message-Flag, das CI-Workflows überspringt, um Endlosschleifen zu vermeiden.

---

<a id="uebersicht"></a>

## 2) Übersicht

ReleaseFlow automatisiert den gesamten Release-Prozess basierend auf Branch-Kontext:

- **Automatische Phase-Erkennung**: Alpha, Beta oder Stable basierend auf PR-Branches
- **Guardrails**: G1-G5 verhindern Prozessverletzungen
- **Backflow PRs**: Automatische Synchronisation von `main` → `dev`-Branches
- **Single Entry Point**: `New-Release` - alles andere ist automatisch

---

<a id="branch-strategie"></a>

## 3) Branch-Strategie

```text
main (stable)
  ↑
release/vX.Y.Z (beta)
  ↑
dev/vX.Y.Z (alpha)
  ↑
feature/* oder fix/*
```

**Branches:**

- `main`: Production-Code, nur stable releases
- `release/vX.Y.Z`: Release-Candidate, nur Bugfixes
- `dev/vX.Y.Z`: Development, Features + Bugfixes
- `feature/*`: Feature-Entwicklung
- `fix/*`: Bugfixes

---

<a id="semantic-versioning"></a>

## 4) Semantic Versioning

Format: `vX.Y.Z[-prerelease]`

- **X** (Major): Breaking Changes
- **Y** (Minor): Neue Features (rückwärtskompatibel)
- **Z** (Patch): Bugfixes
- **prerelease**: `alpha.N` oder `beta.N`

---

<a id="release-phasen"></a>

## 5) Release-Phasen

| Phase | Branch | Pre-Release Format | Beispiel |
|-------|--------|-------------------|----------|
| **Development** | `dev/vX.Y.Z` | `alpha.N` | `v1.2.0-alpha.1` |
| **Release Candidate** | `release/vX.Y.Z` | `beta.N` | `v1.2.0-beta.1` |
| **Production** | `main` | - | `v1.2.0` |

---

<a id="draft-intent"></a>

## 6) Draft Intent System

Ein **Draft Release** definiert das Entwicklungsziel:

1. Entwickler erstellt Draft mit Titel `vX.Y.Z`
2. `dev/vX.Y.Z` Branch wird erstellt
3. Features werden entwickelt
4. Bei Merge → `dev/vX.Y.Z`: Alpha-Tag wird erstellt

**Guardrail G1** blockiert Merges ohne Draft Intent.

---

<a id="guardrails"></a>

## 7) Guardrails

| ID | Name | Prüft | Blockiert |
|----|------|-------|-----------|
| **G1** | Dev-Gate | Draft Intent existiert | Merge ohne Intent |
| **G2** | Freeze-Gate | Release-Branch existiert | Feature PRs nach Freeze |
| **G3** | Beta-Gate | Nur Fix-Commits seit Freeze | Unerlaubte Änderungen |
| **G4** | Stable-Gate | CI grün, alle Betas erfolgreich | Broken Release |
| **G5** | Feature-Freeze-Enforcement | `ISFEATUREFREEZE=true` | Feature PRs während Freeze |

---

<a id="alpha-releases"></a>

## 8) Alpha-Releases

**Trigger:** `feature/*` oder `fix/*` → `dev/vX.Y.Z`

**Ablauf:**

1. G1 prüft Draft Intent
2. Alpha-Tag erstellt: `vX.Y.Z-alpha.N`
3. GitHub Release (prerelease) erstellt

---

<a id="beta-releases"></a>

## 9) Beta-Releases

**Trigger:** `fix/*` → `release/vX.Y.Z`

**Ablauf:**

1. G3 prüft nur Fixes erlaubt
2. Beta-Tag erstellt: `vX.Y.Z-beta.N`
3. GitHub Release (prerelease) erstellt

---

<a id="stable-releases"></a>

## 10) Stable Releases

**Trigger:** `release/vX.Y.Z` → `main`

**Ablauf:**

1. G4 prüft CI-Status
2. Draft Release wird published
3. Stable-Tag: `vX.Y.Z`
4. Smart Tags: `vX`, `vX.Y`
5. Backflow PRs erstellt

---

<a id="backflow"></a>

## 11) Backflow-Mechanismus

Nach Stable Release werden automatisch PRs erstellt:

```text
main (nach v1.0.0)
  │
  ├──► PR → dev/v1.1.0
  ├──► PR → dev/v2.0.0
  └──► PR → dev/v1.0.1 (hotfix)
```

**Ziel:** Development-Branches bleiben synchron mit `main`.

---

<a id="smart-tags"></a>

## 12) Smart Tags

Nach Release von `v1.2.3`:

- `v1.2.3` (stable, unveränderlich)
- `v1.2` (beweglich, zeigt auf latest patch)
- `v1` (beweglich, zeigt auf latest minor)

**Nutzung in Workflows:**

```yaml
uses: GrexyLoco/K.Actions.ReleaseFlow@v1
```

---

<a id="architektur"></a>

## 13) Architektur und Tooling

### Komponenten

| Komponente | Verantwortlich für |
|------------|-------------------|
| **K.Actions.ReleaseFlow** | Prozess-Orchestrierung, Guardrails, PR-Management |
| **K.PSGallery.Smartagr** | Git-Tagging, SemVer-Parsing, Smart Tags |

### Separation of Concerns

- **ReleaseFlow**: Kennt NICHTS über Tag-Strategien
- **Smartagr**: Kennt NICHTS über Draft Intents oder Guardrails

---

<a id="version-update"></a>

## 14) Versionsaktualisierung in Projektdateien (CI-gesteuert)

### 14.1 Grundprinzip

Die Version in Projektdateien (.psd1, Directory.Build.props, etc.) wird **automatisch durch CI** bei jedem Tag aktualisiert. Entwickler ändern diese Dateien **niemals manuell**.

### 14.2 Zeitpunkt der Aktualisierung

Bei **jedem Merge, der einen neuen Tag erzeugt**:

| Merge-Richtung | Tag | Projektdatei-Update |
|----------------|-----|---------------------|
| `feature/*` → `dev/vX.Y.Z` | `vX.Y.Z-alphaN` | `X.Y.Z` + `alphaN` |
| `fix/*` → `dev/vX.Y.Z` | `vX.Y.Z-alphaN` | `X.Y.Z` + `alphaN` |
| `fix/*` → `release/vX.Y.Z` | `vX.Y.Z-betaN` | `X.Y.Z` + `betaN` |
| `release/vX.Y.Z` → `main` | `vX.Y.Z` | `X.Y.Z` (stable) |

### 14.3 PreRelease-Format (PSGallery-kompatibel)

**Ohne Punkte im PreRelease-Suffix:**

- ✅ `1.0.0-alpha3` (funktioniert überall)
- ❌ `1.0.0-alpha.3` (PSGallery-inkompatibel)

**Erlaubte Zeichen:** `0-9`, `A-Z`, `a-z`, `-`
**Verboten:** `.` (Punkt), `+` (Plus)

### 14.4 Projekttyp-spezifische Handler

| Projekttyp | Datei | Felder |
|------------|-------|--------|
| **PowerShell** | `*.psd1` | `ModuleVersion='X.Y.Z'`, `Prerelease='alphaN'` |
| **.NET Multi-Projekt** | `Directory.Build.props` | `<VersionPrefix>X.Y.Z</VersionPrefix>`, `<VersionSuffix>alphaN</VersionSuffix>` |
| **.NET Einzelprojekt** | `*.csproj` | `<VersionPrefix>`, `<VersionSuffix>` |
| **GitHub Actions** | – | Nur Git-Tags, kein File-Update (Tags = Version) |

### 14.5 Erweiterbarkeit

Handler können für neue Projekttypen registriert werden:

```powershell
Register-ProjectVersionHandler -Type 'SqlProject' -Handler { 
    param($Version, $PreRelease)
    # Update *.sqlproj
}
```

### 14.6 Commit-Strategie

- **Eigener Commit** nach Tag-Erstellung
- **Commit-Message:** `chore(version): update to X.Y.Z-alphaN [skip ci]`
- **[skip ci]:** Verhindert Endlosschleifen

### 14.7 Stable-Release: Tag via GitHub-Publish

Der Stable-Tag wird **durch GitHub automatisch erstellt**, wenn der Draft Release publiziert wird:

```powershell
# NICHT:
# git tag v1.0.0 && git push --tags

# SONDERN:
gh release edit v1.0.0 --draft=false  # GitHub erstellt Tag automatisch
```

**Vorteil:** Einzige Quelle der Wahrheit für Stable-Releases.

### 14.8 Validierung mit separatem Workflow

Da `[skip ci]` normale Workflows überspringt, prüft ein separater **Path-Filter-Workflow** die Syntax:

```yaml
on:
  push:
    paths:
      - '**/Directory.Build.props'
      - '**/*.psd1'
```
