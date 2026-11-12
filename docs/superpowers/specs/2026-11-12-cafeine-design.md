# Caféine — spécification de conception

Date : 2026-11-12
Statut : en attente de relecture

## 1. Objectif

Caféine est une application macOS de barre de menus qui garde un MacBook
actif lorsque le capot est fermé, sur secteur ou sur batterie, avec des
garde-fous qui rétablissent la veille normale quand la situation devient
risquée (batterie faible, surchauffe).

Critère de réussite : Caféine activée, capot fermé, sans écran externe, le
Mac continue d'exécuter ses tâches (téléchargement, serveur, session SSH)
jusqu'à ce que l'utilisateur la désactive ou qu'un garde-fou se déclenche.

### Décisions de l'utilisateur

- Fonctionne sur secteur et sur batterie, au choix, avec une option
  « sur secteur uniquement » et un seuil de batterie réglable.
- Forme : icône dans la barre de menus, sans fenêtre ni icône dans le Dock.
- Compilation en local, sur le Mac de l'utilisateur.

### Hypothèses

- macOS 13 (Ventura) ou plus récent.
- Un seul Mac, dont l'utilisateur est administrateur.
- Pas de compte développeur Apple : l'app est signée localement (ad hoc).
- Interface en français uniquement.

### Hors périmètre

- Commande Terminal, compilation par GitHub Actions, distribution à des tiers.
- Garder l'écran allumé capot ouvert (ce que fait déjà `caffeinate`).
- Notifications système, statistiques, raccourcis clavier.

## 2. Mécanisme

macOS force la veille à la fermeture du capot ; les assertions d'alimentation
(`caffeinate`, `IOPMAssertion`) ne l'empêchent pas. Le seul réglage qui le
fait est :

```
pmset -a disablesleep 1    # veille désactivée
pmset -a disablesleep 0    # comportement normal
```

Cette commande exige les droits root. L'état courant se lit sans droits
particuliers : `pmset -g` affiche une ligne `SleepDisabled 1` ou
`SleepDisabled 0`.

### Droits administrateur : règle sudoers installée une fois

À la première activation, Caféine installe le fichier `/etc/sudoers.d/cafeine`
(propriétaire `root:wheel`, mode `0440`) contenant une seule règle :

