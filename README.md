# lilbee engine packs

Engine wheels for [lilbee](https://github.com/tobocop2/lilbee): llama.cpp, mistral.rs and text-embeddings-inference.
Each release of this repository is one batch of wheels. A batch has its own tag. Nothing edits a release after it is published.

## Build a batch

1. Set `LILBEE_REF` to a full commit hash of `tobocop2/lilbee`. The build uses `tools/wheel-build` and the pack tooling at that commit.
2. Run the `Build and publish engine packs` workflow. Pick an engine and give the batch a `tag_suffix` that no earlier tag has.
3. The workflow builds each wheel, then creates the release with the `GITHUB_TOKEN` of this repository. No other token or secret exists.

## Use a batch in lilbee

Run `tools/gen_engine_packs.py` in lilbee with the new tags. It writes `engine_packs.json`.
