# GT4 à 100 FPS · préparation du témoin Windows à 60 FPS

Le kit prépare deux références à 60 FPS. **Published** lance l’exécutable officiel 1.3.0-rc14 vérifié. Il permet de commencer les mesures avec votre ISO. **Source** construit un exécutable local à partir de `main`, avec la capsule USB nécessaire au test du Driving Force GT. La validation de ce second exécutable précède l’intégration de CoreGS 3.0.

## Révisions retenues

| Rôle | Révision exacte |
|---|---|
| Référence source Windows et base de `gt4-native-100fps` | `b0008e8a93b05ff0556cb3347204699c225d85bc` |
| Expérience CoreGS 3.0 retenue, `task/090-coregs3` | `b987f50ee41a3d2307b3e8ed17e829f380139c21` |
| Horloge hôte des premiers essais, ancêtre de la révision retenue | `c2cff162959f7fff2bfc6505ae6d7c00d2962c19` |
| Rendu live du monde, également ancêtre | `356a93c80bf0a3b16743633595f8c3a0cc204eaf` |
| Donneur de la chaîne EE/IOP `ps2-web-recomp` | `1b4808793a12c45125262fd2d5f50a9ec9f7c020` |

L’ancêtre commun est `a4a3a5b6809fd4054e5010449eeb29f03528d3e5`, le merge du Driving Force Pro virtuel. L’audit Git compte 5 commits propres à `main` et 264 propres à TASK-090. L’essai de fusion a signalé un conflit d’ajout dans `docs/journal/2026-11-11.md`. Les 5 commits de `main` concernent les règles de contribution, la décision 0073 et le journal. La branche expérimentale inclut le correctif de dépassement de tampon `34572872`, la couche géométrique live et les changements USB/FFB de TASK-181, dont la capsule `slice409-usb-runtime`. Il faudra tester ces changements de volant comme une variable à part. [Branche retenue](https://github.com/moesuito/gt4-staticrecomp/tree/b987f50ee41a3d2307b3e8ed17e829f380139c21) · [Correctif de démarrage de course](https://github.com/moesuito/gt4-staticrecomp/blob/b987f50ee41a3d2307b3e8ed17e829f380139c21/docs/STATUS.md#L451-L472) · [Capsule USB TASK-181](https://github.com/moesuito/gt4-staticrecomp/blob/b987f50ee41a3d2307b3e8ed17e829f380139c21/docs/inputs/slice409-usb-runtime.json)

Le checkout Windows créé par le kit reprend les sources exactes de la référence et porte le nom `gt4-native-100fps`. Les scripts restent dans le dossier du kit. Il faut un dossier de préparation distinct pour étudier TASK-090. La branche retenue propose 20, 30, 45, 60, 120 et 144 Hz. Le futur mode 100 Hz demandera une modification après la validation de la référence. [Fréquences disponibles](https://github.com/moesuito/gt4-staticrecomp/blob/b987f50ee41a3d2307b3e8ed17e829f380139c21/native/coregs3/coregs3_presentation.cpp#L220-L237)

Le build local utilise le renderer intégré CoreGS 2.0. GT4-decomp à `0bf836499a295edd7e087f90e8ca01961e639da2` sert de référence pour les adresses et la dynamique. GT4Recomp-GS à `4c980f21c84040ce94beb10a7cfa2bc7f422e74d` reste une option de comparaison séparée. Le kit se limite au build de GT4Recomp et à son donneur.

## 1. Ouvrir le kit sous Windows

1. Dans l’Explorateur, ouvrez le dossier **Téléchargements**. Faites un clic droit sur le ZIP du kit, **Propriétés**, puis cochez **Débloquer** si Windows le propose. Utilisez **Extraire tout**.
2. Ouvrez le dossier extrait qui contient `Prepare-GT4.ps1`. Cliquez dans la barre d’adresse de l’Explorateur, tapez `powershell` puis Entrée. Une fenêtre s’ouvre directement dans le bon dossier.
3. Si l’exécution est bloquée, autorisez les scripts locaux pour cette fenêtre uniquement avec la commande ci-dessous. Votre système peut conserver la politique de votre organisation.

```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
```

Le dossier de travail est `%LOCALAPPDATA%\GT4-Dev`. Pour l’ouvrir, tapez ce chemin dans la barre d’adresse de l’Explorateur. Prévoyez plusieurs dizaines de Go libres si vous installez la chaîne C++ et compilez. Les données de jeu et les résultats restent dans `assets` et `runs`, à côté du checkout Git.

## 2. Vérifier votre disque et démarrer le témoin officiel

1. Exécutez l’installation légère. Elle cherche Git et Python 3.12 avec WinGet. Si `winget` est introuvable, installez ou mettez à jour **Programme d’installation d’application** depuis le Microsoft Store. Acceptez les invites d’installation Windows si elles correspondent aux outils affichés.
2. Fermez puis rouvrez PowerShell dans le dossier du kit pour actualiser le chemin des outils.
3. Dans les commandes suivantes, remplacez `D:\Jeux\Gran Turismo 4.iso` par le chemin de votre propre ISO. Conservez les guillemets.

```powershell
.\Prepare-GT4.ps1 -Action Install -PublishedOnly
```

Après réouverture de PowerShell si nécessaire.

```powershell
$iso = 'D:\Jeux\Gran Turismo 4.iso'
.\Prepare-GT4.ps1 -Action Prepare -PublishedOnly -Iso $iso
.\Run-GT4.ps1 -Profile Published -Mode Shaders
.\Run-GT4.ps1 -Profile Published -Mode Performance
```

Le script récupère l’archive portable officielle, contrôle le ZIP et l’exécutable par SHA-256 et utilise CoreGS 2.0 à 1×. L’exécutable est le témoin officiel PGO/ThinLTO. Le futur build local est un Release simple avec un autre profil EE. Gardez les mesures des deux profils distinctes. La première course peut vous demander de formater ou d’initialiser la carte de test. Chaque lancement reçoit une nouvelle carte de test, ou une copie du fichier passé avec `-Card`. Traitez les premiers passages comme des essais de chauffe. [Version officielle 1.3.0-rc14](https://github.com/moesuito/gt4-staticrecomp/releases/tag/v1.3.0-rc14)

### Fichiers lus dans l’ISO

L’image requise est **GT4 USA NTSC-U v2.00, SCUS-97328**, de **5 314 478 080 octets**, SHA-256 `67b6c0075837f3ae1132d608acf2858bf13b2dd62d6eae83dff76df02e4e824f`. Aucun montage manuel n’est nécessaire.

| Fichier sur le disque | Traitement |
|---|---|
| `/CORE.GT4;1` · 2 020 861 octets | Seul fichier extrait sur disque par la préparation. Le producteur l’enregistre dans `assets\private\reference60-disc\CORE.GT4` et reconstruit `SCUS_973.28.elf` dans le même dossier. |
| `/SCUS_973.28;1` · 273 020 octets | Bootstrap vérifié à l’intérieur de l’ISO. |
| `/SYSTEM.CNF;1` · 57 octets | Configuration de démarrage vérifiée à l’intérieur de l’ISO. |
| Autres fichiers, dont `IOPRP300.IMG` | Lus par le jeu dans l’ISO pendant l’exécution. Gardez le fichier ISO à son emplacement. |

L’ELF reconstruit doit avoir le SHA-256 `10f82e2231a51404b95682ed3ea81171100a1af2fefdeed3391943016c7c935c`. Sa reconstruction diffère de la simple extraction du bootstrap. Le kit vérifie l’ISO entière et le manifeste de chaque fichier utile. [Manifeste disque](https://github.com/moesuito/gt4-staticrecomp/blob/b0008e8a93b05ff0556cb3347204699c225d85bc/docs/inputs/usa-v2.00.json) · [Producteur EE](https://github.com/moesuito/gt4-staticrecomp/blob/b0008e8a93b05ff0556cb3347204699c225d85bc/docs/EE-PRODUCER.md)

## 3. Préparer le build local

Retirez `-PublishedOnly` pour installer Visual Studio Build Tools 2022, le SDK Windows 10.0.26100.0, clang-cl 22.1.3, CMake 4.3.1, Ninja 1.13.2 et le SDK Vulkan 1.4.341.1. Le kit initialise l’environnement VS x64 et vérifie l’empreinte exacte de `glslangValidator.exe`. La construction de l’exécutable de jeu passe directement par CMake, sans compilation du launcher Rust. Si Build Tools est déjà installé sans les composants C++, utilisez **Visual Studio Installer → Modifier → Développement Desktop en C++** et sélectionnez les outils MSVC x64/x86 et **Windows 11 SDK 10.0.26100.0**. Pour un SDK Vulkan installé ailleurs, ajoutez `-VulkanSdk 'D:\chemin\1.4.341.1'` à `Check` et `Build`.

```powershell
.\Prepare-GT4.ps1 -Action Install
```

Fermez et rouvrez PowerShell dans le dossier du kit. Puis exécutez la préparation complète, avec votre chemin ISO.

```powershell
.\Prepare-GT4.ps1 -Action Prepare -Iso 'D:\Jeux\Gran Turismo 4.iso'
.\Prepare-GT4.ps1 -Action Check
```

La préparation installe les deux archives SDL3 3.4.18 x64, récupère les en-têtes Vulkan épinglés, génère les capsules de runtime et vérifie les neuf shaders extraits de la version officielle. Elle génère aussi les trois fichiers publics dérivables du port `slice200`. Le dossier du donneur utilise les fins de ligne CRLF qui correspondent aux empreintes publiées. Les scripts préservent les fichiers existants et signalent une empreinte différente. Pour reprendre après une erreur d’installation, corrigez la cause et relancez la même commande.

### Deux entrées privées pour compiler le témoin source

Placez les fichiers suivants dans `%LOCALAPPDATA%\GT4-Dev\assets\private`, sous leurs chemins relatifs exacts. Il faut les récupérer auprès du mainteneur ou depuis les artefacts locaux qualifiés. Le témoin officiel de l’étape 2 reste disponible entre-temps.

| Chemin relatif à `assets\private` | SHA-256 attendu |
|---|---|
| `slice217-ee-aspect-producer\game-build\ps2game.lib` | `8e671a10667cdb3e20ad70367fe4021763309446cd525fc6c5f8d0dec57c129b` |
| `slice200-port\main.cpp` | `b89939f78987096eabb7fa3934734036619bff57b2812b81511aefbeb149b81d` |

La première entrée est une bibliothèque liée au profil EE `aspect`. La chaîne publique historique de production EE génère une autre base. La recette `aspect` suppose une traduction slice208 et un traducteur qualifié. La seconde entrée est la variante Windows `slice200` du point d’entrée avec le contrôle de portabilité et le flush de carte. Le générateur public actuel produit une version dont les octets diffèrent. `Check` rejettera les substitutions. [Pin bibliothèque](https://github.com/moesuito/gt4-staticrecomp/blob/b0008e8a93b05ff0556cb3347204699c225d85bc/docs/inputs/slice217-ee-libraries.json) · [Pin port](https://github.com/moesuito/gt4-staticrecomp/blob/b0008e8a93b05ff0556cb3347204699c225d85bc/docs/inputs/slice262-frame-cost-runtime.json) · [Recette historique du port](https://github.com/moesuito/gt4-staticrecomp/blob/b0008e8a93b05ff0556cb3347204699c225d85bc/docs/BUILD.md#L1355-L1375)

Avec les deux fichiers présents, lancez les commandes dans cet ordre.

```powershell
.\Prepare-GT4.ps1 -Action Check
.\Prepare-GT4.ps1 -Action Build
.\Run-GT4.ps1 -Profile Source -Mode Shaders
.\Run-GT4.ps1 -Profile Source -Mode Performance
```

`Build` produit les tables VU0 et VU1 à partir de l’ELF et les compare aux empreintes de référence, y compris les 128 parties VU1. Il utilise la fin de l’image VU1 déjà épinglée dans le manifeste et valide l’image entière. Les captures d’origine du corpus VU1 seraient nécessaires pour répéter le contrôle sur les instantanés réels. CMake génère `build\reference60\gt4vulkan.exe`, SDL3 et les shaders voisins. Quatre fixtures CTest ciblent pacing, frame skip, USB DFP et volant. Le compilateur et la liste des options sont consignés dans `reference-build.json`. Conservez le journal d’erreur si une étape échoue. La présence d’un fichier EXE seul ne valide ni les tests ni le résultat en jeu.

## 4. Vérifier la GTX 1070 et le volant

Lancez la collecte matérielle. Le dossier de rapport est indiqué à l’écran.

```powershell
.\Prepare-GT4.ps1 -Action Hardware
```

1. Dans `vulkan-summary.txt`, trouvez le **périphérique physique NVIDIA GeForce GTX 1070** et son `apiVersion` au moins égale à 1.2. Le renderer requiert aussi une file graphique, `VK_KHR_swapchain`, `timelineSemaphore`, `dualSrcBlend`, `fragmentStoresAndAtomics` et ses formats de texture et de profondeur. `Source -Mode Shaders` utilise le programme `hw_gs_smoke.exe` pour vérifier l’adaptateur sélectionné et l’ouverture d’une swapchain de test. Si le pilote nomme la carte autrement, copiez le nom exact via `-Adapter 'nom vu dans vulkaninfo'`. Si vous voyez un refus du pilote, vérifiez le pilote Windows que NVIDIA propose pour ce modèle. [Critères du renderer](https://github.com/moesuito/gt4-staticrecomp/blob/b0008e8a93b05ff0556cb3347204699c225d85bc/native/hw_gs/hw_gs_backend.cpp#L565-L615)
2. Branchez l’écran sur la carte NVIDIA. Dans **Paramètres → Système → Affichage → Affichage avancé**, relevez fréquence et résolution. Vérifiez le mode VRR/G-SYNC dans le panneau NVIDIA et dans l’OSD de l’écran. Pour une présentation à intervalles uniformes de 10 ms lors de la phase 100 FPS, il faudra du VRR actif autour de 100 Hz, ou un mode fixe réel 100/200 Hz. Un écran bloqué à 240 Hz donne des intervalles de 8,33 et 12,50 ms pour les images entières à 100 FPS. Pour TASK-090, relevez les familles et le nombre de files dans `vulkan-full.txt`. Le code final peut utiliser une file de présentation dédiée ou le chemin d’images à file partagée. Le chemin de rendu direct retombe sur la cadence invitée. [Chemin hôte retenu](https://github.com/moesuito/gt4-staticrecomp/blob/b987f50ee41a3d2307b3e8ed17e829f380139c21/native/hw_gs/hw_gs_backend.cpp#L2006-L2026)
3. Branchez l’alimentation du **Driving Force GT** et son USB, de préférence directement sur le PC. Windows doit détecter le volant Logitech (identifiant USB attendu `VID_046D&PID_C29A`). Si nécessaire, cherchez le pilote correspondant à votre Windows sur le site de Logitech. Appuyez sur **Windows + R**, entrez `joy.cpl`, puis ouvrez **Propriétés** du volant. Vérifiez que volant, deux pédales et boutons réagissent indépendamment. Réglez la plage réelle de rotation et le mode pédales séparées si le panneau Logitech les propose. [Assistance Logitech](https://support.logi.com/)
4. Sur le **build source**, lancez le mode volant ci-dessous. GT4 voit un Driving Force Pro virtuel sur le port invité 2. Vous pouvez utiliser le clavier pour entrer en course. Vérifiez l’axe de direction, le sens de l’accélérateur et du frein et la montée/descente des rapports. Le kit prend des valeurs initiales et un gain de 25 %. Si nécessaire, copiez `wheel-dfgt.toml`, corrigez la copie, puis passez `-WheelConfig 'C:\chemin\wheel.toml'`. En course, vérifiez l’effort de rappel et son sens. Vérifiez son arrêt à la pause, à la perte de focus et au débranchement. Cherchez `DFP force feedback on the wheel` dans `game.log` et examinez `dfp-forces.csv` pour les commandes du jeu. La présence de commandes indique le fonctionnement du trajet logiciel. Seul l’essai du volant constate l’effort physique.

```powershell
.\Run-GT4.ps1 -Profile Source -Mode Wheel
```

## 5. Mesurer et lire les résultats

Commencez par un contre-la-montre en 480p sur la Nordschleife. Notez vue, résolution, fréquence, VRR et type de commandes. Gardez les mêmes conditions pour chaque comparaison et faites au moins deux répétitions. Effectuez les mesures après chauffe, pendant une portion de course stable. Ne compilez pas en parallèle. Si une mesure montre une anomalie, conservez l’essai.

### Rythme du jeu, performance du renderer et affichage

- Le mode `Performance` écrit `game.log` et `frametime.csv`. Une fois en course, pressez **F7**, roulez environ une minute, puis pressez **F8** et fermez normalement. Relevez les VBlanks invités/s, les coûts EE, VU et GPU disponibles et les reprises audio. La simulation doit garder son rythme de référence d’environ 60 VBlanks/s. Le retour console indique le **dossier du run**.
- L’analyse `cadence` affiche les durées et les percentiles des appels de présentation. `--start-ms` et `--end-ms` sélectionnent une portion de `frametime.csv` par rapport à son origine, l’initialisation du renderer. Les valeurs éventuellement absentes de `shown_ms` sont comptées séparément.
- Pour mesurer les images affichées, gardez le jeu ouvert en course et ouvrez un **deuxième PowerShell** dans le dossier du kit. Copiez le dossier affiché lors du démarrage. Lancez la capture ETW ci-dessous et retournez immédiatement au jeu. Le script télécharge la version CLI 2.3.1 de PresentMon, compare son empreinte officielle et cible uniquement le PID du run. En cas de refus d’accès ETW, utilisez une fenêtre administrateur pour cette capture. L’analyse sépare les swapchains et signale les lignes sans durée d’affichage. Utilisez la swapchain de rendu de la course. [PresentMon et colonnes de mesure](https://github.com/GameTechDev/PresentMon/blob/v2.3.1/README-ConsoleApplication.md)

```powershell
$run = 'C:\chemin\vers\le-dossier-de-mesure'
py -3.12 .\analyze60.py cadence "$run"
.\Capture-Display.ps1 -Run "$run" -Seconds 30
# Remplacez le chemin par le fichier .csv indique par Capture-Display.
py -3.12 .\analyze60.py display 'C:\chemin\vers\GT4-Reference-xxxxxxxx.csv'
```

La capture ETW se fait **avant** de fermer le jeu. Le résumé CoreGS se lit **après** la fermeture pour que la dernière ligne soit écrite. Les appels de présentation, l’affichage ETW et le nombre d’images 3D nouvelles mesurent des choses différentes.

### Premier contrôle de chronomètre et de physique

1. Lancez une capture d’entrées avec votre clavier ou manette et roulez jusqu’à une portion de course avec chronomètre actif. Pressez **F9** pour terminer. Notez le dossier de cet enregistrement.
2. Rejouez deux fois cet enregistrement, avec le même profil, en lançant les commandes ci-dessous. Chaque run repart de la même carte initiale.
3. Avec `race-range`, relevez la plage de VBlanks actifs dans les deux dossiers. Remplacez les valeurs d’exemple 7 000 et 7 400 par un intervalle continu de votre propre course. Le comparateur exige chaque VBlank de la plage et vérifie les chronomètres et les digests de 64 Kio de dynamique. Il échoue si une ligne manque ou si un résultat diverge. Ceux-ci sont des contrôles A/A. Un replay de course GT4 et un replay de rapports volant nécessitent des essais séparés. [Trace de physique du projet](https://github.com/moesuito/gt4-staticrecomp/blob/b0008e8a93b05ff0556cb3347204699c225d85bc/native/frame_skip.cpp#L89-L137)

```powershell
.\Run-GT4.ps1 -Profile Source -Mode Record
# Une fois le jeu ferme, utilisez le dossier de l'enregistrement.
$record = 'C:\chemin\vers\source-record'
.\Run-GT4.ps1 -Profile Source -Mode Replay -ReplayFrom "$record" -Headless
.\Run-GT4.ps1 -Profile Source -Mode Replay -ReplayFrom "$record" -Headless
$a = 'C:\chemin\vers\le-premier-source-replay'
$b = 'C:\chemin\vers\le-second-source-replay'
py -3.12 .\analyze60.py race-range "$a"
py -3.12 .\analyze60.py race-range "$b"
py -3.12 .\analyze60.py physics "$a" "$b" --first 7000 --last 7400
```

Ajoutez une paire de relectures **sans** `-Headless` pour vérifier la vitesse murale pendant la même portion. Les runs sans fenêtre servent au déterminisme. La capture actuelle porte sur le pad par VBlank. Le mode volant USB demande à terme des rapports IN/OUT indexés et un contrôle de l’effort physique.

### Latence entre le geste et l’écran

Avec une caméra à haute fréquence, filmez dans le même plan le geste et une zone fixe de l’écran. Reproduisez un mouvement bref, visible dans la caméra de conduite. Pour chaque répétition, notez le numéro d’image au premier mouvement et au premier changement visible. Copiez `latency-template.csv`, gardez les virgules et saisissez ces deux index et le FPS **de capture** vidéo. Mesurez avec les mêmes réglages écran, caméra et cadence pour chaque référence. Relevez au moins 20 répétitions si possible. La précision de l’estimation est bornée par la durée d’une image caméra. PresentMon mesure un délai logiciel vers l’affichage, complémentaire à cette mesure physique.

```powershell
py -3.12 .\analyze60.py optical 'C:\chemin\vers\mesures-latence.csv'
```

## 6. Éléments restants avant le prototype

- **Dès le témoin 60 FPS.** Votre ISO vérifiée, les deux fichiers privés de la section 3 pour le build source, les outils Windows, un test de course en fenêtre sur la GTX 1070 et un essai de FFB du vrai DFGT. Le témoin publié permet de mesurer le rythme et le rendu indépendamment du build source. Le cloud Debian a vérifié des empreintes, des recettes et les analyseurs. La compilation du jeu et les essais matériels restent à effectuer sur Windows.
- **Premier essai de TASK-090 sans développement 100 FPS.** Après validation du témoin source, la commande `.\Prepare-GT4.ps1 -Action StageTask090` place les sources épinglées dans `task090-inspection`. Il faudra le dossier privé `slice299-ee-flare-producer\generated` et la bibliothèque **flare** correspondante pour le témoin A/B (`d322b0aaa6a217ab8d0275d7447b8a838161d6fb3359478615c963acef616b3a`). L’expérience compile une autre bibliothèque à partir des unités instrumentées par `scripts/coregs3_units.py` de la révision expérimentale, avec son propre reçu. Elle utilise `GT4_EE_PROFILE=flare`, `GT4_EE_LIBRARY` et son SHA-256, `GT4_COREGS3=ON` à la configuration et la capsule USB `slice409` si on qualifie le volant sur cette branche. Vérifier la configuration de la branche et les pins de ces unités avant d’utiliser les modes `off`, `shadow` puis `present` à 60 Hz. [Recette TASK-090](https://github.com/moesuito/gt4-staticrecomp/blob/b987f50ee41a3d2307b3e8ed17e829f380139c21/docs/COREGS3-HOOKS.md#L429-L463) · [Build v2.00 de la branche](https://github.com/moesuito/gt4-staticrecomp/blob/b987f50ee41a3d2307b3e8ed17e829f380139c21/scripts/coregs2_bench/game/configure.cmd)
- **Critère de passage.** Conserver une référence 60 qui démarre, mesure correctement le temps invité et reproduit les digests pour des entrées identiques. Confirmer la conduite et le retour de force sur le DFGT. Conserver les captures de menu, de course et les replays dans les dossiers locaux. Le premier essai à 100 utilisera ensuite une branche distincte du témoin, des transformations géométriques extrapolées avec horizon borné et une nouvelle mesure du délai d’affichage. Les essais à 120 Hz de l’amont restent des résultats historiques.

La chaîne de jeu reste AOT et le renderer de référence intégré reste CoreGS 2.0. GSdx peut servir à une comparaison séparée via son processus GPL et son protocole GS. Le kit télécharge les composants publics nécessaires. Votre ISO, vos fichiers extraits, vos bibliothèques générées, les cartes et les traces restent sur votre PC.
