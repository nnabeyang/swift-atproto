.PHONY: help lexgen
.DEFAULT_GOAL := help
OUTDIR?=../swiftsky/swiftsky/api
LEXDIR?=../../bluesky-social/atproto/lexicons

lexgen: ## Run codegen tool for lexicons (lexicon JSON to Swift codes)
	swift run swift-atproto --prefix app.bsky --outdir "${OUTDIR}/appbsky" $(LEXDIR)
	swift run swift-atproto --prefix com.atproto --outdir "${OUTDIR}/comatproto" $(LEXDIR)

help: ## Show options
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
