# Logic Lyrics

Application macOS native qui extrait en lecture seule les Notes de projet d’un paquet Logic Pro `.logicx`.

Version actuelle : **2.1.1 (build 23)**. Le numéro de build est incrémenté à chaque livraison.

## Architecture production

- Services derrière des protocoles injectables pour isoler le domaine de SwiftUI et faciliter les tests.
- View models confinés au `MainActor`; analyse, encodage et fichiers exécutés hors du thread d’interface.
- Historique persisté par un `actor`, avec coalescence des écritures et remplacement atomique.
- Opérations longues annulables, protégées contre les résultats obsolètes et présentées avec spinner, libellé et temps écoulé.
- Écritures audio transactionnelles via fichier temporaire : aucune sortie partielle n’est publiée.
- Scans `ProjectData` sur `Data` mappé sans duplication intégrale en tableau d’octets.
- Boucles longues coopératives avec l’annulation; processus LAME terminé proprement sur demande.
- Erreurs de persistance remontées à l’utilisateur au lieu d’être silencieusement ignorées.
- Historique versionné par projet, alternative et note, avec migration des anciennes données.
- Copie Logic transactionnelle : la source et une destination existante restent intactes jusqu’à validation complète.
- Annulation reliée au véritable worker de lecture, copie, écriture ou conversion.

Le prompt impose trois blocs séparés et copiables dans ChatGPT/Gemini : **Styles**, **Styles to Exclude** et **Lyrics**.

Le BPM et la tonalité sont lus dans le `MetaData.plist` de l’alternative Logic. Ils sont affichés, restent corrigeables si nécessaire et sont obligatoirement placés au début du bloc **Styles** destiné à Suno AI.

L’onglet **Tags audio** écrit sans réencodage les métadonnées d’un export Suno MP3 ou WAV dans une nouvelle copie. Il reprend le BPM Logic, exclut volontairement la tonalité, propose les paroles en option désactivée par défaut et affiche un aperçu de la pochette sélectionnée. L’artiste par défaut (`wake up fall`) est modifiable dans les Réglages ; l’année courante est utilisée automatiquement.

Le style musical est choisi dans un menu déroulant couvrant les grandes familles et sous-genres courants. Lors du chargement, une pochette ID3/APIC déjà intégrée au MP3 ou au WAV est extraite, prévisualisée et conservée à la réécriture.

Le nom de sortie est construit avec un modèle à tokens, par défaut `{track} {group} - {title} {year}`. Tokens disponibles : `{track}`, `{group}`, `{title}`, `{album}`, `{year}` et `{bpm}`. L’extension d’origine est ajoutée automatiquement.

La conversion WAV vers MP3 utilise LAME 3.100, téléchargé depuis la source officielle, vérifié par SHA-256 puis compilé localement par `BUILD.command` sans Homebrew. Le binaire est conservé dans `~/Library/Caches/com.local.LogicLyrics` et réutilisé par toutes les versions suivantes. Les Réglages proposent CBR 128/192/256/320 kb/s ou VBR V0/V2/V4, fréquence source/44,1/48 kHz, en joint stereo et qualité maximale.

L’historique local conserve automatiquement chaque projet Logic chargé, ses paroles, son dernier prompt Suno, la référence artistique et les réglages vocaux. Les données restent dans Application Support sur le Mac.

## Compilation automatique

Double-cliquer sur **BUILD.command**. Le script compile, signe localement et place **LogicLyrics.app** dans le dossier Téléchargements.

Après la signature locale, le script retire l’attribut de quarantaine hérité du ZIP téléchargé. Sur le Mac qui effectue la compilation, cela évite normalement le passage répété par **Réglages Système > Ouvrir quand même**. Une distribution publique sans avertissement nécessite toujours un certificat Apple Developer ID et la notarisation Apple.

Si un certificat **Developer ID Application** est présent dans le trousseau, `BUILD.command` le détecte automatiquement. Pour notariser également, enregistrer au préalable un profil `notarytool`, puis lancer le build avec `LOGICLYRICS_NOTARY_PROFILE` défini. Sans compte Apple Developer, l’app reste signée localement pour le Mac qui l’a compilée ; Apple ne permet pas de transformer cette signature locale en distribution publique reconnue.

