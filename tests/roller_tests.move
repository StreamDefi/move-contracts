#[test_only]
module stream::roller_tests {
    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use std::signer;
    use std::vector;
    use stream::test_helpers;
    use stream::vault;

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_rollToNextRound(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        assert!(vault::round() == 1, 0);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        test_helpers::assert_deposit_receipt(user, 1, deposit_amount, 0);
        test_helpers::assert_vault_state(1, 0, 0, deposit_amount, 0, 0, 0, 0, 0);
        vault::rollToNextRound(keeper, deposit_amount);

        assert!(vault::round() == 2, 0);
        assert!(vault::totalBalance() == deposit_amount, 0);
        // Vault's decimals is the same as APT (8).
        test_helpers::assert_vault_state(2, deposit_amount, 0, 0, 0, 0, 0, (deposit_amount as u128), deposit_amount);
        test_helpers::assert_deposit_receipt(user, 1, deposit_amount, 0);
        assert!(vault::remainingBalance() == 0, 0);
        assert!(coin::balance<AptosCoin>(signer::address_of(keeper)) == deposit_amount, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123)]
    fun test_multiDepositRollover(owner: &signer, keeper: &signer) {
        test_helpers::setup(owner, keeper);
        assert!(vault::round() == 1, 0);

        let users = vector[@0x1, @0x2, @0x3, @0x4, @0x5, @0x6, @0x7, @0x8, @0x9, @0xa];
        let deposit_amount = test_helpers::one_apt();
        vector::for_each(users, |user_addr| {
            let user = &account::create_signer_for_test(user_addr);
            test_helpers::mint(user, 1000);
            vault::deposit(user, deposit_amount);
            test_helpers::assert_deposit_receipt(user, 1, deposit_amount, 0);
        });

        test_helpers::assert_vault_state(1, 0, 0, deposit_amount * 10, 0, 0, 0, 0, 0);
        vault::rollToNextRound(keeper, deposit_amount * 10);

        assert!(vault::round() == 2, 0);
        assert!(vault::totalBalance() == deposit_amount * 10, 0);
        // Vault's decimals is the same as APT (8).
        test_helpers::assert_vault_state(2, deposit_amount * 10, 0, 0, 0, 0, 0, ((deposit_amount * 10) as u128), deposit_amount);
        vector::for_each(users, |user_addr| {
            let user = &account::create_signer_for_test(user_addr);
            test_helpers::assert_deposit_receipt(user, 1, deposit_amount, 0);
        });
        assert!(vault::remainingBalance() == 0, 0);
        assert!(coin::balance<AptosCoin>(signer::address_of(keeper)) == deposit_amount * 10, 0);
    }
}
