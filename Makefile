# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

all: build test verify

# Some env vars that devs might find useful:
#  GOFLAGS         : extra "go build" flags to use - e.g. -v   (for verbose)
#  NO_DOCKER=1     : execute each step in the native environment instead of a Docker container
#  UNIT_TEST_DIRS= : only run the unit tests from the specified dirs
#  INT_TEST_DIRS=  : only run the integration tests from the specified dirs
#  TEST_FLAGS=     : add flags to the go test command

# Define some constants
#######################
ROOT           = $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
BINDIR        ?= bin
BUILD_DIR     ?= build
COVERAGE      ?= $(CURDIR)/coverage.html
CLUSTER_OPERATOR_PKG = github.com/openshift/cluster-operator
TOP_SRC_DIRS   = cmd pkg
SRC_DIRS       = $(shell sh -c "find $(TOP_SRC_DIRS) -name \\*.go \
                   -exec dirname {} \\; | sort | uniq")
UNIT_TEST_DIRS ?= $(shell sh -c "find $(TOP_SRC_DIRS) -name \\*_test.go \
                   -exec dirname {} \\; | sort | uniq")
INT_TEST_DIRS  ?= $(shell sh -c "find test/integration -name \\*_test.go \
                   -exec dirname {} \\; | sort | uniq")
VERSION        ?= $(shell git describe --always --abbrev=7 --dirty)
BUILD_LDFLAGS   = $(shell build/version.sh $(ROOT) $(CLUSTER_OPERATOR_PKG))

# Run stat against /dev/null and check if it has any stdout output.
# If stdout is blank, we are detecting bsd-stat because stat it has
# returned an error to stderr. If not bsd-stat, assume gnu-stat.
ifeq ($(shell stat -c"%U" /dev/null 2> /dev/null),)
STAT           = stat -f '%c %N'
else
STAT           = stat -c '%Y %n'
endif

TYPES_FILES    = $(shell find pkg/apis -name types.go)
GO_VERSION     = 1.9

ALL_ARCH=amd64 arm arm64 ppc64le s390x

PLATFORM?=linux
ARCH?=amd64

# TODO: Consider using busybox instead of debian
BASEIMAGE?=gcr.io/google-containers/debian-base-$(ARCH):0.2

GO_BUILD       = env GOOS=$(PLATFORM) GOARCH=$(ARCH) go build -i $(GOFLAGS) \
                   -ldflags "-X $(CLUSTER_OPERATOR_PKG)/pkg.VERSION=$(VERSION) $(BUILD_LDFLAGS)"
BASE_PATH      = $(ROOT:/src/github.com/openshift/cluster-operator/=)
export GOPATH  = $(BASE_PATH):$(ROOT)/vendor

MUTABLE_TAG                         ?= canary
CLUSTER_OPERATOR_IMAGE               = $(REGISTRY)cluster-operator-$(ARCH):$(VERSION)
CLUSTER_OPERATOR_MUTABLE_IMAGE       = $(REGISTRY)cluster-operator-$(ARCH):$(MUTABLE_TAG)
FAKE_OPENSHIFT_ANSIBLE_IMAGE         = $(REGISTRY)fake-openshift-ansible:$(VERSION)
FAKE_OPENSHIFT_ANSIBLE_MUTABLE_IMAGE = $(REGISTRY)fake-openshift-ansible:$(MUTABLE_TAG)
PLAYBOOK_MOCK_IMAGE                  = $(REGISTRY)playbook-mock:$(VERSION)
PLAYBOOK_MOCK_MUTABLE_IMAGE          = $(REGISTRY)playbook-mock:$(MUTABLE_TAG)

$(if $(realpath vendor/k8s.io/apimachinery/vendor), \
	$(error the vendor directory exists in the apimachinery \
		vendored source and must be flattened. \
		run 'glide i -v'))

ifdef TEST_LOG_LEVEL
	TEST_FLAGS+=-v
	TEST_LOG_FLAGS=-args --alsologtostderr --v=$(TEST_LOG_LEVEL)
endif

NO_DOCKER ?= 0
ifeq ($(NO_DOCKER), 1)
	DOCKER_CMD =
	clusterOperatorBuildImageTarget =
else
	# Mount .pkg as pkg so that we save our cached "go build" output files
	DOCKER_CMD = docker run --security-opt label:disable --rm -v $(PWD):/go/src/$(CLUSTER_OPERATOR_PKG) \
	  -v $(PWD)/.pkg:/go/pkg clusteroperatorbuildimage
	clusterOperatorBuildImageTarget = .clusterOperatorBuildImage
