# Vernissage selbst hosten

Ja. **Vernissage ist eine relativ neue, quelloffene Fotoplattform im Fediverse**, die sich besonders an Fotografen richtet. Man kann sie als Alternative zu Instagram, Flickr oder Pixelfed betrachten.

Und das Interessante: **Du kannst eine eigene Vernissage-Instanz vollständig selbst hosten.** Seit September 2026 gibt es dafür sogar einen offiziellen Installer namens `vernissagectl`, der die Einrichtung erheblich vereinfacht.  

## **1. Was ist Vernissage?**

Vernissage ist eine dezentrale Plattform zum Veröffentlichen und Entdecken von Fotografien.

Die wichtigsten Eigenschaften:

- **ActivityPub:** Vernetzung mit Mastodon, Pixelfed und anderen Fediverse-Plattformen.
- **Fotografie im Mittelpunkt:** Unterstützung für EXIF-Metadaten, HDR-Fotos und Fotogalerien.
- **Keine Algorithmen:** Chronologische Timelines statt algorithmischer Feeds.
- **Open Source:** Apache-2.0-Lizenz.
- **Eigene Instanzen:** Vollständige Kontrolle über Nutzer, Daten und Infrastruktur.
- **KI-Funktionen:** Optionale automatische ALT-Texte und Hashtag-Vorschläge.
- **Mobile App:** Native iOS-Anwendung.

Offizielle Projektseite: ⁠joinvernissage.org

## **2. Welche Infrastruktur braucht Vernissage?**

Vernissage besteht aus mehreren Komponenten.

| **Komponente**  | **Funktion**                 |
| --------------- | ---------------------------- |
| Vernissage API  | Backend und ActivityPub      |
| Vernissage Web  | Weboberfläche                |
| PostgreSQL      | Datenbank                    |
| Redis           | Warteschlangen und Caching   |
| S3 / MinIO      | Speicherung der Fotos        |
| Nginx           | Reverse Proxy                |
| HTTPS           | Verschlüsselte Kommunikation |
| Background Jobs | Asynchrone Verarbeitung      |

Die Anwendung lässt sich vollständig mit Docker betreiben.

### **Meine Empfehlung für einen kleinen Server**

Für eine private Instanz oder eine kleine Community würde ich zunächst folgende Ausstattung einplanen:

| **Ressource**  | **Empfehlung**             |
| -------------- | -------------------------- |
| Betriebssystem | Ubuntu 24.04 LTS           |
| CPU            | 2–4 vCPU                   |
| RAM            | 4–8 GB                     |
| SSD            | 40–80 GB                   |
| Fotospeicher   | S3 oder MinIO              |
| Container      | Docker Compose             |
| Domain         | z. B. `photos.example.org` |

Das sind **Planungswerte, keine offiziellen Mindestanforderungen**.

Für größere Communities würde ich PostgreSQL und den Objektspeicher von der Anwendungsinstanz trennen.

------

## **3. Vernissage selbst installieren**

Der einfachste Weg ist inzwischen der offizielle Installer `vernissagectl`.

### **Schritt 1: Server vorbereiten**

Du benötigst einen Linux-Server mit öffentlicher IP-Adresse.

Die Domain muss auf den Server zeigen:

```text
photos.example.org  A  203.0.113.10
```

Außerdem müssen folgende Ports erreichbar sein:

```text
22/tcp    SSH
80/tcp    HTTP / Let's Encrypt
443/tcp   HTTPS
```

### **Schritt 2: Docker installieren**

Installiere Docker Engine und das Docker-Compose-Plugin nach der offiziellen Docker-Anleitung.

Anschließend prüfen:

```bash
sudo systemctl status docker
sudo docker compose version
```

### **Schritt 3: Vernissage-Installer installieren**

Der offizielle Installationsbefehl lautet:

```bash
curl -fsSL https://joinvernissage.org/install.sh | sudo sh
```

Sicherer ist es, das Skript vorher herunterzuladen und zu prüfen:

```bash
curl -fsSL https://joinvernissage.org/install.sh -o install.sh

less install.sh

sudo sh install.sh
```

Danach:

```bash
vernissagectl --version
```

### **Schritt 4: Installation starten**

```bash
sudo vernissagectl install
```

Jetzt startet ein interaktiver Installationsassistent.

Er übernimmt unter anderem:

1. Prüfung der Docker-Installation.
2. Einrichtung von PostgreSQL.
3. Einrichtung von Redis.
4. Konfiguration von S3 oder MinIO.
5. Installation des Vernissage-Backends.
6. Installation der Weboberfläche.
7. Erstellung des Administratoraccounts.
8. Einrichtung von Nginx.
9. Ausstellung eines HTTPS-Zertifikats über Let’s Encrypt.

Nach Abschluss sollte deine Instanz unter folgender Adresse erreichbar sein:

```text
https://photos.example.org
```

Diese Vorgehensweise entspricht der offiziellen Installationsanleitung des Projekts.  

------

## **4. Instanz konfigurieren**

Nach der Installation meldest du dich mit deinem Administratoraccount an.

Anschließend solltest du insbesondere folgende Einstellungen überprüfen:

**Instanzeinstellungen**

- Name und Beschreibung
- Administrator-Kontaktadresse
- Registrierung neuer Benutzer
- Moderationsregeln

**E-Mail**

- SMTP-Server
- Absenderadresse
- Zustellung von System-E-Mails

**Medien**

- Maximale Uploadgröße
- S3-/MinIO-Konfiguration
- Speicherlimits

**Fediverse**

- Erreichbarkeit der ActivityPub-Endpunkte
- Kommunikation mit anderen Instanzen
- Funktionierende WebFinger-Auflösung

Wichtig: Die Domain sollte langfristig bestehen bleiben. Ein späterer Domainwechsel kann bestehende föderierte Identitäten und Beziehungen beschädigen.

------

## **5. Wartung und Updates**

Der Installer bietet Verwaltungsbefehle.

Systemstatus:

```bash
sudo vernissagectl status
```

Diagnose:

```bash
sudo vernissagectl doctor
```

Die Installation erzeugt außerdem Konfigurationsdateien:

```text
vernissage.yml
vernissage.secrets.yml
```

Die zweite Datei enthält sensible Zugangsdaten und muss entsprechend geschützt werden.

Für einen zuverlässigen Betrieb brauchst du regelmäßige Backups von PostgreSQL und deinem S3-/MinIO-Speicher.

**Hinweis:** `vernissagectl` wird vom Entwickler noch als experimentell bezeichnet. Für einen produktiven Betrieb sind deshalb Monitoring und regelmäßige Backups besonders wichtig. 

------

## **6. Wie unterscheidet sich Vernissage von Pixelfed?**

| **Eigenschaft**    | **Vernissage**                     | **Pixelfed**                       |
| ------------------ | ---------------------------------- | ---------------------------------- |
| Hauptfokus         | Fotografie                         | Instagram-ähnliches Social Network |
| Fediverse          | Ja                                 | Ja                                 |
| ActivityPub        | Ja                                 | Ja                                 |
| Self-Hosting       | Ja                                 | Ja                                 |
| EXIF-Unterstützung | Zentraler Bestandteil              | Nicht gleichermaßen im Fokus       |
| HDR-Fotografie     | Unterstützt                        | Abhängig von Implementierung       |
| Technologiestack   | Swift-Backend, Angular-Webfrontend | PHP / Laravel                      |
| Docker             | Ja                                 | Ja                                 |
| Entwicklungsstand  | Jüngeres Projekt                   | Länger etabliert                   |

Vernissage ist besonders interessant, wenn es um hochwertige Fotografie, Metadaten und eine entsprechend ausgerichtete Benutzeroberfläche geht.

Pixelfed ist stärker am klassischen Instagram-Erlebnis orientiert.

------

## **7. Meine Empfehlung für dein Hosting**

Wenn du bereits einen eigenen Server betreibst, würde ich Vernissage zunächst so aufbauen:

```text
                 INTERNET
                    |
                    |
          photos.example.org
                    |
                    |
                 HTTPS
                    |
                    v
             +-------------+
             |    Nginx    |
             | Reverse     |
             | Proxy       |
             +-------------+
                    |
          +---------+---------+
          |                   |
          v                   v
    +-----------+       +-----------+
    | Vernissage|       | Vernissage|
    | Web       |       | API       |
    +-----------+       +-----------+
                              |
                 +------------+------------+
                 |            |            |
                 v            v            v
            PostgreSQL      Redis       MinIO/S3
```

Für eine kleine Instanz können alle Komponenten auf demselben Server laufen.

Bei wachsender Nutzerzahl lässt sich die Infrastruktur später auf mehrere Server verteilen.

Die offizielle Dokumentation findest du hier:

⁠Vernissage Server Documentation

------

### **Step by Step:**

# **Vernissage installieren – Ubuntu 26.04 / Docker Compose / Nginx**

**Zielkonfiguration**

| **Parameter**              | **Wert**                         |
| -------------------------- | -------------------------------- |
| Domain                     | `example.gallery`                |
| Projektverzeichnis         | `/var/www/htdocs/vernissage`     |
| Betriebssystem             | Ubuntu 26.04                     |
| Docker + Compose           | Bereits installiert              |
| Nginx                      | Bereits auf dem Host installiert |
| HTTPS                      | Host-Nginx + Let’s Encrypt       |
| Vernissage                 | Docker Compose                   |
| PostgreSQL / Redis / MinIO | Lokale Docker-Container          |
| Interner Port              | `8180`                           |

**Wichtig:** Der offizielle Vernissage-Installer ist experimentell und für Ubuntu 24.04 dokumentiert. Die folgende Anleitung nutzt ihn für die Anwendungskomponenten. Die Anpassung an deinen vorhandenen Nginx erfolgt über die generierte Docker-Compose-Konfiguration. 

## **1. DNS konfigurieren**

Beim DNS-Anbieter:

```text
Typ:   A
Name:  @
Wert:  DEINE-SERVER-IP
```

Prüfen:

```bash
dig +short example.gallery
```

## **2. Projektverzeichnis erstellen**

```bash
sudo mkdir -p /var/www/htdocs/vernissage
sudo chmod 750 /var/www/htdocs/vernissage

cd /var/www/htdocs/vernissage
```

Das Verzeichnis darf nicht direkt als Nginx-DocumentRoot erreichbar sein.

## **3. Vernissage-Installer installieren**

```bash
curl -fsSL https://joinvernissage.org/install.sh \
  -o /tmp/vernissage-install.sh

less /tmp/vernissage-install.sh
```

Nach Prüfung:

```bash
sudo sh /tmp/vernissage-install.sh
```

Installation prüfen:

```bash
vernissagectl --version
```

## **4. Vernissage installieren**

```bash
cd /var/www/htdocs/vernissage

sudo vernissagectl install
```

Im Installationsassistenten folgende Werte verwenden:

| **Einstellung** | **Auswahl**               |
| --------------- | ------------------------- |
| Domain          | `example.gallery`         |
| PostgreSQL      | Lokal                     |
| Redis           | Lokal                     |
| S3-Speicher     | Lokales MinIO             |
| API             | Installieren              |
| Background Jobs | Installieren              |
| Web             | Installieren              |
| Web Push        | Installieren              |
| Administrator   | Eigenen Account erstellen |

**Achtung beim Reverse Proxy:** Der Installer richtet standardmäßig einen eigenen HTTPS-Proxy ein. Dieser darf nicht gleichzeitig mit deinem Host-Nginx die Ports 80/443 belegen.

Falls der Assistent keine Möglichkeit bietet, einen vorhandenen Reverse Proxy zu verwenden, **nicht mit der automatischen HTTPS-Installation fortfahren**. Die dokumentierte Installer-Standardinstallation ist für deinen Fall nicht unmittelbar geeignet.  

## **5. Docker-Proxy konfigurieren**

In der vom Installer erzeugten Compose-Konfiguration muss der interne Vernissage-Proxy ausschließlich lokal veröffentlicht werden.

Die gewünschte Portzuordnung lautet:

```yaml
ports:
  - "127.0.0.1:8180:80"
```

