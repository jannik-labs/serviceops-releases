#!/bin/sh
#
# Installs ServiceOps on a server you control.
#
#   curl -fsSLO https://raw.githubusercontent.com/jannik-labs/serviceops-releases/main/install.sh
#   less install.sh          # read it. it runs as root
#   sudo sh install.sh
#
# It is published in the public repository jannik-labs/serviceops-releases
# and downloaded from there, as above; it holds no host name and no secret.
#
# It asks for your licence server's address and your licence key first, then
# for a domain, an address for the first administrator and, if you want
# mail, an SMTP server. Everything else it works out or generates. You are
# never asked to invent a secret.
#
# Moving to a new machine, or replacing one that is gone:
#
#   sudo sh install.sh --restore
#
# asks, beside the above, for the backup to put back and for the backup key
# the old installation printed once. The backup is two files, the rows and
# the -files half beside them; copy both into one directory on this machine
# first and name the rows half. The key is typed, never passed as an
# argument, and never shown. The new installation gets an APP_SECRET of its
# own, as every installation does: what was sealed with the old one - the
# mail password from Settings and every authenticator - is set up again
# afterwards (the owner's decision of 28 September 2026). Recovery codes are
# kept as prints, not sealed, so anybody with a second factor signs in with
# one and sets it up again, or an administrator takes it off them. The order
# is: lay the installation down with the backup key's public half, migrate,
# put the backup back, and only then start anything. See `serviceops help`
# and docs/docker.md.
#
# Every question explains itself before it is asked: what it is, what is
# recommended and why, a proposal Enter takes or where the answer is found,
# and what a wrong answer does. Where an answer can be checked it is - the
# domain against this machine's address, the licence server's /health, the
# licence key by registering, the SMTP server by signing in. The words are in
# one table below, in German and English: German when the locale says so,
# English for any other, and asked once when there is no locale at all.
# `--lang de` or `--lang en` decides it outright.
#
# On a first installation it offers, once the stack is healthy, to read a
# handover archive in from the system this one replaces (ADR 39), or points
# at the screen that does the same later. `serviceops import` does it on an
# installation that is already running.
#
# Starting again on a machine that already has an installation:
#
#   sudo sh install.sh --fresh
#
# deletes the existing one entirely - database, files, backups, containers
# and volumes - once the domain has been typed to confirm it, and only after
# the new release has been opened, then installs as if the machine were new.
# See docs/adr/0124-the-installer-explains-itself-and-brings-the-data.md.
#
# The software arrives as an encrypted bundle from a public registry. The
# licence key is all it needs to open it: the installer registers with the
# maker's licence server, fetches a lease, and the lease carries the key for
# each version the licence covers (ADR 126). Nothing is written to this
# machine before that key has opened the release. The installation then
# takes the registration over and asks the same server every day which
# modules it may run, and nothing else (ADR 111).
#
# There is no way around the licence server: every key comes through the
# lease (ADR 128).
#
# What it changes on this machine is listed before it changes anything, and
# it asks. See docs/adr/0041-the-product-operates-itself.md and
# docs/adr/0126-a-release-opens-with-a-key-the-lease-carries.md in the
# source, if you have it.
set -eu

RELEASE_REPOSITORY="${SERVICEOPS_RELEASE_REPOSITORY:-ghcr.io/jannik-labs/serviceops-release}"
RELEASE_TAG="${SERVICEOPS_RELEASE:-latest}"
INSTALL_DIR="${SERVICEOPS_DIR:-/opt/serviceops}"

# Where this was started from. The script moves into the installation to
# start it; an archive named, or lying, where the person stood is found here.
STARTED_IN="$PWD"

# ---------------------------------------------------------------- the words --
#
# Everything a person reads while answering, in one place: `<language> <key>
# <text>`, one line each. A question has a label (its heading and its
# prompt), what it is, what is recommended and why, a proposal or where to
# find the answer, and what a wrong answer does; `invalid` is the complaint
# when an answer cannot work, and it is asked again. @NAME@ is filled in.
# docker/test_install.py holds both languages to the same keys.

