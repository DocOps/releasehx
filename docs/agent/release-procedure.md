# ReleaseHx Release Procedure

**Template for Patch Releases (0.x.y)**

This document captures the complete release workflow for ReleaseHx patch releases using a long-lived `release/0.x` branch with PR-based merges to `main`.

## Prerequisites

- [ ] All changes merged to `release/0.x` branch
- [ ] Version number updated in README.adoc (`:this_prod_vrsn_patch:`)
- [ ] Release notes prepared in `docs/release/0.x.y.adoc`
- [ ] Clean working tree on `release/0.x`
- [ ] RubyGems credentials configured (`~/.gem/credentials`)
- [ ] Docker Hub credentials configured (`docker login`)

## Release Stages

### Stage 1: Pre-flight Checks

**Verify CI/CD Setup**
```bash
# Check workflows exist
ls .github/workflows/
# Should see: ci-cd.yml, gh-pages.yml, docs-qa.yml
```

**Check Current State**
```bash
# Verify branch and clean status
git status
# Should be on release/0.x with clean working tree
```

**Run Test Suite**
```bash
bundle exec rake rspec
# All tests must pass
```

**Test Docker Build**
```bash
bundle exec rake buildx
# Note: This creates/updates the buildx builder and tests the build
# May need to recreate builder after Docker updates: docker buildx rm releasehx-builder
```

**Verify Version Numbers**
```bash
# Check version in README.adoc
grep ":this_prod_vrsn" README.adoc
# Verify lib/releasehx/version.rb reads from README attributes
grep "VERSION" lib/releasehx/version.rb
```

**Verify Gemfile**
```bash
# Ensure no local path dependencies
grep -E "path:|git:" Gemfile
# Should be empty
```

**Confirm Release Notes**
```bash
# Verify release notes file exists
ls -lh docs/release/0.x.y.adoc
```

### Stage 2: Build Artifacts

**Build Gem Package**
```bash
bundle exec rake build
# Creates pkg/releasehx-0.x.y.gem
```

**Verify Gem Package**
```bash
ls -lh pkg/releasehx-*.gem
# Confirm version number is correct
```

### Stage 3: Create Pull Request

**Push Release Branch**
```bash
git push origin release/0.x
```

**Create Pull Request**
- Via GitHub UI: https://github.com/DocOps/releasehx/compare/main...release/0.x
- Title: Release 0.x.y
- Body: (leave empty)
- Wait for CI tests to pass

**Merge Strategy**
- Use "Create a merge commit" (NOT squash or rebase)
- This preserves commit history and allows future PRs from the same branch

### Stage 4: Tag Release

**Update Local Main Branch**
```bash
git checkout main
git pull origin main
```

**Create and Push Tag**
```bash
git tag -a v0.x.y -m "Release 0.x.y"
git push origin v0.x.y
```

**Note:** GitHub Pages workflow will auto-deploy docs when tag is pushed.

### Stage 5: Sync Release Branch (Optional but Recommended)

**Cherry-pick Any Post-Merge Fixes**

If you made any fixes to release notes or docs on main after the merge:
```bash
git checkout release/0.x
git cherry-pick <commit-sha>
git push origin release/0.x
```

### Stage 6: Create GitHub Release

**Via GitHub UI** (recommended):
1. Go to: https://github.com/DocOps/releasehx/releases/new
2. Select tag: v0.x.y
3. Title: ReleaseHx 0.x.y
4. Description: `See release notes at https://releasehx.docopslab.org/docs/releases/`
5. Upload: `pkg/releasehx-0.x.y.gem`
6. Click "Publish release"

**Via CLI** (if permissions allow):
```bash
gh release create v0.x.y pkg/releasehx-0.x.y.gem \
  --title "ReleaseHx 0.x.y" \
  --notes "See release notes at https://releasehx.docopslab.org/docs/releases/"
```

### Stage 7: Publish Gem to RubyGems

```bash
gem push pkg/releasehx-0.x.y.gem
# Enter OTP code from authenticator when prompted
```

**Verify Publication**
```bash
# Check on RubyGems.org
open https://rubygems.org/gems/releasehx
```

### Stage 8: Publish Docker Image

**Build and Load Image**
```bash
docker buildx build --platform linux/amd64 \
  --build-arg RELEASEHX_VERSION=0.x.y \
  -t docopslab/releasehx:latest \
  -t docopslab/releasehx:0.x.y \
  --load \
  .
```

**Push Images**
```bash
docker push docopslab/releasehx:0.x.y
docker push docopslab/releasehx:latest
```

**Verify Publication**
```bash
# Check on Docker Hub
open https://hub.docker.com/r/docopslab/releasehx
```

### Stage 9: Post-Release Verification

**Test Gem Installation**
```bash
gem install releasehx --version 0.x.y
rhx --version
# Should show: 0.x.y
```

**Test Docker Image**
```bash
docker pull docopslab/releasehx:0.x.y
docker run --rm docopslab/releasehx:0.x.y rhx --version
# Should show: 0.x.y
```

**Verify Documentation**
```bash
# Check that docs are live
open https://releasehx.docopslab.org/docs/releases/
# Should show 0.x.y release notes
```

### Stage 10: Post-Release Cleanup (Optional)

**Update Version for Next Release**
- Edit `README.adoc` to increment patch version
- Commit on `release/0.x` branch

**Notify Stakeholders**
- Post announcement in relevant channels
- Update downstream projects

## Troubleshooting

### Docker BuildKit Issues

If you encounter TLS certificate errors with buildx:
```bash
# Remove stale builder
docker buildx rm releasehx-builder

# Recreate builder (Rakefile will do this automatically)
bundle exec rake buildx
```

### MFA/OTP Issues with RubyGems

- Get fresh OTP code from authenticator app
- Code expires quickly - have app ready before running `gem push`

### GitHub CLI Permission Issues

If `gh` CLI lacks permissions:
- Use GitHub web UI for creating PRs and Releases
- Upload gem file manually in Release creation form

## Branch Strategy

**Long-lived Branch**: `release/0.x`
- Used for all 0.x.y patch releases
- PR to main for each release
- Merge commits preserve history
- Continue development on same branch

**Tagging**: Tags created on `main` branch after merge

**Documentation**: Auto-deploys from `main` via GitHub Actions

## Notes from 0.1.2 Release

- Total time: ~1-2 hours (including Docker troubleshooting)
- Docker multi-platform builds (arm64) are very slow - stick to amd64 only
- Use `--load` with buildx for single platform, then `docker push` separately
- GitHub Pages deployment takes ~2-3 minutes after tag push
