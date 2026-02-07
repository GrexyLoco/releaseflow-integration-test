# ReleaseFlow v1.0.0 - Manueller Integrationstest

Dieser Testplan validiert die vollständige Funktionalität des ReleaseFlow-Prozesses mit echten Git-Operationen, PRs und Releases.

## Voraussetzungen

- [ ] `gh` CLI installiert und authentifiziert
- [ ] PowerShell 7.5+ installiert
- [ ] Git konfiguriert mit Push-Rechten
- [ ] K.Actions.ReleaseFlow Modul verfügbar
- [ ] Test-Repository erstellt (oder bestehendes nutzen)

## Test-Repository Setup

```powershell
# Option A: Neues Test-Repository erstellen
gh repo create releaseflow-test --public --clone
cd releaseflow-test

# Initiales Setup
@'
@{
    RootModule = 'TestModule.psm1'
    ModuleVersion = '0.0.1'
    GUID = 'test-guid-1234'
    Author = 'Test'
    Description = 'ReleaseFlow Integration Test Module'
    PrivateData = @{
        PSData = @{
            Prerelease = ''
        }
    }
}
'@ | Set-Content TestModule.psd1

'# Test Module' | Set-Content TestModule.psm1
'# ReleaseFlow Test Repository' | Set-Content README.md

git add -A
git commit -m "chore: initial setup"
git push origin main

# Option B: Bestehendes Repository nutzen
# cd path/to/existing/repo
```

---

## Testfall 1: PO-Dispatch (New-ReleaseTrain)

**Ziel:** Validieren, dass ein neuer Release Train korrekt erstellt wird.

### 1.1 Erfolgreicher Release Train

```powershell
# Import Modul
Import-Module K.Actions.ReleaseFlow -Force

# Erstelle Release Train für v1.0.0
$result = New-ReleaseTrain -TargetVersion '1.0.0' -Verbose

# Erwartete Ausgabe:
# - DevBranch: dev/v1.0.0
# - IntentUrl: https://github.com/.../releases/tag/v1.0.0
# - BaseCommit: <sha>
```

**Prüfpunkte:**
- [ ] Branch `dev/v1.0.0` existiert auf remote
- [ ] Draft Release `v1.0.0` existiert (noch nicht publiziert)
- [ ] Draft Release zeigt auf `dev/v1.0.0`

```powershell
# Validierung
git branch -r | Select-String 'dev/v1.0.0'
gh release view v1.0.0 --json isDraft,tagName,targetCommitish
```

### 1.2 Guardrail PD-1: Duplikat-Intent

```powershell
# Versuche erneut denselben Release Train zu erstellen
{ New-ReleaseTrain -TargetVersion '1.0.0' } | Should -Throw '*PD-1*existiert bereits*'
```

**Prüfpunkt:**
- [ ] Fehler mit "PD-1" und "existiert bereits" wird geworfen

### 1.3 Guardrail PD-2: Existierender Tag

```powershell
# Erstelle manuell einen Tag
git tag v2.0.0
git push origin v2.0.0

# Versuche Release Train für v2.0.0
{ New-ReleaseTrain -TargetVersion '2.0.0' } | Should -Throw '*PD-2*'

# Cleanup
git tag -d v2.0.0
git push origin --delete v2.0.0
```

### 1.4 Guardrail PD-3: Existierender Branch

```powershell
# Erstelle manuell einen Branch
git checkout -b dev/v3.0.0
git push origin dev/v3.0.0
git checkout main

# Versuche Release Train für v3.0.0
{ New-ReleaseTrain -TargetVersion '3.0.0' } | Should -Throw '*PD-3*'

# Cleanup
git push origin --delete dev/v3.0.0
git branch -D dev/v3.0.0
```

---

## Testfall 2: Alpha-Release (Feature → Dev)

**Ziel:** Validieren, dass ein Feature-PR nach dev einen Alpha-Release erzeugt.

### 2.1 Feature-Branch erstellen