texts() {
cat <<'TEXTS'
de word.recommended Empfohlen:
en word.recommended Recommended:
de word.proposal Vorschlag:
en word.proposal Proposed:
de word.enter_takes Enter übernimmt ihn.
en word.enter_takes Enter takes it.
de word.find Zu finden:
en word.find Where to find it:
de word.wrong Wenn es falsch ist:
en word.wrong If it is wrong:
de word.yes_no [j/N]
en word.yes_no [y/N]
de word.choice Ihre Wahl
en word.choice Your choice
de word.hidden (wird nicht angezeigt)
en word.hidden (not shown)
de word.stopped Abgebrochen:
en word.stopped Stopped:
de word.next Nächster Schritt:
en word.next Next step:

de language.label Sprache / Language
en language.label Sprache / Language
de language.option1 Deutsch
en language.option1 Deutsch
de language.option2 English
en language.option2 English

de option.unknown Diese Option gibt es nicht: @OPTION@. Es gibt --restore, --fresh und --lang de|en.
en option.unknown There is no such option: @OPTION@. There are --restore, --fresh and --lang de|en.

de ground.step Dieser Server wird angesehen
en ground.step Looking at this machine
de ground.root Bitte mit sudo starten: Das Installationsprogramm installiert Pakete und schreibt nach /opt.
en ground.root Run this with sudo. It installs packages and writes to /opt.
de ground.curl curl wird gebraucht und fehlt. Bitte installieren (apt install curl) und das Installationsprogramm erneut starten.
en ground.curl curl is needed and is not here. Install it and run this again.
de ground.no_os_release Das sieht nicht nach einem Linux mit /etc/os-release aus.
en ground.no_os_release This does not look like a Linux with /etc/os-release.
de ground.not_debian Geschrieben ist das für Debian und Ubuntu; @SYSTEM@ ist keins von beiden.
en ground.not_debian This is written for Debian and Ubuntu; @SYSTEM@ is neither.
de ground.carry_on Trotzdem weitermachen?
en ground.carry_on Carry on anyway?
de ground.facts @SYSTEM@, @RAM@ MB Arbeitsspeicher, @DISK@ GB frei auf /
en ground.facts @SYSTEM@, @RAM@ MB memory, @DISK@ GB free on /
de ground.disk Nur @DISK@ GB frei. Nötig sind mindestens 10, und die Fotos eines Betriebs brauchen deutlich mehr.
en ground.disk Only @DISK@ GB free. This needs at least 10, and a business's photographs need a great deal more.
de ground.exists In @DIR@ liegt schon eine Installation. Auf eine neue Version bringt sie "serviceops update". Ganz von vorn beginnt "sudo sh install.sh --fresh", das alles darin löscht.
en ground.exists @DIR@ already holds an installation. "serviceops update" moves it to a newer version. "sudo sh install.sh --fresh" starts from nothing and deletes everything in it.
de ground.nothing_changed Es wurde nichts verändert.
en ground.nothing_changed Nothing was changed.

de fresh.step Ganz von vorn
en fresh.step Starting afresh
de fresh.label Die bestehende Installation löschen
en fresh.label Deleting the existing installation
de fresh.what ACHTUNG: --fresh löscht ALLES der bestehenden Installation: die Datenbank mit allen Kunden, Maschinen, Vorgängen und Berichten, alle Dateien und Fotos, alle Sicherungen auf diesem Server, die Einstellungen in .env, dazu ihre Container und Volumes. Das lässt sich nicht rückgängig machen.
en fresh.what CAREFUL: --fresh deletes EVERYTHING of the existing installation: the database with every customer, machine, case and report, every file and photograph, every backup on this machine, the settings in .env, and its containers and volumes. It cannot be undone.
de fresh.recommended was Sie behalten wollen, vorher von diesem Server kopieren, mindestens die neueste Sicherung (beide Dateien). Gelöscht wird erst, nachdem das neue Release geöffnet ist, unmittelbar bevor die neue Installation angelegt wird.
en fresh.recommended copy what you want to keep off this machine first, at least the newest backup (both files). Nothing is deleted until the new release has been opened, right before the new installation is laid down.
de fresh.find der Domainname steht in der Zeile unten; er stammt aus der .env der bestehenden Installation.
en fresh.find the domain name is in the line below; it comes from the existing installation's .env.
de fresh.wrong Ein Name, der nicht genau stimmt, löscht nichts: Das Installationsprogramm hört dann auf, ohne etwas zu verändern.
en fresh.wrong A name that does not match exactly deletes nothing: the installer stops without changing anything.
de fresh.where Gelöscht wird @DIR@ mit allem darin, auch @DIR@/data/backups.
en fresh.where Deleted is @DIR@ with everything in it, @DIR@/data/backups included.
de fresh.confirm Zum Bestätigen den Domainnamen der bestehenden Installation eintippen (@NAME@)
en fresh.confirm To confirm, type the domain name of the existing installation (@NAME@)
de fresh.confirm_dir Zum Bestätigen den Pfad der bestehenden Installation eintippen (@NAME@)
en fresh.confirm_dir To confirm, type the path of the existing installation (@NAME@)
de fresh.refused Das stimmt nicht mit @NAME@ überein. Es wurde nichts gelöscht und nichts verändert.
en fresh.refused That does not match @NAME@. Nothing was deleted and nothing was changed.
de fresh.nothing In @DIR@ liegt keine Installation; --fresh hat nichts zu löschen, und es geht wie gewohnt weiter.
en fresh.nothing @DIR@ holds no installation; --fresh has nothing to delete, and this carries on as usual.
de fresh.removing Die bestehende Installation wird gelöscht
en fresh.removing Deleting the existing installation
de fresh.removed @DIR@ ist gelöscht, mit Datenbank, Dateien und Sicherungen; ihre Container und Volumes sind entfernt.
en fresh.removed @DIR@ is gone, with its database, files and backups; its containers and volumes are removed.

de licence_server.step Ihr Lizenzserver
en licence_server.step Your licence server
de licence_server.label Adresse des Lizenzservers
en licence_server.label Licence server address
de licence_server.what Der Server des Herstellers, bei dem sich diese Installation anmeldet und einmal am Tag erfährt, welche Module sie nutzen darf. Über ihn geht nichts aus Ihrem Betrieb hinaus. Eine Adresse, die mit https:// beginnt.
en licence_server.what The maker's server this installation registers with, and asks once a day which modules it may run. Nothing about your business goes there. An address beginning with https://.
de licence_server.recommended die Adresse aus der Installationsanleitung. Ohne sie geht es nicht: Von diesem Server kommt der Schlüssel, der die Software öffnet.
en licence_server.recommended the address from the installation guide. It cannot be left out: the key that opens the software comes from this server.
de licence_server.find in Ihrer Installationsanleitung (PDF) vom Hersteller, direkt über dem Lizenzschlüssel.
en licence_server.find in your installation guide (PDF) from the maker, right above the licence key.
de licence_server.wrong Antwortet dort kein Lizenzserver, sagt das Installationsprogramm es sofort und lässt die Adresse noch einmal eingeben.
en licence_server.wrong If no licence server answers there, the installer says so at once and lets you type the address again.
de licence_server.invalid Die Adresse beginnt mit https://.
en licence_server.invalid The address begins with https://.
de licence_server.needed Ohne Lizenzserver gibt es keinen Schlüssel für die Software. Bitte die Adresse aus der Installationsanleitung eingeben.
en licence_server.needed Without a licence server there is no key to the software. Please type the address from the installation guide.
de licence_server.answers Der Lizenzserver antwortet.
en licence_server.answers The licence server answers.
de licence_server.silent Unter @ADDRESS@ antwortet kein Lizenzserver (gefragt wurde @ADDRESS@/health).
en licence_server.silent No licence server answers at @ADDRESS@ (asked was @ADDRESS@/health).
de licence_server_silent.option1 Adresse anders eingeben
en licence_server_silent.option1 Type the address again
de licence_server_silent.option2 Abbrechen; es wurde nichts verändert
en licence_server_silent.option2 Stop here; nothing was changed
de licence_server.stopped Es wurde nichts verändert. Nächster Schritt: prüfen, ob dieser Server den Lizenzserver erreicht, dann das Installationsprogramm erneut starten.
en licence_server.stopped Nothing was changed. Next step: check that this machine reaches the licence server, then run the installer again.

de licence_key.label Lizenzschlüssel
en licence_key.label Licence key
de licence_key.what Der Schlüssel, mit dem sich diese Installation beim Lizenzserver als Ihre ausweist: SOLK- und acht Vierergruppen aus Buchstaben und Ziffern.
en licence_key.what The key this installation shows the licence server to prove it is yours: SOLK- and eight groups of four letters and digits.
de licence_key.recommended kopieren und einfügen; Leerzeichen und Kleinbuchstaben stören nicht.
en licence_key.recommended copy and paste it; spaces and lower case do no harm.
de licence_key.find in Ihrer Installationsanleitung (PDF) vom Hersteller, unter Lizenzschlüssel.
en licence_key.find in your installation guide (PDF) from the maker, under licence key.
de licence_key.wrong Kennt der Lizenzserver den Schlüssel nicht, sagt das Installationsprogramm es, bevor es etwas holt, und lässt ihn noch einmal eingeben.
en licence_key.wrong If the licence server does not know the key, the installer says so before it fetches anything and lets you type it again.
de licence_key.invalid Das ist kein Lizenzschlüssel: SOLK- und acht Gruppen aus je vier Buchstaben und Ziffern.
en licence_key.invalid That is not a licence key: SOLK- and eight groups of four letters and digits.

de restore.step Was zurückkommt
en restore.step What is being put back
de backup_file.label Sicherungsdatei (die Datensätze)
en backup_file.label Backup file (the rows)
de backup_file.what Die Sicherung, die zurückkommen soll, als Datei auf diesem Server. Eine Sicherung sind zwei Dateien: die Datensätze, serviceops-<Zeitpunkt>.backup, und daneben die Anhänge, serviceops-<Zeitpunkt>-files.backup.
en backup_file.what The backup to put back, as a file on this machine. A backup is two files: the rows, serviceops-<when>.backup, and beside them the attachments, serviceops-<when>-files.backup.
de backup_file.recommended beide in ein Verzeichnis auf diesem Server kopieren, etwa mit scp, und hier die Datensätze nennen.
en backup_file.recommended copy both into one directory on this machine, with scp for example, and name the rows here.
de backup_file.find im Objektspeicher (S3) der alten Installation oder in ihrem Verzeichnis data/backups.
en backup_file.find in the old installation's object store (S3) or in its data/backups directory.
de backup_file.wrong Eine Datei, die der Backup-Schlüssel nicht öffnet, kommt nicht zurück; dann ist nichts gestartet und die Installation leer.
en backup_file.wrong A file the backup key does not open does not come back; nothing has been started then and the installation is empty.
de backup_file.empty Eine Wiederherstellung braucht eine Sicherung.
en backup_file.empty A restore needs a backup to put back.
de backup_file.missing Unter @FILE@ liegt keine Datei.
en backup_file.missing There is no file at @FILE@.
de backup_file.files_half Das ist die Hälfte mit den Anhängen. Bitte die Datensätze nennen, @ROWS@, mit dieser daneben.
en backup_file.files_half That is the attachments half. Name the rows half, @ROWS@, with this one beside it.
de backup_file.no_files_half Neben ihr liegt keine @FILES@; Anhänge kommen dann nicht zurück.
en backup_file.no_files_half There is no @FILES@ beside it, so no attachments will come back.
de backup_file.rows_alone Nur die Datensätze zurückspielen?
en backup_file.rows_alone Put back the rows alone?
de backup_file.rows_alone_no Es wurde nichts verändert. Die Hälfte mit den Anhängen neben die Datensätze kopieren und erneut starten.
en backup_file.rows_alone_no Nothing was changed. Copy the files half beside the rows and run this again.
de backup_key.label Backup-Schlüssel
en backup_key.label Backup key
de backup_key.what Der Schlüssel, den die alte Installation bei ihrer Einrichtung einmal angezeigt hat: 64 Zeichen aus 0-9 und a-f. Er wird nur für diese Wiederherstellung gebraucht und nicht auf diesem Server gespeichert.
en backup_key.what The key the old installation showed once when it was installed: 64 characters of 0-9 and a-f. It is used for this restore and not kept on this machine.
de backup_key.recommended ihn aus dem Passwortmanager kopieren und einfügen.
en backup_key.recommended copy it from your password manager and paste it.
de backup_key.find in Ihrem Passwortmanager oder auf dem Papier, auf dem Sie ihn damals notiert haben.
en backup_key.find in your password manager, or on the paper you wrote it on back then.
de backup_key.wrong Mit einem falschen Schlüssel lässt sich die Sicherung nicht öffnen; die Installation bleibt dann leer, und nichts ist gestartet.
en backup_key.wrong With a wrong key the backup does not open; the installation then stays empty and nothing is started.
de backup_key.invalid Das ist kein Backup-Schlüssel: 64 Zeichen aus 0-9 und a-f. Es wurde nichts verändert.
en backup_key.invalid That is not a backup key: 64 characters of 0-9 and a-f. Nothing was changed.

de questions.step Drei Fragen zur Installation
en questions.step Three questions about the installation
de domain.label Domain
en domain.label Domain
de domain.what Die Adresse, unter der Ihr Team ServiceOps im Browser öffnet, ohne https://, zum Beispiel service.ihre-firma.de. Für sie holt die Installation selbst ein Zertifikat.
en domain.what The address your team opens ServiceOps at in a browser, without https://, for example service.your-firm.com. The installation obtains a certificate for it by itself.
de domain.recommended eine eigene Subdomain nur für ServiceOps, deren A-Eintrag im DNS auf diesen Server zeigt. Wer vorerst ohne Domain arbeiten will, gibt ip ein: Dann ist die Installation über die IP-Adresse erreichbar, mit einem selbst ausgestellten Zertifikat, vor dem Browser warnen.
en domain.recommended a subdomain of its own for ServiceOps whose A record points at this machine. To work without a domain for now, type ip: the installation is then reached by IP address with a certificate it issues itself, which browsers warn about.
de domain.proposal (aus dem Namen dieses Servers).
en domain.proposal (from this machine's name).
de domain.from_reverse (aus dem Reverse-DNS dieses Servers).
en domain.from_reverse (from this machine's reverse DNS).
de domain.find bei dem, der Ihre Domain verwaltet; dort einen A-Eintrag anlegen, der auf diesen Server zeigt. Leer lassen, um über die IP-Adresse zu arbeiten.
en domain.find with whoever manages your domain; add an A record there that points at this machine. Leave it empty to work by IP address.
de domain.wrong Zeigt die Domain nicht auf diesen Server, bekommt die Installation kein Zertifikat und ist unter dem Namen nicht erreichbar. Das Installationsprogramm prüft das gleich.
en domain.wrong If the domain does not point at this machine, the installation gets no certificate and cannot be reached by that name. The installer checks this at once.
de domain.this_server Dieser Server ist aus dem Internet unter @IP@ zu erreichen.
en domain.this_server This machine is reached from the internet at @IP@.
de domain.invalid Das ist kein Domainname wie service.ihre-firma.de.
en domain.invalid That is not a domain name such as service.your-firm.com.
de domain.here @DOMAIN@ zeigt auf diesen Server (@IP@).
en domain.here @DOMAIN@ points at this machine (@IP@).
de domain.elsewhere @DOMAIN@ zeigt auf @FOUND@, dieser Server ist aber @IP@.
en domain.elsewhere @DOMAIN@ points at @FOUND@, but this machine is @IP@.
de domain.unresolved @DOMAIN@ ist im DNS nicht zu finden.
en domain.unresolved @DOMAIN@ cannot be found in DNS.
de domain.certificate Bis der A-Eintrag auf diesen Server zeigt, scheitert das Zertifikat, und Browser warnen. Caddy versucht es von selbst wieder, sobald der Eintrag stimmt; nach einer Änderung im DNS kann das eine Weile dauern.
en domain.certificate Until the A record points at this machine the certificate fails, and browsers warn. Caddy tries again by itself once the record is right; after a change in DNS that can take a while.
de domain_problem.option1 Domain anders eingeben
en domain_problem.option1 Type the domain again
de domain_problem.option2 Trotzdem weiter
en domain_problem.option2 Carry on anyway
de domain.ip_mode Erreichbar unter https://@IP@, mit einem Zertifikat, das dieser Server selbst ausstellt. Browser warnen davor; eine Domain lässt sich später eintragen.
en domain.ip_mode Reached at https://@IP@ with a certificate this machine signs itself. Browsers will warn about it; a domain can be given later.
de domain.no_ip Keine Domain angegeben, und dieser Server konnte seine eigene Adresse nicht herausfinden.
en domain.no_ip No domain given and this machine could not work out its own address.

de admin_email.label E-Mail-Adresse des ersten Administrators
en admin_email.label E-mail address of the first administrator
de admin_email.what Ihre E-Mail-Adresse. An sie schickt die Zertifizierungsstelle Hinweise zum Zertifikat, und mit ihr wird das erste Administratorkonto angelegt, wenn Sie gleich Daten übernehmen.
en admin_email.what Your e-mail address. The certificate authority sends its notices there, and the first administrator account is made with it if you take data over in a moment.
de admin_email.recommended eine Adresse, die jemand liest.
en admin_email.recommended an address somebody reads.
de admin_email.find Ihre eigene Adresse; sie lässt sich nicht erraten, daher kein Vorschlag.
en admin_email.find your own address; it cannot be guessed, so nothing is proposed.
de admin_email.wrong Eine vertippte Adresse bekommt keine Hinweise zum Zertifikat. Ein Konto lässt sich später unter Verwaltung → Personen ändern.
en admin_email.wrong A mistyped address gets no certificate notices. An account can be changed later under Administration → People.
de admin_email.invalid Das ist keine E-Mail-Adresse.
en admin_email.invalid That is not an e-mail address.
de restore_email.label Ihre E-Mail-Adresse, für Hinweise zum Zertifikat
en restore_email.label Your e-mail address, for certificate notices
de restore_email.what Die Konten kommen mit der Sicherung zurück. Die Adresse wird trotzdem gebraucht: An sie schickt die Zertifizierungsstelle Hinweise zum Zertifikat.
en restore_email.what The accounts come back with the backup. The address is still needed: the certificate authority sends its notices there.
de restore_email.recommended eine Adresse, die jemand liest.
en restore_email.recommended an address somebody reads.
de restore_email.find Ihre eigene Adresse; sie lässt sich nicht erraten, daher kein Vorschlag.
en restore_email.find your own address; it cannot be guessed, so nothing is proposed.
de restore_email.wrong Eine vertippte Adresse bekommt keine Hinweise zum Zertifikat.
en restore_email.wrong A mistyped address gets no certificate notices.

de mail.label E-Mail-Versand
en mail.label Sending mail
de mail.what Damit die Installation Kunden Serviceberichte und Ihrem Team Einladungen schicken kann, braucht sie einen Server, über den sie Mails versendet (SMTP). Ohne ihn verschickt sie nichts, und jeder Bildschirm, der etwas verschicken würde, sagt das deutlich.
en mail.what For the installation to send customers their service reports and your team its invitations, it needs a server to send mail through (SMTP). Without one it sends nothing, and every screen that would have sent something says so plainly.
de mail.recommended später, unter Einstellungen in ServiceOps selbst: Dort liegt das Passwort versiegelt, und es lässt sich ohne Kommandozeile ändern. Jetzt nur, wenn Sie die Zugangsdaten zur Hand haben.
en mail.recommended later, under Settings in ServiceOps itself: the password is kept sealed there and can be changed without a shell. Now only if you have the details to hand.
de mail.proposal 2, später unter Einstellungen.
en mail.proposal 2, later under Settings.
de mail.wrong Falsche Angaben prüft das Installationsprogramm gleich, indem es sich beim SMTP-Server anmeldet.
en mail.wrong The installer checks wrong details at once, by signing in to the SMTP server.
de mail.option1 Jetzt einrichten
en mail.option1 Set it up now
de mail.option2 Später unter Einstellungen (empfohlen)
en mail.option2 Later under Settings (recommended)
de smtp_host.label SMTP-Server
en smtp_host.label SMTP server
de smtp_host.what Der Name des Servers, über den Ihr E-Mail-Anbieter Mails annimmt, etwa smtp.ionos.de oder smtp.office365.com.
en smtp_host.what The name of the server your mail provider takes mail through, such as smtp.ionos.de or smtp.office365.com.
de smtp_host.recommended der Server des Postfachs, von dem aus ServiceOps schreiben soll.
en smtp_host.recommended the server of the mailbox ServiceOps should write from.
de smtp_host.find in der Hilfe Ihres E-Mail-Anbieters unter SMTP oder Postausgangsserver. Leer lassen, um das später unter Einstellungen zu tun.
en smtp_host.find in your mail provider's help, under SMTP or outgoing mail server. Leave it empty to do this later under Settings.
de smtp_host.wrong Über einen falschen Server geht keine Mail hinaus; das Installationsprogramm versucht gleich, ihn zu erreichen.
en smtp_host.wrong No mail leaves through a wrong server; the installer tries to reach it in a moment.
de smtp_port.label Port
en smtp_port.label Port
de smtp_port.what Die Nummer, unter der der Server Mails annimmt: 587 (STARTTLS) oder 465 (TLS).
en smtp_port.what The number the server takes mail on: 587 (STARTTLS) or 465 (TLS).
de smtp_port.recommended 587, den fast jeder Anbieter nimmt.
en smtp_port.recommended 587, which almost every provider takes.
de smtp_port.proposal (bei fast jedem Anbieter üblich).
en smtp_port.proposal (usual with almost every provider).
de smtp_port.wrong Unter einem falschen Port ist der Server nicht zu erreichen; das zeigt die Prüfung gleich.
en smtp_port.wrong On a wrong port the server cannot be reached; the check shows it in a moment.
de smtp_port.invalid Der Port ist eine Zahl, meist 587 oder 465.
en smtp_port.invalid The port is a number, usually 587 or 465.
de smtp_user.label Benutzername
en smtp_user.label User name
de smtp_user.what Der Name, mit dem sich die Installation beim SMTP-Server anmeldet; meist die E-Mail-Adresse des Postfachs.
en smtp_user.what The name the installation signs in to the SMTP server with; usually the mailbox's e-mail address.
de smtp_user.recommended die Adresse des Postfachs, von dem aus ServiceOps schreibt.
en smtp_user.recommended the address of the mailbox ServiceOps writes from.
de smtp_user.proposal (Ihre Adresse von oben).
en smtp_user.proposal (your address from above).
de smtp_user.wrong Mit einem falschen Namen lehnt der Server die Anmeldung ab; das zeigt die Prüfung gleich.
en smtp_user.wrong With a wrong name the server refuses the sign-in; the check shows it in a moment.
de smtp_password.label Passwort für den Mailversand
en smtp_password.label Password for sending mail
de smtp_password.what Das Passwort dieses Postfachs. Die Eingabe bleibt unsichtbar; das Passwort steht danach nur in der Datei .env dieser Installation, die nur root lesen kann.
en smtp_password.what That mailbox's password. What you type stays invisible; afterwards it is only in this installation's .env, which only root can read.
de smtp_password.recommended ein eigenes Postfach oder App-Passwort nur für ServiceOps.
en smtp_password.recommended a mailbox or app password for ServiceOps alone.
de smtp_password.find bei Ihrem E-Mail-Anbieter; manche verlangen für Programme ein eigenes App-Passwort.
en smtp_password.find with your mail provider; some want an app password of its own for programs.
de smtp_password.wrong Mit einem falschen Passwort lehnt der Server die Anmeldung ab; das zeigt die Prüfung gleich.
en smtp_password.wrong With a wrong password the server refuses the sign-in; the check shows it in a moment.
de mail_from.label Absenderadresse
en mail_from.label Address it sends from
de mail_from.what Die Adresse, die beim Empfänger als Absender steht.
en mail_from.what The address a recipient sees as the sender.
de mail_from.recommended dieselbe Adresse wie der Benutzername; viele Anbieter lehnen eine andere ab.
en mail_from.recommended the same address as the user name; many providers refuse any other.
de mail_from.proposal (der Benutzername).
en mail_from.proposal (the user name).
de mail_from.wrong Lehnt der Anbieter den Absender ab, kommt keine Mail an; unter Einstellungen lässt er sich ändern.
en mail_from.wrong If the provider refuses the sender, no mail arrives; it can be changed under Settings.
de mail_from.invalid Das ist keine E-Mail-Adresse.
en mail_from.invalid That is not an e-mail address.
de smtp.checking @HOST@:@PORT@ wird versucht …
en smtp.checking Trying @HOST@:@PORT@ …
de smtp.ok Der SMTP-Server hat die Anmeldung angenommen.
en smtp.ok The SMTP server accepted the sign-in.
de smtp.login Der SMTP-Server lehnt Benutzername oder Passwort ab.
en smtp.login The SMTP server refuses the user name or the password.
de smtp.unknown_host Einen Server @HOST@ gibt es nicht.
en smtp.unknown_host There is no server called @HOST@.
de smtp.no_connection @HOST@:@PORT@ ist nicht zu erreichen. Manche Hoster sperren ausgehende Mail-Ports; dann hilft dort eine Freigabe.
en smtp.no_connection @HOST@:@PORT@ cannot be reached. Some hosting providers block outgoing mail ports; they can open them.
de smtp.tls Die verschlüsselte Verbindung zu @HOST@:@PORT@ kam nicht zustande.
en smtp.tls The encrypted connection to @HOST@:@PORT@ did not come about.
de smtp.other Der SMTP-Server antwortet nicht wie erwartet (curl @CODE@).
en smtp.other The SMTP server does not answer as expected (curl @CODE@).
de smtp_problem.option1 Angaben neu eingeben
en smtp_problem.option1 Type the details again
de smtp_problem.option2 Trotzdem so speichern
en smtp_problem.option2 Keep them as they are
de smtp_problem.option3 Ohne E-Mail weiter, später unter Einstellungen
en smtp_problem.option3 Carry on without mail, and set it up later under Settings

de proxy.label Ports 80 und 443
en proxy.label Ports 80 and 443
de proxy.what Auf Port 80 oder 443 hört schon ein anderes Programm. ServiceOps bringt einen eigenen Webserver (Caddy) mit, der genau dort das Zertifikat holt und die Installation ausliefert.
en proxy.what Something is already listening on port 80 or 443. ServiceOps brings a web server of its own (Caddy), which obtains the certificate and serves the installation exactly there.
de proxy.recommended die Ports freimachen, wenn dort nichts Wichtiges läuft. Nur wenn das Ihr eigener Reverse-Proxy ist, der vor ServiceOps stehen soll, ihn behalten.
en proxy.recommended free the ports if nothing important is on them. Keep it only if it is your own reverse proxy, which is to stay in front of ServiceOps.
de proxy.proposal 2, abbrechen und die Ports freimachen.
en proxy.proposal 2, stop and free the ports.
de proxy.wrong Ein Proxy, der nicht an ServiceOps weiterleitet, lässt die Installation von außen unerreichbar; docs/docker.md beschreibt, wohin er leiten muss.
en proxy.wrong A proxy that does not forward to ServiceOps leaves the installation unreachable from outside; docs/docker.md says where it has to forward.
de proxy.option1 Das ist mein eigener Reverse-Proxy; er bleibt davor
en proxy.option1 That is my own reverse proxy; it stays in front
de proxy.option2 Abbrechen, ich mache die Ports frei
en proxy.option2 Stop; I will free the ports
de proxy.stop Ports 80 und 443 freimachen und das Installationsprogramm erneut starten.
en proxy.stop Free ports 80 and 443 and run this again.

de summary.step Zusammenfassung
en summary.step Summary
de summary.nothing_yet Bis hierher wurde nichts verändert.
en summary.nothing_yet Nothing has been changed so far.
de summary.domain Domain: @DOMAIN@, mit einem Zertifikat von Let's Encrypt
en summary.domain Domain: @DOMAIN@, with a certificate from Let's Encrypt
de summary.domain_ip Adresse: @DOMAIN@, mit einem selbst ausgestellten Zertifikat
en summary.domain_ip Address: @DOMAIN@, with a certificate it signs itself
de summary.email E-Mail-Adresse: @EMAIL@
en summary.email E-mail address: @EMAIL@
de summary.licence Lizenzserver: @ADDRESS@, Lizenzschlüssel @KEY@
en summary.licence Licence server: @ADDRESS@, licence key @KEY@
de summary.mail E-Mail-Versand: über @HOST@:@PORT@ als @USER@, Absender @FROM@
en summary.mail Sending mail: through @HOST@:@PORT@ as @USER@, from @FROM@
de summary.mail_later E-Mail-Versand: später unter Einstellungen
en summary.mail_later Sending mail: later under Settings
de summary.do Was jetzt geschieht:
en summary.do What happens now:
de summary.fresh die bestehende Installation in @DIR@ vollständig löschen: Datenbank, Dateien, Sicherungen, Container und Volumes
en summary.fresh delete the existing installation at @DIR@ entirely: database, files, backups, containers and volumes
de summary.docker Docker installieren, von get.docker.com
en summary.docker install Docker, from get.docker.com
de summary.age age und openssl installieren: age öffnet die Software, openssl unterschreibt die Anfragen an den Lizenzserver
en summary.age install age and openssl: age opens the software, openssl signs the requests to the licence server
de summary.fetch sich beim Lizenzserver anmelden, von ihm den Schlüssel für die neueste Version holen, die Ihre Lizenz umfasst, sie aus @RELEASE@ holen und damit öffnen
en summary.fetch register with the licence server, take from it the key of the newest version your licence covers, fetch that version from @RELEASE@ and open it
de summary.write die Installation nach @DIR@ schreiben
en summary.write write the installation to @DIR@
de summary.restore @FILE@ zurückspielen, mit dem angegebenen Backup-Schlüssel
en summary.restore put @FILE@ back into it, locked with the backup key you gave
de summary.https https://@DOMAIN@ ausliefern und das Zertifikat selbst holen
en summary.https serve https://@DOMAIN@, obtaining the certificate itself
de summary.register den Lizenzserver jeden Tag fragen lassen, welche Module sie nutzen darf
en summary.register let it ask the licence server daily which modules it may run
de summary.updates automatische Sicherheitsupdates für diesen Server einschalten
en summary.updates turn on automatic security updates for this machine
de summary.firewall nur die Ports 22, 80 und 443 durch die Firewall lassen
en summary.firewall allow only ports 22, 80 and 443 through the firewall
de summary.swap 2 GB Auslagerungsspeicher anlegen, weil dieser Server nur @RAM@ MB Arbeitsspeicher hat
en summary.swap add 2 GB of swap, because this machine has @RAM@ MB of memory
de summary.takeover zuletzt fragen, ob Daten aus einem anderen System übernommen werden sollen
en summary.takeover ask, last, whether to take data over from another system
de summary.go Installieren?
en summary.go Install?
de summary.no Es wurde nichts verändert. Nächster Schritt: das Installationsprogramm erneut starten, wenn Sie so weit sind.
en summary.no Nothing was changed. Next step: run the installer again when you are ready.

de docker.step Docker wird installiert
en docker.step Installing Docker
de tools.step age und openssl werden installiert
en tools.step Installing age and openssl
de tools.no_apt age oder openssl fehlt, und dies ist kein System mit apt. Bitte beides installieren und das Installationsprogramm erneut starten.
en tools.no_apt age or openssl is missing and this is not an apt system. Please install both and run the installer again.
de swap.step Auslagerungsspeicher wird angelegt
en swap.step Adding swap
de release.asking Der Lizenzserver wird nach dem Schlüssel gefragt
en release.asking Asking the licence server for the key
de release.registered Angemeldet beim Lizenzserver.
en release.registered Registered with the licence server.
de release.newest Ihre Lizenz umfasst Version @VERSION@.
en release.newest Your licence covers version @VERSION@.
de release.not_covered Ihre Lizenz umfasst Version @VERSION@ nicht. Von ServiceOps wurde noch nichts geschrieben. Nächster Schritt: beim Hersteller nachfragen.
en release.not_covered Your licence does not cover version @VERSION@. Nothing of ServiceOps has been written. Next step: ask the maker.
de release.none_covered Ihre Lizenz umfasst noch keine veröffentlichte Version: Es fehlt die Freigabe für Kern und Updates, oder es gibt noch kein Release. Von ServiceOps wurde noch nichts geschrieben. Nächster Schritt: beim Hersteller nachfragen.
en release.none_covered Your licence does not cover any released version yet: the grant for core and updates is missing, or there is no release yet. Nothing of ServiceOps has been written. Next step: ask the maker.
de release.no_answer Der Lizenzserver hat keinen Schlüssel geliefert (@CODE@). Von ServiceOps wurde noch nichts geschrieben.
en release.no_answer The licence server handed over no key (@CODE@). Nothing of ServiceOps has been written.
de release.fetching @RELEASE@ wird geholt
en release.fetching Fetching @RELEASE@
de release.no_pull @RELEASE@ ließ sich nicht holen. Bitte prüfen, ob dieser Server ghcr.io erreicht. Von ServiceOps wurde noch nichts geschrieben.
en release.no_pull Could not fetch @RELEASE@. Please check that this machine reaches ghcr.io. Nothing of ServiceOps has been written.
de release.wrong_version @RELEASE@ ist Version @FOUND@, nicht @VERSION@. Das ist kein Release von uns. Von ServiceOps wurde noch nichts geschrieben.
en release.wrong_version @RELEASE@ is version @FOUND@, not @VERSION@. That is not a release of ours. Nothing of ServiceOps has been written.
de release.opening Version @VERSION@ wird mit dem Schlüssel vom Lizenzserver geöffnet
en release.opening Opening version @VERSION@ with the key from the licence server
de release.does_not_open Der Schlüssel öffnet Version @VERSION@ nicht. Es wurde nichts geschrieben. Nächster Schritt: dem Hersteller sagen, dass Release und Schlüssel nicht zusammenpassen.
en release.does_not_open The key does not open version @VERSION@. Nothing was written. Next step: tell the maker that the release and its key do not belong together.
de release.not_ours Das Paket ließ sich öffnen, ist aber keines von uns. Es wurde nichts geschrieben.
en release.not_ours The bundle opened but is not one of ours. Nothing was written.
de assemble.step Die Anwendung wird zusammengesetzt
en assemble.step Assembling the application
de assemble.no_base Das Basis-Image @IMAGE@ ließ sich nicht holen. Es muss auf ghcr.io öffentlich sein, und dieser Server muss es erreichen.
en assemble.no_base Could not fetch the base image @IMAGE@. It has to be public on ghcr.io, and this machine has to reach it.
de assemble.failed Das Zusammensetzen ist fehlgeschlagen. Die Ausgabe oben sagt, warum.
en assemble.failed Assembling the image failed. The output above says why.
de lay.step Die Installation wird angelegt
en lay.step Laying the installation down
de backup_key.taking Der Backup-Schlüssel wird übernommen
en backup_key.taking Taking over the backup key
de backup_key.taking_failed Der öffentliche Teil dieses Backup-Schlüssels ließ sich nicht ermitteln. Die Ausgabe oben sagt, warum.
en backup_key.taking_failed Could not work out the public half of that backup key. The output above says why.
de backup_key.making Der Schlüssel für Ihre Sicherungen wird erzeugt
en backup_key.making Making the key your backups are encrypted with
de backup_key.making_failed Der Backup-Schlüssel ließ sich nicht erzeugen. Die Ausgabe oben sagt, warum.
en backup_key.making_failed Could not make a backup key. The output above says why.
de start.step ServiceOps wird gestartet
en start.step Starting it
de start.restoring @FILE@ wird zurückgespielt
en start.restoring Putting @FILE@ back
de start.restore_failed Die Sicherung ging nicht zurück, und es wurde nichts gestartet. @DIR@ ist mit Ihrem Backup-Schlüssel angelegt und enthält keine Daten. Was oben steht beheben, dann: serviceops restore @FILE@ und serviceops start.
en start.restore_failed The backup did not go back, and nothing has been started. @DIR@ is laid down with your backup key and holds no data. Put right what the output above says, then: serviceops restore @FILE@ and serviceops start.
de start.adopt_failed Die Installation konnte die Anmeldung des Installationsprogramms nicht übernehmen und meldet sich selbst noch einmal an; der Hersteller sieht dann zwei Einträge.
en start.adopt_failed The installation could not take the installer's registration over and registers again by itself; the maker then sees two entries.
de units.failed Der Aktualisieren-Knopf in ServiceOps erreicht diesen Server nicht; "serviceops install-units" versucht es noch einmal.
en units.failed The update button in the tool will not reach this machine; "serviceops install-units" tries again.
de harden.step Dieser Server wird abgesichert
en harden.step Hardening this machine
de harden.firewall Firewall an. Offen: @SSH@, 80, 443.
en harden.firewall Firewall on. Open: @SSH@, 80, 443.

de licence.step Der Lizenzserver wird gefragt
en licence.step Asking the licence server
de licence.ok Der Lizenzserver hat den Lizenzschlüssel angenommen.
en licence.ok The licence server accepted the licence key.
de licence.key_unknown Der Lizenzserver kennt diesen Lizenzschlüssel nicht.
en licence.key_unknown The licence server does not know this licence key.
de licence.retype Lizenzschlüssel noch einmal eingeben?
en licence.retype Type the licence key again?
de licence.moved Der Lizenzserver ist umgezogen. Als neue Adresse nennt er: @ADDRESS@
en licence.moved The licence server has moved. The new address it names is: @ADDRESS@
de licence.moved_retype Bitte die neue Adresse prüfen, etwa mit einer Nachricht des Herstellers, und eingeben. Das Installationsprogramm wechselt nicht von selbst.
en licence.moved_retype Please check the new address, for example against a message from the maker, and type it. The installer does not switch by itself.
de licence.revoked Dieser Lizenzschlüssel ist widerrufen. Bitte beim Hersteller melden.
en licence.revoked This licence key has been revoked. Please contact the maker.
de licence.installation_ended Der Hersteller hat diese Installation beendet. Bitte beim Hersteller melden.
en licence.installation_ended The maker has ended this installation. Please contact the maker.
de licence.key_taken Diese Installation ist schon unter einem anderen Lizenzschlüssel angemeldet.
en licence.key_taken This installation is registered under another licence key already.
de licence.clock_off Die Uhr dieses Servers geht falsch, deshalb nimmt der Lizenzserver die Anfrage nicht an. Die Uhrzeit stellen (timedatectl), dann: serviceops connect
en licence.clock_off This machine's clock is wrong, so the licence server does not take the request. Set the time (timedatectl), then: serviceops connect
de licence.unreachable Der Lizenzserver war nicht zu erreichen.
en licence.unreachable The licence server could not be reached.
de licence.server_error Der Lizenzserver hatte gerade einen Fehler.
en licence.server_error The licence server had an error just now.
de licence.rate_limited Der Lizenzserver bittet, später wieder zu fragen.
en licence.rate_limited The licence server asks to be asked again later.
de licence.other Der Lizenzserver hat nicht geantwortet wie erwartet (@CODE@).
en licence.other The licence server did not answer as expected (@CODE@).
de licence.later Die Installation läuft trotzdem und fragt jeden Tag wieder; bis dahin laufen die Module zur Probe. Berichtigen mit "serviceops connect", prüfen unter Verwaltung → Erweiterungen.
en licence.later The installation runs anyway and asks again every day; until then its modules run on their trial. Put it right with "serviceops connect" and check under Administration → Extensions.

de takeover.step Daten aus einem anderen System
en takeover.step Data from another system
de takeover.label Daten aus einem anderen System übernehmen?
en takeover.label Take data over from another system?
de takeover.what Wer von einem anderen Programm kommt, bringt seine Daten als Übergabearchiv mit: eine ZIP-Datei (uebergabe-JJJJ-MM-TT.zip), die das alte System beim Export schreibt, mit Kunden, Maschinen, Vorgängen, Berichten, Lager und Dateien. Dazu gehört eine Passphrase, die der Export einmal angezeigt hat; sie öffnet die Passwörter, damit sich alle mit ihrem bisherigen Passwort anmelden.
en takeover.what Coming from another program, a business brings its data as a handover archive: a ZIP file (uebergabe-YYYY-MM-DD.zip) the old system writes when it exports, with customers, machines, cases, reports, stock and files. With it comes a passphrase the export showed once; it opens the passwords, so that everybody signs in with the password they already have.
de takeover.recommended jetzt, wenn das Archiv schon auf diesem Server liegt: Am Terminal kommt die Passphrase genau so an, wie sie getippt ist. Sonst später über die Oberfläche.
en takeover.recommended now, if the archive is on this machine already: at a terminal the passphrase arrives exactly as typed. Otherwise later, through the screen.
de takeover.proposal 2, später über die Oberfläche.
en takeover.proposal 2, later through the screen.
de takeover.wrong Dasselbe Archiv noch einmal zu lesen ist sicher: Was schon da ist, wird übersprungen oder aktualisiert, nie doppelt angelegt. Nur ein zweiter Betrieb gehört nicht in dieselbe Installation.
en takeover.wrong Reading the same archive again is safe: what is in already is passed by or brought up to date, never added twice. Only a second business does not belong in the same installation.
de takeover.option1 Jetzt übernehmen
en takeover.option1 Take it over now
de takeover.option2 Später über die Oberfläche
en takeover.option2 Later, through the screen
de takeover.option3 Nein, ich fange ohne alte Daten an
en takeover.option3 No, I start without old data
de takeover.later Später: Anmelden, dann Verwaltung → Datenübernahme; dort das Archiv hochladen und die Passphrase eingeben. Am Terminal geht es mit: serviceops import <archiv>
en takeover.later Later: sign in, then Administration → Bringing a business over; upload the archive there and give the passphrase. At a terminal: serviceops import <archive>
de import_as.label Unter welchem Administrator?
en import_as.label As which administrator?
de import_as.what Eine Übernahme wird, wie jede Änderung, auf eine Person gebucht. Bei der ersten Installation ist das der erste Administrator: Er wird jetzt mit dieser Adresse angelegt, und mit ihr melden Sie sich danach an.
en import_as.what A takeover is recorded against a person, like every change. On a first installation that is the first administrator: the account is made now with this address, and you sign in with it afterwards.
de import_as.recommended Ihre Adresse von oben.
en import_as.recommended your address from above.
de import_as.proposal (Ihre Adresse von oben).
en import_as.proposal (your address from above).
de import_as.wrong Eine vertippte Adresse wird Ihr Anmeldename; ändern lässt sie sich unter Verwaltung → Personen.
en import_as.wrong A mistyped address becomes your sign-in name; it can be changed under Administration → People.
de import_as.invalid Das ist keine E-Mail-Adresse.
en import_as.invalid That is not an e-mail address.
de admin_name.label Ihr Name
en admin_name.label Your name
de admin_name.what Der Name, unter dem andere Sie in ServiceOps sehen.
en admin_name.what The name other people see you by in ServiceOps.
de admin_name.recommended Vor- und Nachname.
en admin_name.recommended first name and surname.
de admin_name.find Ihr eigener Name; er wird nicht vorgeschlagen.
en admin_name.find your own name; nothing is proposed.
de admin_name.wrong Ein Tippfehler lässt sich später im eigenen Profil ändern.
en admin_name.wrong A typo can be put right later in your own profile.
de admin_name.invalid Ein Name wird gebraucht.
en admin_name.invalid A name is needed.
de admin_password.label Passwort
en admin_password.label Password
de admin_password.what Das Passwort für dieses Konto: mindestens 12 Zeichen und nicht leicht zu erraten. Der Server prüft es und sagt, wenn es nicht reicht. Die Eingabe bleibt unsichtbar und wird nirgends gespeichert. Nach der ersten Anmeldung richten Sie einen zweiten Faktor ein, eine App auf dem Telefon.
en admin_password.what The password for this account: at least 12 characters and not easy to guess. The server judges it and says when it will not do. What you type stays invisible and is kept nowhere. After the first sign-in you set up a second factor, an app on your phone.
de admin_password.recommended ein langer Satz aus mehreren Wörtern, oder ein Passwort aus Ihrem Passwortmanager.
en admin_password.recommended a long sentence of several words, or one from your password manager.
de admin_password.find denken Sie sich eins aus; es wird nicht vorgeschlagen.
en admin_password.find make one up; nothing is proposed.
de admin_password.wrong Ein vergessenes Passwort setzt der Link "Passwort vergessen" auf der Anmeldeseite zurück, sobald Mails hinausgehen.
en admin_password.wrong A forgotten password is reset with "Forgotten password" on the sign-in page, once mail goes out.
de admin_password.again Passwort wiederholen
en admin_password.again Password again
de admin_password.mismatch Die beiden Eingaben sind verschieden. Bitte noch einmal.
en admin_password.mismatch The two do not match. Once more, please.
de admin_password.invalid Ein Passwort wird gebraucht.
en admin_password.invalid A password is needed.
de admin.created @EMAIL@ kann sich jetzt anmelden.
en admin.created @EMAIL@ can sign in now.
de admin.password_too_short Das Passwort ist zu kurz: mindestens 12 Zeichen.
en admin.password_too_short The password is too short: at least 12 characters.
de admin.password_too_common Dieses Passwort steht auf einer Liste häufiger Passwörter.
en admin.password_too_common This password is on a list of common passwords.
de admin.password_not_allowed Dieses Passwort ist hier nicht erlaubt.
en admin.password_not_allowed This password is not allowed here.
de admin.password_too_easy_to_guess Dieses Passwort ist zu leicht zu erraten.
en admin.password_too_easy_to_guess This password is too easy to guess.
de admin.failed Das Konto wurde nicht angelegt (@CODE@).
en admin.failed The account was not made (@CODE@).
de admin.given_up Ohne Administrator wird nichts übernommen. Später: den Link unten öffnen, den Administrator anlegen, dann Verwaltung → Datenübernahme.
en admin.given_up Without an administrator nothing is taken over. Later: open the link below, make the administrator, then Administration → Bringing a business over.
de archive.label Pfad zum Archiv
en archive.label Path to the archive
de archive.what Wo das Übergabearchiv auf diesem Server liegt, als ganzer Pfad. Es bleibt, wo es ist, und wird nicht verändert.
en archive.what Where the handover archive is on this machine, as a whole path. It stays where it is and is not changed.
de archive.recommended /root/ auf diesem Server.
en archive.recommended /root/ on this machine.
de archive.proposal (das neueste uebergabe-*.zip, das hier gefunden wurde).
en archive.proposal (the newest uebergabe-*.zip found here).
de archive.find dort, wohin Sie es kopiert haben, etwa /root/uebergabe-2026-10-02.zip. Leer lassen, um es später zu übernehmen.
en archive.find wherever you copied it to, such as /root/uebergabe-2026-10-02.zip. Leave it empty to take it over later.
de archive.wrong Eine Datei, die kein Übergabearchiv ist, lehnt die Übernahme ab, bevor sie etwas schreibt.
en archive.wrong A file that is no handover archive is refused before anything is written.
de archive.copy Liegt es noch auf Ihrem Rechner, kopieren Sie es von dort hierher, zum Beispiel: scp uebergabe-2026-10-02.zip root@@HOST@:/root/
en archive.copy If it is still on your own computer, copy it here from there, for example: scp uebergabe-2026-10-02.zip root@@HOST@:/root/
de archive.missing Unter @FILE@ liegt keine Datei.
en archive.missing There is no file at @FILE@.
de archive.unreadable Die Installation darf @FILE@ nicht lesen. Für alle lesbar machen (chmod a+r)?
en archive.unreadable The installation may not read @FILE@. Make it readable to all (chmod a+r)?
de passphrase.label Passphrase
en passphrase.label Passphrase
de passphrase.what Die Passphrase, die das alte System beim Export einmal angezeigt hat. Sie öffnet den versiegelten Umschlag mit den Passwörtern. Sie geht nur über die Standardeingabe an die Übernahme: nie in eine Befehlszeile, eine Datei oder ein Protokoll.
en passphrase.what The passphrase the old system showed once when it exported. It opens the sealed envelope of passwords. It reaches the import on standard input only: never on a command line, in a file or in a log.
de passphrase.recommended genau so eingeben, wie sie notiert ist, auch mit Leerzeichen am Anfang oder Ende.
en passphrase.recommended type it exactly as written down, spaces at either end included.
de passphrase.find dort, wo Sie sie beim Export notiert haben. Leer lassen, wenn es keine gibt: Dann bleibt der Umschlag zu, und jeder vergibt sich ein neues Passwort.
en passphrase.find wherever you wrote it down at the export. Leave it empty if there is none: the envelope then stays sealed and everybody sets a new password.
de passphrase.wrong Mit einer falschen Passphrase kommen alle Datensätze trotzdem an, nur der Umschlag bleibt zu. Das Installationsprogramm bietet dann an, das Archiv mit der richtigen noch einmal zu lesen.
en passphrase.wrong With a wrong passphrase every record arrives all the same and only the envelope stays sealed. The installer then offers to read the archive again with the right one.
de import.step Das Archiv wird gelesen
en import.step Reading the archive
de import.patience Bei vielen Fotos dauert das eine Weile. Darunter steht die Abrechnung der Übernahme, auf Englisch: was hinzukam, was aktualisiert, was übersprungen und was abgelehnt wurde, und wer sich mit seinem bisherigen Passwort anmelden kann.
en import.patience With many photographs this takes a while. Below is the import's reckoning: what was added, brought up to date, passed by and refused, and who can sign in with the password they already have.
de import.ok Die Übernahme ist gelungen: Die Datensätze sind da, und jede Zahl, die das alte System zeigte, stimmt hier.
en import.ok The takeover succeeded: the records are in, and every figure the old system showed matches here.
de import.refused Die Übernahme ist nicht gelungen: Das Archiv wurde ganz abgelehnt, und es wurde nichts geschrieben. Der Grund steht oben.
en import.refused The takeover did not succeed: the archive was refused whole and nothing was written. The reason is above.
de import.stopped Die Übernahme ist nur zum Teil gelungen: Das Lesen hielt bei einem Datensatz an, alles davor ist da. Ursache beheben und dasselbe Archiv noch einmal lesen: serviceops import <archiv>
en import.stopped The takeover succeeded only in part: the reading stopped at one record and everything before it is in. Fix the cause and read the same archive again: serviceops import <archive>
de import.differs Die Datensätze sind da, aber nicht jede Zahl stimmt mit dem alten System überein; die Tabelle oben nennt sie.
en import.differs The records are in, but not every figure matches the old system; the table above names them.
de import.failed Die Übernahme ist nicht gelungen. Die Ausgabe oben sagt, warum.
en import.failed The takeover did not succeed. The output above says why.
de import.wrong_passphrase Die Datensätze sind da, aber die Passphrase war falsch: Der Umschlag mit den Passwörtern ist zu.
en import.wrong_passphrase The records are in, but the passphrase was wrong: the envelope of passwords is sealed.
de import.again Mit der richtigen Passphrase noch einmal lesen?
en import.again Read it again with the right passphrase?
de import.safe Erneutes Lesen ist sicher: Was schon da ist, wird übersprungen oder aktualisiert, nie doppelt angelegt.
en import.safe Reading it again is safe: what is in already is passed by or brought up to date, never added twice.
de import.sealed_later Der Umschlag lässt sich auch später öffnen, unter Verwaltung → Datenübernahme.
en import.sealed_later The envelope can also be opened later, under Administration → Bringing a business over.

de result.backup_title BACKUP-SCHLÜSSEL - einmal angezeigt, nirgends gespeichert
en result.backup_title BACKUP KEY - shown once, written nowhere
de result.backup_why Ohne ihn ist jede Sicherung dieser Installation unlesbar. Bewahren Sie ihn dort auf, wo er diesen Server überlebt: in einem Passwortmanager, auf Papier in einem anderen Gebäude. Nicht auf diesem Server.
en result.backup_why Without it, every backup this installation makes is unreadable. Put it somewhere that survives this machine: a password manager, a piece of paper in a different building. Not on this server.
de result.commands Danach, auf diesem Server:
en result.commands Then, on this machine:
de result.doctor was nicht stimmt, wenn etwas nicht stimmt
en result.doctor what is wrong, if anything
de result.backup jetzt eine Sicherung anlegen und zeigen, dass der Schlüssel passt
en result.backup take one now, and prove the key works
de result.update auf eine neuere Version wechseln, mit einem Weg zurück
en result.update move to a newer version, with a way back
de result.setup_once Der Link gilt, bis das erste Konto existiert, danach nie wieder.
en result.setup_once The link works until the first account exists and then never again.
de result.restored Die Anhänge kamen mit der Hälfte daneben zurück. Neu eingerichtet werden zwei Dinge, weil sie mit dem Geheimnis der alten Installation versiegelt waren: das Mail-Passwort unter Einstellungen und jeder zweite Faktor; wer einen hatte, meldet sich mit einem Wiederherstellungscode an und richtet ihn neu ein. Neue Sicherungen sind für den angegebenen Backup-Schlüssel verschlossen, der weiterhin nirgends auf diesem Server liegt.
en result.restored The attachments came back from the half beside it. Two things are set up again, because they were sealed with the old installation's secret: the mail password under Settings, and every second factor; somebody who had one signs in with a recovery code and sets it up again. New backups are locked for the backup key you gave, which is still written nowhere on this machine.
de result.done Fertig: ServiceOps @VERSION@ läuft unter @ORIGIN@.
en result.done Done: ServiceOps @VERSION@ is running at @ORIGIN@.
de result.next_setup diesen Link einmal öffnen und den ersten Administrator anlegen: @LINK@
en result.next_setup open this link once and make the first administrator: @LINK@
de result.next_sign_in @ORIGIN@ öffnen und als @EMAIL@ anmelden.
en result.next_sign_in open @ORIGIN@ and sign in as @EMAIL@.
de result.next_restored @ORIGIN@ öffnen und mit einem Konto aus der Sicherung anmelden.
en result.next_restored open @ORIGIN@ and sign in with an account from the backup.
TEXTS
}

INSTALL_LANG=''

# t KEY [NAME VALUE]...: the text in the chosen language, @NAME@ filled in.
t() {
    _key="$1"; shift
    _text="$(texts | awk -v key="${INSTALL_LANG:-de} $_key" '!found && index($0, key " ") == 1 { print substr($0, length(key) + 2); found = 1 }')"
    while [ "$#" -ge 2 ]; do
        _text="$(fill "$_text" "@$1@" "$2")"
        shift 2
    done
    printf '%s' "$_text"
}

# fill TEXT MARKER VALUE: every MARKER in TEXT replaced by VALUE, literally.
fill() {
    _rest="$1"; _out=''
    while :; do
        case "$_rest" in
            *"$2"*) _out="$_out${_rest%%"$2"*}$3"; _rest="${_rest#*"$2"}" ;;
            *) break ;;
        esac
    done
    printf '%s' "$_out$_rest"
}

