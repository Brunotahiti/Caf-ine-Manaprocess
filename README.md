# Caféine

Caféine est une petite application de barre de menus qui garde votre MacBook
actif **capot fermé**, sur secteur ou sur batterie. Elle rétablit toute seule
la veille normale quand la batterie devient faible, quand le Mac chauffe ou
quand le minuteur est écoulé.

> **Attention à la chauffe.** Un Mac actif dans un sac fermé ne peut pas
> évacuer sa chaleur. Les arrêts automatiques réduisent le risque sans
> l'annuler : évitez de laisser Caféine active dans un sac ou une housse.

## Prérequis

- macOS 13 (Ventura) ou plus récent.
- Un compte administrateur sur le Mac.
- Les outils en ligne de commande d'Apple :

```bash
xcode-select --install
```

## Compilation

Dans le dossier du projet :

```bash
./build.sh
```

Le script crée `Caféine.app` dans ce même dossier.

Les tests sont facultatifs et demandent l'application Xcode complète (les
outils en ligne de commande seuls ne fournissent pas toujours XCTest) :

```bash
swift test
```

## Installation

Glissez `Caféine.app` dans le dossier `/Applications`, puis ouvrez-la. Une
tasse apparaît dans la barre de menus ; il n'y a ni fenêtre ni icône dans le
Dock.

## Première activation

Au premier clic sur **Activer**, macOS demande votre mot de passe
administrateur, une seule fois. Caféine installe alors le fichier
`/etc/sudoers.d/cafeine`, qui contient une seule règle (ici pour
l'utilisateur `bruno`) :

```
bruno ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

Cette règle autorise votre compte à exécuter ces deux commandes exactes sans
mot de passe, et rien d'autre. Elle est nécessaire parce que macOS n'autorise
que l'administrateur à désactiver la veille capot fermé, et que Caféine doit
pouvoir la rétablir seule, capot fermé, quand un garde-fou se déclenche.

Le nom court de votre compte doit commencer par une minuscule ou un tiret
bas, puis ne contenir que des minuscules, chiffres, tirets et tirets bas (par
exemple `bruno` ou `jean-luc`). Un nom avec une majuscule ou un point, comme
`prenom.nom`, est refusé : Caféine affiche alors « Erreur : nom d'utilisateur
non pris en charge ». La commande `whoami` affiche votre nom court.

## Le menu

| Élément | Rôle |
|---|---|
| Première ligne | État courant, ou raison du dernier arrêt automatique |
| Activer / Désactiver | Garde le Mac actif capot fermé, ou rétablit la veille normale |
| Durée | Indéfiniment, 1 h, 2 h ou 4 h. Changer la durée pendant que Caféine est active relance le minuteur |
| Sur secteur uniquement | Met Caféine en pause dès que le Mac est débranché |
| Seuil de batterie | 10 %, 20 % ou 30 % |
| Lancer au démarrage | Ouvre Caféine à l'ouverture de session |
| Quitter | Rétablit la veille normale, puis quitte |

La tasse est pleine quand Caféine maintient le Mac éveillé, vide sinon.
Caféine démarre toujours inactive.

## Arrêts automatiques

| Situation | Effet | Reprise |
|---|---|---|
| Le Mac surchauffe | Arrêt | Manuelle |
| Le minuteur est écoulé | Arrêt | Manuelle |
| Sur batterie, niveau inférieur ou égal au seuil | Arrêt | Manuelle |
| Sur batterie, avec « Sur secteur uniquement » coché | Pause | Automatique au rebranchement |

Après un arrêt, la première ligne du menu en indique la raison, par exemple
« Arrêté : batterie à 19 % ». Le seuil de batterie ne s'applique pas quand le
Mac est branché.

Si le capot est fermé au moment d'un arrêt ou d'une pause automatique,
Caféine met aussitôt le Mac en veille. Après une pause, la reprise
automatique a lieu quand le Mac est réveillé et rebranché.

## Vérifier que tout fonctionne

1. Cliquez sur **Activer**. La première ligne affiche « Actif ».
2. Dans le Terminal, cette commande doit afficher `SleepDisabled 1` :

   ```bash
   pmset -g | grep SleepDisabled
   ```

3. Depuis un autre appareil du même réseau, lancez un `ping` vers le Mac,
   puis fermez le capot : les réponses doivent continuer.
4. Cliquez sur **Désactiver** : la commande de l'étape 2 affiche
   `SleepDisabled 0`.
5. Réactivez, puis quittez Caféine : la commande affiche encore
   `SleepDisabled 0`.
6. Relancez Caféine et cliquez sur **Activer**. Choisissez la durée « 1 h » : la première ligne affiche
   « Actif jusqu'à » suivi de l'heure de fin.
7. Cochez « Sur secteur uniquement » et débranchez le câble : la première
   ligne affiche « En pause : sur batterie », puis « Actif » au rebranchement.

## Dépannage

**Le Mac ne se met plus en veille alors que Caféine est fermée.** Si Caféine
a planté ou si le Mac s'est éteint brutalement pendant qu'elle était active,
le réglage peut rester en place. Rouvrez Caféine (elle le rétablit au
lancement), ou exécutez :

```bash
sudo pmset -a disablesleep 0
```

**« Autorisation manquante ».** La règle a été supprimée ou modifiée. Cliquez
de nouveau sur **Activer** pour la réinstaller.

**« Erreur : impossible de rétablir la veille ».** Caféine n'a pas pu
revenir à la veille normale, le plus souvent parce que la règle
d'autorisation a disparu. Elle réessaie toutes les 30 secondes ; vous pouvez
aussi exécuter la commande `sudo pmset` ci-dessus.

**« Lancement au démarrage indisponible ».** macOS peut refuser cette option
à une application qui n'est pas signée par un développeur enregistré.
Ajoutez alors Caféine à la main dans Réglages Système > Général > Ouverture.

## Désinstallation

1. Quittez Caféine depuis son menu.
2. Supprimez `Caféine.app` du dossier `/Applications`.
3. Retirez la règle d'autorisation :

   ```bash
   sudo rm /etc/sudoers.d/cafeine
   ```

## Pour les curieux

- `Sources/CafeineCore` : la logique (règles de décision, commandes `pmset`,
  préférences), testée par `swift test`.
- `Sources/Cafeine` : l'application elle-même (menu, lecture de la batterie).
- `docs/superpowers/specs` : la spécification de conception.
