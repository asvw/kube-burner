.PHONY: build lint clean test help images push manifest manifest-build all release tag

ARCH ?= amd64
BIN_NAME = kube-burner
BIN_DIR = bin
BIN_PATH = $(BIN_DIR)/$(ARCH)/$(BIN_NAME)
CGO = 0

GIT_COMMIT = $(shell git rev-parse HEAD)
VERSION ?= $(shell hack/tag_name.sh)
SOURCES := $(shell find . -type f -name "*.go")
BUILD_DATE = $(shell date '+%Y-%m-%d-%H:%M:%S')
KUBE_BURNER_VERSION= github.com/cloud-bulldozer/go-commons/version

# Github release
GITHUB_REPOSITORY ?= asvw/kube-burner

# Containers
ENGINE ?= podman
REGISTRY = docker.io
ORG ?= loginfordocker
DOCKER_IO_NAMESPACE = loginfordocker
CONTAINER_NAME = $(REGISTRY)/$(DOCKER_IO_NAMESPACE)/kube-burner:$(VERSION)
CONTAINER_NAME_ARCH = $(REGISTRY)/$(DOCKER_IO_NAMESPACE)/kube-burner:$(VERSION)-$(ARCH)
#MANIFEST_ARCHS ?= amd64 arm64 ppc64le s390x
MANIFEST_ARCHS ?= amd64

all: lint build images push

help:
	@echo "Commands for $(BIN_PATH):"
	@echo
	@echo 'Usage:'
	@echo '    make lint                     Install and execute pre-commit'
	@echo '    make clean                    Clean the compiled binaries'
	@echo '    [ARCH=arch] make build        Compile the project for arch, default amd64'
	@echo '    [ARCH=arch] make install      Installs kube-burner binary in the system, default amd64'
	@echo '    [ARCH=arch] make images       Build images for arch, default amd64'
	@echo '    [ARCH=arch] make push         Push images for arch, default amd64'
	@echo '    make manifest                 Create and push manifest for the different architectures supported'
	@echo '    make help                     Show this message'

build: $(BIN_PATH)

$(BIN_PATH): $(SOURCES)
	@echo -e "\033[2mBuilding $(BIN_PATH)\033[0m"
	@echo "GOPATH=$(GOPATH)"
	GOARCH=$(ARCH) CGO_ENABLED=$(CGO) go build -v -ldflags "-X $(KUBE_BURNER_VERSION).GitCommit=$(GIT_COMMIT) -X $(KUBE_BURNER_VERSION).BuildDate=$(BUILD_DATE) -X $(KUBE_BURNER_VERSION).Version=$(VERSION)" -o $(BIN_PATH) ./cmd/kube-burner

lint:
	@echo "Executing pre-commit for all files"
	pre-commit run --all-files
	@echo "pre-commit executed."

clean:
	test ! -e $(BIN_DIR) || rm -Rf $(BIN_PATH)

install:
	cp $(BIN_PATH) /usr/bin/$(BIN_NAME)

images:
	@echo -e "\n\033[2mBuilding container $(CONTAINER_NAME_ARCH)\033[0m"
	$(ENGINE) build --arch=$(ARCH) -f Containerfile $(BIN_DIR)/$(ARCH)/ -t $(CONTAINER_NAME_ARCH)

push:
	@echo "ORG=$(ORG), DOCKER_IO_NAMESPACE=$(DOCKER_IO_NAMESPACE), CONTAINER_NAME_ARCH=$(CONTAINER_NAME_ARCH)"
	@echo -e "\033[2mPushing container $(CONTAINER_NAME_ARCH)\033[0m"
	$(ENGINE) push $(CONTAINER_NAME_ARCH)

manifest: manifest-build
	@echo -e "\033[2mPushing container manifest $(CONTAINER_NAME)\033[0m"
	$(ENGINE) manifest push $(CONTAINER_NAME) $(CONTAINER_NAME)

manifest-build:
	@echo -e "\033[2mCreating container manifest $(CONTAINER_NAME)\033[0m"
	$(ENGINE) manifest create $(CONTAINER_NAME)
	for arch in $(MANIFEST_ARCHS); do \
		$(ENGINE) manifest add $(CONTAINER_NAME) $(CONTAINER_NAME)-$${arch}; \
	done

tag:
ifndef VERSION
	$(error VERSION is undefined. Usage: make tag VERSION=v1.1.1)
endif
	@git tag -a $(VERSION) -m "Release $(VERSION)"
	@git push origin $(VERSION)
	@echo "Tagged $(VERSION) and pushed to remote repository."

release: $(BIN_PATH)
	# Determine the latest git tag
	$(eval VERSION := $(shell git describe --tags `git rev-list --tags --max-count=1`))
	# Check if the GitHub CLI is installed
	@if ! command -v gh > /dev/null; then \
		@echo "GitHub CLI (gh) is not installed. Please install it to create releases."; \
		exit 1; \
	fi
	# Ensure VERSION is not empty
	@if [ -z "$(VERSION)" ]; then \
		@echo "VERSION is not set. Please ensure you have at least one tag."; \
		exit 1; \
	fi
	# Create a GitHub release for the latest tag
	@if ! gh release view $(VERSION) > /dev/null 2>&1; then \
		gh release create $(VERSION) \
		--repo $(GITHUB_REPOSITORY) \
		--title "Release $(VERSION)" \
		--notes "Private release" \
		$(BIN_PATH) \
		--target $(GIT_COMMIT) \
		--draft; \
		echo "Release $(VERSION) created and $(BIN_NAME) uploaded."; \
	else \
		echo "Release $(VERSION) already exists. Skipping creation."; \
	fi
	# Upload or replace asset
	# Delete existing asset with the same name if it exists
	-gh release delete-asset --repo $(GITHUB_REPOSITORY) --name $(BIN_NAME) $(VERSION) || true
	# Upload the new asset
	gh release upload $(VERSION) $(BIN_PATH) --repo $(GITHUB_REPOSITORY) --clobber
	@echo "$(BIN_NAME) uploaded to Release $(VERSION)."


#test: test-k8s test-ocp
test: test-k8s

test-k8s:
	cd test && bats -F pretty -T --print-output-on-failure test-k8s.bats

test-ocp:
	cd test && bats -F pretty -T --print-output-on-failure test-ocp.bats