endif

NON_VENDOR_DIRS = $(shell $(DOCKER_CMD) glide nv)

# This section builds the output binaries.
# Some will have dedicated targets to make it easier to type, for example
# "cluster-operator" instead of "bin/cluster-operator".
#########################################################################
build: .init .generate_files \
	$(BINDIR)/cluster-operator \
	$(BINDIR)/fake-openshift-ansible \
	$(BINDIR)/playbook-mock

.PHONY: $(BINDIR)/cluster-operator
cluster-operator: $(BINDIR)/cluster-operator
$(BINDIR)/cluster-operator: .init .generate_files
	$(DOCKER_CMD) $(GO_BUILD) -o $@ $(CLUSTER_OPERATOR_PKG)/cmd/cluster-operator

fake-openshift-ansible: $(BINDIR)/fake-openshift-ansible
$(BINDIR)/fake-openshift-ansible: contrib/fake-openshift-ansible/fake-openshift-ansible
	$(DOCKER_CMD) cp contrib/fake-openshift-ansible/fake-openshift-ansible $(BINDIR)

.PHONY: $(BINDIR)/playbook-mock
playbook-mock: $(BINDIR)/playbook-mock
$(BINDIR)/playbook-mock:
	$(DOCKER_CMD) $(GO_BUILD) -o $@ $(CLUSTER_OPERATOR_PKG)/contrib/cmd/playbook-mock


# This section contains the code generation stuff
#################################################
.generate_exes: $(BINDIR)/defaulter-gen \
                $(BINDIR)/deepcopy-gen \
                $(BINDIR)/conversion-gen \
                $(BINDIR)/client-gen \
                $(BINDIR)/lister-gen \
                $(BINDIR)/informer-gen \
                $(BINDIR)/openapi-gen
	touch $@

$(BINDIR)/defaulter-gen: .init
	$(DOCKER_CMD) go build -o $@ $(CLUSTER_OPERATOR_PKG)/vendor/k8s.io/code-generator/cmd/defaulter-gen

$(BINDIR)/deepcopy-gen: .init
	$(DOCKER_CMD) go build -o $@ $(CLUSTER_OPERATOR_PKG)/vendor/k8s.io/code-generator/cmd/deepcopy-gen

$(BINDIR)/conversion-gen: .init
	$(DOCKER_CMD) go build -o $@ $(CLUSTER_OPERATOR_PKG)/vendor/k8s.io/code-generator/cmd/conversion-gen

$(BINDIR)/client-gen: .init
	$(DOCKER_CMD) go build -o $@ $(CLUSTER_OPERATOR_PKG)/vendor/k8s.io/code-generator/cmd/client-gen

$(BINDIR)/lister-gen: .init
	$(DOCKER_CMD) go build -o $@ $(CLUSTER_OPERATOR_PKG)/vendor/k8s.io/code-generator/cmd/lister-gen

$(BINDIR)/informer-gen: .init
	$(DOCKER_CMD) go build -o $@ $(CLUSTER_OPERATOR_PKG)/vendor/k8s.io/code-generator/cmd/informer-gen

$(BINDIR)/openapi-gen: vendor/k8s.io/code-generator/cmd/openapi-gen
	$(DOCKER_CMD) go build -o $@ $(CLUSTER_OPERATOR_PKG)/$^

.PHONY: $(BINDIR)/e2e.test
$(BINDIR)/e2e.test: .init
	$(DOCKER_CMD) go test -c -o $@ $(CLUSTER_OPERATOR_PKG)/test/e2e

# Regenerate all files if the gen exes changed or any "types.go" files changed
.generate_files: .init .generate_exes $(TYPES_FILES)
	# generate apiserver deps
	$(DOCKER_CMD) $(BUILD_DIR)/update-apiserver-gen.sh
	# generate all pkg/client contents
	$(DOCKER_CMD) $(BUILD_DIR)/update-client-gen.sh
	touch $@

# Some prereq stuff
###################

.init: $(clusterOperatorBuildImageTarget)
	touch $@

.clusterOperatorBuildImage: build/build-image/Dockerfile
	sed "s/GO_VERSION/$(GO_VERSION)/g" < build/build-image/Dockerfile | \
	  docker build -t clusteroperatorbuildimage -
	touch $@

