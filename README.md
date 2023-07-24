# nginx-podman-reset-ip

## Description
Script for updating a (rootless podman) nginx reverse proxy address to the changing (docker) nextcloud-aio-apache server ip 

## Usage

Clone repository:
```bash
git clone https://github.com/derenv/nginx-podman-reset-ip.git
```

Copy the template and edit to your settings:
```bash
cp config.conf.example config.conf

nano config.conf
```

Run script:
```bash
bash ./reset.sh
```

## Requirements

- podman
- docker
- [nextcloud-aio](https://github.com/nextcloud/all-in-one)
- [nginx container](https://nginxproxymanager.com/setup/)
- curl
- python3

## Credit

@derenv
@oscarmccabe1998
