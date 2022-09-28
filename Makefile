# Makefile for managing the helm charts

chartPath=charts/camunda-platform
releaseName=camunda-platform-test
gitChglog=quay.io/git-chglog/git-chglog:0.15.1

# test: runs the tests without updating the golden files (runs checks against golden files)
.PHONY: test
test:	deps
	go test ./...

# it: runs the integration tests against the current kube context
.PHONY: it
it:	deps
	go test -p 1 -timeout 1h -tags integration ./.../integration

# it-os: runs a subset of the integration tests against the current Openshift cluster
.PHONY: it-os
it-os: deps
	go test -p 1 -timeout 1h -tags integration,openshift ./.../integration

# golden: runs the tests with updating the golden files
.PHONY: golden
golden:	deps
	go test ./... -args -update-golden 

# fmt: runs the gofmt in order to format all go files
.PHONY: fmt
fmt:
	go fmt ./... 

# addlicense: add license headers to go files
.PHONY: addlicense
addlicense:
	addlicense -c 'Camunda Services GmbH' -l apache charts/camunda-platform/test/**/*.go

# checkLicense: checks that the go files contain license header
.PHONY: checkLicense
checkLicense:
	addlicense -check -l apache charts/camunda-platform/test/**/*.go

# installLicense: installs the addlicense tool
.PHONY: installLicense
installLicense:
	go install github.com/google/addlicense@v1.0.0

#########################################################
######### Tools
#########################################################

# Add asdf plugins.
.asdf-plugins-add:
	@# Add plugins from .tool-versions file within the repo.
	@# If the plugin is already installed asdf exits with 2, so grep is used to handle that.
	@for plugin in $$(awk '{print $$1}' .tool-versions); do \
		echo "$${plugin}"; \
		asdf plugin add $${plugin} 2>&1 | (grep "already added" && exit 0); \
	done

# Install tools via asdf.
asdf-tools-install: .asdf-plugins-add
	asdf install

#########################################################
######### HELM
#########################################################
# deps: updates and downloads the dependencies for the helm chart
.PHONY: deps
deps:
	helm dependency update $(chartPath)
	helm dependency update $(chartPath)/charts/identity

# install: install the local chart into the current kubernetes cluster/namespace
.PHONY: install
install:	deps
	helm install $(releaseName) $(chartPath)

# uninstall: uninstalls the chart and removes all related pvc's
.PHONY: uninstall
uninstall:
	-helm uninstall $(releaseName)
	-kubectl delete pvc -l app.kubernetes.io/instance=$(releaseName)
	-kubectl delete pvc -l release=$(releaseName)

# dry-run: runs an install dry-run with the local chart
.PHONY: dry-run
dry-run:	deps
	helm install $(releaseName) $(chartPath) --dry-run

# template: show all rendered templates for the local chart
.PHONY: template
template:	deps
	helm template $(releaseName) $(chartPath)

#########################################################
######### Testing
#########################################################

.PHONY: topology
topology:
	kubectl exec svc/$(releaseName)-zeebe-gateway -- zbctl --insecure status

#########################################################
######### Release
#########################################################

.PHONY: .bump-chart-version
.bump-chart-version:
	@bash scripts/bump-chart-version.sh

.PHONY: bump-chart-version-and-commit
bump-chart-version-and-commit: .bump-chart-version
	chart_path="charts/camunda-platform";\
	chart_version=`grep -Po '(?<=^version: ).+' $${chart_path}/Chart.yaml`;\
	git add $${chart_path};\
	git commit -m "chore: bump camunda-platform chart version to $${chart_version}"

.PHONY: .generate-release-notes
.generate-release-notes:
	# bash scripts/generate-release-notes.sh
	docker run --rm -w /data -v `pwd`:/data --entrypoint sh $(gitChglog) \
		-c "apk add bash grep yq; bash scripts/generate-release-notes.sh"

.PHONY: generate-release-notes-and-commit
generate-release-notes-and-commit: .generate-release-notes
	chart_path="charts/camunda-platform";\
	chart_version=`grep -Po '(?<=^version: ).+' $${chart_path}/Chart.yaml`;\
	git add charts/camunda-platform;\
	git commit -m "chore: add release notes for camunda-platform $${chart_version}"

.PHONY: generate-release-pr-url
generate-release-pr-url:
	@echo "Open the release PR using this URL:"
	@echo "https://github.com/camunda/camunda-platform-helm/compare/release?expand=1&template=release_template.md"

.PHONY: release-chores
release-chores:
	git checkout main
	git pull
	git branch -D release 2&> /dev/null || true
	git checkout -b release
	$(MAKE) bump-chart-version-and-commit
	$(MAKE) generate-release-notes-and-commit
	git push
	$(MAKE) generate-release-pr-url
