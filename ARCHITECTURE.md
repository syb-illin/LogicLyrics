# LogicLyrics 2.1.1 — architecture et invariants

## Couches

- `Model`: valeurs immuables ou états métier sans dépendance UI.
- `Services`: lecture/écriture Logic, inspection/tag audio, conversion MP3 et persistance.
- `ServiceProtocols`: ports injectables utilisés par les view models.
- `ViewModel`: état d’écran confiné au `MainActor`, validation et orchestration.
- `Views`: rendu SwiftUI et interactions utilisateur uniquement.

## Invariants de sûreté

1. Un projet Logic source n’est jamais modifié.
2. Une copie Logic est produite dans un paquet temporaire; source et ancienne destination restent intactes jusqu’au commit.
3. Une sortie audio est construite dans un fichier temporaire puis publiée en une seule opération.
4. L’historique est encodé hors du thread UI et écrit atomiquement.
5. Toute opération remplaçable possède un identifiant; un ancien résultat ne peut pas écraser le plus récent.
6. Le handle conservé est celui du worker réel; les tâches longues et LAME coopèrent avec son annulation.
7. Les handles de fichiers et accès security-scoped sont fermés dans des `defer`.
8. Les scans de `ProjectData` utilisent les données mappées sans copie intégrale en `[UInt8]`.
9. Les erreurs ayant un impact utilisateur ne sont pas silencieusement ignorées.
10. L’historique possède un schéma versionné et une identité projet + alternative + note.
11. Les mises à jour source et LAME sont vérifiées par SHA-256 avant exécution.

## Validation

`BUILD.command` compile avec la vérification stricte de concurrence, signe l’app, vérifie la signature,
valide `Info.plist`, exécute LAME et refuse toute dépendance Homebrew ou `/usr/local`.

La garantie empirique d’absence de fuite nécessite en complément une session Instruments sur macOS
(`Leaks`, `Allocations`, `Time Profiler`) pendant des cycles répétés de chargement, édition, conversion,
annulation et fermeture de fenêtre.
