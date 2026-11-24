# Gran Turismo 4 Europe sous Windows

Ce guide concerne votre édition **SCES-51719**, CRC PCSX2 **`44A61C8F`**. Vous pouvez tester la manette, le volant et votre sauvegarde dans **PCSX2** avec le jeu PAL à sa vitesse d’origine. Le build natif GT4Recomp disponible cible les éditions américaines et demande une adaptation dédiée pour cette ISO. [Identifiant publié par PCSX2](https://github.com/PCSX2/pcsx2_patches/blob/1fd98102b8e2fffe3e0c29aab55339d48af0ffe5/patches/SCES-51719_44A61C8F.pnach#L1) · [Cibles de GT4Recomp](https://github.com/moesuito/gt4-staticrecomp/blob/7e069b4b9a9939cda48942994aa2e509c95a00ff/native/CMakeLists.txt#L15-L20)

## 1. Retrouver et identifier votre ISO

1. Ouvrez votre PCSX2 habituel. Dans la liste des jeux, faites un clic droit sur **Gran Turismo 4 → Propriétés → Résumé**. Copiez le champ **Chemin**. S’il se termine par `.iso`, vous pouvez sélectionner ce fichier à l’étape suivante. S’il se termine par `.chd`, conservez-le pour jouer et utilisez votre ISO d’origine pour le diagnostic.
2. Téléchargez le [ZIP de la branche `gt4-native-100fps`](https://github.com/flamm789/gt4-staticrecomp/archive/refs/heads/gt4-native-100fps.zip). Sur le fichier ZIP, faites un clic droit → **Propriétés**, cochez **Débloquer** si proposé, puis **Extraire tout**. Gardez tous les dossiers extraits ensemble.
3. Dans le dossier extrait, ouvrez `tools\windows-reference60`. Cliquez dans la barre d’adresse de l’Explorateur, tapez `powershell`, puis appuyez sur Entrée. Si Windows bloque le lancement des scripts, exécutez `Set-ExecutionPolicy -Scope Process RemoteSigned` dans cette fenêtre.
4. Si Python 3.12 manque, installez-le avec cette commande, puis rouvrez PowerShell dans le même dossier. Il suffit d’installer Python pour le diagnostic.

   ```powershell
   winget install --id Python.Python.3.12 --exact --source winget
   ```

5. Lancez le script et sélectionnez votre ISO dans la fenêtre. Vous pouvez aussi indiquer le chemin directement avec `-Iso 'D:\Jeux\Gran Turismo 4.iso'`.

   ```powershell
   .\Inspect-PAL.ps1
   ```

La première exécution installe `pycdlib` dans un environnement Python dédié. La lecture de l’ISO peut prendre plusieurs minutes. Le script affiche le numéro de série et le CRC du fichier ELF de démarrage. Il enregistre un `pal-report.json` dans un nouveau dossier sous `%LOCALAPPDATA%\GT4-Dev\runs`. Le rapport contient les tailles et empreintes de l’ISO et des entrées `SYSTEM.CNF`, `SCES_517.19` et `CORE.GT4`. Il indique si le couple série/CRC correspond et si l’ISO correspond à l’une des deux références Redump connues pour ce numéro de série. Un couple série/CRC peut correspondre même si l’empreinte de l’ISO complète diffère. Vous pouvez transmettre ici uniquement `pal-report.json`. Gardez l’ISO, ses fichiers internes et vos sauvegardes sur votre PC. [Calcul du CRC de l’ELF](https://github.com/PCSX2/pcsx2/blob/v2.8.2/pcsx2/Elfheader.cpp#L248-L259)

## 2. Tester votre manette dans PCSX2

Vous pouvez faire ce test tout de suite avec votre PCSX2 actuel. Fermez le jeu et branchez la manette. Pour le premier passage, débranchez le volant si les deux sont connectés.

1. Appuyez sur `Windows + R`, tapez `joy.cpl` et validez. Sélectionnez votre manette puis **Propriétés** pour vérifier que Windows voit les axes et les boutons.
2. Dans PCSX2, ouvrez **Paramètres → Manettes** (**Settings → Controllers**). Créez un **Nouveau profil** nommé `GT4-PAL-Manette`. Dans **Port manette 1**, choisissez **DualShock 2**, puis **Mappage automatique** et le nom de votre manette. Si le mappage automatique ne trouve pas le bon appareil, cliquez sur les commandes et associez-les une par une.
3. Depuis la liste des jeux, faites un clic droit sur GT4 → **Propriétés → Résumé → Profil de manette**, puis sélectionnez `GT4-PAL-Manette`.
4. Lancez GT4 normalement. Vérifiez la croix directionnelle, le stick gauche et les boutons dans le menu. En contre-la-montre, testez la direction à faible et fort braquage, l’accélération et le freinage selon les commandes affichées par le jeu. Vérifiez les vibrations si votre manette en dispose. Gardez la vitesse normale de PCSX2 à **100 %** et désactivez les correctifs de cadence pour ce premier essai. Les **50 affichés** en PAL constituent votre point de départ.

Le code de GT4Recomp gère déjà les manettes SDL3 en émulant les entrées DualShock 2. Il lit les sticks et les gâchettes et transmet les vibrations. Le kit ajoute son test de mappage aux vérifications de compilation Windows. La détection de votre modèle et l’essai en course restent à vérifier sur votre PC. [Profils PCSX2](https://github.com/PCSX2/pcsx2/blob/master/pcsx2-qt/Settings/ControllerSettingsWindow.cpp#L89-L140) · [Code manette de GT4Recomp](../../native/host_io.cpp)

### Essayer aussi le Logitech Driving Force GT

1. Branchez son alimentation et son câble USB. Dans `joy.cpl`, vérifiez que la direction et les pédales répondent.
2. Créez un autre profil PCSX2, `GT4-PAL-Volant`. Dans **Port USB 1** de l’interface PCSX2, sélectionnez **Wheel Device → Driving Force Pro**. Il s’agit du modèle USB présenté au jeu. Associez les deux sens du volant, les deux pédales séparément, les palettes et les boutons de menu.
3. Cliquez sur la liaison **Force Feedback** et actionnez un axe ou un bouton du volant pour sélectionner le périphérique correspondant. Choisissez `GT4-PAL-Volant` dans les propriétés de GT4.
4. À faible intensité, vérifiez la direction, les pédales et une force qui varie en virage ou sur un vibreur. Un ressort de centrage au repos ne suffit pas à confirmer le retour de force du jeu.

[Ports USB de PCSX2 pour GT4](https://github.com/PCSX2/pcsx2/blob/master/pcsx2/USB/USB.cpp#L50-L61) · [Modèle de volant et liaisons](https://github.com/PCSX2/pcsx2/blob/master/pcsx2/USB/usb-pad/usb-pad.cpp#L98-L125)

## 3. Reprendre votre progression PS2

### Votre progression est déjà dans PCSX2

1. Arrêtez le jeu. Ouvrez **Paramètres → Cartes mémoire**. Notez le nom de la carte du **Slot 1** utilisée par GT4, en vérifiant aussi les propriétés du jeu s’il a une carte dédiée. Cliquez sur **Ouvrir** pour trouver le dossier réel des cartes.
2. Fermez PCSX2. Dans ce dossier, copiez la carte et donnez à la copie un nom distinct, par exemple `GT4-PAL-essai.ps2`. Si la carte apparaît comme un dossier, copiez le dossier entier avec son contenu sous un nom distinct.
3. Relancez PCSX2. Dans la liste des jeux, ouvrez **GT4 → Propriétés → Cartes mémoire**, puis choisissez la copie pour le **Slot 1**. Au besoin, actualisez la liste et faites un clic droit sur la carte → **Utiliser pour le slot 1**.
4. Démarrez GT4 depuis l’ISO. Ouvrez le mode Gran Turismo et vérifiez crédits, permis et garage. Si vous aviez enregistré des replays dans le jeu, vérifiez-les aussi dans le Replay Theater. Si le jeu propose de formater la carte ou de créer une progression alors que vous attendiez la vôtre, quittez et vérifiez la carte choisie et le slot.

Un fichier `.p2s` est un état instantané de l’émulateur. Ouvrez-le dans votre PCSX2 habituel si nécessaire, puis sauvegardez depuis le menu de GT4 sur la bonne carte avant de copier celle-ci. [Sélecteur de cartes de PCSX2](https://github.com/PCSX2/pcsx2/blob/master/pcsx2-qt/Settings/MemoryCardSettingsWidget.cpp#L313-L328)

### Votre progression est sur une carte PS2 physique

1. Si votre PS2 lance déjà wLaunchELF, branchez une clé USB FAT32 et ouvrez `mc0:/` pour le premier slot de la console ou `mc1:/` pour le second. Sélectionnez le dossier entier **`BESCES-51719GAMEDATA`**, puis **R1 → Copy**.
2. Sur la clé, sous `mass:/`, ouvrez un dossier vide et choisissez **R1 → psuPaste**. Vous obtenez un fichier `.psu` qui contient la progression et les fichiers du garage. Répétez l’export pour les dossiers de replays ou de fantômes que vous souhaitez reprendre.
3. Dans PCSX2, créez une nouvelle carte **fichier PS2 de 8 Mo**, puis formatez cette carte vierge dans le gestionnaire du BIOS PS2 si nécessaire. Fermez PCSX2. Conservez le `.psu` original. Téléchargez et extrayez la version Windows x64 de myMCpp, puis utilisez **Open Memory Card… → Import Save…** pour importer le fichier dans une copie de la carte.
4. Fermez myMCpp, puis affectez la carte importée au **Slot 1** pour GT4. Démarrez le jeu et faites les vérifications de la section précédente.

[Nom du dossier PAL](https://github.com/Nenkai/PDTools/blob/d31c442b1a8f9f6467b53d79da7e17e7bdcaf72d/PDTools.SaveFile/GT4/GT4Save.cs#L29-L55) · [Export wLaunchELF](https://github.com/ps2homebrew/wLaunchELF/blob/57c20494395a6b9c83930fc678e4419b63189c05/filer.c#L4592-L4599) · [myMCpp Windows x64](https://github.com/PCSX2/myMCpp/releases/download/v0.3.3/myMCpp-v0.3.3-windows-x64-msvc.zip)

Pour le futur exécutable natif **PAL**, gardez une copie de cette carte fichier de 8 Mo. Le port devra reconnaître le dossier PAL et valider la lecture puis la réécriture sur une copie. Le lanceur actuel filtre selon les dossiers des jeux américains. Renommer votre dossier de progression ne suffit pas à le rendre compatible. [Règles du lanceur](../../launcher/crates/gt4saves/src/names.rs) · [Filtre d’import](../../launcher/crates/gt4saves/src/library.rs)

## 4. Travail restant pour un exécutable Windows PAL

La demande PAL a été clôturée sans plan côté amont. Un essai communautaire a combiné des données PAL avec un exécutable américain. Il a atteint certains menus mais présentait notamment une absence de musique et des blocages. Ce même compte rendu relève un pas physique de 50 Hz pour le PAL. Il reste à reproduire la mesure sur l’édition identifiée et à distinguer la cadence des champs vidéo, celle des images présentées et celle de la simulation en course. [Issue amont](https://github.com/moesuito/gt4-staticrecomp/issues/128#issuecomment-6627130453) · [Essai communautaire](https://github.com/moesuito/gt4-staticrecomp/issues/128#issuecomment-6930068099)

1. Relever les empreintes en local et établir un manifeste PAL séparé. Comparer le contenu du `CORE.GT4` au témoin USA avant toute réutilisation.
2. Qualifier la reconstruction ELF, les sections chargées et le BSS. Vérifier les adresses du code invité, les programmes VU et les modules IOP. Produire localement la bibliothèque AOT PAL et construire un exécutable Windows dédié, selon le précédent Spec II.
3. Valider l’horloge et l’audio PAL ainsi que le démarrage, le chrono, les collisions, l’IA, les replays, la carte et les commandes face au jeu PAL dans PCSX2. Le donneur connaît un mode 50 Hz, mais l’application GT4Recomp actuelle fixe l’horloge fenêtrée à 60 Hz. Forcer `--pal` seul ne suffit pas.
4. Après validation de cette référence, mesurer séparément les présentations à 100 Hz de CoreGS 3.0 et l’avancement de la simulation PAL originale. Les résultats des essais USA à 60 Hz restent une autre référence.

[Précédent Spec II](../../docs/SPEC2-PLAN.md) · [Horloge fenêtrée](../../native/window.cpp) · [VBlank dans le donneur](https://github.com/snuri00/ps2-web-recomp/blob/1b4808793a12c45125262fd2d5f50a9ec9f7c020/runtime/src/system.cpp#L83-L88)