# Util targets
##############
.PHONY: verify verify-generated verify-client-gen
verify: .init .generate_exes verify-generated verify-client-gen
	@echo Running gofmt:
	@$(DOCKER_CMD) gofmt -l -s $(TOP_SRC_DIRS)>.out 2>&1||true
	@[ ! -s .out ] || \
	  (echo && echo "*** Please 'gofmt' the following:" && \
	  cat .out && echo && rm .out && false)
	@rm .out
	@#
	@echo Running golint and go vet:
	@# Exclude the generated (zz) files for now, as well as defaults.go (it
	@# observes conventions from upstream that will not pass lint checks).
	@$(DOCKER_CMD) sh -c \
	  'for i in $$(find $(TOP_SRC_DIRS) -name *.go \
	    | grep -v ^pkg/kubernetes/ \
	    | grep -v generated \
	    | grep -v ^pkg/client/ \
	    | grep -v v1alpha1/defaults.go); \
	  do \
	   golint --set_exit_status $$i || exit 1; \
	  done'
	@#
	$(DOCKER_CMD) go vet $(NON_VENDOR_DIRS)
	@echo Running repo-infra verify scripts
	@$(DOCKER_CMD) vendor/github.com/kubernetes/repo-infra/verify/verify-boilerplate.sh --rootdir=. | grep -v generated > .out 2>&1 || true
	@[ ! -s .out ] || (cat .out && rm .out && false)
	@rm .out
	@#
	@echo Running errexit checker:
	@$(DOCKER_CMD) build/verify-errexit.sh

verify-generated: .init .generate_exes
	$(DOCKER_CMD) $(BUILD_DIR)/update-apiserver-gen.sh --verify-only

verify-client-gen: .init .generate_exes
	$(DOCKER_CMD) $(BUILD_DIR)/verify-client-gen.sh

format: .init
	$(DOCKER_CMD) gofmt -w -s $(TOP_SRC_DIRS)

coverage: .init
	$(DOCKER_CMD) contrib/hack/coverage.sh --html "$(COVERAGE)" \
	  $(addprefix ./,$(UNIT_TEST_DIRS))

test: .init build test-unit test-integration

# this target checks to see if the go binary is installed on the host
.PHONY: check-go
check-go:
	@if [ -z $$(which go) ]; then \
	  echo "Missing \`go\` binary which is required for development"; \
	  exit 1; \
	fi

# this target uses the host-local go installation to test
.PHONY: test-unit-native
test-unit-native: check-go
	go test $(addprefix ${CLUSTER_OPERATOR_PKG}/,${UNIT_TEST_DIRS})

test-unit: .init build .generate_mocks
	@echo Running unit tests:
	$(DOCKER_CMD) go test -race $(TEST_FLAGS) \
	  $(addprefix $(CLUSTER_OPERATOR_PKG)/,$(UNIT_TEST_DIRS)) $(TEST_LOG_FLAGS)

.generate_mocks:
	$(DOCKER_CMD) go generate ./pkg/controller

test-integration: .init build
	@echo Running integration tests:
	$(DOCKER_CMD) go test -race $(TEST_FLAGS) \
	  $(addprefix $(CLUSTER_OPERATOR_PKG)/,$(INT_TEST_DIRS)) $(TEST_LOG_FLAGS)

clean-e2e:
	rm -f $(BINDIR)/e2e.test

test-e2e: .generate_files $(BINDIR)/e2e.test
	$(BINDIR)/e2e.test

clean: clean-bin clean-build-image clean-generated clean-coverage

clean-bin:
	$(DOCKER_CMD) rm -rf $(BINDIR)
	rm -f .generate_exes

clean-build-image:
	$(DOCKER_CMD) rm -rf .pkg
	rm -f .clusterOperatorBuildImage
	docker rmi -f clusteroperatorbuildimage > /dev/null 2>&1 || true

# clean-generated does a `git checkout --` on all generated files and
# directories.  May not work correctly if you have staged some of these files
# or have multiple commits.
clean-generated:
	rm -f .generate_files
	# rollback changes to generated defaults/conversions/deepcopies
	find $(TOP_SRC_DIRS) -name zz_generated* | xargs git checkout --
	# rollback changes to types.generated.go
	find $(TOP_SRC_DIRS) -name types.generated* | xargs git checkout --
	# rollback changes to the generated clientset directories
	find $(TOP_SRC_DIRS) -type d -name *_generated | xargs git checkout --
	# rollback openapi changes
	git checkout -- pkg/openapi/openapi_generated.go

