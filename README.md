# Profi-Fahrpult

iPad-App zur Steuerung einer Modelleisenbahn über die **Roco/Fleischmann Z21** (auch z21, z21start, Z21 XL).
Die Funktionen orientieren sich an der Z21-App von Roco. Die Oberfläche ist an die
**ESU ECoS** angelehnt: dunkle Bedienoberfläche, zwei Fahrregler mit Tacho-Drehregler,
gelb leuchtende Funktionstasten, rote STOP- und grüne GO-Taste.

> Ein unabhängiges Hobbyprojekt. Es verwendet das öffentlich dokumentierte
> „Z21 LAN Protokoll“ von Roco. Es enthält keinen Code, keine Grafiken und keine Logos von Roco oder ESU.

## Funktionen

| Bereich | Inhalt |
|---|---|
| **Fahren** | 2 Fahrregler nebeneinander, Tacho als Drehregler (kreisende Bewegung, lange drücken = Nothalt der Lok), optionaler Schieberegler an der Außenseite jedes Reglers, Richtung, Funktionen F0–F31 auf 3 Seiten, Moment- und Dauerfunktionen, Lokeinstellungen direkt aus dem Fahrregler, RailCom-Geschwindigkeit, Hinweis „wird von anderem Gerät gesteuert“, Kopplung mit zwei Multimäusen (siehe unten) |
| **Loks** | Lokliste mit Name, Adresse (1–9999), 14/28/128 Fahrstufen, Geschwindigkeitsanzeige (km/h bei höchster Fahrstufe oder eingemessene Messpunkte), Einmessen mit drei Belegtmeldern (einzeln oder automatisch), Lokfoto (Mediathek/Kamera), Funktionsbelegung mit 19 Symbolen |
| **Stellpult** | 16 Magnetartikel pro Seite, Adressen 1–2048, rote/grüne Taste, Weichen links/rechts, Signale, Entkuppler, Licht; Rückmeldung der Stellung; Name und Rot/Grün-Tausch per langem Drücken |
| **Melder** | R-Bus-Rückmelder, Module 1–20 mit je 8 Eingängen, Live-Anzeige |
| **Prog.** | CV lesen/schreiben auf dem Programmiergleis, POM (Hauptgleis) schreiben/lesen, Bit-Ansicht, Lokadresse lesen/schreiben (kurz und lang, inkl. CV29) |
| **System** | IP/Port der Z21, Verbinden/Trennen, Hardware, Firmware, Seriennummer, Ströme, Temperatur, Spannungen, Einstellungen (STOP-Verhalten, Schaltzeit, Bildschirmsperre …) |

Aussehen und Farben entsprechen dem Display der ESU ECoS: oben die blaue Menüleiste mit Symboltasten
(die gewählte leuchtet gelb), links daneben STOP und rechts GO, deren Rahmen wie die LEDs der ECoS
leuchten. Darunter eine Statuszeile mit Verbindung, Gleisstatus (Gleisspannung ein/aus, Nothalt,
Kurzschluss, Programmiermodus) und Uhrzeit. Unter „Fahren“ stehen im Hoch- und Querformat die beiden
Fahrregler nebeneinander: Lokname, ◀ Lokbild ▶ (Tippen auf das Bild wählt die Lok), schwarzer Tacho mit
gelbem Zeiger, beim linken Regler links und beim rechten Regler rechts ein Schieberegler mit Strichskala
(abschaltbar unter *System → Einstellungen → Schieberegler neben Tacho anzeigen*), Funktionstasten und
die blaue Tastenleiste mit ⇄ (Regler tauschen), Schraubenschlüssel (Lokeinstellungen) und den Funktionsseiten.

![Querformat](docs/mockup/querformat.png)

## Loks einmessen

Der Tacho zeigt die Maßstabsgeschwindigkeit der Lok. Unter *Loks → Bearbeiten → Geschwindigkeitsanzeige*
gibt es zwei Wege:

- **km/h bei höchster Fahrstufe:** Ein Wert, z. B. 70. Dazwischen wird gleichmäßig gerechnet
  (Fahrstufe 63 von 126 = 35 km/h). Die Tachoskala geht dann bis 70.
- **Messpunkte:** Beliebig viele Paare „Fahrstufe → km/h“. Zwischen den Punkten wird gerechnet,
  über dem höchsten Punkt mit der Steigung der letzten Strecke weiter. Die Grafik zeigt die Kennlinie.

Die **Einmess-Hilfe** (*Messpunkte und Einmessen → Einmessen mit Belegtmeldern*) arbeitet wie die
Messung mit Dauerkontakten in iTrain:

1. Einmalig das Messgleis einrichten (*System → Einstellungen → Messgleis* oder direkt in der
   Einmess-Hilfe): drei Belegtmelder hintereinander auf einem geraden Gleisstück, Adressen
   links/Mitte/rechts (R-Bus 1–160, wie unter „Melder“) und die beiden Abstände in cm.
2. Maßstab wählen (Z, N, TT, H0, S, 0, 1, G).
3. **Einzeln:** Fahrstufe einstellen, „Lok fahren“ – jede Durchfahrt über die drei Melder wird
   automatisch gemessen (beide Abschnitte gemittelt, in beide Richtungen). Mehrere Durchfahrten
   werden gemittelt, dann „Als Messpunkt übernehmen“.
4. **Automatisch:** Bereich (von/bis Fahrstufe) und Schrittweite eingeben, „Automatik starten“.
   Die Lok fährt jede Fahrstufe vorwärts durch die Messstrecke, der Messpunkt wird übernommen, dann
   fährt sie rückwärts hinter den linken Melder zurück und nimmt die nächste Fahrstufe.
   „Lok anhalten / Abbrechen“ beendet die Automatik jederzeit.

Messpunkte von Hand eingeben geht weiterhin wie bisher.

Rechnung: km/h = Strecke (m) ÷ Zeit (s) × 3,6 × Maßstab. Beispiel H0: 1 m in 4,5 s = 69,6 km/h.

## Mit zwei Multimäusen fahren (wie an der ECoS)

Das iPad liegt in der Mitte, links und rechts je eine Roco Multimaus an der Z21.
Regler 1 und Regler 2 der App zeigen, was an den Mäusen passiert:

- **Tempo, Richtung, Funktionen:** Ändert man sie an der Multimaus, bewegt sich der Tacho
  und die Funktionstasten leuchten in der App mit. Unter dem Loknamen steht kurz „Handregler aktiv“.
  Umgekehrt sieht die Multimaus Änderungen aus der App.
- **Lokwechsel:** Wählt man an einer Multimaus eine andere Lok und **fährt sie an oder schaltet eine
  Funktion**, übernimmt die App die Lok auf den Regler, der am längsten nicht benutzt wurde – in der
  Regel der Regler, dessen alte Lok an dieser Maus nicht mehr bedient wird. Loks, die noch nicht in
  der Lokliste stehen, werden als „Lok *Adresse*“ angelegt.
- **⇄** in der blauen Tastenleiste eines Reglers tauscht die beiden Regler, falls die Zuordnung einmal nicht passt.
  Danach bleibt sie, solange man an jeder Maus seine Lok fährt.
- Ein Regler, der gerade in der App bedient wird, wird nicht ersetzt.
- Ein-/Ausschalten unter *System → Einstellungen → Lokwechsel an Multimaus folgen*.

Grenzen der Z21: Die Zentrale meldet nur, *welche* Lok bedient wurde, nicht an *welcher* Maus.
Das bloße Auswählen einer Lok an der Multimaus meldet sie gar nicht – die App bemerkt den Wechsel
erst beim ersten Drehen am Fahrregler oder Tastendruck. Die App nutzt dafür das Broadcast-Flag
`0x00010000` (Lok-Infos aller Loks, ab Z21-Firmware 1.20).

Ohne echte Multimaus lässt sich das mit dem Simulator testen:

```bash
python3 tools/multimaus.py 23 fahre 40
```

```bash
python3 tools/multimaus.py 23 f 0 an
```

## Kompatibilität

- Nur iPad (Hoch- und Querformat).
- Reines UIKit ohne SwiftUI, ohne SF Symbols und ohne Network.framework (UDP über BSD-Sockets).
  Dadurch läuft der Code auch auf älteren iOS-Versionen.
- Im Projekt ist **iOS 12.0** als Mindestversion eingestellt. Das ist das Minimum, das aktuelle
  Xcode-Versionen zulassen; damit laufen u. a. iPad Air 1, iPad mini 2/3 und alle neueren iPads.
- Für noch ältere Geräte (iOS 9–11, z. B. iPad 4 oder iPad mini 1) kann man mit einem älteren
  Xcode (12 oder 13) unter *Target → General → Minimum Deployments* einen kleineren Wert einstellen.
  Der Code prüft neuere Schnittstellen mit `#available`.

## App bauen und auf das iPad bringen

Voraussetzungen: ein Mac mit Xcode und eine (kostenlose) Apple-ID.