```powershell
git checkout dev/v1.0.0
git checkout -b feature/TEST-001-add-hello-function

# Dummy-Änderung
@'
function Get-Hello {
    "Hello from ReleaseFlow!"
}
'@ | Add-Content TestModule.psm1

git add -A
git commit -m "feat: add Get-Hello function

Implements a simple greeting function for testing purposes.

Closes #TEST-001"

git push origin feature/TEST-001-add-hello-function
```

### 2.2 PR erstellen und mergen

```powershell
# PR erstellen
gh pr create `
    --base dev/v1.0.0 `
    --head feature/TEST-001-add-hello-function `
    --title "feat: Add Get-Hello function" `
    --body "## Summary
Adds a greeting function.

## Testing
- [ ] Manual test passed

Closes #TEST-001"

# PR Nummer merken
$prNumber = (gh pr list --head feature/TEST-001-add-hello-function --json number -q '.[0].number')

# PR mergen (löst Workflow aus)
gh pr merge $prNumber --squash --delete-branch
```

### 2.3 Alpha-Release validieren

```powershell
# Warte auf Workflow (ca. 30-60 Sekunden)
Start-Sleep -Seconds 60

# Prüfe ob Alpha-Tag erstellt wurde
git fetch --tags
git tag -l 'v1.0.0-alpha*'

# Prüfe GitHub Release
gh release list | Select-String 'alpha'
gh release view v1.0.0-alpha1 --json tagName,isPrerelease,isDraft
```

**Prüfpunkte:**
- [ ] Tag `v1.0.0-alpha1` existiert
- [ ] GitHub Release `v1.0.0-alpha1` existiert
- [ ] Release ist als Pre-release markiert (`isPrerelease: true`)
- [ ] Release ist KEIN Draft (`isDraft: false`)

### 2.4 Version-Update validieren

```powershell
# Prüfe ob .psd1 aktualisiert wurde
git checkout dev/v1.0.0
git pull origin dev/v1.0.0

$manifest = Import-PowerShellDataFile TestModule.psd1
$manifest.ModuleVersion  # Sollte: 1.0.0
$manifest.PrivateData.PSData.Prerelease  # Sollte: alpha1
```

**Prüfpunkte:**
- [ ] `ModuleVersion = '1.0.0'`
- [ ] `Prerelease = 'alpha1'`
- [ ] Commit-Message enthält `[skip ci]`

---

## Testfall 3: Zweiter Alpha-Release

**Ziel:** Validieren, dass die Alpha-Nummer korrekt inkrementiert wird.

```powershell
git checkout dev/v1.0.0
git checkout -b feature/TEST-002-add-goodbye-function

@'

function Get-Goodbye {
    "Goodbye from ReleaseFlow!"
}
'@ | Add-Content TestModule.psm1

git add -A
git commit -m "feat: add Get-Goodbye function"
git push origin feature/TEST-002-add-goodbye-function

gh pr create --base dev/v1.0.0 --head feature/TEST-002-add-goodbye-function --title "feat: Add Get-Goodbye" --body "Another feature"
$prNumber = (gh pr list --head feature/TEST-002-add-goodbye-function --json number -q '.[0].number')
gh pr merge $prNumber --squash --delete-branch

# Warte und validiere
Start-Sleep -Seconds 60
git fetch --tags
git tag -l 'v1.0.0-alpha*'
```

**Prüfpunkte:**
- [ ] Tag `v1.0.0-alpha2` existiert (nicht `alpha1` oder `alpha.2`)
- [ ] PreRelease-Format ist `alpha2` (ohne Punkt!)

---

## Testfall 4: Freeze & Beta-Phase

**Ziel:** Validieren, dass der Übergang zu Beta funktioniert.

### 4.1 Release-Branch erstellen (Freeze)

```powershell
# Erstelle release Branch aus dev
git checkout dev/v1.0.0
git pull origin dev/v1.0.0
git checkout -b release/v1.0.0
git push origin release/v1.0.0

# Oder via PR (empfohlen für Produktiv):
# gh pr create --base release/v1.0.0 --head dev/v1.0.0 --title "Freeze: v1.0.0"
```

