#[test_only]
module stream::deposits_tests {
    use std::signer;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use stream::test_helpers;
    use stream::vault;

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_depositReceiptCreatedForNewDepositer(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        test_helpers::assert_deposit_receipt(user, 1, deposit_amount, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user_1 = @0x234, user_2 = @0x235)]
    fun test_depositReceiptIncreasesWhenDepositingSameRound(owner: &signer, keeper: &signer, user_1: &signer, user_2: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user_1, 1000);
        test_helpers::mint(user_2, 1000);
        let deposit_amount_1 = test_helpers::one_apt();
        vault::deposit(user_1, deposit_amount_1);
        test_helpers::assert_deposit_receipt(user_1, 1, deposit_amount_1, 0);
        test_helpers::assert_vault_state(1, 0, 0, deposit_amount_1, 0, 0, 0, 0, 0);

        let deposit_amount_2 = 2 * test_helpers::one_apt();
        vault::deposit(user_2, deposit_amount_2);
        test_helpers::assert_deposit_receipt(user_2, 1, deposit_amount_2, 0);
        test_helpers::assert_vault_state(1, 0, 0, deposit_amount_1 + deposit_amount_2, 0, 0, 0, 0, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EEXCEEDS_CAP)]
    fun test_RevertIfDepositExceedsCap(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        // 1e9 tokens is the cap.
        let cap = 1000000000;
        test_helpers::mint(user, cap + 1);
        let deposit_amount = cap * test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        test_helpers::assert_deposit_receipt(user, 1, deposit_amount, 0);

        // Attempting to deposit more than the cap should revert.
        vault::deposit(user, test_helpers::one_apt());
    }

    #[test(owner = @0xcafe, keeper = @0x123, user_1 = @0x234, user_2 = @0x235)]
    fun test_vaultStateMaintainedThroughDeposits(owner: &signer, keeper: &signer, user_1: &signer, user_2: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user_1, 1000);
        test_helpers::mint(user_2, 1000);
        let deposit_amount_1 = test_helpers::one_apt();
        vault::deposit(user_1, deposit_amount_1);
        let deposit_amount_2 = 2 * test_helpers::one_apt();
        vault::deposit(user_2, deposit_amount_2);

        assert!(vault::totalBalance() == deposit_amount_1 + deposit_amount_2, 0);
        // should have zero shares minted
        assert!(vault::total_unredeemed_shares() == 0, 0);
        test_helpers::assert_deposit_receipt(user_1, 1, deposit_amount_1, 0);
        test_helpers::assert_deposit_receipt(user_2, 1, deposit_amount_2, 0);
        test_helpers::assert_vault_state(1, 0, 0, deposit_amount_1 + deposit_amount_2, 0, 0, 0, 0, 0);

        test_helpers::rollToNextRound(keeper, deposit_amount_1 + deposit_amount_2);
        assert!(coin::balance<AptosCoin>(signer::address_of(keeper)) == deposit_amount_1 + deposit_amount_2, 0);
        assert!(vault::remainingBalance() == 0, 0);
        assert!(vault::total_unredeemed_shares() == deposit_amount_1 + deposit_amount_2, 0);
        // deposit receipts shouldn't change yet
        test_helpers::assert_deposit_receipt(user_1, 1, deposit_amount_1, 0);
        test_helpers::assert_deposit_receipt(user_2, 1, deposit_amount_2, 0);

        // vault state should change
        test_helpers::assert_vault_state(2, deposit_amount_1 + deposit_amount_2, 0, 0, 0, 0, 0, ((deposit_amount_1 + deposit_amount_2) as u128), test_helpers::one_apt());
    }

    #[test(owner = @0xcafe, keeper = @0x123, user_1 = @0x234, user_2 = @0x235)]
    fun test_processesDepositFromPrevRound(owner: &signer, keeper: &signer, user_1: &signer, user_2: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user_1, 1000);
        test_helpers::mint(user_2, 1000);
        let deposit_amount_1 = test_helpers::one_apt();
        vault::deposit(user_1, deposit_amount_1);
        let deposit_amount_2 = 2 * test_helpers::one_apt();
        vault::deposit(user_2, deposit_amount_2);

        assert!(vault::totalBalance() == deposit_amount_1 + deposit_amount_2, 0);
        // should have zero shares minted
        assert!(vault::total_unredeemed_shares() == 0, 0);
        test_helpers::assert_deposit_receipt(user_1, 1, deposit_amount_1, 0);
        test_helpers::assert_deposit_receipt(user_2, 1, deposit_amount_2, 0);
        test_helpers::assert_vault_state(1, 0, 0, deposit_amount_1 + deposit_amount_2, 0, 0, 0, 0, 0);

        test_helpers::rollToNextRound(keeper, deposit_amount_1 + deposit_amount_2);
        assert!(coin::balance<AptosCoin>(signer::address_of(keeper)) == deposit_amount_1 + deposit_amount_2, 0);
        assert!(vault::remainingBalance() == 0, 0);
        assert!(vault::total_unredeemed_shares() == deposit_amount_1 + deposit_amount_2, 0);
        // deposit receipts shouldn't change yet
        test_helpers::assert_deposit_receipt(user_1, 1, deposit_amount_1, 0);
        test_helpers::assert_deposit_receipt(user_2, 1, deposit_amount_2, 0);

        // vault state should change
        test_helpers::assert_vault_state(2, deposit_amount_1 + deposit_amount_2, 0, 0, 0, 0, 0, ((deposit_amount_1 + deposit_amount_2) as u128), test_helpers::one_apt());

        let secondary_deposit_amount = test_helpers::one_apt();
        vault::deposit(user_1, secondary_deposit_amount);
        vault::deposit(user_2, secondary_deposit_amount);
        assert!(vault::remainingBalance() == 2 * secondary_deposit_amount, 0);
        test_helpers::assert_deposit_receipt(user_1, 2, secondary_deposit_amount, deposit_amount_1);
        test_helpers::assert_deposit_receipt(user_2, 2, secondary_deposit_amount, deposit_amount_2);
        test_helpers::assert_vault_state(2, deposit_amount_1 + deposit_amount_2, 0, 2 * secondary_deposit_amount, 0, 0, 0, ((deposit_amount_1 + deposit_amount_2) as u128), test_helpers::one_apt());
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EZERO_AMOUNT)]
    fun test_RevertIfAmountNotGreaterThanZero(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        vault::deposit(user, 0);
    }
}