# ---------------------------------------------------------------- talking --

red=''; green=''; bold=''; dim=''; off=''
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    red="$(tput setaf 1)"; green="$(tput setaf 2)"; bold="$(tput bold)"; dim="$(tput dim)"; off="$(tput sgr0)"
fi

say()  { printf '%s\n' "$*"; }
step() { printf '\n%s==>%s %s\n' "$bold" "$off" "$*"; }
note() { printf '    %s%s%s\n' "$dim" "$*" "$off"; }
ok()   { printf '    %s✓%s %s\n' "$green" "$off" "$*"; }
die()  { printf '\n%s%s%s %s\n' "$red$bold" "$(t word.stopped)" "$off" "$*" >&2; exit 1; }

# A paragraph, wrapped and indented. To the terminal, so that a question
# asked inside $(...) still shows it.
para() { printf '%s\n' "$*" | fold -s -w 72 | sed 's/^/    /' > /dev/tty; }

# Reads an answer from the person even when this script arrived on a pipe,
# which is when stdin is the script itself rather than a keyboard.
ask() {
    _prompt="$1"; _fallback="${2:-}"
    if [ -n "$_fallback" ]; then
        printf '  %s [%s]: ' "$_prompt" "$_fallback" > /dev/tty
    else
        printf '  %s: ' "$_prompt" > /dev/tty
    fi
    IFS= read -r _answer < /dev/tty || _answer=''
    printf '%s' "${_answer:-$_fallback}"
}