### 4.2 Fix-Branch für Beta

```powershell
git checkout release/v1.0.0
git checkout -b fix/TEST-003-typo-in-hello

# Dummy-Fix
(Get-Content TestModule.psm1) -replace 'Hello from', 'Greetings from' | Set-Content TestModule.psm1

git add -A
git commit -m "fix: correct greeting message"
git push origin fix/TEST-003-typo-in-hello

gh pr create --base release/v1.0.0 --head fix/TEST-003-typo-in-hello --title "fix: Correct greeting" --body "Bugfix for beta"
$prNumber = (gh pr list --head fix/TEST-003-typo-in-hello --json number -q '.[0].number')
gh pr merge $prNumber --squash --delete-branch

# Warte und validiere
Start-Sleep -Seconds 60
git fetch --tags
git tag -l 'v1.0.0-beta*'
```

**Prüfpunkte:**
- [ ] Tag `v1.0.0-beta1` existiert
- [ ] GitHub Release `v1.0.0-beta1` ist Pre-release
- [ ] `Prerelease = 'beta1'` in .psd1

---

## Testfall 5: Stable Release & Backflow

**Ziel:** Validieren, dass Stable-Release und Backflow-PRs funktionieren.

### 5.1 Vorbereitung: Zweiter Release Train

```powershell
# Erstelle parallelen Release Train für v2.0.0
New-ReleaseTrain -TargetVersion '2.0.0'
```

### 5.2 Stable Release

```powershell
# PR von release → main
gh pr create --base main --head release/v1.0.0 --title "Release: v1.0.0" --body "Stable release"
$prNumber = (gh pr list --head release/v1.0.0 --json number -q '.[0].number')
gh pr merge $prNumber --merge  # Nicht squash für Release!

# Warte auf Workflow
Start-Sleep -Seconds 90
```

### 5.3 Validierung

```powershell
# Stable-Tag
git fetch --tags
git tag -l 'v1.0.0'  # Ohne Suffix!

# Draft Release sollte jetzt publiziert sein
gh release view v1.0.0 --json isDraft,tagName
# isDraft sollte false sein

# Smart-Tags prüfen
git tag -l 'v1' 'v1.0' 'latest'

# Backflow-PR prüfen
gh pr list --base dev/v2.0.0
```

**Prüfpunkte:**
- [ ] Tag `v1.0.0` existiert (stable, ohne Suffix)
- [ ] Draft Release ist jetzt publiziert (`isDraft: false`)
- [ ] Smart-Tags existieren: `v1`, `v1.0`, `latest`
- [ ] Backflow-PR nach `dev/v2.0.0` wurde erstellt
- [ ] `Prerelease = ''` (leer) in .psd1 auf main

---

## Testfall 6: Validierungs-Workflow

**Ziel:** Validieren, dass der Version-Validation-Workflow bei `[skip ci]` Commits trotzdem läuft.

### 6.1 Simuliere fehlerhaften Version-Update

```powershell
git checkout main
git checkout -b test/invalid-psd1

# Erstelle ungültige .psd1
'invalid powershell content {{{' | Set-Content TestModule.psd1

git add -A
git commit -m "test: invalid psd1 [skip ci]"
git push origin test/invalid-psd1
```

### 6.2 Workflow-Run prüfen

```powershell
# Prüfe ob Validation-Workflow gelaufen ist
gh run list --workflow version-validation.yml --limit 5

# Der letzte Run sollte FAILED sein
```

**Prüfpunkte:**
- [ ] Workflow `version-validation.yml` wurde ausgelöst (trotz `[skip ci]`)
- [ ] Workflow ist FAILED (wegen ungültiger .psd1)

### 6.3 Cleanup

```powershell
git checkout main
git branch -D test/invalid-psd1
git push origin --delete test/invalid-psd1
```

---

