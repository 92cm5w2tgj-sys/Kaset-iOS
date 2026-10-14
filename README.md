# YTM Spike — la lecture YouTube Music tient-elle en arrière-plan sur iOS ?

Mini-app iOS : un seul `WKWebView` sur `music.youtube.com`, une `AVAudioSession(.playback)`,
`UIBackgroundModes=audio`, et beaucoup d'instrumentation. Elle sert à répondre à une seule question :
**une playlist continue-t-elle et enchaîne-t-elle les pistes écran verrouillé / app en arrière-plan ?**

## Lancer

```bash
cd "/Users/mickaelbelhassen/Desktop/Developer/Kaset-iOS"
xcodegen generate          # régénère YTMSpike.xcodeproj depuis project.yml
open YTMSpike.xcodeproj
```

1. Dans Xcode : target `YTMSpike` ▸ *Signing & Capabilities* ▸ choisis ton Team.
2. Branche un **iPhone réel** (le simulateur ne dit rien de fiable sur la suspension en arrière-plan).
3. Run. Connecte-toi à YouTube Music dans la WebView (idéalement un compte Premium).

Le build simulateur compile (`xcodebuild … -destination 'generic/platform=iOS Simulator'`), mais je n'ai
**pas** lancé l'app : le pont JS → Swift et les sélecteurs de la page ne sont pas encore vérifiés.

## Ce que l'app mesure

| Source | Signal |
|---|---|
| Heartbeat JS (5 s) | La page tourne-t-elle encore ? `vis=` donne la visibilité **réelle** vue par la page |
| Ticker natif (5 s) | Le process app est-il suspendu ? (trou > 12 s) |
| Événements `<video>` | `pause`, `ended`, `error`, `stalled`, `play` + changement de titre = enchaînement de piste |
| `WEBCONTENT PROCESS TERMINATED` | iOS a tué le process de la page |
| `AVAudioSession` | interruptions, changements de route |
| Rapport | Résumé affiché au retour au premier plan, et ligne `[report]` dans le log |

Le log est écrit **ligne par ligne sur disque** (`Documents/spike-log.txt`) : il survit même si l'app est tuée.
Récupération : bouton partage dans l'app, ou app Fichiers ▸ Sur mon iPhone ▸ YTM Spike.

## Protocole de test

Pour chaque essai : lance une **playlist** (pas un seul titre), vérifie que ça joue, **verrouille l'iPhone**
(ou passe sur l'écran d'accueil), attends **20 à 30 min**, puis note : le son a-t-il continué ? les pistes
se sont-elles enchaînées ? le bouton suivant de l'écran verrouillé marche-t-il ?

Change les réglages (⚙︎ *Réglages*, puis *Recharger* pour ceux de la première section) dans cet ordre :

| # | UA desktop | Mentir visibilité | Relancer play() | WebView cachée 1×1 | Question |
|---|---|---|---|---|---|
| 1 | oui | non | non | non | Base : ça tient sans bidouille ? |
| 2 | oui | non | oui | non | Un `play()` en entrant en arrière-plan suffit-il ? |
| 3 | oui | oui | non | non | Empêcher la page de savoir qu'elle est cachée suffit-il ? |
| 4 | oui | oui | oui | non | Les deux |
| 5 | meilleur réglage de 1–4 | | | **oui** | Même chose avec la WebView cachée, comme Kaset |
| 6 | non (UA mobile) | meilleur de 1–4 | | non | Le site mobile se comporte-t-il autrement ? |

## Lire le résultat

- **Son continue + pistes changent** → le chemin WebView est viable, le portage vaut le coup.
- **`pause` à l'entrée en arrière-plan, `vis=hidden`** → YouTube coupe sur la visibilité : essais 2–4.
- **Trous JS mais son OK** → timers de la page throttlés : acceptable tant que la file avance côté YouTube,
  mais la synchro d'état de Kaset devra le tolérer.
- **Trous natifs** → l'app entière est suspendue : l'audio session n'est pas tenue, vérifie `[audio]` dans le log.
- **`WEBCONTENT PROCESS TERMINATED`** → iOS tue la page : la WebView ne suffit pas.

## Si tout échoue (plan B, à ne creuser qu'après ce spike)

1. Compte Premium vs non-Premium : YouTube réserve probablement la lecture écran verrouillé au Premium.
2. Lecteur iframe/embed au lieu de la page complète.
3. Flux audio récupérés via InnerTube et lus par `AVPlayer` : fonctionne en arrière-plan sans discussion, mais
   casse la règle « WebView pour la lecture » de Kaset et le DRM, et dépend de tokens (PO token) fragiles.

## Limites connues

- Sélecteurs `.next-button.ytmusic-player-bar` etc. repris de Kaset, non revalidés ici.
- L'auto-confirmation du dialogue « Continuer ? » est un essai sans garantie (sélecteur supposé).
- La connexion Google dans une WebView peut être refusée selon le compte ; sinon dis-le, il y aura un plan.
