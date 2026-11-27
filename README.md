# lilbee engine packs

Engine wheels for [lilbee](https://github.com/tobocop2/lilbee): llama.cpp, mistral.rs, text-embeddings-inference and ik_llama.cpp.
Each release of this repository is one batch of wheels. A batch has its own tag. Nothing edits a release after it is published.

## Build a batch

1. Set `LILBEE_REF` to a tag of `tobocop2/lilbee`. The build uses `tools/wheel-build` and the pack tooling at that tag. A tag keeps its commit reachable. The run fails at once if the tag does not exist.
2. Run the `Build and publish engine packs` workflow. Pick an engine and give the batch a `tag_suffix` that no earlier tag has. The choice `all` selects every engine of `cells.yml`.
3. The plan skips each cell whose wheel a release already ships, so a run builds only the new cells. To build a published cell again, raise its build number in `cells.yml`.
4. The plan screens the licence that each cell declares with lilbee's own install check. If lilbee would refuse a cell, the run fails before any build starts.
5. The workflow builds each wheel and checks it as `lilbee engine install` does. Then it creates the release with the `GITHUB_TOKEN` of this repository. No other token or secret exists. Set `prerelease` to create the release as a prerelease in the same call.

## Use a batch in lilbee

Run `tools/gen_engine_packs.py` in lilbee with the new tags. It writes `engine_packs.json`.