## Testfall 7: Guardrails (G1-G5)

**Ziel:** Validieren, dass die Guardrails korrekt blockieren.

### 7.1 G1: Dev-Gate (kein Intent)

```powershell
# Erstelle Branch ohne Intent
git checkout main
git checkout -b dev/v99.0.0
git push origin dev/v99.0.0

git checkout -b feature/no-intent-test
echo "test" >> README.md
git add -A
git commit -m "feat: test without intent"
git push origin feature/no-intent-test

# PR sollte von Guardrail G1 blockiert werden
gh pr create --base dev/v99.0.0 --head feature/no-intent-test --title "Should fail G1"
# → Merge sollte scheitern oder Warnung zeigen
```

### 7.2 G5: Feature-Freeze

```powershell
# Versuche Feature-PR nach release Branch
git checkout release/v1.0.0 2>/dev/null || git checkout -b release/v1.0.0 origin/release/v1.0.0
git checkout -b feature/should-be-blocked

echo "new feature" >> README.md
git add -A
git commit -m "feat: new feature after freeze"
git push origin feature/should-be-blocked

# PR nach release sollte blockiert werden (nur fix/* erlaubt)
gh pr create --base release/v1.0.0 --head feature/should-be-blocked --title "Should fail G5"
```

---

## Cleanup nach Tests

```powershell
# Alle Test-Branches löschen
git checkout main
git fetch --prune

# Lokale Branches
git branch | Where-Object { $_ -match 'feature/|fix/|test/' } | ForEach-Object { git branch -D $_.Trim() }

# Remote Branches (vorsichtig!)
# git push origin --delete dev/v1.0.0 dev/v2.0.0 release/v1.0.0

# Test-Releases löschen
# gh release delete v1.0.0-alpha1 v1.0.0-alpha2 v1.0.0-beta1 v1.0.0 --yes

# Test-Tags löschen
# git tag -d v1.0.0-alpha1 v1.0.0-alpha2 v1.0.0-beta1 v1.0.0 v1 v1.0 latest
# git push origin --delete v1.0.0-alpha1 v1.0.0-alpha2 v1.0.0-beta1 v1.0.0
```

---

## Testergebnis-Protokoll

| Testfall | Beschreibung | Ergebnis | Datum | Tester |
|----------|--------------|----------|-------|--------|
| 1.1 | New-ReleaseTrain erfolgreich | ⬜ | | |
| 1.2 | Guardrail PD-1 | ⬜ | | |
| 1.3 | Guardrail PD-2 | ⬜ | | |
| 1.4 | Guardrail PD-3 | ⬜ | | |
| 2.1-2.4 | Alpha-Release | ⬜ | | |
| 3 | Alpha-Inkrement | ⬜ | | |
| 4.1-4.2 | Beta-Release | ⬜ | | |
| 5.1-5.3 | Stable + Backflow | ⬜ | | |
| 6.1-6.3 | Validation-Workflow | ⬜ | | |
| 7.1 | Guardrail G1 | ⬜ | | |
| 7.2 | Guardrail G5 | ⬜ | | |

**Legende:** ✅ Bestanden | ❌ Fehlgeschlagen | ⬜ Nicht getestet

---

## Bekannte Einschränkungen

1. **Workflow-Wartezeit:** Alpha/Beta/Stable-Releases werden async durch Workflows erstellt. Tests müssen warten.
2. **Rate Limits:** Bei vielen Tests können GitHub API Rate Limits greifen.
3. **Branch Protection:** Wenn Branch Protection aktiv ist, müssen PRs reviewed werden.

---

## Referenzen

- [Konzept-Dokument](https://github.com/GrexyLoco/1d70f/blob/main/K/branching_semver_cicd_concept_backflow_updated.md)
- [K.Actions.ReleaseFlow README](https://github.com/GrexyLoco/K.Actions.ReleaseFlow/blob/master/README.md)
- [GitHub Project: ReleaseFlow v1.0.0](https://github.com/users/GrexyLoco/projects/7)
