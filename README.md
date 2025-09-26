# celo-l2-public

## `check-celo.sh`

A script to perform a sanity check on the overall sync status of a Celo L2 Optimism Node. Make sure `jq` and `cast` are installed. To install `cast`:
```
curl -L https://foundry.paradigm.xyz | bash
# logout/login, then
foundryup
```

Important numbers are the `lag` values:
```
Sync lag:         X (internal)
```
This is how close our node is to a reference node (in this case forno). Should be less than 10 if we are healthy. Or if we are syncing, it should decrease over time.

```
  Safe lag:       XXXXX block(s) behind unsafe
```
This shows the distance between the "safe" block height and the "unsafe" block height. When things are very healthy, this is generally less than 1,000. Values of 20,000 seem to be ok. When it creeps up to 200,000 or more, we *might* be in trouble.

```
Finalized lag:  XXXXX block(s) behind safe
```
Healthy is generally a few hundred. 0 usually means that the safe height is not advancing sufficiently.

When we are syncing, we want to see the safe height decreasing over time. Once it is sufficiently small, the unsafe height will start advancing toward the reference node block height.