confirm() {
    _answer="$(ask "$1 $(t word.yes_no)" '')"
    case "$_answer" in j|J|ja|Ja|JA|y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac
}

# The same, for a secret: nothing typed appears on the screen. `read -s` is
# bash and this is /bin/sh, so the echo is turned off around the read -
# before the prompt, so that nothing typed ahead of it shows either.
ask_hidden() {
    stty -echo < /dev/tty 2>/dev/null || true
    printf '  %s %s: ' "$1" "$(t word.hidden)" > /dev/tty
    IFS= read -r _answer < /dev/tty || _answer=''
    stty echo < /dev/tty 2>/dev/null || true
    printf '\n' > /dev/tty
    printf '%s' "$_answer"
}

# choose KEY DEFAULT: the options KEY.option1, KEY.option2 ... as a numbered
# list; prints the number chosen.
choose() {
    _count=0
    while [ -n "$(t "$1.option$((_count + 1))")" ]; do
        _count=$((_count + 1))
        printf '    %s) %s\n' "$_count" "$(t "$1.option$_count")" > /dev/tty
    done
    while :; do
        _choice="$(ask "$(t word.choice)" "$2")"
        case "$_choice" in
            ''|*[!0-9]*) ;;
            *) if [ "$_choice" -ge 1 ] && [ "$_choice" -le "$_count" ]; then printf '%s' "$_choice"; return 0; fi ;;
        esac
    done
}

