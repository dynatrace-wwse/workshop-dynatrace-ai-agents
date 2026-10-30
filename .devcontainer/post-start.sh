#!/bin/bash
##############################################################
## Runs every time the container starts (after post-create).
## Training content is delivered through the Enablement App (or
## GitHub Pages); MkDocs is not served from inside the container.
##############################################################
source .devcontainer/util/source_framework.sh

printInfoSection "Your dev.container finished starting up"
