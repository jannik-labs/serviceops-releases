# Installing ServiceOps

ServiceOps runs on a Linux server you control, in containers. Installing it
is one command, and it asks you for four things: your licence key, a domain,
the e-mail address of the first administrator and, if you want it to send
mail, an SMTP server. Everything else it works out or generates.

## What you need

- A server running Debian 12 or Ubuntu 22.04 or newer, with at least 2 GB of
  memory and 10 GB of free disk, and a great deal more disk if your business
  keeps photographs.
- Root on it, and a way to reach ports 80 and 443 on it from the internet.
- A domain whose A record points at the server. Without one, the installation
  is reached by IP address with a certificate the server signs itself.
- Your licence key, one line beginning with `AGE-SECRET-KEY-1`, which was
  given to you with the software.

## Installing

```sh
curl -fsSLO https://raw.githubusercontent.com/jannik-labs/serviceops-releases/main/install.sh
less install.sh          # read it; it runs as root
sudo sh install.sh
```

It lists what it is about to change and asks before changing anything. When
it is done it prints a link to make the first administrator, and a backup
key that is shown once and written nowhere. Put that key somewhere that
survives the server.

## Afterwards

```sh
serviceops status      what is running, and what version
serviceops doctor      what is wrong, if anything
serviceops update      move to a newer version, with a way back
serviceops backup      take a copy now
serviceops restore     put one back, into an empty installation
serviceops logs        follow what the containers are saying
```

An update takes a backup, fetches the newer release, opens it with your
licence key, migrates, restarts and checks that the installation is alive;
if it is not, it goes back to the version you had. The licence key never
leaves the server and is never sent anywhere. If it does not cover a newer
version, the update says so and the version you have keeps running.

## What this repository is

Only the installer. The software itself is published as an encrypted bundle
in a public registry, and your licence key is what opens it. Nothing here
holds source, a secret or anything about any customer.