# explain KEY [PROPOSAL [WHENCE]]: before a question is asked, what it is,
# what is recommended and why, the proposal Enter takes or where to find the
# answer, and what a wrong answer does.
explain() {
    printf '\n  %s%s%s\n' "$bold" "$(t "$1.label")" "$off" > /dev/tty
    para "$(t "$1.what")"
    para "$(t word.recommended) $(t "$1.recommended")"
    if [ -n "${2:-}" ]; then
        para "$(t word.proposal) $2 ${3:-$(t "$1.proposal")} $(t word.enter_takes)"
    elif [ -n "$(t "$1.find")" ]; then
        para "$(t word.find) $(t "$1.find")"
    else
        para "$(t word.proposal) $(t "$1.proposal") $(t word.enter_takes)"
    fi
    para "$(t word.wrong) $(t "$1.wrong")"
}

is_email() { printf '%s' "$1" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'; }

# --------------------------------------------------------------- options --

RESTORE='no'
FRESH='no'
BAD_OPTION=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --restore) RESTORE='yes' ;;
        --fresh) FRESH='yes' ;;
        --lang=de|--lang=en) INSTALL_LANG="${1#--lang=}" ;;
        --lang)
            case "${2:-}" in
                de|en) INSTALL_LANG="$2"; shift ;;
                *) BAD_OPTION="$1 ${2:-}" ;;
            esac ;;
        *) BAD_OPTION="${BAD_OPTION:-$1}" ;;
    esac
    shift
done

# German when the locale says German, English for any other, and asked once
# when the locale says nothing - C and POSIX are what a server says when
# nobody chose. Most who run this are German, so German is the default.
if [ -z "$INSTALL_LANG" ]; then
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
        de|de_*|de.*) INSTALL_LANG='de' ;;
        ''|C|C.*|POSIX) INSTALL_LANG='' ;;
        *) INSTALL_LANG='en' ;;
    esac
fi

[ -z "$BAD_OPTION" ] || { INSTALL_LANG="${INSTALL_LANG:-de}"; die "$(t option.unknown OPTION "$BAD_OPTION")"; }

if [ -z "$INSTALL_LANG" ]; then
    INSTALL_LANG='de'
    printf '\n    1) %s\n    2) %s\n' "$(t language.option1)" "$(t language.option2)" > /dev/tty
    [ "$(ask "$(t language.label)" 1)" = 2 ] && INSTALL_LANG='en'
fi

WORK="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK"
    docker rm -f serviceops-fetch >/dev/null 2>&1 || true
    # A secret being typed when this was interrupted would leave the
    # terminal not echoing.
    { stty echo < /dev/tty; } 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ------------------------------------------------------------- the ground --

step "$(t ground.step)"

[ "$(id -u)" -eq 0 ] || die "$(t ground.root)"

command -v curl >/dev/null 2>&1 || die "$(t ground.curl)"

# shellcheck source=/dev/null
. /etc/os-release 2>/dev/null || die "$(t ground.no_os_release)"
case "${ID:-}${ID_LIKE:-}" in
    *debian*|*ubuntu*) ;;
    *) note "$(t ground.not_debian SYSTEM "${PRETTY_NAME:-?}")"
       confirm "$(t ground.carry_on)" || die "$(t ground.nothing_changed)" ;;
esac

TOTAL_RAM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
FREE_DISK_GB="$(df -k / 2>/dev/null | awk 'NR==2 {print int($4/1048576)}')"
note "$(t ground.facts SYSTEM "${PRETTY_NAME:-?}" RAM "$TOTAL_RAM_MB" DISK "${FREE_DISK_GB:-?}")"

if [ -n "$FREE_DISK_GB" ] && [ "$FREE_DISK_GB" -lt 10 ]; then
    die "$(t ground.disk DISK "$FREE_DISK_GB")"
fi

# An installation already here is refused, unless --fresh was given and its
# domain is typed back. Asked here, before any other question; carried out
# only once the new release is open (see "the old installation" below).
OLD_PROJECT="${COMPOSE_PROJECT_NAME:-serviceops}"
if [ -e "$INSTALL_DIR/compose.yaml" ]; then
    [ "$FRESH" = yes ] || die "$(t ground.exists DIR "$INSTALL_DIR")"

    step "$(t fresh.step)"
    OLD_DOMAIN="$(sed -n 's/^SERVICEOPS_DOMAIN=//p' "$INSTALL_DIR/.env" 2>/dev/null | head -1)"
    OLD_PROJECT="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$INSTALL_DIR/.env" 2>/dev/null | head -1)"
    OLD_PROJECT="${OLD_PROJECT:-${COMPOSE_PROJECT_NAME:-serviceops}}"
    explain fresh
    para "$(t fresh.where DIR "$INSTALL_DIR")"
    if [ -n "$OLD_DOMAIN" ]; then
        TYPED="$(ask "$(t fresh.confirm NAME "$OLD_DOMAIN")" '')"
    else
        OLD_DOMAIN="$INSTALL_DIR"
        TYPED="$(ask "$(t fresh.confirm_dir NAME "$OLD_DOMAIN")" '')"
    fi
    [ "$(printf '%s' "$TYPED" | tr -d ' \t')" = "$OLD_DOMAIN" ] || die "$(t fresh.refused NAME "$OLD_DOMAIN")"
elif [ "$FRESH" = yes ]; then
    note "$(t fresh.nothing DIR "$INSTALL_DIR")"
    FRESH='no'
fi

# ------------------------------------------------------- the licence server --
#
# Asked once and written into .env. The installation registers with it by
# itself, with a key pair it makes and keeps, and asks it every day which
# modules it may run (ADR 111). Nothing about the business goes there. Its
# /health is asked now; whether it knows the key is only learnt by
# registering, which the installation does once it runs.

step "$(t licence_server.step)"

licence_server_answers() {
    curl -fsS --max-time 10 "$1/health" 2>/dev/null | grep -q '"ok"'
}

# Asks until the licence key has the shape of one. Sets SERVER_KEY.
ask_licence_key() {
    while :; do
        SERVER_KEY="$(ask "$(t licence_key.label)" '' | tr -d ' \t' | tr '[:lower:]' '[:upper:]')"
        case "$SERVER_KEY" in
            SOLK-????-????-????-????-????-????-????-????) return 0 ;;
        esac
        note "$(t licence_key.invalid)"
    done
}