Dabei muss `80` dem tatsächlichen HTTP-Port des internen Vernissage-Proxys entsprechen.

Die übrigen Dienste erhalten keine öffentlichen Portfreigaben.

**Hinweis:** Die konkrete Compose-Datei und ihre Service-Namen hängen von der Installer-Version ab. Die Portzuordnung ist deshalb eine Konfigurationsvorgabe, kein unverändert übernehmbarer Dateiausschnitt.

## **6. Nginx konfigurieren**

```bash
sudo nano /etc/nginx/sites-available/example.gallery
```

Inhalt:

```nginx
server {
    listen 80;
    listen [::]:80;

    server_name example.gallery;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:8180;

        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }
}
```

Aktivieren:

```bash
sudo ln -s \
  /etc/nginx/sites-available/example.gallery \
  /etc/nginx/sites-enabled/example.gallery

sudo nginx -t
sudo systemctl reload nginx
```

## **7. HTTPS einrichten**

```bash
sudo apt update
sudo apt install -y certbot python3-certbot-nginx
```

Zertifikat erstellen:

```bash
sudo certbot --nginx -d example.gallery
```

Automatische Verlängerung testen:

```bash
sudo certbot renew --dry-run
```

## **8. Vernissage prüfen**

```bash
curl -I http://127.0.0.1:8180
curl -I https://example.gallery
```

Diagnose:

```bash
sudo vernissagectl doctor
sudo vernissagectl status
```

Die Diagnosebefehle müssen aus dem Verzeichnis mit der generierten `vernissage.yml` ausgeführt werden. Alternativ kann der Konfigurationspfad mit `--config` angegeben werden.

## **9. Administration**

Im Browser öffnen:

**https://example.gallery**

Mit dem bei der Installation erstellten Administratoraccount anmelden.

Anschließend konfigurieren:

1. Instanzname und Beschreibung
2. Administrator-E-Mail
3. SMTP
4. Registrierungsoptionen
5. Moderation
6. Uploadlimits
7. Web-Push-Benachrichtigungen

## **10. Backups**

Mindestens sichern:

```text
PostgreSQL-Datenbank
MinIO-Objektspeicher
vernissage.yml
vernissage.secrets.yml
Docker-Compose-Konfiguration
Nginx-Konfiguration
```

Die Backups müssen zusätzlich außerhalb des Servers gespeichert werden.

------

### **Technischer Vorbehalt**

**Die Schritte 1–3 und 6–10 sind direkt ausführbar. Die Schritte 4–5 sind noch keine garantiert durchgängige Installation.**

Die offizielle Dokumentation bestätigt zwar den Docker-Compose-Betrieb, liefert aber in den hier zugänglichen Quellen keine verifizierte Installer-Konfiguration für einen bereits vorhandenen Host-Nginx.  

Ich möchte dir keine Compose-Datei mit geratenen Images, Umgebungsvariablen oder Container-Ports als funktionierende Komplettlösung verkaufen. Dafür müssen die offiziellen Installationsdateien konkret vorliegen.

Die technische Zielarchitektur steht jedoch fest: **Host-Nginx → localhost:8180 → Vernissage-Proxy → Web/API**, mit PostgreSQL, Redis und MinIO im internen Docker-Netzwerk.

Hier sind die relevanten Anleitungen:

**1. Offizielle Docker-Compose-Anleitung (Englisch)**

⁠Vernissage – Hosting in Docker Containers

Unter **„Hosting Vernissage in Docker containers“** findest du die manuelle Installation.

**2. Deutsche Self-Hosting-Anleitung**

⁠Vernissage hosten – OgeR

Dort findest du eine Anleitung mit Docker Compose, MinIO und einem vorhandenen Nginx-Reverse-Proxy.

**3. Offizieller Installer**

⁠Vernissage – Installationsanleitung

Dort findest du den Beitrag **„Deploying your own Vernissage instance“** vom 4. September 2026.

**Meine Empfehlung:** Schau dir insbesondere **Anleitung 2** an. Sie behandelt praktisch genau dein Setup: Docker Compose, lokales MinIO und einen bereits vorhandenen Nginx. 