1. Repository klonen und `ProfiFahrpult.xcodeproj` in Xcode öffnen.
2. Links das Projekt anklicken → Target **ProfiFahrpult** → *Signing & Capabilities*:
   bei **Team** die eigene Apple-ID wählen. Falls nötig, die *Bundle Identifier*
   (`de.profifahrpult.app`) ändern, z. B. in `de.<deinname>.fahrpult`.
3. iPad per Kabel anschließen, oben als Ziel auswählen und **▶ Run** drücken.
4. Beim ersten Start auf dem iPad den Zugriff auf das **lokale Netzwerk** erlauben.

Mit einer kostenlosen Apple-ID muss die App alle 7 Tage neu aus Xcode installiert werden.
Mit einem kostenpflichtigen Entwicklerkonto gilt sie ein Jahr.

### Ohne eigenen Mac: Cloud-Build + Sideloadly

Wer keinen Mac hat, kann den Xcode-Build per GitHub Actions in der Cloud laufen lassen und
die fertige App dann von einem Windows-PC aus aufs iPad bringen:

1. Im GitHub-Repository unter **Actions → Build IPA → Run workflow** den Workflow starten
   (er läuft auch automatisch bei jedem Push auf `main`).
2. Nach erfolgreichem Lauf das Artefakt **ProfiFahrpult-ipa** herunterladen und entpacken –
   darin liegt `ProfiFahrpult.ipa`. Die App ist darin absichtlich **unsigniert**.
3. Auf einem Windows- (oder Linux-)PC [Sideloadly](https://sideloadly.io) installieren,
   iPad per USB-Kabel anschließen, die `.ipa` hineinziehen, mit der eigenen (kostenlosen)
   Apple-ID anmelden und installieren lassen. Sideloadly signiert die App dabei selbst –
   genau das, was sonst Xcode erledigt.
4. Wie beim direkten Xcode-Weg läuft die App mit einer kostenlosen Apple-ID nur 7 Tage;
   danach einfach dieselbe `.ipa` erneut über Sideloadly installieren (ein neuer Cloud-Build
   ist nur nötig, wenn sich der Code geändert hat).
5. Beim ersten Start auf dem iPad den Zugriff auf das **lokale Netzwerk** erlauben.

## Verbindung zur Z21

- Das iPad muss im WLAN des Routers sein, an dem die Z21 hängt.
- Werkseinstellung der Z21: IP `192.168.0.111`, UDP-Port `21105` (unter *System* änderbar).
- Die App meldet sich mit `LAN_SET_BROADCASTFLAGS` an, fragt den Systemzustand regelmäßig ab
  (hält die Verbindung aktiv) und verbindet sich bei Unterbrechung selbst neu.
- Beim Wechsel in den Hintergrund meldet sich die App mit `LAN_LOGOFF` ab.

## Testen ohne Z21

Ein Z21-Simulator liegt bei:

```bash
python3 tools/z21_simulator.py
```

In der App unter *System* die IP des Macs eintragen (im iOS-Simulator auf demselben Mac: `127.0.0.1`).
Der Simulator kennt Gleisspannung, Nothalt, Loks, Funktionen, Weichen, CVs und lässt
R-Bus-Melder zufällig wechseln. `tools/multimaus.py` spielt einen Handregler (siehe oben).

## Aufbau des Codes

```
ProfiFahrpult/
  App/          AppDelegate, Info.plist, Startbildschirm
  Z21/          Z21-LAN-Protokoll (Codec), UDP-Socket, Z21Client (Verbindung + Zustand)
  Core/         Rechenlogik ohne UIKit (Geschwindigkeitskennlinie, Maßstäbe, Multimaus-Zuordnung)
  Model/        Lok, Lokliste, Magnetartikel, Einstellungen (JSON/UserDefaults)
  UI/           ECoS-Design (Theme), Tacho, Funktionssymbole, alle Bildschirme
Tests/          Unit-Tests für Protokoll und Kennlinie + Integrationstest gegen den Simulator
tools/          z21_simulator.py, multimaus.py
```

Die Protokollschicht (`ProfiFahrpult/Z21`) und die Rechenlogik (`ProfiFahrpult/Core`) haben keine UIKit-Abhängigkeit und kann mit
`swift test` geprüft werden (macOS oder Linux):

```bash
swift test
```

Mit laufendem Simulator zusätzlich den Integrationstest ausführen:

```bash
Z21_HOST=127.0.0.1 swift test
```

## Noch nicht enthalten (Ideen für später)

- Gleisbild-Stellwerk mit Fahrstraßen
- Mehrfachtraktion
- LocoNet- und CAN-Rückmelder
- Import der Lokliste aus der Z21-App
- Z21-Einstellungen (z. B. Weichenadress-Versatz RCN-213)