# Asks until a licence server answers at the address typed, which may name a
# port of its own. Sets LICENCE_SERVER.
ask_licence_server() {
    while :; do
        LICENCE_SERVER="$(ask "$(t licence_server.label)" '' | tr -d ' \t')"
        LICENCE_SERVER="${LICENCE_SERVER%/}"
        if [ -z "$LICENCE_SERVER" ]; then
            note "$(t licence_server.needed)"
            continue
        fi
        case "$LICENCE_SERVER" in
            https://?*) ;;
            *) note "$(t licence_server.invalid)"; continue ;;
        esac
        if licence_server_answers "$LICENCE_SERVER"; then
            ok "$(t licence_server.answers)"
            return 0
        fi
        note "$(t licence_server.silent ADDRESS "$LICENCE_SERVER")"
        [ "$(choose licence_server_silent 1)" = 2 ] && die "$(t licence_server.stopped)"
    done
}

explain licence_server
ask_licence_server

SERVER_KEY=''
explain licence_key
ask_licence_key

# ------------------------------------------------------ what comes back --
#
# Asked before anything else is, so that a restore which cannot work stops
# here, before anything has been fetched or written.

if [ "$RESTORE" = yes ]; then
    step "$(t restore.step)"

    explain backup_file
    while :; do
        BACKUP_FILE="$(ask "$(t backup_file.label)" '')"
        [ -n "$BACKUP_FILE" ] || die "$(t backup_file.empty)"
        if [ ! -f "$BACKUP_FILE" ]; then
            note "$(t backup_file.missing FILE "$BACKUP_FILE")"
            continue
        fi
        case "$BACKUP_FILE" in
            *-files.backup)
                note "$(t backup_file.files_half ROWS "$(basename "$BACKUP_FILE" | sed 's/-files\.backup$/.backup/')")"
                continue ;;
        esac
        break
    done
    BACKUP_FILE="$(cd "$(dirname "$BACKUP_FILE")" && pwd)/$(basename "$BACKUP_FILE")"
    BACKUP_FILES_HALF="${BACKUP_FILE%.backup}-files.backup"
    if [ ! -f "$BACKUP_FILES_HALF" ]; then
        note "$(t backup_file.no_files_half FILES "$(basename "$BACKUP_FILES_HALF")")"
        confirm "$(t backup_file.rows_alone)" || die "$(t backup_file.rows_alone_no)"
    fi

    explain backup_key
    BACKUP_SECRET="$(ask_hidden "$(t backup_key.label)")"
    case "$BACKUP_SECRET" in
        *[!0-9a-fA-F]*|'') die "$(t backup_key.invalid)" ;;
    esac
    [ "${#BACKUP_SECRET}" -eq 64 ] || die "$(t backup_key.invalid)"
fi

# ------------------------------------------------------------- the asking --

step "$(t questions.step)"

# This machine's address as the internet sees it, and the ones it has
# itself: a domain that resolves to either is pointing here.
PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
LOCAL_IPS="$(hostname -I 2>/dev/null || true)"
[ -n "$PUBLIC_IP" ] || PUBLIC_IP="$(printf '%s' "$LOCAL_IPS" | awk '{print $1}')"

# The proposal: this machine's own full name, unless it is one nobody
# outside can look up, and otherwise what its address resolves back to.
DOMAIN_PROPOSAL=''
DOMAIN_WHENCE=''
NAME_HERE="$(hostname -f 2>/dev/null || true)"
case "$NAME_HERE" in
    localhost*|*.localdomain|*.local|*.lan|*.home|*.internal|*.localhost|*[!a-zA-Z0-9.-]*) ;;
    ?*.?*) DOMAIN_PROPOSAL="$NAME_HERE" ;;
esac
if [ -z "$DOMAIN_PROPOSAL" ] && [ -n "$PUBLIC_IP" ]; then
    NAME_HERE="$(getent hosts "$PUBLIC_IP" 2>/dev/null | awk '{print $2; exit}' || true)"
    NAME_HERE="${NAME_HERE%.}"
    if [ -n "$NAME_HERE" ]; then
        DOMAIN_PROPOSAL="$NAME_HERE"
        DOMAIN_WHENCE="$(t domain.from_reverse)"
    fi
fi

# points_here NAME: whether NAME resolves to this machine. Sets FOUND to
# the addresses it resolves to.
points_here() {
    FOUND="$(getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' || true)"
    FOUND="${FOUND% }"
    for _address in $FOUND; do
        for _mine in $PUBLIC_IP $LOCAL_IPS; do
            [ "$_address" = "$_mine" ] && return 0
        done
    done
    return 1
}

explain domain "$DOMAIN_PROPOSAL" "$DOMAIN_WHENCE"
[ -z "$PUBLIC_IP" ] || para "$(t domain.this_server IP "$PUBLIC_IP")"
while :; do
    DOMAIN="$(ask "$(t domain.label)" "$DOMAIN_PROPOSAL" | tr -d ' \t' | sed 's|^[hH][tT][tT][pP][sS]*://||; s|/.*$||' | tr '[:upper:]' '[:lower:]')"
    case "$DOMAIN" in
        ''|ip) DOMAIN=''; break ;;
    esac
    if ! printf '%s' "$DOMAIN" | grep -Eq '^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9]$'; then
        note "$(t domain.invalid)"
        continue
    fi
    if points_here "$DOMAIN"; then
        ok "$(t domain.here DOMAIN "$DOMAIN" IP "$FOUND")"
        break
    fi
    if [ -z "$FOUND" ]; then
        note "$(t domain.unresolved DOMAIN "$DOMAIN")"
    else
        note "$(t domain.elsewhere DOMAIN "$DOMAIN" FOUND "$FOUND" IP "${PUBLIC_IP:-?}")"
    fi
    para "$(t domain.certificate)"
    [ "$(choose domain_problem 1)" = 2 ] && break
done

TLS_DIRECTIVE=''
ACME_EMAIL=''
if [ -z "$DOMAIN" ]; then
    [ -n "$PUBLIC_IP" ] || die "$(t domain.no_ip)"
    DOMAIN="$PUBLIC_IP"
    TLS_DIRECTIVE='tls internal'
    note "$(t domain.ip_mode IP "$DOMAIN")"
fi

# The accounts come back with a restore. The address is still wanted, for
# the certificate authority and as the address mail is sent from.
EMAIL_QUESTION='admin_email'
[ "$RESTORE" = yes ] && EMAIL_QUESTION='restore_email'
if [ "$EMAIL_QUESTION" = restore_email ]; then explain restore_email; else explain admin_email; fi
while :; do
    ADMIN_EMAIL="$(ask "$(t "$EMAIL_QUESTION.label")" '' | tr -d ' \t')"
    is_email "$ADMIN_EMAIL" && break
    note "$(t admin_email.invalid)"
done

if [ -z "$TLS_DIRECTIVE" ]; then
    ACME_EMAIL="email $ADMIN_EMAIL"
fi

# urlencode TEXT: TEXT with everything but letters, digits and -._~ as %XX,
# for the user and the password inside MAILER_DSN. Read through a pipe, so
# a password is on no command line.
urlencode() {
    printf '%s' "$1" | od -An -tx1 -v | tr ' ' '\n' | sed '/^$/d' | while IFS= read -r _hex; do
        case "$_hex" in
            3[0-9]|4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a]|2d|2e|5f|7e)
                # shellcheck disable=SC2059 # the octal escape is the point
                printf "\\$(printf '%03o' "0x$_hex")" ;;
            *) printf '%%%s' "$(printf '%s' "$_hex" | tr '[:lower:]' '[:upper:]')" ;;
        esac
    done
}

# Signs in to the SMTP server as the installation would, and says nothing.
# curl gets the credentials as a config on standard input, never as an
# argument. Sets SMTP_CODE to curl's exit code: 0, or 8 when the server
# answers the closing HELP oddly, mean it took the sign-in.
smtp_check() {
    _scheme='smtp'
    [ "$SMTP_PORT" = 465 ] && _scheme='smtps'
    SMTP_CODE=0
    printf 'user = "%s"\n' "$(printf '%s' "$SMTP_USER:$SMTP_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
        | curl -sS --max-time 20 --ssl -K - "$_scheme://$SMTP_HOST:$SMTP_PORT" >/dev/null 2>&1 || SMTP_CODE=$?
}

# Asks for the SMTP details and checks them. Sets MAILER_DSN, MAIL_FROM and
# MAIL_SUMMARY, or leaves mail for later.
ask_for_mail() {
    _explained=''
    while :; do
        [ -n "$_explained" ] || explain smtp_host
        SMTP_HOST="$(ask "$(t smtp_host.label)" '' | tr -d ' \t')"
        [ -n "$SMTP_HOST" ] || return 0
        [ -n "$_explained" ] || explain smtp_port 587
        while :; do
            SMTP_PORT="$(ask "$(t smtp_port.label)" 587 | tr -d ' \t')"
            case "$SMTP_PORT" in ''|*[!0-9]*) note "$(t smtp_port.invalid)" ;; *) break ;; esac
        done
        [ -n "$_explained" ] || explain smtp_user "$ADMIN_EMAIL"
        SMTP_USER="$(ask "$(t smtp_user.label)" "$ADMIN_EMAIL" | tr -d ' \t')"
        [ -n "$_explained" ] || explain smtp_password
        SMTP_PASSWORD="$(ask_hidden "$(t smtp_password.label)")"
        _from="$ADMIN_EMAIL"
        is_email "$SMTP_USER" && _from="$SMTP_USER"
        [ -n "$_explained" ] || explain mail_from "$_from"
        while :; do
            MAIL_FROM="$(ask "$(t mail_from.label)" "$_from" | tr -d ' \t')"
            is_email "$MAIL_FROM" && break
            note "$(t mail_from.invalid)"
        done
        _explained='yes'

        note "$(t smtp.checking HOST "$SMTP_HOST" PORT "$SMTP_PORT")"
        smtp_check
        _keep='no'
        case "$SMTP_CODE" in
            0|8) ok "$(t smtp.ok)"; _keep='yes' ;;
            67) note "$(t smtp.login)" ;;
            6) note "$(t smtp.unknown_host HOST "$SMTP_HOST")" ;;
            7|28) note "$(t smtp.no_connection HOST "$SMTP_HOST" PORT "$SMTP_PORT")" ;;
            35|58|59|60|64|66|77|83|90|91) note "$(t smtp.tls HOST "$SMTP_HOST" PORT "$SMTP_PORT")" ;;
            *) note "$(t smtp.other CODE "$SMTP_CODE")" ;;
        esac
        if [ "$_keep" = no ]; then
            case "$(choose smtp_problem 1)" in
                1) continue ;;
                3) MAIL_FROM=''; SMTP_PASSWORD=''; return 0 ;;
            esac
        fi
        MAILER_DSN="smtp://$(urlencode "$SMTP_USER"):$(urlencode "$SMTP_PASSWORD")@$SMTP_HOST:$SMTP_PORT"
        SMTP_PASSWORD=''
        MAIL_SUMMARY="$(t summary.mail HOST "$SMTP_HOST" PORT "$SMTP_PORT" USER "$SMTP_USER" FROM "$MAIL_FROM")"
        return 0
    done
}

MAILER_DSN='null://null'
MAIL_FROM=''
MAIL_SUMMARY="$(t summary.mail_later)"
explain mail
if [ "$(choose mail 2)" = 1 ]; then
    ask_for_mail
fi

# -------------------------------------------------------- what will happen --

NEEDS_DOCKER='no'
command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 || NEEDS_DOCKER='yes'

NEEDS_AGE='no'
command -v age >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1 || NEEDS_AGE='yes'

NEEDS_SWAP='no'
if [ "$TOTAL_RAM_MB" -lt 3000 ] && [ "$(swapon --show --noheadings 2>/dev/null | wc -l)" -eq 0 ]; then
    NEEDS_SWAP='yes'
fi

# Ports 80 and 443 held by the installation --fresh is about to delete are
# not in anybody's way.
ours_on_the_ports() {
    [ "$FRESH" = yes ] && [ "$NEEDS_DOCKER" = no ] \
        && [ -n "$(docker ps -q --filter "label=com.docker.compose.project=$OLD_PROJECT" --filter publish=443 2>/dev/null || true)" ]
}

PROXY_PROFILE='caddy'
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq ':(80|443)$' && ! ours_on_the_ports; then
    explain proxy
    if [ "$(choose proxy 2)" = 1 ]; then
        PROXY_PROFILE=''
    else
        die "$(t proxy.stop)"
    fi
fi

step "$(t summary.step)"
para "$(t summary.nothing_yet)"
say ''
if [ -n "$TLS_DIRECTIVE" ]; then
    note "$(t summary.domain_ip DOMAIN "$DOMAIN")"
else
    note "$(t summary.domain DOMAIN "$DOMAIN")"
fi
note "$(t summary.email EMAIL "$ADMIN_EMAIL")"
note "$(t summary.licence ADDRESS "$LICENCE_SERVER" KEY "$SERVER_KEY")"
note "$MAIL_SUMMARY"
say ''
say "  $(t summary.do)"
[ "$FRESH" = yes ] && say "  - $(t summary.fresh DIR "$INSTALL_DIR")"
[ "$NEEDS_DOCKER" = yes ] && say "  - $(t summary.docker)"
[ "$NEEDS_AGE" = yes ] && say "  - $(t summary.age)"
say "  - $(t summary.fetch RELEASE "$RELEASE_REPOSITORY:$RELEASE_TAG")"
say "  - $(t summary.write DIR "$INSTALL_DIR")"
[ "$RESTORE" = yes ] && say "  - $(t summary.restore FILE "$BACKUP_FILE")"
[ "$PROXY_PROFILE" = caddy ] && say "  - $(t summary.https DOMAIN "$DOMAIN")"
say "  - $(t summary.register)"
say "  - $(t summary.updates)"
say "  - $(t summary.firewall)"
[ "$NEEDS_SWAP" = yes ] && say "  - $(t summary.swap RAM "$TOTAL_RAM_MB")"
[ "$RESTORE" = yes ] || say "  - $(t summary.takeover)"
say ''

