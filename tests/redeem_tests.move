#[test_only]
module stream::redeem_tests {
    use std::signer;
    use aptos_framework::coin;
    use stream::vault::VaultToken;
    use stream::test_helpers;
    use stream::vault;

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EZERO_AMOUNT)]
    fun test_RevertIfRedeemingZero(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);
        vault::deposit(user, test_helpers::one_apt());
        vault::redeem(user, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_redeemerReceivesSharesMax(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        let user_addr = signer::address_of(user);
        assert!(vault::shares(user_addr) == 0, 0);

        vault::rollToNextRound(keeper, deposit_amount);

        assert!(vault::shares(user_addr) == deposit_amount, 0);
        // Balance = 0
        assert!(!coin::is_account_registered<VaultToken>(user_addr), 0);

        vault::maxRedeem(user);

        assert!(vault::shares(user_addr) == deposit_amount, 0);
        assert!(coin::balance<VaultToken>(user_addr) == deposit_amount, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_redeemerReceivesSharesPartial(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        let user_addr = signer::address_of(user);
        assert!(vault::shares(user_addr) == 0, 0);

        vault::rollToNextRound(keeper, deposit_amount);

        assert!(vault::shares(user_addr) == deposit_amount, 0);
        // Balance = 0
        assert!(!coin::is_account_registered<VaultToken>(user_addr), 0);

        vault::redeem(user, deposit_amount / 2);

        assert!(vault::shares(user_addr) == deposit_amount, 0);
        assert!(coin::balance<VaultToken>(user_addr) == deposit_amount / 2, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EEXCEEDS_AVAILABLE)]
    fun test_RevertIfRedeemingMoreThanAvailableShares(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        vault::rollToNextRound(keeper, deposit_amount);
        vault::redeem(user, deposit_amount + 1);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_updatesDepositReceiptWhenRedeeming(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        test_helpers::assert_deposit_receipt(user, 1, deposit_amount, 0);
        vault::rollToNextRound(keeper, deposit_amount);

        vault::redeem(user, deposit_amount - 1);
        test_helpers::assert_deposit_receipt(user, 1, 0, 1);

        vault::maxRedeem(user);
        test_helpers::assert_deposit_receipt(user, 1, 0, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_nothingHappensWhenNumSharesIsZero(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        let user_addr = signer::address_of(user);
        assert!(vault::shares(user_addr) == 0, 0);
        // Balance = 0
        assert!(!coin::is_account_registered<VaultToken>(user_addr), 0);

        vault::maxRedeem(user);
        test_helpers::assert_deposit_receipt(user, 0, 0, 0);
        assert!(vault::shares(user_addr) == 0, 0);
        assert!(coin::balance<VaultToken>(user_addr) == 0, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_redeemDoesntUpdateSameRoundDeposits(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount_1 = test_helpers::one_apt();
        vault::deposit(user, deposit_amount_1);
        vault::rollToNextRound(keeper, deposit_amount_1);

        test_helpers::assert_deposit_receipt(user, 1, deposit_amount_1, 0);

        let deposit_amount_2 = 2 * test_helpers::one_apt();
        vault::deposit(user, deposit_amount_2);
        test_helpers::assert_deposit_receipt(user, 2, deposit_amount_2, deposit_amount_1);

        vault::maxRedeem(user);
        test_helpers::assert_deposit_receipt(user, 2, deposit_amount_2, 0);
    }
}