```
<utilisateur> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

Elle autorise ces deux commandes exactes, sans mot de passe, et rien d'autre.
Caféine exécute ensuite `sudo -n /usr/bin/pmset -a disablesleep <0|1>`.

Installation :

1. Caféine vérifie que le nom d'utilisateur correspond à
   `^[a-z_][a-z0-9_-]*$` ; sinon elle refuse et affiche une erreur.
2. Elle écrit la règle dans un fichier temporaire.
3. Elle lance, via la boîte de dialogue d'authentification de macOS
   (`osascript`, `with administrator privileges`), un script qui valide le
   fichier avec `visudo -cf`, puis le copie avec
   `install -m 0440 -o root -g wheel`. Si la validation échoue, rien n'est
   copié.

Si l'utilisateur annule la boîte de dialogue, Caféine reste inactive.

Approches écartées :

- **Mot de passe à chaque bascule** : un garde-fou ne pourrait pas rétablir
  la veille capot fermé, puisqu'il faudrait saisir un mot de passe.
- **Service privilégié `SMAppService`** : exige une signature par un compte
  développeur Apple.

## 3. Interface

Icône de tasse dans la barre de menus, pleine quand Caféine maintient le Mac
éveillé, vide sinon. Le menu contient :

| Élément | Comportement |
|---|---|
| Ligne d'état | « Actif », « Actif jusqu'à 15:30 », « En pause : sur batterie », « Inactif », ou la raison du dernier arrêt automatique (« Arrêté : batterie à 19 % ») |
| Activer / Désactiver | Bascule principale |
| Durée | Indéfiniment (défaut), 1 h, 2 h, 4 h |
| Sur secteur uniquement | Case à cocher, décochée par défaut |
| Seuil de batterie | 10 %, 20 % (défaut), 30 % |
| Lancer au démarrage | Case à cocher (`SMAppService.mainApp`) |
| Quitter | Rétablit la veille normale puis quitte |

Les réglages sont conservés dans `UserDefaults`. L'état « activé » ne l'est
pas : Caféine démarre toujours inactive.

## 4. Règles de décision

Caféine réévalue la situation à chaque changement d'alimentation, à chaque
changement d'état thermique, à chaque changement de réglage et toutes les
30 secondes.

Quand l'utilisateur a activé Caféine, les règles s'appliquent dans cet ordre :

| Condition | Effet | Reprise |
|---|---|---|
| État thermique « sérieux » ou « critique » | Arrêt | Manuelle |
| Minuteur écoulé | Arrêt | Manuelle |
| Sur batterie, niveau inférieur ou égal au seuil | Arrêt | Manuelle |
| Sur batterie et « sur secteur uniquement » coché | Pause | Automatique au rebranchement |
| Aucune des conditions ci-dessus | Veille désactivée | — |

- **Arrêt** : veille normale rétablie, Caféine passe à « inactif » et la
  ligne d'état indique la raison. L'utilisateur doit réactiver.
- **Pause** : veille normale rétablie, Caféine reste « activée » et reprend
  seule quand la condition disparaît.

Le seuil de batterie ne s'applique pas sur secteur. Sur un Mac sans batterie,
seuls le minuteur et l'état thermique s'appliquent.

Ajouts issus de la relecture du code :

- Après un arrêt ou une pause automatique, si le capot est fermé
  (`AppleClamshellState` lu par `ioreg`), Caféine exécute `pmset sleepnow`.
- Si le retour à la veille normale échoue, Caféine le retente à chaque
  réévaluation et à la fermeture de l'app.
- « Sur secteur uniquement » met en pause sur batterie même si le niveau de
  batterie est illisible.

### Cohérence de l'état système

- À la fermeture de l'app (`applicationWillTerminate`) : `disablesleep 0`.
- Au lancement : si `pmset -g` indique `SleepDisabled 1` (plantage ou
  extinction brutale précédente), Caféine exécute `disablesleep 0`.
- Après chaque commande, Caféine relit `pmset -g` ; si l'état réel diffère de
  l'état voulu, elle passe à « inactif » et affiche l'erreur.

## 5. Architecture

Paquet Swift sans dépendance externe, trois cibles.

### `CafeineCore` (bibliothèque, sans interface ni IOKit)

- `Settings` : `acOnly`, `batteryThreshold`, `duration`. Lecture et écriture
  dans un `UserDefaults` injecté.
- `PowerState` : `onAC: Bool`, `batteryPercent: Int?`.
- `ThermalLevel` : `nominal`, `fair`, `serious`, `critical`.
- `Policy.decide(enabled:settings:power:thermal:endDate:now:) -> Decision` :
  fonction pure qui applique le tableau de la section 4. `Decision` vaut
  `.stayAwake`, `.pause(reason)` ou `.stop(reason)`.
- `CommandRunner` : protocole `run(_ executable: String, _ arguments: [String]) throws -> CommandResult`
  (code de sortie, sortie standard, sortie d'erreur).
- `SleepController` : construit avec un `CommandRunner`. Méthodes
  `isSleepDisabled()`, `setSleepDisabled(_:)`, `isAuthorized()` (via
  `sudo -n -l`), `sudoersRule(for:)` et `installAuthorization()`.

### `Cafeine` (exécutable, dépend de `CafeineCore`)

- `ProcessCommandRunner` : implémentation réelle de `CommandRunner` avec
  `Process`.
- `PowerMonitor` : lit l'alimentation via IOKit (`IOPSCopyPowerSourcesInfo`),
  signale les changements (`IOPSNotificationCreateRunLoopSource`) et l'état
  thermique (`ProcessInfo.thermalStateDidChangeNotification`).
- `AppModel` : objet observable qui détient l'état « activé », la date de fin
  et le dernier message ; appelle `Policy` puis `SleepController`.
- `CafeineApp` : scène `MenuBarExtra` SwiftUI qui affiche `AppModel`.

### `CafeineCoreTests` (tests unitaires)

### Fichiers hors code

- `build.sh` : `swift build -c release`, assemble `Caféine.app`
  (`Contents/MacOS/Cafeine`, `Contents/Info.plist` avec `LSUIElement` à
  `true`, identifiant `com.cafeine.app`, version minimale macOS 13), puis
  `codesign --force --sign -`.
- `README.md` en français : prérequis (`xcode-select --install`),
  compilation, installation dans `/Applications`, utilisation,
  désinstallation (`sudo rm /etc/sudoers.d/cafeine`), avertissement de
  chauffe.

## 6. Gestion des erreurs

| Situation | Comportement |
|---|---|
| Règle sudoers absente à l'activation | Lance l'installation ; inactive si annulée |
| `sudo -n` refusé alors que la règle était présente | Inactif, message « Autorisation manquante », nouvelle installation proposée à la prochaine activation |
| `pmset` échoue ou l'état relu ne correspond pas | Inactif, message d'erreur dans la ligne d'état |
| Nom d'utilisateur non conforme | Refus d'installer, message d'erreur |
| Lecture de la batterie impossible | Traité comme un Mac sans batterie |
| Échec de « Lancer au démarrage » | Case décochée, message d'erreur |

## 7. Tests

Tests unitaires, lancés par `swift test` sur le Mac :

- `Policy` : une ligne du tableau de la section 4 par test, plus l'ordre de
  priorité, le seuil exact (égal au seuil = arrêt), le seuil ignoré sur
  secteur et le cas sans batterie.
- `SleepController`, avec un faux `CommandRunner` : commandes exactes émises,
  analyse de la sortie de `pmset -g`, texte exact de la règle sudoers, refus
  des noms d'utilisateur non conformes, propagation des échecs.
- `Settings` : valeurs par défaut et relecture après écriture.

Vérification manuelle, décrite dans le README et à faire par l'utilisateur :
activer, fermer le capot, constater qu'une tâche continue (par exemple un
`ping` vu depuis une autre machine) ; puis vérifier un arrêt par minuteur.

Limite : l'environnement de développement de ce projet est sous Linux. Le
code y est écrit mais ni compilé ni exécuté ; la première compilation et le
premier `swift test` ont lieu sur le Mac de l'utilisateur.

## 8. Risques

- **Chauffe** : un Mac actif dans un sac fermé chauffe. Les garde-fous
  thermique et batterie réduisent le risque sans l'annuler ; le README le dit.
- **Plantage** : si Caféine plante pendant qu'elle est active, la veille
  reste désactivée jusqu'au prochain lancement de l'app ou jusqu'à
  `sudo pmset -a disablesleep 0`. Le README donne cette commande.
- **Lancement au démarrage avec signature ad hoc** : `SMAppService.mainApp`
  peut refuser une app non signée par un compte développeur ; à vérifier sur
  le Mac. En cas de refus, l'option est retirée et le README indique l'ajout
  manuel dans Réglages Système > Général > Ouverture.