confirm "$(t summary.go)" || die "$(t summary.no)"

# ------------------------------------------------------------- doing it --

if [ "$NEEDS_DOCKER" = yes ]; then
    step "$(t docker.step)"
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi

if [ "$NEEDS_AGE" = yes ]; then
    step "$(t tools.step)"
    command -v apt-get >/dev/null 2>&1 || die "$(t tools.no_apt)"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq age openssl >/dev/null
fi

if [ "$NEEDS_SWAP" = yes ]; then
    step "$(t swap.step)"
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
fi

# ============================================ the release, opened by the lease
#
# Everything from here to "the application" is how the release reaches this
# machine and opens (ADR 126). The installer registers with the licence
# server with a key pair it makes here, fetches a lease, and takes from it
# the key of the newest version the licence covers, or of SERVICEOPS_RELEASE
# when that names one. Then it pulls that version and opens it. The
# application takes the registration over once it is laid down, so the
# server sees one installation.
#
# Every request is signed as the server's docs/api.md says: Ed25519 over
# SOLAPI1, the method, the path, the time, a nonce and the body's SHA-256,
# made with openssl. The licence key and the version key go into files only
# root can read and are never on a command line.
#
# The same steps, as the update makes them, are in "serviceops update"; that
# one asks the application for the key, because by then it holds the lease.

umask 077

b64url() { base64 | tr '+/' '-_' | tr -d '=\n'; }

from_b64url() {
    _text="$(printf '%s' "$1" | tr '_-' '/+')"
    while [ $(( ${#_text} % 4 )) -ne 0 ]; do _text="$_text="; done
    printf '%s' "$_text" | base64 -d 2>/dev/null
}

# licence_post PATH BODY-FILE [INSTALLATION]: the signed request. The answer
# lands in $WORK/answer; prints the HTTP status, 000 when nothing answered.
licence_post() {
    _stamp="$(date +%s)"
    _nonce="$(head -c 16 /dev/urandom | b64url)"
    _hash="$(sha256sum "$2" | cut -d ' ' -f 1)"
    printf 'SOLAPI1\nPOST\n%s\n%s\n%s\n%s' "$1" "$_stamp" "$_nonce" "$_hash" > "$WORK/message"
    openssl pkeyutl -sign -inkey "$WORK/installation.pem" -rawin -in "$WORK/message" -out "$WORK/signature" 2>/dev/null || return 1
    {
        printf 'Content-Type: application/json\n'
        printf 'X-SO-Timestamp: %s\n' "$_stamp"
        printf 'X-SO-Nonce: %s\n' "$_nonce"
        printf 'X-SO-Signature: %s\n' "$(b64url < "$WORK/signature")"
        [ -z "${3:-}" ] || printf 'X-SO-Installation: %s\n' "$3"
    } > "$WORK/headers"
    curl -sS -o "$WORK/answer" -w '%{http_code}' --max-time 20 -X POST \
        -H @"$WORK/headers" --data-binary @"$2" "$LICENCE_SERVER$1" 2>/dev/null || printf '000'
}

answer_field() { sed -n "s/.*\"$1\": *\"\\([^\"]*\\)\".*/\\1/p" "$WORK/answer" | head -1; }

# The server's code, worded where the table has words for it; the process
# stops here, before anything was fetched or written.
licence_refused() {
    case "$1" in
        licence.unknown) _said=licence.key_unknown ;;
        licence.revoked) _said=licence.revoked ;;
        installation.ended) _said=licence.installation_ended ;;
        installation.key_taken) _said=licence.key_taken ;;
        timestamp.stale) _said=licence.clock_off ;;
        rate.limited) _said=licence.rate_limited ;;
        000) _said=licence.unreachable ;;
        5??|server.*) _said=licence.server_error ;;
        *) die "$(t licence.other CODE "$1") $(t release.no_answer CODE "$1")" ;;
    esac
    die "$(t "$_said") $(t release.no_answer CODE "$1")"
}

INSTALLATION_ID=''
step "$(t release.asking)"

openssl genpkey -algorithm ed25519 -out "$WORK/installation.pem" 2>/dev/null \
    || die "$(t licence.other CODE openssl)"
PUBLIC_KEY="$(openssl pkey -in "$WORK/installation.pem" -pubout -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\n')"

while :; do
    printf '{"licence_key":"%s","public_key":"%s","label":"%s"}' \
        "$SERVER_KEY" "$PUBLIC_KEY" "$(hostname -f 2>/dev/null | tr -cd 'A-Za-z0-9.-')" > "$WORK/body"
    STATUS="$(licence_post /api/installations/register "$WORK/body")"
    case "$STATUS" in
        200|201) INSTALLATION_ID="$(answer_field installation)"; break ;;
    esac
    CODE="$(answer_field code)"
    if [ "$CODE" = licence.unknown ]; then
        para "$(t licence.key_unknown)"
        confirm "$(t licence.retype)" || die "$(t licence.key_unknown) $(t summary.no)"
        ask_licence_key
        continue
    fi
    # A licence server that moved names where it went (ADR 149). That answer
    # is signed by nobody, so it is shown and the person types the address;
    # nothing switches by itself.
    if [ "$CODE" = server.moved ]; then
        para "$(t licence.moved ADDRESS "$(answer_field moved_to | tr -cd 'A-Za-z0-9.:/_-')")"
        para "$(t licence.moved_retype)"
        ask_licence_server
        continue
    fi
    licence_refused "${CODE:-$STATUS}"
done
rm -f "$WORK/body"
[ -n "$INSTALLATION_ID" ] || licence_refused "$STATUS"
ok "$(t release.registered)"

printf '{"version":"","modules":[]}' > "$WORK/body"
STATUS="$(licence_post /api/lease "$WORK/body" "$INSTALLATION_ID")"
if [ "$STATUS" != 200 ]; then
    CODE="$(answer_field code)"
    licence_refused "${CODE:-$STATUS}"
fi
LEASE="$(answer_field lease)"
LEASE_PAYLOAD="$(from_b64url "$(printf '%s' "$LEASE" | cut -d . -f 2)")"

if [ "$RELEASE_TAG" = latest ]; then
    RELEASE_VERSION="$(printf '%s' "$LEASE_PAYLOAD" | sed -n 's/.*"newest_version":"\([0-9.]*\)".*/\1/p')"
    [ -n "$RELEASE_VERSION" ] || die "$(t release.none_covered)"
else
    RELEASE_VERSION="$RELEASE_TAG"
fi
case "$RELEASE_VERSION" in
    *[!0-9.]*|'') die "$(t release.not_covered VERSION "$RELEASE_VERSION")" ;;
esac
VERSION_PATTERN="$(printf '%s' "$RELEASE_VERSION" | sed 's/\./\\./g')"
printf '%s' "$LEASE_PAYLOAD" | sed -n "s/.*\"$VERSION_PATTERN\":\"\(AGE-SECRET-KEY-1[0-9A-Z]*\)\".*/\1/p" > "$WORK/version.key"
LEASE='' LEASE_PAYLOAD=''
[ -s "$WORK/version.key" ] || die "$(t release.not_covered VERSION "$RELEASE_VERSION")"
ok "$(t release.newest VERSION "$RELEASE_VERSION")"
umask 022

step "$(t release.fetching RELEASE "$RELEASE_REPOSITORY:$RELEASE_VERSION")"

docker pull -q "$RELEASE_REPOSITORY:$RELEASE_VERSION" >/dev/null \
    || die "$(t release.no_pull RELEASE "$RELEASE_REPOSITORY:$RELEASE_VERSION")"

# The release image is nothing but a manifest and an encrypted bundle, so it
# is not run; the two files are copied out of it.
docker rm -f serviceops-fetch >/dev/null 2>&1 || true
docker create --name serviceops-fetch "$RELEASE_REPOSITORY:$RELEASE_VERSION" true >/dev/null
docker cp serviceops-fetch:/manifest.json "$WORK/manifest.json"
docker cp serviceops-fetch:/core.age "$WORK/core.age"
docker rm serviceops-fetch >/dev/null
RELEASE_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "$RELEASE_REPOSITORY:$RELEASE_VERSION" 2>/dev/null || echo "$RELEASE_REPOSITORY:$RELEASE_VERSION")"

FOUND_VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$WORK/manifest.json" | head -1)"
[ "$FOUND_VERSION" = "$RELEASE_VERSION" ] \
    || die "$(t release.wrong_version RELEASE "$RELEASE_REPOSITORY:$RELEASE_VERSION" FOUND "${FOUND_VERSION:-?}" VERSION "$RELEASE_VERSION")"

step "$(t release.opening VERSION "$RELEASE_VERSION")"

mkdir -p "$WORK/bundle"
if ! age -d -i "$WORK/version.key" "$WORK/core.age" 2>/dev/null | tar -xz -C "$WORK/bundle"; then
    die "$(t release.does_not_open VERSION "$RELEASE_VERSION")"
fi
rm -f "$WORK/version.key"
[ -f "$WORK/bundle/Dockerfile" ] || die "$(t release.not_ours)"

# ============================================ end of the release, opened by the lease

step "$(t assemble.step)"

# The base image is pulled on its own first, so that the one thing likely to
# go wrong here says so plainly: the package is still private, or ghcr.io
# cannot be reached.
BASE_IMAGE="$(sed -n 's/^FROM //p' "$WORK/bundle/Dockerfile" | head -1)"
docker pull -q "$BASE_IMAGE" >/dev/null \
    || die "$(t assemble.no_base IMAGE "$BASE_IMAGE")"

# The bundle's own Dockerfile: our files on a public base image, pinned by
# digest. It copies and nothing else, which is why this takes seconds and
# needs no toolchain.
docker build -q -t "serviceops:$RELEASE_VERSION" "$WORK/bundle" >/dev/null \
    || die "$(t assemble.failed)"
IMAGE="serviceops:$RELEASE_VERSION"

# ------------------------------------------------- the old installation --
#
# Only with --fresh, and only now: the new release is open and assembled,
# so a key that does not open it, or a registry that cannot be reached,
# has stopped this with the old installation still standing. Compose takes
# down what it knows, with its named volumes; whatever carries the
# project's label and survived that goes after it; then the directory,
# with the database, the files and the backups in it.

if [ "$FRESH" = yes ]; then
    step "$(t fresh.removing)"
    ( cd "$INSTALL_DIR" && docker compose --profile tools --profile caddy down --volumes --remove-orphans ) || true
    OLD_CONTAINERS="$(docker ps -aq --filter "label=com.docker.compose.project=$OLD_PROJECT" 2>/dev/null || true)"
    # shellcheck disable=SC2086 # one identifier per word
    [ -z "$OLD_CONTAINERS" ] || docker rm -f $OLD_CONTAINERS >/dev/null || true
    OLD_VOLUMES="$(docker volume ls -q --filter "label=com.docker.compose.project=$OLD_PROJECT" 2>/dev/null || true)"
    # shellcheck disable=SC2086 # one name per word
    [ -z "$OLD_VOLUMES" ] || docker volume rm $OLD_VOLUMES >/dev/null || true
    case "$INSTALL_DIR" in
        /?*) rm -rf "$INSTALL_DIR" ;;
        *) die "$INSTALL_DIR" ;;
    esac
    rm -f /usr/local/bin/serviceops
    ok "$(t fresh.removed DIR "$INSTALL_DIR")"
fi

# ----------------------------------------------------- the installation --

step "$(t lay.step)"

mkdir -p "$INSTALL_DIR"/data/postgres "$INSTALL_DIR"/data/files \
         "$INSTALL_DIR"/data/backups "$INSTALL_DIR"/data/caddy "$INSTALL_DIR"/data/caddy-config
chmod 700 "$INSTALL_DIR"

# The application runs as www-data, uid 33 in the image, and writes the file
# store and the backups. Made by root here, neither would take a single
# attachment. PostgreSQL and Caddy look after their own directories.
chown 33:33 "$INSTALL_DIR"/data/files "$INSTALL_DIR"/data/backups

for file in compose.yaml compose.traefik.yaml Caddyfile serviceops; do
    cp "$WORK/bundle/deploy/$file" "$INSTALL_DIR/$file"
done
chmod +x "$INSTALL_DIR/serviceops"
ln -sf "$INSTALL_DIR/serviceops" /usr/local/bin/serviceops

cp "$WORK/manifest.json" "$INSTALL_DIR/manifest.json"
printf 'core\n' > "$INSTALL_DIR/opened"

# Every secret is made here. The operator invents nothing, which is the whole
# difference between this and a page of instructions.
random() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

APP_SECRET="$(random 32)"
POSTGRES_PASSWORD="$(random 24)"
SETUP_TOKEN="$(random 24)"

if [ "$RESTORE" = yes ]; then
    step "$(t backup_key.taking)"

    # The public half is worked out from the secret one, so this installation
    # locks its backups for the key the operator already holds. The secret
    # half is not written here, for the reason it never is: a machine
    # somebody has broken into must not be able to read its own backups. It
    # reaches the container through the environment, not the command line.
    BACKUP_PUBLIC="$(SERVICEOPS_BACKUP_SECRET="$BACKUP_SECRET" docker run --rm \
        -e SERVICEOPS_BACKUP_SECRET --entrypoint php "$IMAGE" \
        -r 'echo sodium_bin2hex(sodium_crypto_box_publickey_from_secretkey(sodium_hex2bin(getenv("SERVICEOPS_BACKUP_SECRET"))));')" \
        || die "$(t backup_key.taking_failed)"