## Mises à jour

L’app vérifie les releases GitHub. Lorsqu’une version plus récente et complète existe, le bouton **Installer v…** télécharge l’archive source et sa somme SHA-256, les vérifie, quitte l’ancienne instance, puis reconstruit et remplace l’app au même emplacement. Il n’est plus nécessaire de télécharger et décompresser manuellement chaque version, et LAME n’est ni retéléchargé ni recompilé tant que son cache partagé reste présent.

Les releases destinées à l’updater doivent être créées avec un tag `vX.Y.Z`. Le workflow GitHub publie automatiquement `LogicLyrics-macOS-source.zip` et son fichier `.sha256`.

L’application Xcode complète n’est pas nécessaire. Le script utilise uniquement les **Apple Command Line Tools**. Si elles sont absentes, il ouvre automatiquement leur installateur léger ; terminer l’installation puis redouble-cliquer sur le script.

Le script sélectionne explicitement le SDK macOS fourni par les Command Line Tools et compile pour l’architecture du Mac avec une cible macOS 14, y compris lorsque le système hôte est macOS 26.

## Utilisation

1. Ouvrir `LogicLyrics.xcodeproj` dans Xcode 16 ou plus récent.
2. Sélectionner le schéma **LogicLyrics** et **My Mac**.
3. Lancer avec `⌘R`.
4. Glisser un projet `.logicx` dans la fenêtre.

Le bouton **Copier** place l’intégralité des paroles dans le presse-papiers. Le raccourci est `⇧⌘C`.

Les paroles extraites sont directement éditables dans l’application. Les changements sont sauvegardés automatiquement dans l’historique local et alimentent immédiatement la copie, l’export, le prompt Suno et les tags audio, sans modifier le projet `.logicx` original.

Le bouton expérimental **Copie Logic** duplique le projet puis remplace le RTF des Notes. Lorsque le RTF terminal doit changer de taille, l’app ne le fait que si elle reconnaît exactement l’enregistrement de Notes de 98 octets et met à jour ses deux longueurs redondantes. Si le projet ne contient aucune parole, un brouillon éditable est proposé et peut être ajouté à une copie selon le même contrôle structurel. Si la structure n’est pas reconnue ou si la relecture échoue, la copie temporaire est supprimée et l’original reste intact. La compatibilité définitive doit être confirmée en ouvrant la copie dans Logic Pro.

L’app détecte automatiquement les balises Suno (`[Verse 1]`, `[Chorus]`, `[Bridge]`, `[Outro]`, etc.) et permet de copier chaque section séparément.

L’écran **Générer pour Suno** construit localement un prompt complet demandant **Styles**, **Styles to Exclude** et **Lyrics + instructions Suno**. Il peut copier ce prompt puis ouvrir ChatGPT ou Gemini. Aucune clé API n’est nécessaire.

Le générateur renforce la fidélité du profil **Suno Voice** dans les trois champs : voix lead baryton unique, voix de poitrine, grain et formants naturels, sans falsetto, voix de tête, changement de chanteur ni remplacement synthétique.

La performance reste volontairement réaliste et reproductible : aucun high belt, whistle register, screaming, growl, distorsion extrême, mélisme rapide, run virtuose, grand saut d’octave ou autre acrobatie dépassant une tessiture baryton confortable.

Les back vocals restent possibles. Une option **Autoriser des chœurs féminins** permet d’ajouter des harmonies, réponses ou textures féminines sans jamais remplacer la voix lead baryton.

Les notes sont lues dans `Alternatives/<numéro>/ProjectData`. Chaque document RTF intégré est décodé avec les frameworks natifs de macOS. Le projet Logic n’est jamais modifié.

## Compatibilité validée

- macOS 14+
- Projet enregistré avec Logic Pro 12.2 (build 6644)
- Notes de projet RTF

## Distribution locale

Dans Xcode : **Product > Archive**, puis **Distribute App > Copy App**. Pour distribuer l’app à d’autres Mac sans avertissement Gatekeeper, utiliser un compte Apple Developer et la notarisation.