# purge-generated removes generated files from the filesystem.
purge-generated:
	find $(TOP_SRC_DIRS) -name zz_generated* -exec rm {} \;
	find $(TOP_SRC_DIRS) -type d -name *_generated -exec rm -rf {} \;
	rm -f pkg/openapi/openapi_generated.go
	echo 'package v1alpha1' > pkg/apis/clusteroperator/v1alpha1/types.generated.go

clean-coverage:
	rm -f $(COVERAGE)

# Building Docker Images for our executables
############################################
images: cluster-operator-image fake-openshift-ansible-image playbook-mock-image

images-all: $(addprefix arch-image-,$(ALL_ARCH))
arch-image-%:
	$(MAKE) ARCH=$* build
	$(MAKE) ARCH=$* images

define build-and-tag # (service, image, mutable_image, prefix)
	$(eval build_path := "$(4)build/$(1)")
	$(eval tmp_build_path := "$(build_path)/tmp")
	mkdir -p $(tmp_build_path)
	cp $(BINDIR)/$(1) $(tmp_build_path)
	cp $(build_path)/Dockerfile $(tmp_build_path)
	# -i.bak is required for cross-platform compat: https://stackoverflow.com/questions/5694228/sed-in-place-flag-that-works-both-on-mac-bsd-and-linux
	sed -i.bak "s|BASEIMAGE|$(BASEIMAGE)|g" $(tmp_build_path)/Dockerfile
	rm $(tmp_build_path)/Dockerfile.bak
	docker run --rm --privileged multiarch/qemu-user-static:register --reset
	docker build -t $(2) $(tmp_build_path)
	docker tag $(2) $(3)
	rm -rf $(tmp_build_path)
endef

cluster-operator-image: build/cluster-operator/Dockerfile $(BINDIR)/cluster-operator
	$(call build-and-tag,"cluster-operator",$(CLUSTER_OPERATOR_IMAGE),$(CLUSTER_OPERATOR_MUTABLE_IMAGE))
ifeq ($(ARCH),amd64)
	docker tag $(CLUSTER_OPERATOR_IMAGE) $(REGISTRY)cluster-operator:$(VERSION)
	docker tag $(CLUSTER_OPERATOR_MUTABLE_IMAGE) $(REGISTRY)cluster-operator:$(MUTABLE_TAG)
endif

fake-openshift-ansible-image: build/fake-openshift-ansible/Dockerfile $(BINDIR)/fake-openshift-ansible
	$(call build-and-tag,"fake-openshift-ansible",$(FAKE_OPENSHIFT_ANSIBLE_IMAGE),$(FAKE_OPENSHIFT_ANSIBLE_MUTABLE_IMAGE))
	docker tag $(FAKE_OPENSHIFT_ANSIBLE_IMAGE) $(REGISTRY)fake-openshift-ansible:$(VERSION)
	docker tag $(FAKE_OPENSHIFT_ANSIBLE_MUTABLE_IMAGE) $(REGISTRY)fake-openshift-ansible:$(MUTABLE_TAG)

playbook-mock-image: build/playbook-mock/Dockerfile $(BINDIR)/playbook-mock
	$(call build-and-tag,"playbook-mock",$(PLAYBOOK_MOCK_IMAGE),$(PLAYBOOK_MOCK_MUTABLE_IMAGE))
	docker tag $(PLAYBOOK_MOCK_IMAGE) $(REGISTRY)playbook-mock:$(VERSION)
	docker tag $(PLAYBOOK_MOCK_MUTABLE_IMAGE) $(REGISTRY)playbook-mock:$(MUTABLE_TAG)


# Push our Docker Images to a registry
######################################
push: cluster-operator-push

cluster-operator-push: cluster-operator-image
	docker push $(CLUSTER_OPERATOR_IMAGE)
	docker push $(CLUSTER_OPERATOR_MUTABLE_IMAGE)
ifeq ($(ARCH),amd64)
	docker push $(REGISTRY)cluster-operator:$(VERSION)
	docker push $(REGISTRY)cluster-operator:$(MUTABLE_TAG)
endif


release-push: $(addprefix release-push-,$(ALL_ARCH))
release-push-%:
	$(MAKE) ARCH=$* build
	$(MAKE) ARCH=$* push