else
    step "$(t backup_key.making)"

    # X25519, through libsodium, which is in the image already. A backup holds
    # every customer a business has; it must not be readable by whoever ends up
    # with the bucket.
    #
    # **Past the entrypoint, not through it.** The entrypoint insists on an
    # APP_SECRET and a DATABASE_URL before it runs anything, which is right for
    # starting the application and wrong here: neither exists yet, and making a
    # keypair is not starting anything.
    BACKUP_KEYS="$(docker run --rm --entrypoint php "$IMAGE" \
        -r '$k=sodium_crypto_box_keypair();
            echo sodium_bin2hex(sodium_crypto_box_publickey($k)), " ",
                 sodium_bin2hex(sodium_crypto_box_secretkey($k));')" \
        || die "$(t backup_key.making_failed)"

    BACKUP_PUBLIC="${BACKUP_KEYS% *}"
    BACKUP_SECRET="${BACKUP_KEYS#* }"
fi

ORIGIN="https://$DOMAIN"

umask 077
cat > "$INSTALL_DIR/.env" <<ENV
# Written by install.sh. Everything in here is this installation's own.
# Keep it: losing it loses the database password and the backup key.
SERVICEOPS_IMAGE=$IMAGE
SERVICEOPS_RELEASE_REPOSITORY=$RELEASE_REPOSITORY
SERVICEOPS_RELEASE_DIGEST=$RELEASE_DIGEST
SERVICEOPS_DOMAIN=$DOMAIN
SERVICEOPS_ORIGIN=$ORIGIN
SERVICEOPS_TLS=$TLS_DIRECTIVE
SERVICEOPS_ACME_EMAIL=$ACME_EMAIL
COMPOSE_PROFILES=$PROXY_PROFILE

APP_SECRET=$APP_SECRET
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Opens /setup for the first administrator and shuts for good on the first
# account. See docs/adr/0029-the-first-way-in-needs-a-token-and-closes-for-good.md
SERVICEOPS_SETUP_TOKEN=$SETUP_TOKEN

MAILER_DSN=$MAILER_DSN
MAIL_FROM=$MAIL_FROM

# The maker's licence server and the key it issued (ADR 111). The only place
# this installation talks to outside itself. Empty means it talks to nobody.
SERVICEOPS_LICENCE_SERVER=$LICENCE_SERVER
SERVICEOPS_LICENCE_KEY=$SERVER_KEY

# The public half of the backup key. The installation can encrypt a backup
# with this and cannot read one back: that needs the secret half, which is
# printed once by this script and written nowhere.
SERVICEOPS_BACKUP_KEY=$BACKUP_PUBLIC
SERVICEOPS_BACKUP_KEEP_DAYS=30

# Where a copy goes, off this machine. Empty means backups stay here, which
# is no protection at all against this machine being gone. Fill these in and
# run "serviceops backup" to try it.
SERVICEOPS_BACKUP_S3_ENDPOINT=
SERVICEOPS_BACKUP_S3_REGION=
SERVICEOPS_BACKUP_S3_BUCKET=
SERVICEOPS_BACKUP_S3_KEY=
SERVICEOPS_BACKUP_S3_SECRET=
ENV
chmod 600 "$INSTALL_DIR/.env"
umask 022

step "$(t start.step)"

cd "$INSTALL_DIR"
docker compose --profile tools run --rm migrate

# Before anything else starts, because a backup goes back only into an
# installation that holds nothing, and a worker or a first administrator
# would already be something.
if [ "$RESTORE" = yes ]; then
    step "$(t start.restoring FILE "$BACKUP_FILE")"
    # The word restore is typed for it: the operator said yes to exactly
    # this above, into an installation this script made a minute ago.
    printf 'restore\n' | SERVICEOPS_BACKUP_SECRET="$BACKUP_SECRET" "$INSTALL_DIR/serviceops" restore "$BACKUP_FILE" \
        || die "$(t start.restore_failed DIR "$INSTALL_DIR" FILE "$BACKUP_FILE")"
fi

# The registration the installer made, taken over before anything starts,
# so the application signs with the same key and the server sees one
# installation (ADR 126). A restore brought the old one back with the rows;
# this replaces it. The seed reaches the console on standard input only.
openssl pkey -in "$WORK/installation.pem" -outform DER 2>/dev/null | tail -c 32 | base64 \
    | docker compose --profile tools run --rm -T console serviceops:licence:adopt "$INSTALLATION_ID" >/dev/null 2>&1 \
    || note "$(t start.adopt_failed)"
rm -f "$WORK/installation.pem"

docker compose up -d --wait

step "$(t licence.step)"

# Registers and fetches the first lease now, so a wrong address or key is
# said here rather than on the Extensions page tomorrow. Not fatal: the
# installation asks again every day, and "Check now" asks at once. A key
# the server does not know can be typed again on the spot.
while :; do
    if LICENCE_SAID="$(docker compose --profile tools run --rm -T console serviceops:licence:check 2>&1)"; then
        ok "$(t licence.ok)"
        note "$LICENCE_SAID"
        break
    fi
    note "$LICENCE_SAID"
    LICENCE_CODE="$(printf '%s' "$LICENCE_SAID" | grep -o 'licence\.[a-z_]*' | tail -1 || true)"
    case "$LICENCE_CODE" in
        licence.key_unknown)
            para "$(t licence.key_unknown)"
            if confirm "$(t licence.retype)"; then
                ask_licence_key
                sed "s|^SERVICEOPS_LICENCE_KEY=.*|SERVICEOPS_LICENCE_KEY=$SERVER_KEY|" .env > "$WORK/env"
                cat "$WORK/env" > .env
                rm -f "$WORK/env"
                docker compose up -d --wait >/dev/null
                continue
            fi ;;
        licence.revoked|licence.installation_ended|licence.key_taken|licence.clock_off|licence.unreachable|licence.server_error|licence.rate_limited)
            para "$(t "$LICENCE_CODE")" ;;
        *) para "$(t licence.other CODE "${LICENCE_CODE:-?}")" ;;
    esac
    para "$(t licence.later)"
    break
done

# ------------------------------------------------------ the update button --
#
# The units that let "Jetzt aktualisieren" in the tool, and its nightly
# switch, reach this machine (ADR 125). The installation's own command lays
# them down, so that every update lays down the next version's the same way.

SERVICEOPS_DIR="$INSTALL_DIR" "$INSTALL_DIR/serviceops" install-units \
    || note "$(t units.failed)"

step "$(t harden.step)"

if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades ufw >/dev/null
    dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true

    SSH_PORT="$(awk '/^Port /{print $2}' /etc/ssh/sshd_config 2>/dev/null | tail -1)"
    ufw allow "${SSH_PORT:-22}"/tcp >/dev/null
    ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
    ufw allow 443/udp >/dev/null
    ufw --force enable >/dev/null
    note "$(t harden.firewall SSH "${SSH_PORT:-22}")"
fi

# ----------------------------------------------------------- the takeover --
#
# Last, on a first installation, with the stack healthy: the records of the
# system this one replaces, read in from a handover archive (ADR 39). The
# import is written against a person, so the first administrator is made
# here, with the address given above. The reading itself is
# `serviceops import`, the same command an operator runs later; the
# passphrase reaches it on standard input and goes no other way.

ADMIN_MADE=''

# Asks for the first administrator's name and password and makes the
# account. Sets ADMIN_MADE, or leaves it empty after five refusals.
make_the_first_administrator() {
    explain admin_name
    while :; do
        ADMIN_NAME="$(ask "$(t admin_name.label)" '')"
        [ -n "$(printf '%s' "$ADMIN_NAME" | tr -d ' \t')" ] && break
        note "$(t admin_name.invalid)"
    done
    explain admin_password
    _goes=0
    while [ "$_goes" -lt 5 ]; do
        _password="$(ask_hidden "$(t admin_password.label)")"
        if [ -z "$_password" ]; then note "$(t admin_password.invalid)"; _goes=$((_goes + 1)); continue; fi
        if [ "$_password" != "$(ask_hidden "$(t admin_password.again)")" ]; then
            note "$(t admin_password.mismatch)"
            continue
        fi
        # Through the environment of this one run, which is how the command
        # takes a password from a script: never an argument.
        if _said="$(SERVICEOPS_NEW_PASSWORD="$_password" docker compose --profile tools run --rm -T \
                -e SERVICEOPS_NEW_PASSWORD console serviceops:user:create \
                --email="$IMPORT_AS" --name="$ADMIN_NAME" --administrator --no-interaction 2>&1)"; then
            _password=''
            ok "$(t admin.created EMAIL "$IMPORT_AS")"
            ADMIN_MADE="$IMPORT_AS"
            return 0
        fi
        _password=''
        _code="$(printf '%s' "$_said" | grep -o 'user\.[a-z_]*' | tail -1 || true)"
        case "$_code" in
            user.password_too_short|user.password_too_common|user.password_not_allowed|user.password_too_easy_to_guess)
                note "$(t "admin.${_code#user.}")" ;;
            *) note "$_said"; note "$(t admin.failed CODE "${_code:-?}")" ;;
        esac
        _goes=$((_goes + 1))
    done
    para "$(t admin.given_up)"
}

# The newest uebergabe-*.zip where somebody is likely to have put one.
newest_archive() {
    _home="$(getent passwd "${SUDO_USER:-root}" 2>/dev/null | cut -d: -f6 || true)"
    # shellcheck disable=SC2012 # names we made up; ls -t is the point
    ls -t "$STARTED_IN"/uebergabe-*.zip /root/uebergabe-*.zip "${HOME:-/root}"/uebergabe-*.zip \
        "${_home:-/root}"/uebergabe-*.zip 2>/dev/null | head -1 || true
}

take_the_data_over() {
    explain import_as "$ADMIN_EMAIL"
    while :; do
        IMPORT_AS="$(ask "$(t import_as.label)" "$ADMIN_EMAIL" | tr -d ' \t')"
        is_email "$IMPORT_AS" && break
        note "$(t import_as.invalid)"
    done
    make_the_first_administrator
    if [ -z "$ADMIN_MADE" ]; then
        return 0
    fi

    _proposal="$(newest_archive)"
    explain archive "$_proposal"
    para "$(t archive.copy HOST "$DOMAIN")"
    while :; do
        ARCHIVE="$(ask "$(t archive.label)" "$_proposal")"
        if [ -z "$ARCHIVE" ]; then
            para "$(t takeover.later)"
            return 0
        fi
        case "$ARCHIVE" in /*) ;; *) ARCHIVE="$STARTED_IN/$ARCHIVE" ;; esac
        if [ ! -f "$ARCHIVE" ]; then
            note "$(t archive.missing FILE "$ARCHIVE")"
            continue
        fi
        # The import runs as the application's own user, which sees this one
        # file through a mount and nothing else around it.
        if [ -z "$(find "$ARCHIVE" -prune -perm -004 2>/dev/null)" ]; then
            if confirm "$(t archive.unreadable FILE "$ARCHIVE")"; then
                chmod a+r "$ARCHIVE"
            else
                para "$(t takeover.later)"
                return 0
            fi
        fi
        break
    done

    explain passphrase
    while :; do
        PASSPHRASE="$(ask_hidden "$(t passphrase.label)")"
        step "$(t import.step)"
        para "$(t import.patience)"
        IMPORTED=0
        printf '%s\n' "$PASSPHRASE" | "$INSTALL_DIR/serviceops" import "$ARCHIVE" --as "$IMPORT_AS" || IMPORTED=$?
        PASSPHRASE=''
        say ''
        case "$IMPORTED" in
            0) ok "$(t import.ok)" ;;
            1) para "$(t import.refused)" ;;
            2) para "$(t import.stopped)" ;;
            3) para "$(t import.differs)" ;;
            4) para "$(t import.wrong_passphrase)"
               para "$(t import.safe)"
               if confirm "$(t import.again)"; then
                   continue
               fi
               para "$(t import.sealed_later)"
               return 0 ;;
            *) para "$(t import.failed)" ;;
        esac
        para "$(t import.safe)"
        return 0
    done
}

if [ "$RESTORE" != yes ]; then
    step "$(t takeover.step)"
    explain takeover
    case "$(choose takeover 2)" in
        1) take_the_data_over ;;
        2) para "$(t takeover.later)" ;;
    esac
fi

# ------------------------------------------------------------------ done --
#
# What to keep, then one line: that it runs, and what to do next.

if [ "$RESTORE" = yes ]; then
    say ''
    para "$(t result.restored)"
    NEXT="$(t result.next_restored ORIGIN "$ORIGIN")"
else
    say ''
    printf '  %s%s%s\n\n' "$bold" "$(t result.backup_title)" "$off"
    printf '    %s\n\n' "$BACKUP_SECRET"
    para "$(t result.backup_why)"
    if [ -n "$ADMIN_MADE" ]; then
        NEXT="$(t result.next_sign_in ORIGIN "$ORIGIN" EMAIL "$ADMIN_MADE")"
    else
        say ''
        para "$(t result.setup_once)"
        NEXT="$(t result.next_setup LINK "$ORIGIN/setup?token=$SETUP_TOKEN")"
    fi
fi

say ''
say "  $(t result.commands)"
say ''
say "    serviceops doctor        $(t result.doctor)"
say "    serviceops backup        $(t result.backup)"
say "    serviceops update        $(t result.update)"
say ''
printf '%s%s %s %s%s\n' "$bold" "$(t result.done VERSION "$RELEASE_VERSION" ORIGIN "$ORIGIN")" "$(t word.next)" "$NEXT" "$off"
