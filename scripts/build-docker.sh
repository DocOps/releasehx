#!/usr/bin/env bash
# ReleaseHx Docker build script
# Builds Docker image with proper version extraction from README.adoc

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Project-specific configuration
PROJECT_NAME="releasehx"
DOCKER_ORG="docopslab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}🐳 ${PROJECT_NAME} Docker Build Script${NC}"
echo "=================================="

# Check we're in project root
if [ ! -f "releasehx.gemspec" ]; then
  echo -e "${RED}❌ Error: releasehx.gemspec not found. Run this script from the project root.${NC}"
  exit 1
fi

# Check Docker is available
if ! command -v docker &> /dev/null; then
  echo -e "${RED}❌ Error: Docker is not installed or not in PATH${NC}"
  exit 1
fi

# Check if gem exists in pkg/ directory
echo -e "${YELLOW}📋 Looking for built gem in pkg/...${NC}"
gem_file=$(find pkg -name "${PROJECT_NAME}-*.gem" -type f 2>/dev/null | head -n 1)

if [ -z "$gem_file" ]; then
  echo -e "${RED}❌ Error: No gem found in pkg/ directory${NC}"
  echo -e "${YELLOW}Build the gem first with: bundle exec rake build${NC}"
  exit 1
fi

echo -e "${GREEN}📦 Found gem: $gem_file${NC}"

# Extract version from the built gem using Ruby and the gem's VERSION constant
# This is the single source of truth - the gem itself declares its version
echo -e "${YELLOW}📋 Extracting version from gem...${NC}"
current_version=$(ruby -e "
  require 'bundler/setup'
  require 'releasehx/version'
  puts ReleaseHx::VERSION
")

if [ -z "$current_version" ]; then
  echo -e "${RED}❌ Error: Could not extract version from ReleaseHx::VERSION${NC}"
  exit 1
fi

echo -e "${GREEN}📋 Current version: $current_version${NC}"

# Verify gem file exists
gem_file="pkg/${PROJECT_NAME}-$current_version.gem"
if [ ! -f "$gem_file" ]; then
  echo -e "${RED}❌ Error: Gem file not found after build: $gem_file${NC}"
  exit 1
else
  echo -e "${GREEN}✅ Using gem: $gem_file${NC}"
fi

# Build Docker image
echo -e "${YELLOW}🐳 Building Docker image...${NC}"
docker build \
  --build-arg RELEASEHX_VERSION="$current_version" \
  -t "${DOCKER_ORG}/${PROJECT_NAME}:${current_version}" \
  .

# Tag as latest
docker tag "${DOCKER_ORG}/${PROJECT_NAME}:${current_version}" "${DOCKER_ORG}/${PROJECT_NAME}:latest"

# Test the image
echo -e "${YELLOW}🧪 Testing Docker image...${NC}"
docker run --rm "${DOCKER_ORG}/${PROJECT_NAME}:${current_version}" --version

echo
echo -e "${GREEN}✅ Docker build completed successfully!${NC}"
echo "=================================="
echo
echo "Image tags created:"
echo "  ${DOCKER_ORG}/${PROJECT_NAME}:${current_version}"
echo "  ${DOCKER_ORG}/${PROJECT_NAME}:latest"
echo
echo "Test the image with:"
echo "  docker run --rm -v \$(pwd):/workdir ${DOCKER_ORG}/${PROJECT_NAME}:${current_version} --help"
echo "  docker run --rm -v \$(pwd):/workdir ${DOCKER_ORG}/${PROJECT_NAME}:${current_version} _configs/sample.yml --yaml"
echo
echo "To publish to Docker Hub:"
echo "  docker push ${DOCKER_ORG}/${PROJECT_NAME}:${current_version}"
echo "  docker push ${DOCKER_ORG}/${PROJECT_NAME}:latest"
