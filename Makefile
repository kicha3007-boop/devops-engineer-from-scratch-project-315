# В Git Bash на Windows не даём MSYS переписывать пути вида /work/... в аргументах docker
export MSYS_NO_PATHCONV := 1

# ============================================================================
# Приложение (команды исходного репозитория; нужен JDK 27)
# ============================================================================

build:
	./gradlew build

start: run

run:
	./gradlew bootRun

test:
	./gradlew test

lint:
	./gradlew spotlessCheck

lint-fix:
	./gradlew spotlessApply

# ============================================================================
# Docker-образ (нужен только Docker)
# ============================================================================

IMAGE ?= ghcr.io/kicha3007-boop/devops-engineer-from-scratch-project-315
IMAGE_TAG ?= local

docker-build:
	docker build --no-cache -t $(IMAGE):$(IMAGE_TAG) .

# Тесты приложения внутри сборки (стадия test в Dockerfile)
docker-test:
	docker build --no-cache --target test -t $(IMAGE):test .

# Приложение на http://localhost:28081 с H2 в памяти (профиль dev)
docker-start:
	docker run --rm --name p315-app -p 28081:8080 -e SPRING_PROFILES_ACTIVE=dev $(IMAGE):$(IMAGE_TAG)

# ============================================================================
# Инфраструктура: Ansible и Terraform
# ============================================================================
# Инструменты запускаются в контейнере toolbox (lab/toolbox): на машине нужен только Docker.
# Если Ansible и Terraform стоят локально: make deploy TOOLBOX=

ENV ?= production
INVENTORY = inventories/$(ENV)
COMPOSE = docker compose -f lab/compose.yaml
TOOLBOX ?= $(COMPOSE) run --rm toolbox
VAULT_FILE = $(INVENTORY)/group_vars/all/vault.yml

# make deploy TAGS=app TAG=<sha> — только приложение нужной сборки (откат на прежнюю — так же)
TAGS ?=
TAG ?=
PULL ?=
ANSIBLE_ARGS = $(if $(TAGS),--tags $(TAGS)) $(if $(TAG),-e app_image_tag=$(TAG)) $(if $(PULL),-e app_image_pull=$(PULL))

toolbox:
	$(COMPOSE) build --no-cache toolbox

# Сторонние роли и коллекции из requirements.yml (с повтором: Galaxy иногда обрывает загрузку)
install:
	for i in 1 2 3; do $(TOOLBOX) ansible-galaxy install -r requirements.yml && exit 0; sleep 5; done; exit 1

setup: toolbox install

# Подготовка сервера и деплой (идемпотентно: повторный запуск ничего не меняет)
deploy:
	$(TOOLBOX) ansible-playbook -i $(INVENTORY) playbook.yml $(ANSIBLE_ARGS)

# Сухой прогон: что изменится на сервере
deploy-check:
	$(TOOLBOX) ansible-playbook -i $(INVENTORY) playbook.yml --check --diff $(ANSIBLE_ARGS)

ping:
	$(TOOLBOX) ansible -i $(INVENTORY) all -m ansible.builtin.ping

vault-encrypt:
	$(TOOLBOX) ansible-vault encrypt $(VAULT_FILE)

vault-edit:
	$(TOOLBOX) ansible-vault edit $(VAULT_FILE)

vault-view:
	$(TOOLBOX) ansible-vault view $(VAULT_FILE)

lint-infra:
	$(TOOLBOX) sh -c 'ansible-lint && terraform -chdir=terraform fmt -check -recursive'

TF = $(TOOLBOX) terraform -chdir=terraform

tf-init:
	$(TF) init

tf-validate: tf-init
	$(TF) validate

tf-plan:
	$(TF) plan

tf-apply:
	$(TF) apply

tf-output:
	$(TF) output

tf-destroy:
	$(TF) destroy

# ============================================================================
# Локальный стенд вместо облака: make lab-up && make lab-deploy && make lab-check
# ============================================================================

LAB_TOOLBOX = $(COMPOSE) run --rm toolbox

# Собрать образы стенда, сгенерировать секреты, поднять «ВМ», MinIO и Pebble, создать бакет
lab-up:
	$(COMPOSE) build --no-cache vm toolbox
	$(LAB_TOOLBOX) python3 lab/bin/lab-secrets.py
	$(COMPOSE) up -d vm minio pebble
	$(MAKE) install
	$(LAB_TOOLBOX) sh -c 'for i in $$(seq 1 60); do ssh -q -i /lab-ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2 ubuntu@p315-vm true && exit 0; sleep 2; done; echo "«ВМ» не отвечает по SSH"; exit 1'
	$(MAKE) lab-s3

lab-secrets:
	$(LAB_TOOLBOX) python3 lab/bin/lab-secrets.py

# Бакет, политики и ключ приложения в MinIO (локальный аналог terraform/)
lab-s3:
	$(LAB_TOOLBOX) ansible-playbook -i inventories/lab lab/s3.yml

lab-deploy:
	$(MAKE) deploy ENV=lab

lab-deploy-check:
	$(MAKE) deploy-check ENV=lab

# Проверки стенда: HTTPS, редирект, шифры, кеш nginx, БД, загрузка файла в S3, продление сертификата
lab-check:
	$(LAB_TOOLBOX) sh lab/bin/lab-check.sh

# Собрать образ из текущего кода и задеплоить его на стенд без публикации в реестр
lab-image:
	docker build --no-cache -t $(IMAGE):local .
	docker save $(IMAGE):local | docker exec -i p315-vm docker load
	$(MAKE) deploy ENV=lab TAGS=app TAG=local PULL=false

lab-ssh:
	$(LAB_TOOLBOX) ssh -i /lab-ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@p315-vm

# Перезагрузка «ВМ»: приложение должно подняться само (restart policy + автозапуск docker)
lab-reboot:
	docker restart p315-vm

lab-down:
	$(COMPOSE) --profile tools down -v --remove-orphans

.PHONY: build start run test lint lint-fix docker-build docker-test docker-start \
	toolbox install setup deploy deploy-check ping vault-encrypt vault-edit vault-view lint-infra \
	tf-init tf-validate tf-plan tf-apply tf-output tf-destroy \
	lab-up lab-secrets lab-s3 lab-deploy lab-deploy-check lab-check lab-image lab-ssh lab-reboot lab-down
