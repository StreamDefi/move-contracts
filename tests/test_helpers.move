#[test_only]
module stream::test_helpers {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::stake;
    use stream::vault;

    const ONE_APT: u64 = 100000000;

    public fun one_apt(): u64 {
        ONE_APT
    }

    public fun setup(owner: &signer, keeper: &signer) {
        vault::init_for_test(owner);
        vault::setNewKeeper(owner, signer::address_of(keeper));
    }

    public fun mint(user: &signer, amount: u64) {
        let addr = signer::address_of(user);
        if (!account::exists_at(addr)) {
            account::create_account_for_test(signer::address_of(user));
        };
        // Need to be initialized so we can mint APT for tests.
        stake::initialize_for_test(&account::create_signer_for_test(@0x1));
        stake::mint(user, amount * ONE_APT);
    }

    public fun assert_deposit_receipt(user: &signer, expected_round: u64, expected_amount: u64, expected_unredeemed_shares: u64) {
        let (round, amount, unredeemed_shares) = vault::get_deposit_receipt(signer::address_of(user));
        assert!(round == expected_round, 0);
        assert!(amount == expected_amount, 0);
        assert!(unredeemed_shares == expected_unredeemed_shares, 0);
    }

    public fun assert_withdrawal(user: &signer, expected_round: u64, expected_shares: u64) {
        let (round, shares) = vault::get_withdrawal(signer::address_of(user));
        assert!(round == expected_round, 0);
        assert!(shares == expected_shares, 0);
    }

    public fun assert_vault_state(
        expected_round: u64,
        expected_locked_amount: u64,
        expected_last_locked_amount: u64,
        expected_total_pending: u64,
        expected_queued_withdraw_shares: u64,
        expected_last_queued_withdraw_amount: u64,
        expected_current_queued_withdraw_shares: u64,
        expected_total_share_supply: u128,
        expected_curr_round_price_per_share: u64,
    ) {
        let (
            round,
            locked_amount,
            last_locked_amount,
            total_pending,
            queued_withdraw_shares,
            last_queued_withdraw_amount,
            current_queued_withdraw_shares,
            curr_round_price_per_share,
        ) = vault::vault_state();
        assert!(round == expected_round, 0);
        assert!(locked_amount == expected_locked_amount, 0);
        assert!(last_locked_amount == expected_last_locked_amount, 0);
        assert!(total_pending == expected_total_pending, 0);
        assert!(queued_withdraw_shares == expected_queued_withdraw_shares, 0);
        assert!(last_queued_withdraw_amount == expected_last_queued_withdraw_amount, 0);
        assert!(current_queued_withdraw_shares == expected_current_queued_withdraw_shares, 0);
        assert!(vault::totalSupply() == expected_total_share_supply, (vault::totalSupply() as u64));
        assert!(curr_round_price_per_share == expected_curr_round_price_per_share, 0);
    }

    public fun rollToNextRound(keeper: &signer, deposit_amount: u64) {
        vault::rollToNextRound(keeper, deposit_amount);
    }

    public fun add_to_balance(keeper: &signer, deposit_amount: u64) {
        vault::add_to_balance(keeper, deposit_amount);
    }
}
