module stream::shares_math {
    use aptos_std::math128;
    use aptos_std::math64;

    /// Invalid asset per share
    const EINVALID_ASSET_PER_SHARE: u64 = 1;

    const PLACEHOLDER_UINT: u64 = 1;

    public fun assetToShares(
        asset_amount: u64,
        asset_per_share: u64,
        decimals: u64,
    ): u64 {
        // If this throws, it means that vault's roundPricePerShare[currentRound] has not been set yet
        // which should never happen.
        // Has to be larger than 1 because `1` is used in `initRoundPricePerShares` to prevent cold writes.
        assert!(asset_per_share > PLACEHOLDER_UINT, EINVALID_ASSET_PER_SHARE);
        math64::mul_div(asset_amount, math64::pow(10, decimals), asset_per_share)
    }

    public fun sharesToAsset(
        shares: u64,
        asset_per_share: u64,
        decimals: u64,
    ): u64 {
        // If this throws, it means that vault's roundPricePerShare[currentRound] has not been set yet
        // which should never happen.
        // Has to be larger than 1 because `1` is used in `initRoundPricePerShares` to prevent cold writes.
        assert!(asset_per_share > PLACEHOLDER_UINT, EINVALID_ASSET_PER_SHARE);
        math64::mul_div(shares, asset_per_share, math64::pow(10, decimals))
    }

    public fun pricePerShare(
        total_supply: u128,
        total_balance: u64,
        pending_amount: u64,
        decimals: u64,
    ): u64 {
        let single_share = math64::pow(10, decimals);
        if (total_supply > 0) {
            (math128::mul_div((single_share as u128), ((total_balance - pending_amount) as u128), total_supply) as u64)
        } else {
            single_share
        }
    }
}
