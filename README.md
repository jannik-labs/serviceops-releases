# Installing ServiceOps

ServiceOps runs in containers on a Linux server you control. This repository
holds only the installer.

## What you need

- A server with Debian 12 or Ubuntu 22.04 or newer, root access and at least
  2 GB of memory.
- A domain whose A record points at the server.
- The licence server address and your licence key (`SOLK-…`), both from the
  installation guide you were given.

## Install

```sh
curl -fsSLO https://raw.githubusercontent.com/jannik-labs/serviceops-releases/main/install.sh
less install.sh          # it runs as root, so read it first
sudo sh install.sh
```

The installer explains each question and shows a summary before it changes
anything. At the end it prints a **backup key**. It is shown only once, so
keep it somewhere outside the server, for example in a password manager.

## Afterwards

```sh
serviceops status      what is running, and which version
serviceops doctor      what is wrong, if anything
serviceops update      move to the newest version your licence covers, with a way back
serviceops backup      take a copy now
serviceops logs        follow the containers
```

You can also update from within ServiceOps: *Administration → Updates*.

The software comes as an encrypted bundle in a public registry. The key that
opens a version comes from the licence server, and only for versions your
licence covers. Nothing about your business is sent there.
