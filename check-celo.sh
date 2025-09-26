#!/bin/bash
L2_RPC="http://localhost:9993"
OP_NODE_RPC="http://localhost:9545"
FORNO="https://forno.celo.org"

# ---------------- Execution client (op-geth) ----------------
sync=$(cast rpc --rpc-url $L2_RPC eth_syncing | jq)

if [[ "$sync" == "false" ]]; then
  current_hex=$(cast block --rpc-url $L2_RPC latest --json | jq -r .number)
  current_dec=$((16#${current_hex:2}))
  lag=0
else
  current=$(echo "$sync" | jq -r .currentBlock)
  highest=$(echo "$sync" | jq -r .highestBlock)

  if [[ "$current" == "null" || "$highest" == "null" ]]; then
    echo "❌ Could not fetch L2 sync info from op-geth."
    exit 1
  fi

  current_dec=$((16#${current:2}))
  highest_dec=$((16#${highest:2}))
  lag=$((highest_dec - current_dec))
  if (( lag < 0 )); then
    lag=0
  fi
fi

# ---------------- Reference L2 block ----------------
ref_l2_hex=$(curl -s -X POST $FORNO \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r .result)
ref_l2=$((16#${ref_l2_hex:2}))

# ---------------- Rollup client (op-node) ----------------
l1_status=$(curl -s -X POST $OP_NODE_RPC \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' \
  | jq -r .result)

head_eth_l1=$(echo "$l1_status" | jq -r .head_l1.number)
finalized_eth_l1=$(echo "$l1_status" | jq -r .finalized_l1.number)
unsafe_l2=$(echo "$l1_status" | jq -r .unsafe_l2.number)
unsafe_origin=$(echo "$l1_status" | jq -r .unsafe_l2.l1origin.number)
safe_l2=$(echo "$l1_status" | jq -r .safe_l2.number)
safe_origin=$(echo "$l1_status" | jq -r .safe_l2.l1origin.number)
finalized_l2=$(echo "$l1_status" | jq -r .finalized_l2.number)
finalized_origin=$(echo "$l1_status" | jq -r .finalized_l2.l1origin.number)

# ---------------- Gap calculations ----------------
diff_ref=$((current_dec - ref_l2))
gap_unsafe_safe=$((unsafe_l2 - safe_l2))
gap_safe_finalized=$((safe_l2 - finalized_l2))

# ---------------- Output ----------------
echo "=== Execution (op-geth: Celo OP L2) ==="
echo "Local L2 block:   $current_dec"
echo "Reference L2:     $ref_l2"
echo "Sync lag:         $lag (internal)"
echo "Local vs Forno:   ${diff_ref} block(s)"
echo

echo "=== Rollup (op-node) ==="
echo "Unsafe L2:        $unsafe_l2 (origin ETH L1: $unsafe_origin)"
echo "Safe L2:          $safe_l2 (origin ETH L1: $safe_origin)"
echo "Finalized L2:     $finalized_l2 (origin ETH L1: $finalized_origin)"
echo "Unsafe→Safe gap:  $gap_unsafe_safe block(s)"
echo "Safe→Finalized gap: $gap_safe_finalized block(s)"
echo

echo "=== Ethereum L1 (data availability) ==="
echo "Head ETH L1:      $head_eth_l1"
echo "Finalized ETH L1: $finalized_eth_l1"
echo

# ---------------- Health Checks ----------------

# Execution layer check
if (( lag > 0 )); then
  echo "⏳ Execution layer (op-geth) is still catching up ($lag blocks behind internally)."
elif (( diff_ref < -2 )); then
  echo "⚠️ Execution layer is behind external tip by $(( -diff_ref )) block(s)."
elif (( diff_ref > 2 )); then
  echo "⚠️ Execution layer is ahead of Forno by $diff_ref block(s). (Possible propagation delay)"
else
  echo "✅ Execution layer (op-geth) is synced to chain tip."
fi

# Rollup layer check
if [[ "$unsafe_l2" == "null" || "$safe_l2" == "null" || "$finalized_l2" == "null" ]]; then
  echo "❌ Rollup layer (op-node) did not return sync info."
else
  gap_unsafe=$(( ref_l2 - unsafe_l2 ))
  if (( gap_unsafe > 5 )); then
    echo "⏳ Rollup layer unsafe head is $gap_unsafe blocks behind external tip."
  else
    echo "✅ Rollup layer unsafe head is near tip."
  fi

  echo "   Safe lag:       $gap_unsafe_safe block(s) behind unsafe"
  echo "   Finalized lag:  $gap_safe_finalized block(s) behind safe"
fi
